import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/models.dart';

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

  /// Laedt den aktuellen Messwert (GET /v1/data – oeffentlich).
  Future<Measurement> fetchLatest(Device device) async {
final uri = Uri.parse(device.apiUrl);
final response = await _client
.get(uri, headers: _basicAuthHeaders(device))
.timeout(const Duration(seconds: 10));

if (response.statusCode != 200) {
  throw ApiException('HTTP ${response.statusCode}', uri.toString());
}

final json = jsonDecode(response.body);
if (json is! Map<String, dynamic>) {
  throw ApiException('Ungueltiges JSON-Format', uri.toString());
}

return Measurement.fromJson(json);
  }

  /// Laedt Verlaufsdaten (GET /v1/history – JWT Bearer erforderlich).
  Future<List<MeasurementPoint>> fetchHistory(
Device device, {
int hours = 24,
String? bearerToken,
  }) async {
final now = DateTime.now();
final from = now.subtract(Duration(hours: hours));

final uri = Uri.parse(device.historyUrl).replace(queryParameters: {
  if (device.stationSlug.isNotEmpty) 'station': device.stationSlug,
  'from':  _fmtDate(from),
  'to':    _fmtDate(now),
  'limit': '500',
});

final response = await _client
.get(uri, headers: _bearerHeaders(bearerToken))
.timeout(const Duration(seconds: 15));

if (response.statusCode != 200) {
  throw ApiException('HTTP ${response.statusCode}', uri.toString());
}

// GET /v1/history gibt {"station":"...","count":N,"data":[...]} zurueck
final json = jsonDecode(response.body);
final List<dynamic> rows;
if (json is Map<String, dynamic> && json['data'] is List) {
  rows = json['data'] as List<dynamic>;
} else if (json is List) {
  rows = json;
} else {
  throw ApiException('History: unbekanntes Antwortformat', uri.toString());
}

return rows
.cast<Map<String, dynamic>>()
.map(MeasurementPoint.fromJson)
.toList();
  }

  String _fmtDate(DateTime dt) =>
  '${dt.year.toString().padLeft(4, '0')}-'
  '${dt.month.toString().padLeft(2, '0')}-'
  '${dt.day.toString().padLeft(2, '0')}';

  void dispose() => _client.close();
}

class ApiException implements Exception {
  final String message;
  final String url;
  ApiException(this.message, this.url);

  @override
  String toString() => 'ApiException: $message ($url)';
}
