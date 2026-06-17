import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/models.dart';
import '../services/services.dart';
import '../widgets/widgets.dart';
import '../widgets/device_editor_sheet.dart';
import 'settings_screen.dart';

class DetailScreen extends StatefulWidget {
  final Device device;
  final bool isEmbedded;

  const DetailScreen({super.key, required this.device, this.isEmbedded = false});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  List<MeasurementPoint> _history = [];
  bool _loadingHistory = false;
  String? _historyError;
  int _selectedHours = 24;
  late final ApiService _api;
  late Device _device;

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

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final auth = context.read<AuthService>();
      if (!auth.isLoggedIn) {
        setState(() {
          _loadingHistory = false;
          _history = [];
        });
        return;
      }
      
      final result = await _api.fetchHistory(
        _device,
        hours: _selectedHours,
        bearerToken: auth.currentUser?.token,
      );
      
      if (result.error != null) {
        setState(() => _historyError = result.error);
      } else {
        setState(() => _history = result.data ?? []);
      }
    } catch (e) {
      setState(() => _historyError = 'Fehler beim Laden des Verlaufs');
    } finally {
      setState(() => _loadingHistory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeviceProvider>();
    final measurement = provider.measurementFor(_device.id);
    final theme = Theme.of(context);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          provider.refreshDevice(_device.id);
          await _loadHistory();
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              expandedHeight: 200,
              pinned: true,
              stretch: true,
              flexibleSpace: FlexibleSpaceBar(
                stretchModes: const [StretchMode.zoomBackground],
                title: Text(
                  _device.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: WeatherUtils.gradientForZambretti(
                          measurement?.zambretti ?? '',
                        ),
                      ),
                    ),
                    Positioned(
                      right: -20,
                      bottom: -20,
                      child: Icon(
                        WeatherUtils.iconForZambretti(
                          measurement?.zambretti ?? '',
                        ),
                        color: Colors.white12,
                        size: 200,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _showRenameDialog,
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CurrentDataCard(measurement: measurement),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Verlauf',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        _PeriodSelector(
                          selected: _selectedHours,
                          onChanged: (h) {
                            setState(() => _selectedHours = h);
                            _loadHistory();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildHistorySection(theme),
                    const SizedBox(height: 32),
                    _DeviceInfo(device: _device),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySection(ThemeData theme) {
    if (_loadingHistory) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_historyError != null) {
      return Center(
        child: Text(_historyError!, style: const TextStyle(color: Colors.red)),
      );
    }

    if (_history.isEmpty) {
      final auth = context.read<AuthService>();
      if (!auth.isLoggedIn) {
        return _LoginHint(
          onLogin: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
            _loadHistory();
          },
        );
      }
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text('Keine Daten für diesen Zeitraum vorhanden.'),
        ),
      );
    }

    return Column(
      children: [
        _ChartContainer(
          title: 'Temperatur Aussen (°C)',
          height: 200,
          child: MetricChart(
            points: _history,
            color: Colors.orange,
            getValue: (p) => p.temperature,
          ),
        ),
        if (_history.any((p) => p.poolTemperature != null)) ...[
          const SizedBox(height: 16),
          _ChartContainer(
            title: 'Temperatur Wasser (°C)',
            height: 200,
            child: MetricChart(
              points: _history.where((p) => p.poolTemperature != null).toList(),
              color: Colors.blue,
              getValue: (p) => p.poolTemperature!,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _ChartContainer(
          title: 'Luftfeuchtigkeit (%)',
          height: 200,
          child: MetricChart(
            points: _history,
            color: Colors.teal,
            getValue: (p) => p.humidity,
            intValues: true,
          ),
        ),
        const SizedBox(height: 16),
        _ChartContainer(
          title: 'Luftdruck (hPa)',
          height: 200,
          child: MetricChart(
            points: _history,
            color: Colors.indigo,
            getValue: (p) => p.relPressure,
            intValues: true,
          ),
        ),
        const SizedBox(height: 16),
        _ChartContainer(
          title: 'Batterie (%)',
          height: 180,
          child: MetricChart(
            points: _history,
            color: Colors.green,
            getValue: (p) => p.batteryPct.toDouble(),
            intValues: true,
          ),
        ),
        const SizedBox(height: 16),
        _ChartContainer(
          title: 'WLAN-Stärke (dBm)',
          height: 180,
          child: MetricChart(
            points: _history,
            color: Colors.blueGrey,
            getValue: (p) => p.extraSensors['wifi_strength'] ?? 0,
            intValues: true,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 500.ms);
  }

  Future<void> _showRenameDialog() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DeviceEditorSheet(device: _device),
    );
    // Nach dem Schließen des Editors das lokale Objekt aktualisieren
    final updated = context.read<DeviceProvider>().devices.firstWhere((d) => d.id == _device.id);
    setState(() => _device = updated);
  }
}

class _CurrentDataCard extends StatelessWidget {
  final Measurement? measurement;
  const _CurrentDataCard({this.measurement});

  @override
  Widget build(BuildContext context) {
    if (measurement == null) return const SizedBox.shrink();
    final m = measurement!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatusItem(
                  icon: Icons.thermostat,
                  label: 'Temperatur',
                  value: '${m.temperature.toStringAsFixed(1)}°C',
                  color: Colors.orange,
                ),
                _StatusItem(
                  icon: Icons.water_drop,
                  label: 'Feuchte',
                  value: '${m.humidity.toStringAsFixed(0)}%',
                  color: Colors.blue,
                ),
                _StatusItem(
                  icon: Icons.compress,
                  label: 'Luftdruck',
                  value: '${m.relPressure.toStringAsFixed(0)}',
                  color: Colors.purple,
                ),
              ],
            ),
            const Divider(height: 32),
            _InfoRow(
              label: 'Vorhersage', 
              value: m.zambretti, 
              icon: Icons.wb_sunny,
              isWeather: true,
            ),
            _InfoRow(
              label: 'Drucktrend', 
              value: m.trend, 
              icon: Icons.trending_up,
              isTrend: true,
            ),
            _InfoRow(
              label: 'Batterie', 
              value: '${m.batteryPct}% (${m.batteryVolt.toStringAsFixed(2)}V)', 
              icon: Icons.battery_charging_full
            ),
            if (m.extraSensors.isNotEmpty) ...[
              const Divider(height: 32),
              ...m.extraSensors.entries.map((e) {
                final info = WeatherUtils.sensorInfo(e.key);
                return _InfoRow(
                  label: info.$2,
                  value: '${e.value.toStringAsFixed(0)}${WeatherUtils.sensorUnit(e.key)}',
                  icon: info.$1,
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatusItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isWeather;
  final bool isTrend;

  const _InfoRow({
    required this.label, 
    required this.value, 
    required this.icon,
    this.isWeather = false,
    this.isTrend = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: Colors.grey),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.grey)),
          const SizedBox(width: 16),
          Expanded(
            child: isWeather
                ? _WeatherIconRow(zambretti: value)
                : isTrend
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              value,
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            WeatherUtils.trendIcon(value),
                            color: WeatherUtils.trendColor(value),
                            size: 22,
                          ),
                        ],
                      )
                    : Text(
                        value,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
          ),
        ],
      ),
    );
  }
}

