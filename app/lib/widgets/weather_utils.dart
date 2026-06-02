import 'package:flutter/material.dart';

/// Hilfsfunktionen fuer Wetter-Icons, Farben, Gradienten und Zeitformatierung.
abstract final class WeatherUtils {
  // ── Zambretti → Icon ────────────────────────────────────────────────────────

  static IconData iconForZambretti(String zambretti) {
	final z = zambretti.toLowerCase();
	if (z.contains('sonnig') || z.contains('heiter') || z.contains('klar')) {
	  return Icons.wb_sunny_rounded;
	}
	if (z.contains('wolkig') || z.contains('bewölkt') || z.contains('bedeckt')) {
	  return Icons.wb_cloudy_rounded;
	}
	if (z.contains('regen') || z.contains('schauer') || z.contains('nass')) {
	  return Icons.grain_rounded;
	}
	if (z.contains('gewitter') || z.contains('sturm')) {
	  return Icons.thunderstorm_rounded;
	}
	if (z.contains('schnee') || z.contains('frost')) {
	  return Icons.ac_unit_rounded;
	}
	if (z.contains('nebel') || z.contains('dunst')) {
	  return Icons.blur_on_rounded;
	}
	return Icons.thermostat_rounded;
  }

  // ── Zambretti → Gradient ────────────────────────────────────────────────────

  static LinearGradient gradientForZambretti(String zambretti) {
	final z = zambretti.toLowerCase();
	if (z.contains('sonnig') || z.contains('heiter') || z.contains('klar')) {
	  return const LinearGradient(
		colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
		begin: Alignment.topLeft,
		end: Alignment.bottomRight,
	  );
	}
	if (z.contains('gewitter') || z.contains('sturm')) {
	  return const LinearGradient(
		colors: [Color(0xFF37474F), Color(0xFF546E7A)],
		begin: Alignment.topLeft,
		end: Alignment.bottomRight,
	  );
	}
	if (z.contains('regen') || z.contains('schauer')) {
	  return const LinearGradient(
		colors: [Color(0xFF455A64), Color(0xFF78909C)],
		begin: Alignment.topLeft,
		end: Alignment.bottomRight,
	  );
	}
	if (z.contains('schnee') || z.contains('frost')) {
	  return const LinearGradient(
		colors: [Color(0xFF546E7A), Color(0xFF90A4AE)],
		begin: Alignment.topLeft,
		end: Alignment.bottomRight,
	  );
	}
	if (z.contains('wolkig') || z.contains('bewölkt') || z.contains('bedeckt')) {
	  return const LinearGradient(
		colors: [Color(0xFF546E7A), Color(0xFF78909C)],
		begin: Alignment.topLeft,
		end: Alignment.bottomRight,
	  );
	}
	// Standard: neutrales Blaugrau
	return const LinearGradient(
	  colors: [Color(0xFF37474F), Color(0xFF607D8B)],
	  begin: Alignment.topLeft,
	  end: Alignment.bottomRight,
	);
  }

  // ── Akku-Farbe ──────────────────────────────────────────────────────────────

  static Color batteryColor(int pct) {
	if (pct >= 60) return const Color(0xFF66BB6A); // gruen
	if (pct >= 30) return const Color(0xFFFFA726); // orange
	return const Color(0xFFEF5350);                // rot
  }

  // ── Relative Zeit ───────────────────────────────────────────────────────────

  /// Gibt "vor X Min." / "vor X Std." / "gerade eben" zurück.
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

  // ── Geräte-Avatare ──────────────────────────────────────────────────────────

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
}
