import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/models.dart';
import '../services/device_provider.dart';
import 'weather_utils.dart';

/// Eine modernisierte, animierte Kachel für das Dashboard.
class TileCard extends StatelessWidget {
  final Device device;
  final VoidCallback onTap;
  final VoidCallback onRefresh;
  final bool isSelected;

  const TileCard({
    super.key,
    required this.device,
    required this.onTap,
    required this.onRefresh,
    this.isSelected = false,
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
      elevation: isSelected ? 8 : 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: isSelected 
          ? BorderSide(color: Colors.white.withOpacity(0.5), width: 2)
          : BorderSide.none,
      ),
      // Nutze Ink im Container für den Gradient-Effekt
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: 600.ms,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
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
              const SizedBox(height: 16),
              if (error != null)
                _ErrorRow(error: error)
              else if (measurement != null)
                _DataSection(measurement: measurement, sparkline: sparkline)
              else if (!loading)
                const Text(
                  'Keine Daten verfügbar',
                  style: TextStyle(color: Colors.white70),
                ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }
}

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
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(deviceIcon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                [
                  if (relTime != null) relTime,
                  if (zambretti.isNotEmpty) zambretti,
                ].join(' • '),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Icon(weatherIcon, color: WeatherUtils.colorForIcon(weatherIcon), size: 32)
            .animate(onPlay: (c) => c.repeat())
            .shimmer(delay: 2.seconds, duration: 1.5.seconds),
        const SizedBox(width: 8),
        _RefreshButton(loading: loading, onRefresh: onRefresh),
      ],
    );
  }
}

class _RefreshButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onRefresh;

  const _RefreshButton({required this.loading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white,
        ),
      );
    }
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
      onPressed: () {
        HapticFeedback.mediumImpact();
        onRefresh();
      },
    );
  }
}

class _DataSection extends StatelessWidget {
  final Measurement measurement;
  final List<MeasurementPoint> sparkline;

  const _DataSection({required this.measurement, required this.sparkline});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  measurement.temperature.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.w200,
                    height: 1,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4, left: 2),
                  child: Text(
                    '°C',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
            if (measurement.poolTemperature != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.pool, color: Colors.white70, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '${measurement.poolTemperature!.toStringAsFixed(1)} °C Pool',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            _BatteryIndicator(pct: measurement.batteryPct),
          ],
        ),
        const Spacer(),
        if (sparkline.length > 5)
          _MiniChart(points: sparkline)
        else
          _SecondaryInfo(measurement: measurement),
      ],
    );
  }
}

class _BatteryIndicator extends StatelessWidget {
  final int pct;
  const _BatteryIndicator({required this.pct});

  @override
  Widget build(BuildContext context) {
    final color = WeatherUtils.batteryColor(pct);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pct > 80 ? Icons.battery_full : Icons.battery_charging_full,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            '$pct%',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChart extends StatelessWidget {
  final List<MeasurementPoint> points;
  const _MiniChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final temps = points.map((p) => p.temperature).toList();
    final minT = temps.reduce((a, b) => a < b ? a : b);
    final maxT = temps.reduce((a, b) => a > b ? a : b);

    return SizedBox(
      width: 100,
      height: 50,
      child: LineChart(
        LineChartData(
          minY: minT - 0.5,
          maxY: maxT + 0.5,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: points.asMap().entries.map((e) {
                return FlSpot(e.key.toDouble(), e.value.temperature);
              }).toList(),
              isCurved: true,
              curveSmoothness: 0.4,
              color: Colors.white,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.3),
                    Colors.white.withOpacity(0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryInfo extends StatelessWidget {
  final Measurement measurement;
  const _SecondaryInfo({required this.measurement});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _InfoLabel(
          icon: Icons.water_drop,
          label: '${measurement.humidity.toStringAsFixed(0)}%',
        ),
        const SizedBox(height: 4),
        _InfoLabel(
          icon: Icons.compress,
          label: '${measurement.relPressure.toStringAsFixed(0)} hPa',
        ),
      ],
    );
  }
}

class _InfoLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white60, size: 14),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ],
    );
  }
}

class _ErrorRow extends StatelessWidget {
  final String error;
  const _ErrorRow({required this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
