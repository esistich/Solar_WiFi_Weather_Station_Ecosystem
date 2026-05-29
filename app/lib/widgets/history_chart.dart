import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';

/// Temperatur-Verlaufschart für einen Zeitraum.
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

	final outsideSpots = _toSpots((p) => p.temperature);
	final poolSpots = showPool
		? _toSpots((p) => p.poolTemperature ?? double.nan)
		: <FlSpot>[];

	final allValues = [
	  ...outsideSpots.map((s) => s.y),
	  if (showPool) ...poolSpots.where((s) => !s.y.isNaN).map((s) => s.y),
	];
	final minY = (allValues.reduce((a, b) => a < b ? a : b) - 2).floorToDouble();
	final maxY = (allValues.reduce((a, b) => a > b ? a : b) + 2).ceilToDouble();

	return LineChart(
	  LineChartData(
		minY: minY,
		maxY: maxY,
		titlesData: FlTitlesData(
		  bottomTitles: AxisTitles(
			sideTitles: SideTitles(
			  showTitles: true,
			  reservedSize: 28,
			  interval: _xInterval(),
			  getTitlesWidget: (value, meta) {
				final idx = value.toInt().clamp(0, points.length - 1);
				final t = points[idx].time;
				return Padding(
				  padding: const EdgeInsets.only(top: 4),
				  child: Text(
					'${t.hour.toString().padLeft(2, '0')}:'
					'${t.minute.toString().padLeft(2, '0')}',
					style: const TextStyle(fontSize: 10),
				  ),
				);
			  },
			),
		  ),
		  leftTitles: AxisTitles(
			sideTitles: SideTitles(
			  showTitles: true,
			  reservedSize: 36,
			  getTitlesWidget: (value, meta) => Text(
				'${value.toInt()}°',
				style: const TextStyle(fontSize: 10),
			  ),
			),
		  ),
		  topTitles: const AxisTitles(
			sideTitles: SideTitles(showTitles: false),
		  ),
		  rightTitles: const AxisTitles(
			sideTitles: SideTitles(showTitles: false),
		  ),
		),
		gridData: FlGridData(
		  drawHorizontalLine: true,
		  drawVerticalLine: false,
		  horizontalInterval: 5,
		  getDrawingHorizontalLine: (v) => FlLine(
			color: Colors.grey.withOpacity(0.15),
			strokeWidth: 1,
		  ),
		),
		borderData: FlBorderData(show: false),
		lineBarsData: [
		  _line(outsideSpots, Colors.orange, 'Aussen'),
		  if (showPool && poolSpots.isNotEmpty)
			_line(
			  poolSpots.where((s) => !s.y.isNaN).toList(),
			  Colors.blue,
			  'Wasser',
			),
		],
		lineTouchData: LineTouchData(
		  touchTooltipData: LineTouchTooltipData(
			getTooltipItems: (spots) => spots.map((s) {
			  final idx = s.x.toInt().clamp(0, points.length - 1);
			  final t = points[idx].time;
			  return LineTooltipItem(
				'${s.y.toStringAsFixed(1)}°C\n'
				'${t.hour.toString().padLeft(2, '0')}:'
				'${t.minute.toString().padLeft(2, '0')}',
				const TextStyle(fontSize: 11),
			  );
			}).toList(),
		  ),
		),
	  ),
	);
  }

  List<FlSpot> _toSpots(double Function(MeasurementPoint) getValue) {
	return [
	  for (var i = 0; i < points.length; i++)
		FlSpot(i.toDouble(), getValue(points[i])),
	];
  }

  double _xInterval() {
	if (points.length <= 6) return 1;
	return (points.length / 6).ceilToDouble();
  }

  LineChartBarData _line(List<FlSpot> spots, Color color, String label) =>
	  LineChartBarData(
		spots: spots,
		isCurved: true,
		color: color,
		barWidth: 2,
		dotData: const FlDotData(show: false),
		belowBarData: BarAreaData(
		  show: true,
		  color: color.withOpacity(0.08),
		),
	  );
}
