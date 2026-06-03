import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';

// ---------------------------------------------------------------------------
// Moderne Hilfsfunktionen
// ---------------------------------------------------------------------------

double _xInterval(int len) {
  if (len <= 6) return 1;
  return (len / 5).ceilToDouble();
}

Widget _timeLabel(double value, TitleMeta meta, List<MeasurementPoint> pts) {
  if (value < 0 || value >= pts.length) return const SizedBox.shrink();
  final t = pts[value.toInt()].time;
  return SideTitleWidget(
    axisSide: meta.axisSide,
    space: 8,
    child: Text(
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
      style: TextStyle(
        fontSize: 10,
        color: Colors.grey.shade600,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

Widget _valueLabel(double value, TitleMeta meta, String unit, bool isInt) {
  final text = isInt ? '${value.toInt()}$unit' : '${value.toStringAsFixed(1)}$unit';
  return SideTitleWidget(
    axisSide: meta.axisSide,
    space: 8,
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        color: Colors.grey.shade600,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
/// Generischer, modernisierter Linien-Chart mit Scroll-Unterstützung.
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
    if (points.isEmpty) return const Center(child: Text('Keine Daten verfügbar'));

    final sorted = [...points]..sort((a, b) => a.time.compareTo(b.time));
    final spots = sorted.asMap().entries.map((e) => FlSpot(e.key.toDouble(), getValue(e.value))).toList();

    final values = spots.map((s) => s.y).toList();
    final rawMin = values.reduce((a, b) => a < b ? a : b);
    final rawMax = values.reduce((a, b) => a > b ? a : b);
    final range = (rawMax - rawMin).abs();
    final pad = (range * 0.15).clamp(0.5, 5.0);
    
    final minY = (rawMin - pad);
    final maxY = (rawMax + pad);
    final yInterval = ((maxY - minY) / 3).clamp(0.1, 1000.0);

    // Dynamische Breite für horizontales Scrollen bei vielen Punkten
    final chartWidth = (sorted.length * 15.0).clamp(MediaQuery.of(context).size.width - 64, 2000.0);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        width: chartWidth,
        padding: const EdgeInsets.only(right: 20),
        child: LineChart(
          LineChartData(
            minY: minY,
            maxY: maxY,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: yInterval,
              getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              show: true,
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  interval: _xInterval(sorted.length),
                  getTitlesWidget: (v, m) => _timeLabel(v, m, sorted),
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: yInterval,
                  getTitlesWidget: (v, m) => _valueLabel(v, m, unit, intValues),
                  reservedSize: 42,
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => Colors.blueGrey.shade900,
                getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                  final idx = s.x.toInt();
                  final t = sorted[idx].time;
                  final val = intValues ? '${s.y.toInt()}$unit' : '${s.y.toStringAsFixed(1)}$unit';
                  return LineTooltipItem('$val\n${t.hour}:${t.minute.toString().padLeft(2, '0')}', const TextStyle(color: Colors.white));
                }).toList(),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: color,
                barWidth: 3,
                belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [color.withOpacity(0.2), color.withOpacity(0)])),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
/// Kombinierter Temperatur-Chart: Aussen & Wasser.
// ---------------------------------------------------------------------------
class HistoryChart extends StatelessWidget {
  final List<MeasurementPoint> points;

  const HistoryChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    final sorted = [...points]..sort((a, b) => a.time.compareTo(b.time));
    final hasPool = sorted.any((p) => p.poolTemperature != null);

    final outsideSpots = sorted.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.temperature)).toList();
    final poolSpots = hasPool
        ? sorted.asMap().entries
            .where((e) => e.value.poolTemperature != null)
            .map((e) => FlSpot(e.key.toDouble(), e.value.poolTemperature!))
            .toList()
        : <FlSpot>[];

    final allValues = [
      ...outsideSpots.map((s) => s.y),
      ...poolSpots.map((s) => s.y),
    ];
    final minY = (allValues.reduce((a, b) => a < b ? a : b) - 1.5).floorToDouble();
    final maxY = (allValues.reduce((a, b) => a > b ? a : b) + 1.5).ceilToDouble();

    final chartWidth = (sorted.length * 15.0).clamp(MediaQuery.of(context).size.width - 64, 2000.0);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        width: chartWidth,
        padding: const EdgeInsets.only(right: 20),
        child: Column(
          children: [
            _ChartLegend(hasPool: hasPool),
            const SizedBox(height: 16),
            Expanded(
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 2, getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.withOpacity(0.08))),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: _xInterval(sorted.length),
                        getTitlesWidget: (v, m) => _timeLabel(v, m, sorted),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 2,
                        getTitlesWidget: (v, m) => _valueLabel(v, m, '°', false),
                        reservedSize: 36,
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => Colors.blueGrey.shade900,
                      getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                        final isOutside = s.barIndex == 0;
                        return LineTooltipItem('${isOutside ? "Aussen" : "Wasser"}: ${s.y.toStringAsFixed(1)} °C', TextStyle(color: isOutside ? Colors.orange : Colors.blue, fontWeight: FontWeight.bold));
                      }).toList(),
                    ),
                  ),
                  lineBarsData: [
                    _buildBar(outsideSpots, Colors.orange),
                    if (hasPool) _buildBar(poolSpots, Colors.blue),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  LineChartBarData _buildBar(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.35,
      color: color,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [color.withOpacity(0.15), color.withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  final bool hasPool;
  const _ChartLegend({required this.hasPool});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LegendItem(color: Colors.orange, label: 'Aussen'),
        if (hasPool) ...[
          const SizedBox(width: 24),
          _LegendItem(color: Colors.blue, label: 'Wasser'),
        ],
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
