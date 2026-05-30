import 'dart:convert';

/// Repräsentiert ein registriertes SWS-Gerät (Wetterstation oder Display).
class Device {
  final String id;         // UUID, lokal generiert
  final String name;       // Benutzer-Name, z.B. "Garten"
  final String apiHost;    // z.B. "meinserver.de"
  final String apiPath;    // z.B. "/api/data.php"
  final bool apiHttps;
  final bool active;
  final String apiUser;     // Basic-Auth Benutzername (leer = kein Auth)
  final String apiPassword; // Basic-Auth Passwort

  const Device({
	required this.id,
	required this.name,
	required this.apiHost,
	required this.apiPath,
	this.apiHttps = true,
	this.active = true,
	this.apiUser = '',
	this.apiPassword = '',
  });

  String get apiUrl =>
	  '${apiHttps ? 'https' : 'http'}://$apiHost$apiPath';

  String get historyUrl {
	final base = '${apiHttps ? 'https' : 'http'}://$apiHost';
	// Leitet history.php aus data.php-Pfad ab
	final histPath = apiPath.replaceFirst('data.php', 'history.php');
	return '$base$histPath';
  }

  Device copyWith({
	String? name,
	String? apiHost,
	String? apiPath,
	bool? apiHttps,
	bool? active,
	String? apiUser,
	String? apiPassword,
  }) =>
	  Device(
		id: id,
		name: name ?? this.name,
		apiHost: apiHost ?? this.apiHost,
		apiPath: apiPath ?? this.apiPath,
		apiHttps: apiHttps ?? this.apiHttps,
		active: active ?? this.active,
		apiUser: apiUser ?? this.apiUser,
		apiPassword: apiPassword ?? this.apiPassword,
	  );

  Map<String, dynamic> toJson() => {
		'id': id,
		'name': name,
		'apiHost': apiHost,
		'apiPath': apiPath,
		'apiHttps': apiHttps,
		'active': active,
		'apiUser': apiUser,
		'apiPassword': apiPassword,
	  };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
		id: json['id'] as String,
		name: json['name'] as String,
		apiHost: json['apiHost'] as String,
		apiPath: json['apiPath'] as String,
		apiHttps: json['apiHttps'] as bool? ?? true,
		active: json['active'] as bool? ?? true,
		apiUser: json['apiUser'] as String? ?? '',
		apiPassword: json['apiPassword'] as String? ?? '',
	  );

  /// Serialisiert eine Liste von Geräten für SharedPreferences.
  static String encodeList(List<Device> devices) =>
	  jsonEncode(devices.map((d) => d.toJson()).toList());

  static List<Device> decodeList(String raw) {
	final list = jsonDecode(raw) as List<dynamic>;
	return list.map((e) => Device.fromJson(e as Map<String, dynamic>)).toList();
  }
}
