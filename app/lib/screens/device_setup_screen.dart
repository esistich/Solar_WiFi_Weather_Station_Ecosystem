import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/models.dart';
import '../services/services.dart';
import '../widgets/weather_utils.dart';

class DeviceSetupScreen extends StatefulWidget {
  final Device? device;
  const DeviceSetupScreen({super.key, this.device});

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _busy = false;
  String? _error;

  // Formular-Zustand
  final _nameCtrl        = TextEditingController(text: 'Meine Station');
  final _apiHostCtrl     = TextEditingController(text: 'timm-sander.net');
  final _apiPathCtrl     = TextEditingController(text: '/sws/api/v1/data');
  final _apiUserCtrl     = TextEditingController();
  final _apiPassCtrl     = TextEditingController();
  final _stationSlugCtrl = TextEditingController();
  bool _apiHttps         = true;
  int  _iconIndex        = 0;

  // Soft-AP Zustand
  final _ssidCtrl    = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _setupService = DeviceSetupService();

  @override
  void initState() {
    super.initState();
    if (widget.device != null) {
      final d = widget.device!;
      _nameCtrl.text = d.name;
      _apiHostCtrl.text = d.apiHost;
      _apiPathCtrl.text = d.apiPath;
      _apiUserCtrl.text = d.apiUser;
      _apiPassCtrl.text = d.apiPassword;
      _stationSlugCtrl.text = d.stationSlug;
      _apiHttps = d.apiHttps;
      _iconIndex = d.iconIndex;
      _currentPage = 2; // Direkt zum Formular im Edit-Modus
    }
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: 400.ms,
      curve: Curves.easeInOutCubic,
    );
  }

  void _prevPage() {
    _pageController.previousPage(
      duration: 400.ms,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device != null ? 'Gerät anpassen' : 'Neues Gerät'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Fortschrittsbalken oben
          if (widget.device == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (_currentPage + 1) / 4,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
          
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (idx) => setState(() => _currentPage = idx),
              children: [
                _MethodStep(
                  onManual: () {
                    setState(() => _currentPage = 2);
                    _pageController.jumpToPage(2);
                  },
                  onSoftAp: _nextPage,
                ),
                _SoftApStep(
                  ssidCtrl: _ssidCtrl,
                  passCtrl: _passCtrl,
                  busy: _busy,
                  onNext: _nextPage,
                ),
                _ConfigStep(
                  nameCtrl: _nameCtrl,
                  apiHostCtrl: _apiHostCtrl,
                  apiPathCtrl: _apiPathCtrl,
                  apiUserCtrl: _apiUserCtrl,
                  apiPassCtrl: _apiPassCtrl,
                  stationSlugCtrl: _stationSlugCtrl,
                  apiHttps: _apiHttps,
                  onHttpsChanged: (v) => setState(() => _apiHttps = v),
                  iconIndex: _iconIndex,
                  onIconChanged: (i) => setState(() => _iconIndex = i),
                  onSave: _saveDevice,
                  busy: _busy,
                  error: _error,
                ),
                _SuccessStep(
                  name: _nameCtrl.text,
                  onDone: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveDevice() async {
    setState(() { _busy = true; _error = null; });
    try {
      final existing = widget.device;
      final device = Device(
        id: existing?.id ?? const Uuid().v4(),
        name: _nameCtrl.text.trim(),
        apiHost: _apiHostCtrl.text.trim(),
        apiPath: _apiPathCtrl.text.trim(),
        apiHttps: _apiHttps,
        apiUser: _apiUserCtrl.text.trim(),
        apiPassword: _apiPassCtrl.text,
        stationSlug: _stationSlugCtrl.text.trim(),
        iconIndex: _iconIndex,
      );

      final provider = context.read<DeviceProvider>();
      if (existing != null) {
        await provider.updateDevice(device);
      } else {
        await provider.addDevice(device);
      }
      _nextPage();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }
}

// --- SUB-WIDGETS ---

class _MethodStep extends StatelessWidget {
  final VoidCallback onManual;
  final VoidCallback onSoftAp;

  const _MethodStep({required this.onManual, required this.onSoftAp});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_to_home_screen_rounded, size: 80, color: Colors.blue)
              .animate()
              .scale(duration: 600.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 24),
          Text(
            'Einrichtung starten',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Wie möchtest du deine Wetterstation verbinden?',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 40),
          _MethodCard(
            title: 'Automatisches Setup',
            subtitle: 'Empfohlen: App sendet WLAN-Daten direkt an das Gerät.',
            icon: Icons.auto_fix_high_rounded,
            onTap: onSoftAp,
            isPrimary: true,
          ),
          const SizedBox(height: 16),
          _MethodCard(
            title: 'Manuelle Eingabe',
            subtitle: 'Direkte Eingabe der API-URL (für Fortgeschrittene).',
            icon: Icons.settings_ethernet_rounded,
            onTap: onManual,
            isPrimary: false,
          ),
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  const _MethodCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: isPrimary ? 4 : 0,
      color: isPrimary ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Icon(icon, size: 32, color: isPrimary ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftApStep extends StatelessWidget {
  final TextEditingController ssidCtrl;
  final TextEditingController passCtrl;
  final bool busy;
  final VoidCallback onNext;

  const _SoftApStep({
    required this.ssidCtrl,
    required this.passCtrl,
    required this.busy,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.wifi_tethering_rounded, size: 64, color: Colors.blue),
          const SizedBox(height: 24),
          const Text(
            'Gerät vorbereiten',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            '1. Halte den Button am Gerät für 2 Sek. gedrückt.\n2. Warte bis die LED blinkt.\n3. Gib hier deine WLAN-Daten ein.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.5, color: Colors.grey),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: ssidCtrl,
            decoration: const InputDecoration(labelText: 'WLAN Name (SSID)', prefixIcon: Icon(Icons.wifi)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: passCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'WLAN Passwort', prefixIcon: Icon(Icons.lock_outline)),
          ),
          const SizedBox(height: 40),
          FilledButton(
            onPressed: onNext,
            child: const Center(child: Text('Weiter zur API-Konfiguration')),
          ),
        ],
      ),
    );
  }
}

class _ConfigStep extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController apiHostCtrl;
  final TextEditingController apiPathCtrl;
  final TextEditingController apiUserCtrl;
  final TextEditingController apiPassCtrl;
  final TextEditingController stationSlugCtrl;
  final bool apiHttps;
  final ValueChanged<bool> onHttpsChanged;
  final int iconIndex;
  final ValueChanged<int> onIconChanged;
  final VoidCallback onSave;
  final bool busy;
  final String? error;

  const _ConfigStep({
    required this.nameCtrl,
    required this.apiHostCtrl,
    required this.apiPathCtrl,
    required this.apiUserCtrl,
    required this.apiPassCtrl,
    required this.stationSlugCtrl,
    required this.apiHttps,
    required this.onHttpsChanged,
    required this.iconIndex,
    required this.onIconChanged,
    required this.onSave,
    required this.busy,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('Gerätename'),
          TextField(controller: nameCtrl, decoration: const InputDecoration(hintText: 'z.B. Garten')),
          const SizedBox(height: 20),
          _label('Server Adresse'),
          TextField(controller: apiHostCtrl, decoration: const InputDecoration(hintText: 'meinserver.de')),
          const SizedBox(height: 12),
          _label('API Pfad'),
          TextField(controller: apiPathCtrl, decoration: const InputDecoration(hintText: '/sws/api/v1/data')),
          const SizedBox(height: 12),
          SwitchListTile(
            value: apiHttps,
            onChanged: onHttpsChanged,
            title: const Text('Sichere Verbindung (HTTPS)'),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(height: 40),
          _label('Station Symbol'),
          const SizedBox(height: 8),
          _IconPicker(selected: iconIndex, onChanged: onIconChanged),
          const SizedBox(height: 32),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          FilledButton.icon(
            onPressed: busy ? null : onSave,
            icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
            label: Text(busy ? 'Speichere...' : 'Einrichtung abschließen'),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey));
}

class _IconPicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _IconPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: List.generate(WeatherUtils.deviceIcons.length, (i) {
        final isSelected = selected == i;
        return GestureDetector(
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: 200.ms,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isSelected ? Colors.blue : Colors.grey.withOpacity(0.3), width: 2),
            ),
            child: Icon(WeatherUtils.deviceIcons[i], color: isSelected ? Colors.blue : Colors.grey),
          ),
        );
      }),
    );
  }
}

class _SuccessStep extends StatelessWidget {
  final String name;
  final VoidCallback onDone;

  const _SuccessStep({required this.name, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.celebration_rounded, size: 80, color: Colors.orange)
              .animate()
              .shake(duration: 500.ms),
          const SizedBox(height: 24),
          const Text('Alles bereit!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('Die Station "$name" wurde erfolgreich eingerichtet.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 48),
          FilledButton(onPressed: onDone, child: const Center(child: Text('Zum Dashboard'))),
        ],
      ),
    );
  }
}
