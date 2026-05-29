/// Messwert-Datensatz von der API (data.php).
class Measurement {
  final double temperature;       // Außentemperatur
  final double? poolTemperature;  // Wassertemperatur (optional)
  final double? indoorTemperature;// Innentemperatur (optional, vom Display)
  final double humidity;
  final double pressure;
  final String createdAt;         // Lokalzeit-String aus API, z.B. "2024-07-01 14:23:00"
  final int dataAgeSeconds;       // Wie alt sind die Daten (API-Feld data_age_s)

  const Measurement({
	required this.temperature,
	this.poolTemperature,
	this.indoorTemperature,
	required this.humidity,
	required this.pressure,
	required this.createdAt,
	required this.dataAgeSeconds,
  });

  /// Daten gelten ab 2× Messintervall (Standard: 30 Min) als veraltet.
  bool get isStale => dataAgeSeconds > 3600;

  /// Formatierter Zeitstempel – nur HH:MM aus "YYYY-MM-DD HH:MM:SS".
  String get timeShort {
	if (createdAt.length >= 16) return createdAt.substring(11, 16);
	return createdAt;
  }

  factory Measurement.fromJson(Map<String, dynamic> json) => Measurement(
		temperature: _toDouble(json['temperature']),
		poolTemperature: json['pool_temperature'] != null
			? _toDouble(json['pool_temperature'])
			: null,
		indoorTemperature: json['indoor_temperature'] != null
			? _toDouble(json['indoor_temperature'])
			: null,
		humidity: _toDouble(json['humidity']),
		pressure: _toDouble(json['pressure']),
		createdAt: json['created_at'] as String? ?? '',
		dataAgeSeconds: (json['data_age_s'] as num?)?.toInt() ?? 0,
	  );

  static double _toDouble(dynamic v) {
	if (v == null) return 0.0;
	if (v is double) return v;
	if (v is int) return v.toDouble();
	return double.tryParse(v.toString()) ?? 0.0;
  }
}

/// Einzelner Messpunkt für den History-Chart.
class MeasurementPoint {
  final DateTime time;
  final double temperature;
  final double? poolTemperature;
  final double pressure;

  const MeasurementPoint({
	required this.time,
	required this.temperature,
	this.poolTemperature,
	required this.pressure,
  });

  factory MeasurementPoint.fromJson(Map<String, dynamic> json) {
	final raw = json['created_at'] as String? ?? '';
	return MeasurementPoint(
	  time: DateTime.tryParse(raw) ?? DateTime.now(),
	  temperature: Measurement._toDouble(json['temperature']),
	  poolTemperature: json['pool_temperature'] != null
		  ? Measurement._toDouble(json['pool_temperature'])
		  : null,
	  pressure: Measurement._toDouble(json['pressure']),
	);
  }
}
