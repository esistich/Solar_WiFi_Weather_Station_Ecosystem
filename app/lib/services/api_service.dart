import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// Kommuniziert mit der bestehenden PHP/MySQL-API (data.php, history.php).
class ApiService {
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Lädt den aktuellen Messwert für ein Gerät.
  Future<Measurement> fetchLatest(Device device) async {
	final uri = Uri.parse(device.apiUrl);
	final response = await _client
		.get(uri)
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

	final uri = Uri.parse(device.historyUrl).replace(queryParameters: {
	  'from': _fmt(from),
	  'to': _fmt(now),
	});

	final response = await _client
		.get(uri)
		.timeout(const Duration(seconds: 15));

	if (response.statusCode != 200) {
	  throw ApiException('HTTP ${response.statusCode}', uri.toString());
	}

	final json = jsonDecode(response.body);
	if (json is! List) {
	  throw ApiException('History: kein Array', uri.toString());
	}

	return json
		.cast<Map<String, dynamic>>()
		.map(MeasurementPoint.fromJson)
		.toList();
  }

  String _fmt(DateTime dt) =>
	  '${dt.year.toString().padLeft(4, '0')}-'
	  '${dt.month.toString().padLeft(2, '0')}-'
	  '${dt.day.toString().padLeft(2, '0')} '
	  '${dt.hour.toString().padLeft(2, '0')}:'
	  '${dt.minute.toString().padLeft(2, '0')}:00';

  void dispose() => _client.close();
}

class ApiException implements Exception {
  final String message;
  final String url;
  ApiException(this.message, this.url);

  @override
  String toString() => 'ApiException: $message ($url)';
}
