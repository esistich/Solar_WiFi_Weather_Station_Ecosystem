import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// Ein Record, der entweder Daten oder einen Fehler enthält.
/// Ähnlich wie ein Result<T> in C#.
typedef ApiResult<T> = ({T? data, String? error});

/// Kommuniziert mit der SWS API v1 (GET /v1/data, GET /v1/history).
class ApiService {
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Basic-Auth-Header fuer GET /v1/data (leer wenn keine Credentials hinterlegt).
  Map<String, String> _basicAuthHeaders(Device device) {
    if (device.apiUser.isEmpty) return {};
    final credentials = base64Encode(
      utf8.encode('${device.apiUser}:${device.apiPassword}'),
    );
    return {HttpHeaders.authorizationHeader: 'Basic $credentials'};
  }

  /// JWT-Bearer-Header fuer GET /v1/history und GET /v1/stations.
  Map<String, String> _bearerHeaders(String? token) {
    if (token == null || token.isEmpty) return {};
    return {HttpHeaders.authorizationHeader: 'Bearer $token'};
  }

  /// Laedt den aktuellen Messwert (GET /v1/data).
  /// Nutzt Dart 3 Records für die Rückgabe.
  Future<ApiResult<Measurement>> fetchLatest(Device device) async {
    try {
      final base = Uri.parse(device.apiUrl);
      final uri = device.stationSlug.isNotEmpty
          ? base.replace(queryParameters: {'station': device.stationSlug})
          : base;

      final response = await _client
          .get(uri, headers: _basicAuthHeaders(device))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return (data: null, error: 'Serverfehler: HTTP ${response.statusCode}');
      }

      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) {
        return (data: null, error: 'Ungültiges Datenformat vom Server');
      }

      return (data: Measurement.fromJson(json), error: null);
    } on SocketException {
      return (data: null, error: 'Keine Internetverbindung');
    } catch (e) {
      return (data: null, error: 'Fehler: $e');
    }
  }

  /// Laedt Verlaufsdaten (GET /v1/history).
  Future<ApiResult<List<MeasurementPoint>>> fetchHistory(
    Device device, {
    int hours = 24,
    String? bearerToken,
  }) async {
    try {
      final now = DateTime.now();
      final from = now.subtract(Duration(hours: hours));

      final uri = Uri.parse(device.historyUrl).replace(queryParameters: {
        if (device.stationSlug.isNotEmpty) 'station': device.stationSlug,
        'from': _fmtDateTime(from),
        'to': _fmtDateTime(now),
        'limit': '500',
      });

      final response = await _client
          .get(uri, headers: _bearerHeaders(bearerToken))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return (data: null, error: 'Historie-Fehler: HTTP ${response.statusCode}');
      }

      final json = jsonDecode(response.body);
      final List<dynamic> rows;

      // Pattern Matching / Type Checking
      if (json case {'data': List data}) {
        rows = data;
      } else if (json case List list) {
        rows = list;
      } else {
        return (data: null, error: 'Unbekanntes Historie-Format');
      }

      final points = rows
          .cast<Map<String, dynamic>>()
          .map(MeasurementPoint.fromJson)
          .toList();

      return (data: points, error: null);
    } catch (e) {
      return (data: null, error: 'Historie konnte nicht geladen werden');
    }
  }

  String _fmtDate(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';

  String _fmtDateTime(DateTime dt) =>
      '${_fmtDate(dt)} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';

  /// Aktualisiert Name und Slug einer Station (PATCH /v1/admin/stations).
  Future<ApiResult<Map<String, dynamic>>> updateStation(
    Device device, {
    required String currentSlug,
    required String name,
    required String newSlug,
    required String bearerToken,
  }) async {
    try {
      final uri = Uri.parse(device.historyUrl)
          .replace(path: _adminStationsPath(device), queryParameters: {});
      final response = await _client
          .patch(
            uri,
            headers: {
              ..._bearerHeaders(bearerToken),
              HttpHeaders.contentTypeHeader: 'application/json',
            },
            body: jsonEncode(
                {'slug': currentSlug, 'name': name, 'new_slug': newSlug}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return (data: null, error: 'Fehler beim Aktualisieren: ${response.statusCode}');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return (data: json['station'] as Map<String, dynamic>, error: null);
    } catch (e) {
      return (data: null, error: 'Netzwerkfehler beim Aktualisieren');
    }
  }

  /// Liefert den Pfad zu PATCH /v1/admin/stations relativ zur History-URL.
  String _adminStationsPath(Device device) {
    final base = Uri.parse(device.historyUrl);
    final parent = base.path.replaceFirst(RegExp(r'/history$'), '');
    return '$parent/admin/stations';
  }

  void dispose() => _client.close();
}
