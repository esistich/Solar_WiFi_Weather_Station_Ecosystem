import 'package:flutter/material.dart';
import '../models/models.dart';
import 'weather_utils.dart';

/// Das Design des Widgets, das in ein Bild gerendert wird.
class WeatherWidgetDesign extends StatelessWidget {
  final Device device;
  final Measurement measurement;
  final bool showHumidity;
  final bool showPressure;

  const WeatherWidgetDesign({
    super.key,
    required this.device,
    required this.measurement,
    this.showHumidity = true,
    this.showPressure = false,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = WeatherUtils.gradientForZambretti(measurement.zambretti);
    final icons = WeatherUtils.iconsForZambretti(measurement.zambretti);

    return Container(
      width: 400, // Basis-Größe für das Rendering
      height: 200,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(32),
      ),
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          // Linke Seite: Große Temperatur
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold),
                  maxLines: 1,
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      measurement.temperature.toStringAsFixed(1),
                      style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w200),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 12, left: 4),
                      child: Text('°C', style: TextStyle(color: Colors.white70, fontSize: 24)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Rechte Seite: Icons und Zusatzwerte
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: icons.map((icon) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(icon, color: WeatherUtils.colorForIcon(icon), size: 36),
                  )).toList(),
                ),
                const SizedBox(height: 16),
                if (showHumidity)
                  _SmallInfo(icon: Icons.water_drop, value: '${measurement.humidity.toStringAsFixed(0)}%'),
                if (showPressure)
                  _SmallInfo(icon: Icons.compress, value: '${measurement.relPressure.toStringAsFixed(0)} hPa'),
                const Spacer(),
                Text(
                  'Stand: ${measurement.timeShort}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallInfo extends StatelessWidget {
  final IconData icon;
  final String value;
  const _SmallInfo({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white54, size: 14),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
