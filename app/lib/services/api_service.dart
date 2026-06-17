import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/models.dart';

typedef ApiResult<T> = ({T? data, String? error});

class ApiService {
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> _basicAuthHeaders(Device device) {
    if (device.apiUser.isEmpty) return {};
    final credentials = base64Encode(
      utf8.encode('${device.apiUser}:${device.apiPassword}'),
    );
    return {HttpHeaders.authorizationHeader: 'Basic $credentials'};
  }

  Map<String, String> _bearerHeaders(String? token) {
    if (token == null || token.isEmpty) return {};
    return {HttpHeaders.authorizationHeader: 'Bearer $token'};
  }

  /// Hilfsmethode zur Erstellung der API-URL (umgeht Server-Umleitungen)
  Uri _buildUri(Device device, String route, [Map<String, dynamic>? query]) {
    final baseUrl = device.baseUrl;
    final apiRoot = device.apiPath.contains('/v1/')
		? device.apiPath.substring(0, device.apiPath.indexOf('/v1/'))
		: device.apiPath.replaceFirst(RegExp(r'/[^/]+\.php$'), '');
    
    // Nutze index.php?r=route als sichersten Weg
    return Uri.parse('$baseUrl$apiRoot/v1/index.php').replace(
      queryParameters: {
        'r': route,
        ...?(query ?? {}),
      },
    );
  }

  Future<ApiResult<Measurement>> fetchLatest(Device device) async {
    try {
      final uri = _buildUri(device, 'data', {
        if (device.stationSlug.isNotEmpty) 'station': device.stationSlug,
      });

      final response = await _client
          .get(uri, headers: _basicAuthHeaders(device))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 404) {
        return (data: null, error: 'Station noch nicht im System. Warte auf erste Messung...');
      }

      if (response.statusCode != 200) {
        return (data: null, error: 'Server-Fehler: HTTP ${response.statusCode}');
      }

      final json = jsonDecode(response.body);
      return (data: Measurement.fromJson(json), error: null);
    } catch (e) {
      return (data: null, error: 'Verbindungsfehler: Keine Antwort vom Server.');
    }
  }

  Future<ApiResult<List<MeasurementPoint>>> fetchHistory(
    Device device, {
    int hours = 24,
    String? bearerToken,
  }) async {
    try {
      final now = DateTime.now();
      final from = now.subtract(Duration(hours: hours));
        
      final uri = _buildUri(device, 'history', {
        if (device.stationSlug.isNotEmpty) 'station': device.stationSlug,
        'from': _fmtDateTime(from),
        'to': _fmtDateTime(now),
        'limit': '2000',
      });

      final response = await _client
          .get(uri, headers: _bearerHeaders(bearerToken))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) return (data: null, error: 'Bitte in den Einstellungen anmelden.');
      if (response.statusCode != 200) return (data: null, error: 'Fehler beim Laden des Verlaufs.');

      final json = jsonDecode(response.body);
      final List<dynamic> rows = (json is Map && json['data'] is List) ? json['data'] : (json is List ? json : []);

      return (data: rows.cast<Map<String, dynamic>>().map(MeasurementPoint.fromJson).toList(), error: null);
    } catch (e) {
      return (data: null, error: 'Verbindung zur Historie fehlgeschlagen.');
    }
  }

  String _fmtDate(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';

  String _fmtDateTime(DateTime dt) =>
      '${_fmtDate(dt)}T${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';

  Future<ApiResult<Map<String, dynamic>>> updateStation(
    Device device, {
    required String currentSlug,
    required String name,
    required String newSlug,
    required String bearerToken,
  }) async {
    try {
      final uri = _buildUri(device, 'admin/stations');
      
      final response = await _client
          .patch(
            uri,
            headers: {
              ..._bearerHeaders(bearerToken),
              HttpHeaders.contentTypeHeader: 'application/json',
            },
            body: jsonEncode({
              'slug': currentSlug.isEmpty ? newSlug : currentSlug, 
              'name': name, 
              'new_slug': newSlug
            }),
          )
          .timeout(const Duration(seconds: 10));

      final json = jsonDecode(response.body);
      if (response.statusCode != 200) {
        final String errorMsg = json['error']?.toString() ?? 'Fehler beim Speichern (HTTP ${response.statusCode})';
        return (data: null, error: errorMsg);
      }
      
      final Map<String, dynamic> stationData = json['station'] as Map<String, dynamic>;
      return (data: stationData, error: null);
    } catch (e) {
      return (data: null, error: 'Server nicht erreichbar oder Zeitüberschreitung.');
    }
  }

  void dispose() => _client.close();
}