class _WeatherIconRow extends StatelessWidget {
  final String zambretti;
  const _WeatherIconRow({required this.zambretti});

  @override
  Widget build(BuildContext context) {
    final icons = WeatherUtils.iconsForZambretti(zambretti);
    final theme = Theme.of(context);

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      children: [
        ...icons.map((iconData) => Icon(
          iconData, 
          color: WeatherUtils.colorForIcon(iconData), 
          size: 24,
        )),
        if (icons.isEmpty)
          Text(zambretti, textAlign: TextAlign.right),
      ],
    );
  }
}

class _ChartContainer extends StatelessWidget {
  final String title;
  final double height;
  final Widget child;

  const _ChartContainer({
    required this.title,
    required this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 20),
            SizedBox(height: height, child: child),
          ],
        ),
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _PeriodSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = {6: '6h', 24: '24h', 168: '7d'};
    return Row(
      children: options.entries.map((e) {
        final isSelected = selected == e.key;
        return Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: ChoiceChip(
            label: Text(e.value),
            selected: isSelected,
            onSelected: (_) => onChanged(e.key),
          ),
        );
      }).toList(),
    );
  }
}

class _DeviceInfo extends StatelessWidget {
  final Device device;
  const _DeviceInfo({required this.device});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('API Konfiguration'),
        subtitle: Text(device.apiUrl, style: const TextStyle(fontSize: 10)),
      ),
    );
  }
}

class _LoginHint extends StatelessWidget {
  final VoidCallback onLogin;
  const _LoginHint({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.lock_person_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Historie geschützt',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Um den Verlauf zu sehen, musst du dich anmelden.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onLogin, child: const Text('Jetzt anmelden')),
          ],
        ),
      ),
    );
  }
}
