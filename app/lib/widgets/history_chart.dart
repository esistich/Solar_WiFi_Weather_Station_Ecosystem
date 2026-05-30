import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';

// ---------------------------------------------------------------------------
// Hilfsfunktionen (geteilt)
// ---------------------------------------------------------------------------

double _xInterval(int len) {
  // Max. ~6 Labels auf der X-Achse
  if (len <= 6) return 1;
  return (len / 6).ceilToDouble();
}

Widget _timeLabel(double value, TitleMeta meta, List<MeasurementPoint> pts) {
  // min/max-Werte werden von fl_chart extra gerendert und überlagern sich –
  // diese einfach leer lassen
  if (value == meta.min || value == meta.max) return const SizedBox.shrink();
  final idx = value.toInt().clamp(0, pts.length - 1);
  final t = pts[idx].time;
  return SideTitleWidget(
    axisSide: meta.axisSide,
    space: 4,
    child: Text(
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
      style: const TextStyle(fontSize: 10),
    ),
  );
}

Widget _valueLabel(
  double value,
  TitleMeta meta,
  String unit,
  bool isInt,
) {
  if (value == meta.min || value == meta.max) return const SizedBox.shrink();
  final text = isInt ? '${value.toInt()}$unit' : '${value.toStringAsFixed(1)}$unit';
  return SideTitleWidget(
    axisSide: meta.axisSide,
    space: 4,
    child: Text(text, style: const TextStyle(fontSize: 10)),
  );
}

LineChartBarData _lineBar(List<FlSpot> spots, Color color) => LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 2,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: true, color: color.withOpacity(0.08)),
    );

FlGridData _grid(double interval) => FlGridData(
      drawHorizontalLine: true,
      drawVerticalLine: false,
      horizontalInterval: interval,
      getDrawingHorizontalLine: (_) =>
          FlLine(color: Colors.grey.withOpacity(0.15), strokeWidth: 1),
    );

// ---------------------------------------------------------------------------
/// Generischer Linien-Chart fuer einen einzelnen Messwert.
// ---------------------------------------------------------------------------
class MetricChart extends StatelessWidget {
  final List<MeasurementPoint> points;
  final String unit;
  final Color color;
  final double Function(MeasurementPoint) getValue;
  final bool intValues;

  const MetricChart({
    super.key,
    required this.points,
    required this.unit,
    required this.color,
    required this.getValue,
    this.intValues = false,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(child: Text('Keine Verlaufsdaten'));
    }

    // Chronologisch sortieren (aelteste zuerst = links im Chart)
    final sorted = [...points]..sort((a, b) => a.time.compareTo(b.time));

    final spots = [
      for (var i = 0; i < sorted.length; i++)
        FlSpot(i.toDouble(), getValue(sorted[i])),
    ];
    final values = spots.map((s) => s.y).toList();
    final raw_min = values.reduce((a, b) => a < b ? a : b);
    final raw_max = values.reduce((a, b) => a > b ? a : b);
    final range   = (raw_max - raw_min).clamp(1.0, double.infinity);
    final pad     = (range * 0.1).clamp(1.0, 10.0).ceilToDouble();
    final minY    = (raw_min - pad).floorToDouble();
    final maxY    = (raw_max + pad).ceilToDouble();
    final yInterval = ((maxY - minY) / 4).ceilToDouble().clamp(1.0, 9999.0);

    // reservedSize dynamisch: breitestes Label bestimmt den Platz
    final widestLabel = intValues
        ? '${raw_max.toInt()}$unit'
        : '${raw_max.toStringAsFixed(1)}$unit';
    final reservedLeft = (widestLabel.length * 7.0).clamp(40.0, 80.0);

    return LineChart(LineChartData(
      minY: minY,
      maxY: maxY,
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: _xInterval(sorted.length),
            getTitlesWidget: (v, m) => _timeLabel(v, m, sorted),
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: reservedLeft,
            interval: yInterval,
            getTitlesWidget: (v, m) => _valueLabel(v, m, unit, intValues),
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: _grid(yInterval),
      borderData: FlBorderData(show: false),
      lineBarsData: [_lineBar(spots, color)],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
            final idx = s.x.toInt().clamp(0, sorted.length - 1);
            final t = sorted[idx].time;
            final val = intValues
                ? '${s.y.toInt()}$unit'
                : '${s.y.toStringAsFixed(1)}$unit';
            return LineTooltipItem(
              '$val\n'
              '${t.hour.toString().padLeft(2, '0')}:'
              '${t.minute.toString().padLeft(2, '0')}',
              const TextStyle(fontSize: 11),
            );
          }).toList(),
        ),
      ),
    ));
  }
}

// ---------------------------------------------------------------------------
/// Temperatur-Chart: Aussen (BME280) + optional Wasser (DS18B20).
// ---------------------------------------------------------------------------
class HistoryChart extends StatelessWidget {
  final List<MeasurementPoint> points;
  final bool showPool;

  const HistoryChart({
    super.key,
    required this.points,
    this.showPool = true,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(child: Text('Keine Verlaufsdaten'));
    }

    final sorted  = [...points]..sort((a, b) => a.time.compareTo(b.time));
    final hasPool = showPool && sorted.any((p) => p.poolTemperature != null);

    final outsideSpots = [
      for (var i = 0; i < sorted.length; i++)
        FlSpot(i.toDouble(), sorted[i].temperature),
    ];
    final poolSpots = hasPool
        ? [
            for (var i = 0; i < sorted.length; i++)
              FlSpot(i.toDouble(), sorted[i].poolTemperature ?? double.nan),
          ]
        : <FlSpot>[];

    final allValues = [
      ...outsideSpots.map((s) => s.y),
      if (hasPool) ...poolSpots.where((s) => !s.y.isNaN).map((s) => s.y),
    ];
    final minY = (allValues.reduce((a, b) => a < b ? a : b) - 2).floorToDouble();
    final maxY = (allValues.reduce((a, b) => a > b ? a : b) + 2).ceilToDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legende
        Row(children: [
          _dot(Colors.orange),
          const SizedBox(width: 4),
          const Text('Aussen (BME280)', style: TextStyle(fontSize: 11)),
          if (hasPool) ...[
            const SizedBox(width: 16),
            _dot(Colors.blue),
            const SizedBox(width: 4),
            const Text('Wasser (DS18B20)', style: TextStyle(fontSize: 11)),
          ],
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: LineChart(LineChartData(
            minY: minY,
            maxY: maxY,
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: _xInterval(sorted.length),
                  getTitlesWidget: (v, m) => _timeLabel(v, m, sorted),
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  interval: 2,
                  getTitlesWidget: (v, m) => _valueLabel(v, m, '°', false),
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: _grid(2.0),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              _lineBar(outsideSpots, Colors.orange),
              if (hasPool && poolSpots.isNotEmpty)
                _lineBar(poolSpots.where((s) => !s.y.isNaN).toList(), Colors.blue),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                  final idx   = s.x.toInt().clamp(0, sorted.length - 1);
                  final t     = sorted[idx].time;
                  final label = s.barIndex == 0 ? 'Aussen' : 'Wasser';
                  return LineTooltipItem(
                    '$label: ${s.y.toStringAsFixed(1)} °C\n'
                    '${t.hour.toString().padLeft(2, '0')}:'
                    '${t.minute.toString().padLeft(2, '0')}',
                    const TextStyle(fontSize: 11),
                  );
                }).toList(),
              ),
            ),
          )),
        ),
      ],
    );
  }

  Widget _dot(Color color) => Container(
        width: 12, height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

