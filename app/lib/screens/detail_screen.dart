import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/services.dart';
import '../widgets/widgets.dart';

/// Detail-Ansicht eines Geräts: aktuelle Werte + History-Chart.
class DetailScreen extends StatefulWidget {
  final Device device;

  const DetailScreen({super.key, required this.device});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  List<MeasurementPoint> _history = [];
  bool _loadingHistory = false;
  String? _historyError;
  int _selectedHours = 24;
  late final ApiService _api;

  @override
  void initState() {
	super.initState();
	_api = ApiService();
	_loadHistory();
  }

  @override
  void dispose() {
	_api.dispose();
	super.dispose();
  }

  Future<void> _loadHistory() async {
	setState(() {
	  _loadingHistory = true;
	  _historyError = null;
	});
	try {
	  final data = await _api.fetchHistory(
		widget.device,
		hours: _selectedHours,
	  );
	  setState(() => _history = data);
	} catch (e) {
	  setState(() => _historyError = e.toString());
	} finally {
	  setState(() => _loadingHistory = false);
	}
  }

  @override
  Widget build(BuildContext context) {
	final provider = context.watch<DeviceProvider>();
	final measurement = provider.measurementFor(widget.device.id);
	final loading = provider.isLoading(widget.device.id);

	return Scaffold(
	  appBar: AppBar(
		title: Text(widget.device.name),
		actions: [
		  IconButton(
			icon: const Icon(Icons.refresh),
			onPressed: () {
			  provider.refreshDevice(widget.device.id);
			  _loadHistory();
			},
		  ),
		],
	  ),
	  body: RefreshIndicator(
		onRefresh: () async {
		  provider.refreshDevice(widget.device.id);
		  await _loadHistory();
		},
		child: ListView(
		  padding: const EdgeInsets.all(16),
		  children: [
			// Aktuelle Werte
			_CurrentValues(
			  measurement: measurement,
			  loading: loading,
			  error: provider.errorFor(widget.device.id),
			),
			const SizedBox(height: 24),

			// Zeitraum-Auswahl
			_PeriodSelector(
			  selected: _selectedHours,
			  onChanged: (h) {
				setState(() => _selectedHours = h);
				_loadHistory();
			  },
			),
			const SizedBox(height: 16),

			// Chart
			SizedBox(
			  height: 220,
			  child: _loadingHistory
				  ? const Center(child: CircularProgressIndicator())
				  : _historyError != null
					  ? Center(
						  child: Text(
							_historyError!,
							style: const TextStyle(color: Colors.red),
						  ),
						)
					  : HistoryChart(
						  points: _history,
						  showPool: _history.any(
							(p) => p.poolTemperature != null,
						  ),
						),
			),

			const SizedBox(height: 24),

			// API-Endpunkt Info
			_DeviceInfo(device: widget.device),
		  ],
		),
	  ),
	);
  }
}

class _CurrentValues extends StatelessWidget {
  final Measurement? measurement;
  final bool loading;
  final String? error;

  const _CurrentValues({
	required this.measurement,
	required this.loading,
	required this.error,
  });

  @override
  Widget build(BuildContext context) {
	if (loading && measurement == null) {
	  return const Center(child: CircularProgressIndicator());
	}
	if (error != null && measurement == null) {
	  return Text(error!, style: const TextStyle(color: Colors.red));
	}
	if (measurement == null) return const Text('Keine Daten');

	return Card(
	  child: Padding(
		padding: const EdgeInsets.all(16),
		child: Column(
		  crossAxisAlignment: CrossAxisAlignment.start,
		  children: [
			Text(
			  'Aktuelle Messung',
			  style: Theme.of(context).textTheme.titleSmall,
			),
			const SizedBox(height: 12),
			_row('Aussen', measurement!.temperature),
			if (measurement!.poolTemperature != null)
			  _row('Wasser', measurement!.poolTemperature!),
			if (measurement!.indoorTemperature != null)
			  _row('Innen', measurement!.indoorTemperature!),
			const Divider(height: 20),
			Row(
			  children: [
				const Icon(Icons.opacity, size: 14, color: Colors.grey),
				const SizedBox(width: 4),
				Text('${measurement!.humidity.toStringAsFixed(0)} %',
					style: const TextStyle(fontSize: 13)),
				const SizedBox(width: 16),
				const Icon(Icons.compress, size: 14, color: Colors.grey),
				const SizedBox(width: 4),
				Text('${measurement!.pressure.toStringAsFixed(1)} hPa',
					style: const TextStyle(fontSize: 13)),
				const Spacer(),
				Text(
				  'Stand: ${measurement!.timeShort} Uhr',
				  style: const TextStyle(fontSize: 12, color: Colors.grey),
				),
			  ],
			),
		  ],
		),
	  ),
	);
  }

  Widget _row(String label, double value) => Padding(
		padding: const EdgeInsets.symmetric(vertical: 4),
		child: Row(
		  children: [
			Text(label, style: const TextStyle(color: Colors.grey)),
			const Spacer(),
			Text(
			  '${value.toStringAsFixed(1)} °C',
			  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
			),
		  ],
		),
	  );
}

class _PeriodSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _PeriodSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
	const options = [6, 12, 24, 48, 168]; // in Stunden
	const labels = ['6h', '12h', '24h', '2d', '7d'];

	return SegmentedButton<int>(
	  segments: [
		for (var i = 0; i < options.length; i++)
		  ButtonSegment(value: options[i], label: Text(labels[i])),
	  ],
	  selected: {selected},
	  onSelectionChanged: (s) => onChanged(s.first),
	);
  }
}

class _DeviceInfo extends StatelessWidget {
  final Device device;
  const _DeviceInfo({required this.device});

  @override
  Widget build(BuildContext context) {
	return Card(
	  child: ListTile(
		leading: const Icon(Icons.link),
		title: const Text('API-Endpunkt'),
		subtitle: Text(
		  device.apiUrl,
		  style: const TextStyle(fontSize: 11),
		),
	  ),
	);
  }
}
