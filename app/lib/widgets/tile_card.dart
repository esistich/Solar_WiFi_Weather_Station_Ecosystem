import 'package:flutter/material.dart';
import '../models/models.dart';

/// Kachel für ein einzelnes Gerät im Dashboard.
class TileCard extends StatelessWidget {
  final Device device;
  final Measurement? measurement;
  final bool loading;
  final String? error;
  final VoidCallback onTap;
  final VoidCallback onRefresh;

  const TileCard({
	super.key,
	required this.device,
	required this.measurement,
	required this.loading,
	required this.error,
	required this.onTap,
	required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
	final theme = Theme.of(context);
	final stale = measurement?.isStale ?? false;
	final borderColor = error != null
		? theme.colorScheme.error
		: stale
			? Colors.orange
			: theme.colorScheme.primary;

	return Card(
	  clipBehavior: Clip.antiAlias,
	  shape: RoundedRectangleBorder(
		borderRadius: BorderRadius.circular(16),
		side: BorderSide(color: borderColor, width: 1.5),
	  ),
	  child: InkWell(
		onTap: onTap,
		child: Padding(
		  padding: const EdgeInsets.all(16),
		  child: Column(
			crossAxisAlignment: CrossAxisAlignment.start,
			children: [
			  _Header(
				device: device,
				stale: stale,
				error: error,
				loading: loading,
				onRefresh: onRefresh,
			  ),
			  const SizedBox(height: 12),
			  if (loading && measurement == null)
				const Center(
				  child: Padding(
					padding: EdgeInsets.symmetric(vertical: 16),
					child: CircularProgressIndicator(),
				  ),
				)
			  else if (error != null && measurement == null)
				_ErrorBody(error: error!)
			  else if (measurement != null)
				_MeasurementBody(measurement: measurement!)
			  else
				const Text('Keine Daten'),
			],
		  ),
		),
	  ),
	);
  }
}

class _Header extends StatelessWidget {
  final Device device;
  final bool stale;
  final String? error;
  final bool loading;
  final VoidCallback onRefresh;

  const _Header({
	required this.device,
	required this.stale,
	required this.error,
	required this.loading,
	required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
	final theme = Theme.of(context);
	return Row(
	  children: [
		Icon(
		  Icons.wb_sunny_outlined,
		  color: theme.colorScheme.primary,
		  size: 22,
		),
		const SizedBox(width: 8),
		Expanded(
		  child: Text(
			device.name,
			style: theme.textTheme.titleMedium
				?.copyWith(fontWeight: FontWeight.bold),
			overflow: TextOverflow.ellipsis,
		  ),
		),
		if (stale)
		  const Tooltip(
			message: 'Daten veraltet (> 1 Stunde)',
			child: Icon(Icons.warning_amber, color: Colors.orange, size: 18),
		  ),
		if (error != null)
		  const Tooltip(
			message: 'Abruf fehlgeschlagen',
			child: Icon(Icons.cloud_off, color: Colors.red, size: 18),
		  ),
		if (loading)
		  const SizedBox(
			width: 18,
			height: 18,
			child: CircularProgressIndicator(strokeWidth: 2),
		  )
		else
		  IconButton(
			icon: const Icon(Icons.refresh, size: 18),
			onPressed: onRefresh,
			tooltip: 'Aktualisieren',
			padding: EdgeInsets.zero,
			constraints: const BoxConstraints(),
		  ),
	  ],
	);
  }
}

class _MeasurementBody extends StatelessWidget {
  final Measurement measurement;

  const _MeasurementBody({required this.measurement});

  @override
  Widget build(BuildContext context) {
	return Column(
	  children: [
		_TempRow(
		  icon: Icons.thermostat_outlined,
		  label: 'Aussen',
		  value: measurement.temperature,
		  color: _tempColor(measurement.temperature),
		),
		if (measurement.poolTemperature != null)
		  _TempRow(
			icon: Icons.pool_outlined,
			label: 'Wasser',
			value: measurement.poolTemperature!,
			color: _tempColor(measurement.poolTemperature!),
		  ),
		const SizedBox(height: 8),
		Row(
		  children: [
			const Icon(Icons.access_time, size: 13, color: Colors.grey),
			const SizedBox(width: 4),
			Text(
			  'Stand: ${measurement.timeShort} Uhr',
			  style: const TextStyle(fontSize: 12, color: Colors.grey),
			),
		  ],
		),
	  ],
	);
  }

  Color _tempColor(double t) {
	if (t <= 0) return Colors.blue;
	if (t <= 15) return Colors.teal;
	if (t <= 25) return Colors.green;
	if (t <= 32) return Colors.orange;
	return Colors.red;
  }
}

class _TempRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final Color color;

  const _TempRow({
	required this.icon,
	required this.label,
	required this.value,
	required this.color,
  });

  @override
  Widget build(BuildContext context) {
	return Padding(
	  padding: const EdgeInsets.symmetric(vertical: 3),
	  child: Row(
		children: [
		  Icon(icon, size: 16, color: color),
		  const SizedBox(width: 6),
		  Text(
			label,
			style: const TextStyle(fontSize: 13, color: Colors.grey),
		  ),
		  const Spacer(),
		  Text(
			'${value.toStringAsFixed(1)} °C',
			style: TextStyle(
			  fontSize: 16,
			  fontWeight: FontWeight.w600,
			  color: color,
			),
		  ),
		],
	  ),
	);
  }
}

class _ErrorBody extends StatelessWidget {
  final String error;
  const _ErrorBody({required this.error});

  @override
  Widget build(BuildContext context) {
	return Row(
	  children: [
		const Icon(Icons.error_outline, color: Colors.red, size: 16),
		const SizedBox(width: 8),
		Expanded(
		  child: Text(
			error,
			style: const TextStyle(fontSize: 12, color: Colors.red),
			maxLines: 2,
			overflow: TextOverflow.ellipsis,
		  ),
		),
	  ],
	);
  }
}
