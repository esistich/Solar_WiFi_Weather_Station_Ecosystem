import 'package:flutter/material.dart';

/// Hilfsfunktionen fuer Wetter-Icons, Farben, Gradienten und Zeitformatierung.
abstract final class WeatherUtils {
  
  // ── Zambretti → Icons (Mehrzahl) ──────────────────────────────────────────

  /// Analysiert den Text basierend auf den Translation_DE.h Strings.
  static List<IconData> iconsForZambretti(String zambretti) {
    final z = zambretti.toLowerCase();
    final List<IconData> icons = [];

    // 1. Sonne / Gutes Wetter
    if (z.contains('schön') || z.contains('gut') || z.contains('aufhellungen') || z.contains('klart')) {
      icons.add(Icons.wb_sunny_rounded);
    }

    // 2. Bewölkung / Veränderlich
    if (z.contains('veränderlich') || z.contains('wechselhaft') || z.contains('wechselnd') || z.contains('wolkig') || z.contains('bewölkt')) {
      icons.add(Icons.wb_cloudy_rounded);
    }

    // 3. Niederschlag (Regen/Schnee)
    if (z.contains('regen') || z.contains('schnee') || z.contains('schauer') || z.contains('nass') || z.contains('schauerhaft')) {
      icons.add(Icons.grain_rounded);
    }

    // 4. Sturm / Wind
    if (z.contains('stürmisch') || z.contains('sturm') || z.contains('unruhig')) {
      icons.add(Icons.air_rounded);
    }

    // 5. Sonderfall: Batterie
    if (z.contains('batterie') || z.contains('leer') || z.contains('nachladen')) {
      return [Icons.battery_alert_rounded];
    }

    // Fallback: Wenn gar nichts erkannt wurde (z.B. "Wetter wird gut")
    if (icons.isEmpty) {
      if (z.contains('gut')) return [Icons.wb_sunny_rounded];
      return [Icons.thermostat_rounded];
    }
    
    // Doppelte vermeiden und auf max 3 begrenzen
    return icons.toSet().toList().take(3).toList();
  }

  /// Liefert das primäre Icon für die Kachel.
  static IconData iconForZambretti(String zambretti) {
    final icons = iconsForZambretti(zambretti);
    return icons.isNotEmpty ? icons.first : Icons.thermostat_rounded;
  }

  // ── Zambretti → Gradient ────────────────────────────────────────────────────

  static LinearGradient gradientForZambretti(String zambretti) {
	final z = zambretti.toLowerCase();
    
    // Sturm / Schlecht
    if (z.contains('stürmisch') || z.contains('unruhig')) {
      return const LinearGradient(
		colors: [Color(0xFF37474F), Color(0xFF546E7A)],
		begin: Alignment.topLeft, end: Alignment.bottomRight,
	  );
    }
    
    // Regen
    if (z.contains('regen') || z.contains('schauer') || z.contains('schauerhaft')) {
      return const LinearGradient(
		colors: [Color(0xFF455A64), Color(0xFF78909C)],
		begin: Alignment.topLeft, end: Alignment.bottomRight,
	  );
    }

	if (z.contains('schön') || z.contains('gut') || z.contains('klar')) {
	  return const LinearGradient(
		colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
		begin: Alignment.topLeft, end: Alignment.bottomRight,
	  );
	}

	return const LinearGradient(
	  colors: [Color(0xFF37474F), Color(0xFF607D8B)],
	  begin: Alignment.topLeft, end: Alignment.bottomRight,
	);
  }

  static Color batteryColor(int pct) {
	if (pct >= 60) return const Color(0xFF66BB6A); // gruen
	if (pct >= 30) return const Color(0xFFFFA726); // orange
	return const Color(0xFFEF5350);                // rot
  }

  static String relativeTime(int ageSeconds) {
	if (ageSeconds < 60) return 'gerade eben';
	if (ageSeconds < 3600) {
	  final min = (ageSeconds / 60).round();
	  return 'vor $min Min.';
	}
	if (ageSeconds < 86400) {
	  final h = (ageSeconds / 3600).round();
	  return 'vor $h Std.';
	}
	final d = (ageSeconds / 86400).round();
	return 'vor $d Tag${d > 1 ? 'en' : ''}';
  }

