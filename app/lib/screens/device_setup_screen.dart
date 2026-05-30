import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/services.dart';

/// Geräte-Setup in drei Schritten:
///  1. Manuell (nur API-URL) oder Soft-AP
///  2. Soft-AP: Mit ESP-Hotspot verbinden → Config senden
///  3. Gerät benennen und speichern
class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  // Schritt 0 = Methode wählen, 1 = Soft-AP, 2 = Manuell, 3 = Abschluss
  int _step = 0;
  bool _busy = false;
  String? _error;

  // Formular-Felder
  final _nameCtrl     = TextEditingController(text: 'Meine Station');
  final _apiHostCtrl  = TextEditingController();
  final _apiPathCtrl  = TextEditingController(text: '/api/data.php');
  final _apiUserCtrl  = TextEditingController();
  final _apiPassCtrl  = TextEditingController();
  bool _apiHttps      = true;

  // Soft-AP spezifisch
  final _ssidCtrl    = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _setupService = DeviceSetupService();

  @override
  void dispose() {
	for (final c in [_nameCtrl, _apiHostCtrl, _apiPathCtrl, _apiUserCtrl, _apiPassCtrl, _ssidCtrl, _passCtrl]) {
	  c.dispose();
	}
	super.dispose();
  }

  @override
  Widget build(BuildContext context) {
	return Scaffold(
	  appBar: AppBar(
		title: const Text('Gerät hinzufügen'),
		leading: _step > 0
			? IconButton(
				icon: const Icon(Icons.arrow_back),
				onPressed: _busy ? null : () => setState(() {
				  _step = 0;
				  _error = null;
				}),
			  )
			: null,
	  ),
	  body: SafeArea(
		child: AnimatedSwitcher(
		  duration: const Duration(milliseconds: 250),
		  child: _buildStep(),
		),
	  ),
	);
  }

  Widget _buildStep() {
	return switch (_step) {
	  0 => _MethodSelector(
		  key: const ValueKey(0),
		  onManual:  () => setState(() => _step = 2),
		  onSoftAp:  () => setState(() => _step = 1),
		),
	  1 => _SoftApSetup(
		  key: const ValueKey(1),
		  ssidCtrl:    _ssidCtrl,
		  passCtrl:    _passCtrl,
		  apiHostCtrl: _apiHostCtrl,
		  apiPathCtrl: _apiPathCtrl,
		  apiHttps:    _apiHttps,
		  onHttpsChanged: (v) => setState(() => _apiHttps = v),
		  busy:  _busy,
		  error: _error,
		  onSend: _doSoftApSetup,
		),
	  2 => _ManualSetup(
		  key: const ValueKey(2),
		  nameCtrl:    _nameCtrl,
		  apiHostCtrl: _apiHostCtrl,
		  apiPathCtrl: _apiPathCtrl,
		  apiUserCtrl: _apiUserCtrl,
		  apiPassCtrl: _apiPassCtrl,
		  apiHttps:    _apiHttps,
		  onHttpsChanged: (v) => setState(() => _apiHttps = v),
		  busy:  _busy,
		  error: _error,
		  onSave: _saveManual,
		),
	  3 => _SuccessStep(
		  key: const ValueKey(3),
		  name: _nameCtrl.text,
		  onDone: () => Navigator.pop(context),
		),
	  _ => const SizedBox.shrink(),
	};
  }

  // ---- Soft-AP Flow ----

  Future<void> _doSoftApSetup() async {
	setState(() { _busy = true; _error = null; });
	try {
	  // 1. Mit ESP-Hotspot verbinden
	  _showSnack('Verbinde mit ESP-Hotspot…');
	  final ok = await _setupService.connectToDevice(_ssidCtrl.text.trim());
	  if (!ok) throw Exception('WLAN-Verbindung fehlgeschlagen. Bitte manuell verbinden und erneut versuchen.');

	  // 2. Config senden
	  _showSnack('Sende Konfiguration…');
	  await _setupService.sendConfig(
		wifiSsid: _ssidCtrl.text.trim(),
		wifiPass: _passCtrl.text,
		apiHost:  _apiHostCtrl.text.trim(),
		apiPath:  _apiPathCtrl.text.trim(),
		apiHttps: _apiHttps,
	  );

	  // 3. Gerät im lokalen Heimnetz registrieren
	  await _setupService.disconnect();
	  await _addDevice();
	  setState(() => _step = 3);
	} catch (e) {
	  setState(() => _error = e.toString());
	} finally {
	  setState(() => _busy = false);
	}
  }

  // ---- Manuelle Eingabe ----

  Future<void> _saveManual() async {
	if (_apiHostCtrl.text.trim().isEmpty) {
	  setState(() => _error = 'Bitte API-Host eingeben.');
	  return;
	}
	setState(() { _busy = true; _error = null; });
	try {
	  await _addDevice();
	  setState(() => _step = 3);
	} catch (e) {
	  setState(() => _error = e.toString());
	} finally {
	  setState(() => _busy = false);
	}
  }

  Future<void> _addDevice() async {
	final device = Device(
	  id:          const Uuid().v4(),
	  name:        _nameCtrl.text.trim().isEmpty ? 'Station' : _nameCtrl.text.trim(),
	  apiHost:     _apiHostCtrl.text.trim(),
	  apiPath:     _apiPathCtrl.text.trim(),
	  apiHttps:    _apiHttps,
	  apiUser:     _apiUserCtrl.text.trim(),
	  apiPassword: _apiPassCtrl.text,
	);
	if (!mounted) return;
	await context.read<DeviceProvider>().addDevice(device);
  }

  void _showSnack(String msg) {
	if (!mounted) return;
	ScaffoldMessenger.of(context).showSnackBar(
	  SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
	);
  }
}

