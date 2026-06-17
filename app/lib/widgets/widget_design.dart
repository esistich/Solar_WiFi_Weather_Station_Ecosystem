import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import 'weather_utils.dart';

class WeatherWidgetDesign extends StatelessWidget {
  final Device device;
  final Measurement measurement;
  final List<String> selectedMetrics;

  const WeatherWidgetDesign({
    super.key,
    required this.device,
    required this.measurement,
    required this.selectedMetrics,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = WeatherUtils.gradientForZambretti(measurement.zambretti);
    final icons = WeatherUtils.iconsForZambretti(measurement.zambretti);
    final currentTime = DateFormat('HH:mm').format(DateTime.now());

    return Container(
      width: 400,
      height: 200,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.all(20),
      child: Stack(
        children: [
          // Aktuelle Uhrzeit oben rechts
          Positioned(
            right: 0,
            top: 0,
            child: Text(
              currentTime,
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          
          Row(
            children: [
              // Links: Station & Haupt-Temperatur
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          measurement.temperature.toStringAsFixed(1),
                          style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w200, height: 1),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 8, left: 2),
                          child: Text('°C', style: TextStyle(color: Colors.white70, fontSize: 20)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Wetter-Icons & Kurzer Text
                    Row(
                      children: [
                        ...icons.take(2).map((icon) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(icon, color: WeatherUtils.colorForIcon(icon), size: 24),
                        )),
                        Expanded(
                          child: Text(
                            measurement.zambretti,
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const VerticalDivider(color: Colors.white12, indent: 20, endIndent: 20, width: 32),

              // Rechts: Gewählte Zusatzwerte
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: selectedMetrics.map((key) => _buildMetricRow(key)).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String key) {
    final info = WeatherUtils.sensorInfo(key);
    final unit = WeatherUtils.sensorUnit(key);
    double value = 0;
    
    // Wert ermitteln
    if (key == 'humidity') value = measurement.humidity;
    else if (key == 'rel_pressure') value = measurement.relPressure;
    else if (key == 'battery_pct') value = measurement.batteryPct.toDouble();
    else if (key == 'pool_temperature') value = measurement.poolTemperature ?? 0;
    else if (key == 'wifi_strength') value = measurement.wifiStrength.toDouble();
    else value = measurement.extraSensors[key] ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(info.$1, color: Colors.white54, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${value.toStringAsFixed(key.contains('pressure') ? 0 : 1)}$unit',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