  static const List<IconData> deviceIcons = [
	Icons.home_rounded,         // 0 Haus
	Icons.pool_rounded,         // 1 Pool
	Icons.yard_rounded,         // 2 Garten
	Icons.balcony_rounded,      // 3 Balkon
	Icons.roofing_rounded,      // 4 Dach
	Icons.garage_rounded,       // 5 Garage
	Icons.cabin_rounded,        // 6 Hütte
	Icons.wb_cloudy_rounded,    // 7 Allgemein
  ];

  static const List<String> deviceIconLabels = [
	'Haus', 'Pool', 'Garten', 'Balkon', 'Dach', 'Garage', 'Hütte', 'Allgemein',
  ];

  static IconData deviceIcon(int index) =>
	  deviceIcons[index.clamp(0, deviceIcons.length - 1)];

  // ── Icon-Farben ─────────────────────────────────────────────────────────────

  /// Liefert eine passende Farbe für ein Wetter-Icon.
  static Color colorForIcon(IconData icon) {
    if (icon == Icons.wb_sunny_rounded) return Colors.amber;
    if (icon == Icons.wb_cloudy_rounded) return Colors.white.withOpacity(0.9);
    if (icon == Icons.grain_rounded) return Colors.lightBlueAccent;
    if (icon == Icons.thunderstorm_rounded) return Colors.deepPurpleAccent;
    if (icon == Icons.ac_unit_rounded) return Colors.cyanAccent;
    if (icon == Icons.air_rounded) return Colors.blueGrey.shade100;
    if (icon == Icons.battery_alert_rounded) return Colors.redAccent;
    if (icon == Icons.trending_up_rounded) return Colors.orangeAccent;
    if (icon == Icons.trending_down_rounded) return Colors.lightBlue;
    
    return Colors.white70;
  }

  // ── Drucktrend ─────────────────────────────────────────────────────────────

  /// Liefert ein Icon passend zum Luftdrucktrend.
  static IconData trendIcon(String trend) {
    final t = trend.toLowerCase();
    if (t.contains('rasch steigend')) return Icons.keyboard_double_arrow_up;
    if (t.contains('langsam steigend')) return Icons.trending_up;
    if (t.contains('steigend')) return Icons.arrow_upward;
    
    if (t.contains('rasch fallend')) return Icons.keyboard_double_arrow_down;
    if (t.contains('langsam fallend')) return Icons.trending_down;
    if (t.contains('fallend')) return Icons.arrow_downward;
    
    // Icon für gleichbleibend / beständig
    return Icons.trending_flat;
  }

  /// Liefert eine Farbe passend zum Trend.
  static Color trendColor(String trend) {
    final t = trend.toLowerCase();
    if (t.contains('steigend')) return Colors.orange;
    if (t.contains('fallend')) return Colors.blue;
    // Deutlichere Farbe für Gleichbleibend
    return Colors.grey.shade700;
  }

  // ── Extra Sensoren ─────────────────────────────────────────────────────────

  /// Liefert Icon und Label für dynamische Sensoren.
  static (IconData, String) sensorInfo(String key) {
    final k = key.toLowerCase();
    if (k.contains('co2')) return (Icons.co2_rounded, 'CO2');
    if (k.contains('pm2') || k.contains('aqi')) return (Icons.air_rounded, 'Feinstaub');
    if (k.contains('voc')) return (Icons.gas_meter_rounded, 'VOC');
    if (k.contains('lux') || k.contains('hell')) return (Icons.light_mode_rounded, 'Helligkeit');
    if (k.contains('uv')) return (Icons.wb_sunny_rounded, 'UV-Index');
    
    return (Icons.sensors_rounded, key.toUpperCase());
  }

  /// Liefert die Einheit für dynamische Sensoren.
  static String sensorUnit(String key) {
    final k = key.toLowerCase();
    if (k.contains('co2')) return ' ppm';
    if (k.contains('pm2')) return ' µg/m³';
    if (k.contains('lux')) return ' lx';
    if (k.contains('prozent')) return ' %';
    
    return '';
  }
}