// ─────────────────────────────────────────────────────────────
//  Schritt 0: Methode wählen
// ─────────────────────────────────────────────────────────────
class _MethodSelector extends StatelessWidget {
  final VoidCallback onManual;
  final VoidCallback onSoftAp;

  const _MethodSelector({super.key, required this.onManual, required this.onSoftAp});

  @override
  Widget build(BuildContext context) {
	return Padding(
	  padding: const EdgeInsets.all(24),
	  child: Column(
		crossAxisAlignment: CrossAxisAlignment.stretch,
		children: [
		  const Text(
			'Wie möchtest du das Gerät hinzufügen?',
			style: TextStyle(fontSize: 16),
		  ),
		  const SizedBox(height: 32),
		  _OptionCard(
			icon: Icons.wifi,
			title: 'Soft-AP Setup',
			subtitle: 'Gerät ist im Einrichtungsmodus (blinkt). '
				'App verbindet sich direkt und sendet die WLAN-Daten.',
			onTap: onSoftAp,
		  ),
		  const SizedBox(height: 16),
		  _OptionCard(
			icon: Icons.edit_outlined,
			title: 'Manuell',
			subtitle: 'Gerät ist bereits im Netz. '
				'API-URL direkt eingeben.',
			onTap: onManual,
		  ),
		],
	  ),
	);
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionCard({
	required this.icon,
	required this.title,
	required this.subtitle,
	required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
	return Card(
	  child: InkWell(
		onTap: onTap,
		borderRadius: BorderRadius.circular(12),
		child: Padding(
		  padding: const EdgeInsets.all(20),
		  child: Row(
			children: [
			  Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
			  const SizedBox(width: 16),
			  Expanded(
				child: Column(
				  crossAxisAlignment: CrossAxisAlignment.start,
				  children: [
					Text(title,
						style: const TextStyle(
							fontSize: 16, fontWeight: FontWeight.bold)),
					const SizedBox(height: 4),
					Text(subtitle,
						style: const TextStyle(
							fontSize: 13, color: Colors.grey)),
				  ],
				),
			  ),
			  const Icon(Icons.chevron_right),
			],
		  ),
		),
	  ),
	);
  }
}

// ─────────────────────────────────────────────────────────────
//  Schritt 1: Soft-AP
// ─────────────────────────────────────────────────────────────
class _SoftApSetup extends StatelessWidget {
  final TextEditingController ssidCtrl;
  final TextEditingController passCtrl;
  final TextEditingController apiHostCtrl;
  final TextEditingController apiPathCtrl;
  final bool apiHttps;
  final ValueChanged<bool> onHttpsChanged;
  final bool busy;
  final String? error;
  final VoidCallback onSend;

  const _SoftApSetup({
	super.key,
	required this.ssidCtrl,
	required this.passCtrl,
	required this.apiHostCtrl,
	required this.apiPathCtrl,
	required this.apiHttps,
	required this.onHttpsChanged,
	required this.busy,
	required this.error,
	required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
	return SingleChildScrollView(
	  padding: const EdgeInsets.all(24),
	  child: Column(
		crossAxisAlignment: CrossAxisAlignment.stretch,
		children: [
		  const _StepHint(
			icon: Icons.info_outline,
			text: 'Halte den Config-Taster des Geräts 2 Sekunden gedrückt, '
				'bis es einen WLAN-Hotspot öffnet (z.B. "SWS-Display").',
		  ),
		  const SizedBox(height: 24),
		  _label('Heimnetz WLAN-Name (SSID)'),
		  TextField(
			controller: ssidCtrl,
			decoration: const InputDecoration(hintText: 'Mein WLAN'),
		  ),
		  const SizedBox(height: 12),
		  _label('WLAN-Passwort'),
		  TextField(
			controller: passCtrl,
			obscureText: true,
			decoration: const InputDecoration(hintText: '••••••••'),
		  ),
		  const SizedBox(height: 20),
		  _label('API-Host'),
		  TextField(
			controller: apiHostCtrl,
			keyboardType: TextInputType.url,
			decoration: const InputDecoration(hintText: 'meinserver.de'),
		  ),
		  const SizedBox(height: 12),
		  _label('API-Pfad'),
		  TextField(
			controller: apiPathCtrl,
			decoration: const InputDecoration(hintText: '/api/data.php'),
		  ),
		  const SizedBox(height: 12),
		  SwitchListTile(
			value: apiHttps,
			onChanged: onHttpsChanged,
			title: const Text('HTTPS verwenden'),
			contentPadding: EdgeInsets.zero,
		  ),
		  if (error != null) ...[
			const SizedBox(height: 12),
			Text(error!, style: const TextStyle(color: Colors.red)),
		  ],
		  const SizedBox(height: 24),
		  FilledButton.icon(
			onPressed: busy ? null : onSend,
			icon: busy
				? const SizedBox(
					width: 18,
					height: 18,
					child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
				  )
				: const Icon(Icons.send),
			label: Text(busy ? 'Sende…' : 'Konfiguration senden'),
		  ),
		],
	  ),
	);
  }
}

// ─────────────────────────────────────────────────────────────
//  Schritt 2: Manuell
// ─────────────────────────────────────────────────────────────
class _ManualSetup extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController apiHostCtrl;
  final TextEditingController apiPathCtrl;
  final TextEditingController apiUserCtrl;
  final TextEditingController apiPassCtrl;
  final bool apiHttps;
  final ValueChanged<bool> onHttpsChanged;
  final bool busy;
  final String? error;
  final VoidCallback onSave;

  const _ManualSetup({
	super.key,
	required this.nameCtrl,
	required this.apiHostCtrl,
	required this.apiPathCtrl,
	required this.apiUserCtrl,
	required this.apiPassCtrl,
	required this.apiHttps,
	required this.onHttpsChanged,
	required this.busy,
	required this.error,
	required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
	return SingleChildScrollView(
	  padding: const EdgeInsets.all(24),
	  child: Column(
		crossAxisAlignment: CrossAxisAlignment.stretch,
		children: [
		  _label('Name'),
		  TextField(
			controller: nameCtrl,
			decoration: const InputDecoration(hintText: 'z.B. Garten'),
		  ),
		  const SizedBox(height: 12),
		  _label('API-Host'),
		  TextField(
			controller: apiHostCtrl,
			keyboardType: TextInputType.url,
			decoration: const InputDecoration(hintText: 'meinserver.de'),
		  ),
		  const SizedBox(height: 12),
		  _label('API-Pfad'),
		  TextField(
			controller: apiPathCtrl,
			decoration: const InputDecoration(hintText: '/api/data.php'),
		  ),
		  const SizedBox(height: 12),
		  _label('API-Benutzername (optional)'),
		  TextField(
			controller: apiUserCtrl,
			decoration: const InputDecoration(hintText: 'Leer lassen wenn keine Auth'),
		  ),
		  const SizedBox(height: 12),
		  _label('API-Passwort'),
		  TextField(
			controller: apiPassCtrl,
			obscureText: true,
			decoration: const InputDecoration(hintText: '••••••••'),
		  ),
		  const SizedBox(height: 12),
		  SwitchListTile(
			value: apiHttps,
			onChanged: onHttpsChanged,
			title: const Text('HTTPS verwenden'),
			contentPadding: EdgeInsets.zero,
		  ),
		  if (error != null) ...[
			const SizedBox(height: 12),
			Text(error!, style: const TextStyle(color: Colors.red)),
		  ],
		  const SizedBox(height: 24),
		  FilledButton.icon(
			onPressed: busy ? null : onSave,
			icon: busy
				? const SizedBox(
					width: 18,
					height: 18,
					child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
				  )
				: const Icon(Icons.check),
			label: Text(busy ? 'Speichere…' : 'Gerät speichern'),
		  ),
		],
	  ),
	);
  }
}

// ─────────────────────────────────────────────────────────────
//  Schritt 3: Erfolg
// ─────────────────────────────────────────────────────────────
class _SuccessStep extends StatelessWidget {
  final String name;
  final VoidCallback onDone;

  const _SuccessStep({super.key, required this.name, required this.onDone});

  @override
  Widget build(BuildContext context) {
	return Center(
	  child: Padding(
		padding: const EdgeInsets.all(32),
		child: Column(
		  mainAxisSize: MainAxisSize.min,
		  children: [
			const Icon(Icons.check_circle, color: Colors.green, size: 72),
			const SizedBox(height: 16),
			Text(
			  '"$name" wurde hinzugefügt!',
			  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
			  textAlign: TextAlign.center,
			),
			const SizedBox(height: 8),
			const Text(
			  'Daten werden nun automatisch abgerufen.',
			  style: TextStyle(color: Colors.grey),
			  textAlign: TextAlign.center,
			),
			const SizedBox(height: 32),
			FilledButton(onPressed: onDone, child: const Text('Zum Dashboard')),
		  ],
		),
	  ),
	);
  }
}

// ─────────────────────────────────────────────────────────────
//  Hilfsfunktionen
// ─────────────────────────────────────────────────────────────
Widget _label(String text) => Padding(
	  padding: const EdgeInsets.only(bottom: 6),
	  child: Text(text,
		  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
	);

class _StepHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _StepHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
	return Container(
	  padding: const EdgeInsets.all(12),
	  decoration: BoxDecoration(
		color: Theme.of(context).colorScheme.primaryContainer,
		borderRadius: BorderRadius.circular(8),
	  ),
	  child: Row(
		crossAxisAlignment: CrossAxisAlignment.start,
		children: [
		  Icon(icon, size: 18,
			  color: Theme.of(context).colorScheme.onPrimaryContainer),
		  const SizedBox(width: 8),
		  Expanded(
			child: Text(
			  text,
			  style: TextStyle(
				  fontSize: 13,
				  color: Theme.of(context).colorScheme.onPrimaryContainer),
			),
		  ),
		],
	  ),
	);
  }
}
