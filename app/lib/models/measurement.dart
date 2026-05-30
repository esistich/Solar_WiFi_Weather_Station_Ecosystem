/// Messwert-Datensatz von der API (data.php).
class Measurement {
  final double temperature;      // Außentemperatur (BME280)
  final double? poolTemperature; // Wassertemperatur DS18B20 (null wenn Sensor fehlt)
  final double humidity;         // Relative Luftfeuchte BME280 in %
  final double relPressure;      // Relativer Luftdruck in hPa (rel_pressure)
  final double absPressure;      // Absoluter Luftdruck in hPa (abs_pressure)
  final String pressureState;    // Zustandstext z.B. "Kräftiges Hoch"
  final String zambretti;        // Wettervorhersage
  final String trend;            // Drucktrend z.B. "langsam fallend"
  final int batteryPct;          // Akkustand in %
  final double batteryVolt;      // Akkuspannung in V
  final int wifiStrength;        // WLAN-Signalstärke in dBm
  final String createdAt;        // Lokalzeit-String aus API, z.B. "2024-07-01 14:23:00"
  final int dataAgeSeconds;      // Wie alt sind die Daten (API-Feld data_age_s)

  const Measurement({
	required this.temperature,
	this.poolTemperature,
	required this.humidity,
	required this.relPressure,
	required this.absPressure,
	required this.pressureState,
	required this.zambretti,
	required this.trend,
	required this.batteryPct,
	required this.batteryVolt,
	required this.wifiStrength,
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

  factory Measurement.fromJson(Map<String, dynamic> json) {
	final poolRaw = json['pool_temperature'] != null
		? _toDouble(json['pool_temperature'])
		: null;
	return Measurement(
	  temperature:   _toDouble(json['temperature']),
	  // DS18B20 liefert -87 als Fehlerwert – dann kein Pool-Wert anzeigen
	  poolTemperature: (poolRaw != null && poolRaw > -50) ? poolRaw : null,
	  humidity:      _toDouble(json['humidity']),
	  relPressure:   _toDouble(json['rel_pressure']),
	  absPressure:   _toDouble(json['abs_pressure']),
	  pressureState: json['pressure_state'] as String? ?? '',
	  zambretti:     json['zambretti']      as String? ?? '',
	  trend:         json['trend']          as String? ?? '',
	  batteryPct:    (json['battery_pct']   as num?)?.toInt() ?? 0,
	  batteryVolt:   _toDouble(json['battery_volt']),
	  wifiStrength:  (json['wifi_strength'] as num?)?.toInt() ?? 0,
	  createdAt:     json['created_at']     as String? ?? '',
	  dataAgeSeconds:(json['data_age_s']    as num?)?.toInt() ?? 0,
	);
  }

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
  final double relPressure;
  final double humidity;
  final int batteryPct;

  const MeasurementPoint({
	required this.time,
	required this.temperature,
	this.poolTemperature,
	required this.relPressure,
	required this.humidity,
	required this.batteryPct,
  });

  factory MeasurementPoint.fromJson(Map<String, dynamic> json) {
	final raw = json['created_at'] as String? ?? '';
	final poolRaw = json['pool_temperature'] != null
		? Measurement._toDouble(json['pool_temperature'])
		: null;
	return MeasurementPoint(
	  time:           DateTime.tryParse(raw) ?? DateTime.now(),
	  temperature:    Measurement._toDouble(json['temperature']),
	  poolTemperature:(poolRaw != null && poolRaw > -50) ? poolRaw : null,
	  relPressure:    Measurement._toDouble(json['rel_pressure']),
	  humidity:       Measurement._toDouble(json['humidity']),
	  batteryPct:     (json['battery_pct'] as num?)?.toInt() ?? 0,
	);
  }
}
