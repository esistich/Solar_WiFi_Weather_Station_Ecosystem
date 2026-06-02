import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/device_provider.dart';
import 'weather_utils.dart';

/// Visuell aufgewertete Kachel fuer die Startseite.
class TileCard extends StatelessWidget {
  final Device device;
  final VoidCallback onTap;
  final VoidCallback onRefresh;

  const TileCard({
    super.key,
    required this.device,
    required this.onTap,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeviceProvider>();
    final measurement = provider.measurementFor(device.id);
    final loading = provider.isLoading(device.id);
    final error = provider.errorFor(device.id);
    final sparkline = provider.sparklineFor(device.id);

    final zambretti = measurement?.zambretti ?? '';
    final gradient = WeatherUtils.gradientForZambretti(zambretti);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(gradient: gradient),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(
                device: device,
                loading: loading,
                error: error,
                measurement: measurement,
                onRefresh: onRefresh,
              ),
              const SizedBox(height: 12),
              if (error != null)
                _ErrorRow(error: error)
              else if (measurement != null)
                _DataSection(measurement: measurement, sparkline: sparkline)
              else if (!loading)
                const Text(
                  'Keine Daten',
                  style: TextStyle(color: Colors.white70),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _CardHeader extends StatelessWidget {
  final Device device;
  final bool loading;
  final String? error;
  final Measurement? measurement;
  final VoidCallback onRefresh;

  const _CardHeader({
    required this.device,
    required this.loading,
    required this.error,
    required this.measurement,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final ageSeconds = measurement?.dataAgeSeconds;
    final relTime =
        ageSeconds != null ? WeatherUtils.relativeTime(ageSeconds) : null;
    final zambretti = measurement?.zambretti ?? '';
    final weatherIcon = WeatherUtils.iconForZambretti(zambretti);
    final deviceIcon = WeatherUtils.deviceIcon(device.iconIndex);

    return Row(
      children: [
        // Geraete-Avatar
        CircleAvatar(
          backgroundColor: Colors.white24,
          radius: 20,
          child: Icon(deviceIcon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (relTime != null)
                Text(
                  relTime,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
            ],
          ),
        ),
        // Wetter-Icon
        Icon(weatherIcon, color: Colors.white70, size: 28),
        const SizedBox(width: 4),
        // Status / Refresh
        if (loading)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white70,
            ),
          )
        else
          InkWell(
            onTap: onRefresh,
            borderRadius: BorderRadius.circular(16),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.refresh, color: Colors.white70, size: 20),
            ),
          ),
      ],
    );
  }
}

// ── Daten-Bereich ────────────────────────────────────────────────────────────

class _DataSection extends StatelessWidget {
  final Measurement measurement;
  final List<MeasurementPoint> sparkline;

  const _DataSection({required this.measurement, required this.sparkline});

  @override
  Widget build(BuildContext context) {
    final battery = measurement.batteryPct;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Grosse Temperaturanzeige
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${measurement.temperature.toStringAsFixed(1)} °C',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w300,
                height: 1.1,
              ),
            ),
            if (measurement.poolTemperature != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.pool, color: Colors.white60, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${measurement.poolTemperature!.toStringAsFixed(1)} °C',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            // Akku-Balken
            _BatteryBar(pct: battery),
          ],
        ),
        const Spacer(),
        // Mini-Sparkline
        if (sparkline.length > 3)
          _Sparkline(points: sparkline)
        else
          // Zusaetzliche Feuchte/Druck-Infos wenn keine Sparkline
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (measurement.humidity > 0)
                _InfoChip(
                  icon: Icons.water_drop_outlined,
                  value: '${measurement.humidity.toStringAsFixed(0)} %',
                ),
              if (measurement.relPressure > 0)
                _InfoChip(
                  icon: Icons.compress,
                  value: '${measurement.relPressure.toStringAsFixed(0)} hPa',
                ),
            ],
          ),
      ],
    );
  }
}

// ── Akku-Balken ──────────────────────────────────────────────────────────────

class _BatteryBar extends StatelessWidget {
  final int pct;
  const _BatteryBar({required this.pct});

  @override
  Widget build(BuildContext context) {
    final color = WeatherUtils.batteryColor(pct);
    return Row(
      children: [
        Icon(
          pct > 75
              ? Icons.battery_full
              : pct > 40
                  ? Icons.battery_4_bar
                  : Icons.battery_2_bar,
          color: color,
          size: 16,
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 80,
          height: 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct / 100.0,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$pct %',
          style: TextStyle(color: color, fontSize: 12),
        ),
      ],
    );
  }
}

// ── Mini-Sparkline ────────────────────────────────────────────────────────────

class _Sparkline extends StatelessWidget {
  final List<MeasurementPoint> points;
  const _Sparkline({required this.points});

  @override
  Widget build(BuildContext context) {
    final temps = points.map((p) => p.temperature).toList();
    final minT = temps.reduce((a, b) => a < b ? a : b);
    final maxT = temps.reduce((a, b) => a > b ? a : b);
    final spots = [
      for (var i = 0; i < temps.length; i++) FlSpot(i.toDouble(), temps[i]),
    ];

    return SizedBox(
      width: 90,
      height: 54,
      child: LineChart(
        LineChartData(
          minY: minT - 1,
          maxY: maxT + 1,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.white,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Info-Chip ────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String value;
  const _InfoChip({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white60, size: 14),
          const SizedBox(width: 4),
          Text(value, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

// ── Fehler ───────────────────────────────────────────────────────────────────

class _ErrorRow extends StatelessWidget {
  final String error;
  const _ErrorRow({required this.error});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.cloud_off, color: Colors.white70, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            error,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
