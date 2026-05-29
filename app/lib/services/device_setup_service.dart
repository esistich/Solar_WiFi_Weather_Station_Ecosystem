import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:wifi_iot/wifi_iot.dart';

/// Steuert den Soft-AP Setup-Flow für einen ESP8266/ESP32.
///
/// Ablauf:
///  1. App verbindet sich ins ESP-WLAN (SSID beginnt mit "SWS-")
///  2. App schickt JSON-Config an 192.168.4.1/api/config
///  3. ESP verbindet sich ins Heimnetz
///  4. App trennt Soft-AP-Verbindung
class DeviceSetupService {
  static const _espGateway = '192.168.4.1';
  static const _configPath = '/api/config';

  /// Scannt nach ESP-Hotspots (SSIDs die mit [prefix] beginnen).
  Future<List<WifiNetwork>> scanForDevices({
	String prefix = 'SWS-',
  }) async {
	final networks = await WiFiForIoTPlugin.loadWifiList();
	return networks.where((n) => n.ssid?.startsWith(prefix) ?? false).toList();
  }

  /// Verbindet mit dem ESP-Hotspot (kein Passwort nötig für Config-Portal).
  Future<bool> connectToDevice(String ssid) async {
	return WiFiForIoTPlugin.connect(
	  ssid,
	  security: NetworkSecurity.NONE,
	  joinOnce: true,
	  withInternet: false,
	);
  }

  /// Sendet die WLAN- und API-Konfiguration an den ESP.
  Future<void> sendConfig({
	required String wifiSsid,
	required String wifiPass,
	required String apiHost,
	required String apiPath,
	required bool apiHttps,
	int scrollMs = 60,
	int fetchSec = 300,
  }) async {
	final uri = Uri.http(_espGateway, _configPath);
	final body = jsonEncode({
	  'wifi_ssid': wifiSsid,
	  'wifi_pass': wifiPass,
	  'api_host': apiHost,
	  'api_path': apiPath,
	  'api_https': apiHttps ? 1 : 0,
	  'scroll_ms': scrollMs,
	  'fetch_sec': fetchSec,
	});

	final response = await http
		.post(
		  uri,
		  headers: {'Content-Type': 'application/json'},
		  body: body,
		)
		.timeout(const Duration(seconds: 8));

	if (response.statusCode != 200) {
	  throw Exception(
		'ESP antwortete mit HTTP ${response.statusCode}: ${response.body}',
	  );
	}
  }

  /// Liest die aktuelle Config vom ESP aus (GET /api/config).
  Future<Map<String, dynamic>> readConfig() async {
	final uri = Uri.http(_espGateway, _configPath);
	final response = await http
		.get(uri)
		.timeout(const Duration(seconds: 5));

	if (response.statusCode != 200) {
	  throw Exception('Konnte Config nicht lesen: HTTP ${response.statusCode}');
	}

	return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Trennt die WiFi-Verbindung zum ESP.
  Future<void> disconnect() async {
	await WiFiForIoTPlugin.disconnect();
  }
}
