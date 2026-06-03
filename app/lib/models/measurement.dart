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
  
  /// Zusätzliche Sensordaten (z.B. Luftqualität, CO2, PM2.5), 
  /// die dynamisch von der API kommen können.
  final Map<String, double> extraSensors;

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
    this.extraSensors = const {},
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
    
    // Bekannte Felder sammeln, um den Rest als "Extras" zu identifizieren
    final knownKeys = {
      'temperature', 'pool_temperature', 'humidity', 'rel_pressure', 
      'abs_pressure', 'pressure_state', 'zambretti', 'zambretti_text',
      'trend', 'trend_text', 'battery_pct', 'battery_volt', 
      'wifi_strength', 'created_at', 'data_age_s'
    };

    final extras = <String, double>{};
    json.forEach((key, value) {
      if (!knownKeys.contains(key) && value is num) {
        extras[key] = value.toDouble();
      }
    });

	return Measurement(
	  temperature:   _toDouble(json['temperature']),
	  poolTemperature: (poolRaw != null && poolRaw > -50) ? poolRaw : null,
	  humidity:      _toDouble(json['humidity']),
	  relPressure:   _toDouble(json['rel_pressure']),
	  absPressure:   _toDouble(json['abs_pressure']),
	  pressureState: _toStr(json['pressure_state']) ?? '',
	  zambretti:     _toStr(json['zambretti_text']) ?? _toStr(json['zambretti']) ?? '',
	  trend:         _toStr(json['trend_text']) ?? '',
	  batteryPct:    (json['battery_pct']   as num?)?.toInt() ?? 0,
	  batteryVolt:   _toDouble(json['battery_volt']),
	  wifiStrength:  (json['wifi_strength'] as num?)?.toInt() ?? 0,
	  createdAt:     _toStr(json['created_at']) ?? '',
	  dataAgeSeconds:(json['data_age_s']    as num?)?.toInt() ?? 0,
      extraSensors:  extras,
	);
  }

  static double _toDouble(dynamic v) {
	if (v == null) return 0.0;
	if (v is double) return v;
	if (v is int) return v.toDouble();
	return double.tryParse(v.toString()) ?? 0.0;
  }

  static String? _toStr(dynamic v) {
	if (v == null) return null;
	if (v is String) return v.isEmpty ? null : v;
	return v.toString();
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
  final Map<String, double> extraSensors;

  const MeasurementPoint({
	required this.time,
	required this.temperature,
	this.poolTemperature,
	required this.relPressure,
	required this.humidity,
	required this.batteryPct,
    this.extraSensors = const {},
  });

  factory MeasurementPoint.fromJson(Map<String, dynamic> json) {
	final raw = json['created_at'] as String? ?? '';
	final poolRaw = json['pool_temperature'] != null
		? Measurement._toDouble(json['pool_temperature'])
		: null;
        
    final knownKeys = {
      'temperature', 'pool_temperature', 'humidity', 'rel_pressure', 
      'abs_pressure', 'battery_pct', 'created_at'
    };

    final extras = <String, double>{};
    json.forEach((key, value) {
      if (!knownKeys.contains(key) && value is num) {
        extras[key] = value.toDouble();
      }
    });

	return MeasurementPoint(
	  time:           DateTime.tryParse(raw) ?? DateTime.now(),
	  temperature:    Measurement._toDouble(json['temperature']),
	  poolTemperature:(poolRaw != null && poolRaw > -50) ? poolRaw : null,
	  relPressure:    Measurement._toDouble(json['rel_pressure']),
	  humidity:       Measurement._toDouble(json['humidity']),
	  batteryPct:     (json['battery_pct'] as num?)?.toInt() ?? 0,
      extraSensors:   extras,
	);
  }
}
