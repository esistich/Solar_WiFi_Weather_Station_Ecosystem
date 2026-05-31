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
  late Device _device; // lokal aktualisierbar nach Rename

  @override
  void initState() {
	super.initState();
	_device = widget.device;
	_api = ApiService();
	_loadHistory();
  }

  @override
  void dispose() {
	_api.dispose();
	super.dispose();
  }

  /// Zeigt Dialog zum Aendern von Stationsname und Slug.
  Future<void> _showRenameDialog() async {
    final nameCtrl = TextEditingController(text: _device.name);
    final slugCtrl = TextEditingController(text: _device.stationSlug);
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Station umbenennen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Name'),
              const SizedBox(height: 4),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(hintText: 'z.B. Waggum'),
              ),
              const SizedBox(height: 12),
              const Text('Slug (API-Bezeichner)'),
              const SizedBox(height: 4),
              TextField(
                controller: slugCtrl,
                decoration: const InputDecoration(hintText: 'z.B. waggum'),
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 8),
                Text(dialogError!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () async {
                final auth = context.read<AuthService>();
                final token = auth.currentUser?.token;
                if (token == null) {
                  setDialogState(() => dialogError = 'Nicht eingeloggt.');
                  return;
                }
                final newName = nameCtrl.text.trim();
                final newSlug = slugCtrl.text.trim().toLowerCase();
                if (newName.isEmpty || newSlug.isEmpty) {
                  setDialogState(() => dialogError = 'Name und Slug duerfen nicht leer sein.');
                  return;
                }
                try {
                  await _api.updateStation(
                    _device,
                    currentSlug: _device.stationSlug,
                    name: newName,
                    newSlug: newSlug,
                    bearerToken: token,
                  );
                  // Lokales Device und gespeichertes Device aktualisieren
                  final updated = _device.copyWith(
                    name: newName,
                    stationSlug: newSlug,
                  );
                  if (!mounted) return;
                  await context.read<DeviceProvider>().updateDevice(updated);
                  setState(() => _device = updated);
                  if (!mounted) return;
                  Navigator.pop(ctx);
                } catch (e) {
                  setDialogState(() => dialogError = e.toString());
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadHistory() async {
	setState(() {
	  _loadingHistory = true;
	  _historyError = null;
	});
	try {
	  final auth = context.read<AuthService>();
	  final data = await _api.fetchHistory(
		_device,
		hours: _selectedHours,
		bearerToken: auth.currentUser?.token,
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
	final measurement = provider.measurementFor(_device.id);
	final loading = provider.isLoading(_device.id);

	return Scaffold(
	  appBar: AppBar(
		title: Text(_device.name),
		actions: [
		  IconButton(
			icon: const Icon(Icons.edit_outlined),
			tooltip: 'Station umbenennen',
			onPressed: _showRenameDialog,
		  ),
		  IconButton(
			icon: const Icon(Icons.refresh),
			onPressed: () {
			  provider.refreshDevice(_device.id);
			  _loadHistory();
			},
		  ),
		],
	  ),
	  body: RefreshIndicator(
		onRefresh: () async {
		  provider.refreshDevice(_device.id);
		  await _loadHistory();
		},
		child: ListView(
		  padding: const EdgeInsets.all(16),
		  children: [
			// Aktuelle Werte
			_CurrentValues(
			  measurement: measurement,
			  loading: loading,
			  error: provider.errorFor(_device.id),
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

			// Charts
			if (_loadingHistory)
			  const SizedBox(
				height: 100,
				child: Center(child: CircularProgressIndicator()),
			  )
			else if (_historyError != null)
			  Padding(
				padding: const EdgeInsets.symmetric(vertical: 16),
				child: Text(
				  _historyError!,
				  style: const TextStyle(color: Colors.red),
				),
			  )
			else ...[
				  _ChartCard(
					title: 'Temperatur Aussen (BME280)',
					height: 200,
					child: MetricChart(
					  points: _history,
					  unit: ' °C',
					  color: Colors.orange,
					  getValue: (p) => p.temperature,
					),
				  ),
				  if (_history.any((p) => p.poolTemperature != null)) ...[
					const SizedBox(height: 16),
					_ChartCard(
					  title: 'Temperatur Wasser (DS18B20)',
					  height: 200,
					  child: MetricChart(
						points: _history
							.where((p) => p.poolTemperature != null)
							.toList(),
						unit: ' °C',
						color: Colors.blue,
						getValue: (p) => p.poolTemperature!,
					  ),
					),
				  ],
				  const SizedBox(height: 16),
				  _ChartCard(
					title: 'Luftfeuchte',
					height: 180,
					child: MetricChart(
					  points: _history,
					  unit: ' %',
					  color: Colors.teal,
					  getValue: (p) => p.humidity,
					  intValues: true,
					),
				  ),
				  const SizedBox(height: 16),
				  _ChartCard(
					title: 'Luftdruck (rel.)',
					height: 180,
					child: MetricChart(
					  points: _history,
					  unit: ' hPa',
					  color: Colors.purple,
					  getValue: (p) => p.relPressure,
					  intValues: true,
					),
				  ),
				  const SizedBox(height: 16),
				  _ChartCard(
					title: 'Batterie',
					height: 180,
					child: MetricChart(
					  points: _history,
					  unit: ' %',
					  color: Colors.green,
					  getValue: (p) => p.batteryPct.toDouble(),
					  intValues: true,
					),
				  ),
				],

			const SizedBox(height: 24),

			// API-Endpunkt Info
			_DeviceInfo(device: _device),
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

	final m = measurement!;
	return Card(
	  child: Padding(
		padding: const EdgeInsets.all(16),
		child: Column(
		  crossAxisAlignment: CrossAxisAlignment.start,
		  children: [
			Row(
			  mainAxisAlignment: MainAxisAlignment.spaceBetween,
			  children: [
				Text('Aktuelle Messung',
					style: Theme.of(context).textTheme.titleSmall),
				Text(
				  'Stand: ${m.timeShort} Uhr',
				  style: const TextStyle(fontSize: 12, color: Colors.grey),
				),
			  ],
			),
			const SizedBox(height: 12),
			_row('Außen (BME280)', m.temperature),
			if (m.poolTemperature != null)
			  _row('Wasser (DS18B20)', m.poolTemperature!),
			const Divider(height: 20),
			_infoRow(Icons.opacity,
				'Luftfeuchte', '${m.humidity.toStringAsFixed(1)} %'),
			const SizedBox(height: 6),
			_infoRow(Icons.compress,
				'Rel. Luftdruck', '${m.relPressure.toStringAsFixed(0)} hPa  •  ${m.pressureState}'),
			const SizedBox(height: 6),
			_infoRow(Icons.trending_flat,
				'Drucktrend', m.trend),
			const SizedBox(height: 6),
			_infoRow(Icons.wb_sunny_outlined,
				'Vorhersage', m.zambretti),
			const Divider(height: 20),
			_infoRow(Icons.battery_std,
				'Akku', '${m.batteryPct} %  •  ${m.batteryVolt.toStringAsFixed(2)} V'),
			const SizedBox(height: 6),
			_infoRow(_wifiIcon(m.wifiStrength),
				'WLAN', _wifiLabel(m.wifiStrength)),
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

  Widget _infoRow(IconData icon, String label, String value) => Row(
		children: [
		  Icon(icon, size: 14, color: Colors.grey),
		  const SizedBox(width: 6),
		  Text('$label: ', style: const TextStyle(fontSize: 13, color: Colors.grey)),
		  Expanded(
			child: Text(value, style: const TextStyle(fontSize: 13)),
		  ),
		],
	  );

  /// dBm → lesbare Qualitätsstufe
  static String _wifiLabel(int dbm) {
	if (dbm >= -50) return 'Ausgezeichnet';
	if (dbm >= -60) return 'Gut';
	if (dbm >= -70) return 'Mittel';
	if (dbm >= -80) return 'Schwach';
	return 'Sehr schwach';
  }

  static IconData _wifiIcon(int dbm) {
	if (dbm >= -60) return Icons.wifi;
	if (dbm >= -70) return Icons.wifi_2_bar;
	return Icons.wifi_1_bar;
  }
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

class _ChartCard extends StatelessWidget {
  final String title;
  final double height;
  final Widget child;

  const _ChartCard({
	required this.title,
	required this.height,
	required this.child,
  });

  @override
  Widget build(BuildContext context) {
	return Card(
	  child: Padding(
		padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
		child: Column(
		  crossAxisAlignment: CrossAxisAlignment.start,
		  children: [
			Text(title, style: Theme.of(context).textTheme.titleSmall),
			const SizedBox(height: 8),
			SizedBox(height: height, child: child),
		  ],
		),
	  ),
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
