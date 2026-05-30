import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// Kommuniziert mit der bestehenden PHP/MySQL-API (data.php, history.php).
class ApiService {
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Erstellt den Basic-Auth-Header für ein Gerät (leer wenn keine Credentials).
  Map<String, String> _authHeaders(Device device) {
	if (device.apiUser.isEmpty) return {};
	final credentials = base64Encode(
	  utf8.encode('${device.apiUser}:${device.apiPassword}'),
	);
	return {HttpHeaders.authorizationHeader: 'Basic $credentials'};
  }

  /// Lädt den aktuellen Messwert für ein Gerät.
  Future<Measurement> fetchLatest(Device device) async {
	final uri = Uri.parse(device.apiUrl);
	final response = await _client
		.get(uri, headers: _authHeaders(device))
		.timeout(const Duration(seconds: 10));

	if (response.statusCode != 200) {
	  throw ApiException('HTTP ${response.statusCode}', uri.toString());
	}

	final json = jsonDecode(response.body);
	if (json is! Map<String, dynamic>) {
	  throw ApiException('Ungültiges JSON-Format', uri.toString());
	}

	return Measurement.fromJson(json);
  }

  /// Lädt die History-Daten für ein Gerät (letzten [hours] Stunden).
  Future<List<MeasurementPoint>> fetchHistory(
	Device device, {
	int hours = 24,
  }) async {
	final now = DateTime.now();
	final from = now.subtract(Duration(hours: hours));

	// history.php akzeptiert nur YYYY-MM-DD als Datumsformat
	final uri = Uri.parse(device.historyUrl).replace(queryParameters: {
	  'from': _fmtDate(from),
	  'to': _fmtDate(now),
	  'limit': '500',
	});

	final response = await _client
		.get(uri, headers: _authHeaders(device))
		.timeout(const Duration(seconds: 15));

	if (response.statusCode != 200) {
	  throw ApiException('HTTP ${response.statusCode}', uri.toString());
	}

	// history.php gibt {"count":…,"data":[…]} zurück
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
