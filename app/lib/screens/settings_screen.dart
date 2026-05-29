import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'device_setup_screen.dart';

/// Einstellungen: Geräteliste verwalten, Auth-Status, App-Info.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
	return Scaffold(
	  appBar: AppBar(title: const Text('Einstellungen')),
	  body: ListView(
		children: [
		  // ── Geräte ──────────────────────────────────────────
		  const _SectionHeader('Geräte'),
		  Consumer<DeviceProvider>(
			builder: (context, provider, _) {
			  if (provider.devices.isEmpty) {
				return const ListTile(
				  leading: Icon(Icons.info_outline),
				  title: Text('Keine Geräte registriert'),
				);
			  }
			  return Column(
				children: provider.devices
					.map((d) => _DeviceTile(device: d))
					.toList(),
			  );
			},
		  ),
		  ListTile(
			leading: const Icon(Icons.add_circle_outline),
			title: const Text('Gerät hinzufügen'),
			onTap: () => Navigator.push(
			  context,
			  MaterialPageRoute(builder: (_) => const DeviceSetupScreen()),
			),
		  ),

		  const Divider(),

		  // ── Account ─────────────────────────────────────────
		  const _SectionHeader('Account'),
		  Consumer<AuthService>(
			builder: (context, auth, _) {
			  if (auth.currentUser == null) {
				return ListTile(
				  leading: const Icon(Icons.login),
				  title: const Text('Anmelden'),
				  subtitle: const Text('Für Push-Benachrichtigungen'),
				  onTap: () => _showLoginDialog(context, auth),
				);
			  }
			  return ListTile(
				leading: const Icon(Icons.account_circle),
				title: Text(auth.currentUser!.email),
				subtitle: const Text('Angemeldet'),
				trailing: TextButton(
				  onPressed: () => auth.logout(),
				  child: const Text('Abmelden'),
				),
			  );
			},
		  ),

		  const Divider(),

		  // ── App-Info ─────────────────────────────────────────
		  const _SectionHeader('App'),
		  const ListTile(
			leading: Icon(Icons.info_outline),
			title: Text('SWS Companion'),
			subtitle: Text('Version 1.0.0'),
		  ),
		  ListTile(
			leading: const Icon(Icons.code),
			title: const Text('Quellcode'),
			subtitle: const Text('github.com/esistich/Solar_WiFi_Weather_Station'),
			onTap: () {},
		  ),
		],
	  ),
	);
  }

  void _showLoginDialog(BuildContext context, AuthService auth) {
	showDialog(
	  context: context,
	  builder: (ctx) => _AuthDialog(auth: auth),
	);
  }
}

/// Dialog mit zwei Tabs: Anmelden und Registrieren (mit Einladungscode).
class _AuthDialog extends StatefulWidget {
  final AuthService auth;
  const _AuthDialog({required this.auth});

  @override
  State<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<_AuthDialog>
	with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  final _inviteCtrl = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void initState() {
	super.initState();
	_tabs = TabController(length: 2, vsync: this);
	_tabs.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
	_tabs.dispose();
	_emailCtrl.dispose();
	_passCtrl.dispose();
	_inviteCtrl.dispose();
	super.dispose();
  }

  Future<void> _submit() async {
	setState(() { _error = null; _loading = true; });
	try {
	  if (_tabs.index == 0) {
		await widget.auth.login(_emailCtrl.text.trim(), _passCtrl.text);
	  } else {
		await widget.auth.register(
		  _emailCtrl.text.trim(),
		  _passCtrl.text,
		  _inviteCtrl.text.trim(),
		);
	  }
	  if (mounted) Navigator.pop(context);
	} catch (e) {
	  setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
	} finally {
	  if (mounted) setState(() => _loading = false);
	}
  }

  @override
  Widget build(BuildContext context) {
	return AlertDialog(
	  title: TabBar(
		controller: _tabs,
		tabs: const [Tab(text: 'Anmelden'), Tab(text: 'Registrieren')],
	  ),
	  content: SizedBox(
		width: 320,
		child: Column(
		  mainAxisSize: MainAxisSize.min,
		  children: [
			const SizedBox(height: 12),
			TextField(
			  controller: _emailCtrl,
			  decoration: const InputDecoration(labelText: 'E-Mail'),
			  keyboardType: TextInputType.emailAddress,
			),
			const SizedBox(height: 8),
			TextField(
			  controller: _passCtrl,
			  decoration: const InputDecoration(labelText: 'Passwort'),
			  obscureText: true,
			),
			// Einladungscode nur im Registrieren-Tab
			AnimatedSize(
			  duration: const Duration(milliseconds: 200),
			  child: _tabs.index == 1
				  ? Padding(
					  padding: const EdgeInsets.only(top: 8),
					  child: TextField(
						controller: _inviteCtrl,
						decoration: const InputDecoration(
						  labelText: 'Einladungscode',
						  prefixIcon: Icon(Icons.vpn_key_outlined),
						),
					  ),
					)
				  : const SizedBox.shrink(),
			),
			if (_error != null) ...[
			  const SizedBox(height: 8),
			  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
			],
		  ],
		),
	  ),
	  actions: [
		TextButton(
		  onPressed: _loading ? null : () => Navigator.pop(context),
		  child: const Text('Abbrechen'),
		),
		FilledButton(
		  onPressed: _loading ? null : _submit,
		  child: _loading
			  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
			  : Text(_tabs.index == 0 ? 'Anmelden' : 'Registrieren'),
		),
	  ],
	);
  }
}

class _DeviceTile extends StatelessWidget {
  final Device device;
  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context) {
	return ListTile(
	  leading: const Icon(Icons.wb_sunny_outlined),
	  title: Text(device.name),
	  subtitle: Text(device.apiUrl,
		  style: const TextStyle(fontSize: 11),
		  overflow: TextOverflow.ellipsis),
	  trailing: PopupMenuButton<String>(
		onSelected: (action) => _onAction(context, action),
		itemBuilder: (_) => const [
		  PopupMenuItem(value: 'edit',   child: Text('Bearbeiten')),
		  PopupMenuItem(value: 'delete', child: Text('Entfernen')),
		],
	  ),
	);
  }

  void _onAction(BuildContext context, String action) {
	final provider = context.read<DeviceProvider>();
	switch (action) {
	  case 'edit':
		_showEditDialog(context, provider);
	  case 'delete':
		_confirmDelete(context, provider);
	}
  }

  void _showEditDialog(BuildContext context, DeviceProvider provider) {
	final nameCtrl = TextEditingController(text: device.name);
	final hostCtrl = TextEditingController(text: device.apiHost);
	final pathCtrl = TextEditingController(text: device.apiPath);
	bool https = device.apiHttps;

	showDialog(
	  context: context,
	  builder: (ctx) => StatefulBuilder(
		builder: (ctx, setState) => AlertDialog(
		  title: const Text('Gerät bearbeiten'),
		  content: SingleChildScrollView(
			child: Column(
			  mainAxisSize: MainAxisSize.min,
			  children: [
				TextField(controller: nameCtrl,
					decoration: const InputDecoration(labelText: 'Name')),
				const SizedBox(height: 8),
				TextField(controller: hostCtrl,
					decoration: const InputDecoration(labelText: 'API-Host')),
				const SizedBox(height: 8),
				TextField(controller: pathCtrl,
					decoration: const InputDecoration(labelText: 'API-Pfad')),
				const SizedBox(height: 4),
				SwitchListTile(
				  value: https,
				  onChanged: (v) => setState(() => https = v),
				  title: const Text('HTTPS'),
				  contentPadding: EdgeInsets.zero,
				),
			  ],
			),
		  ),
		  actions: [
			TextButton(onPressed: () => Navigator.pop(ctx),
				child: const Text('Abbrechen')),
			FilledButton(
			  onPressed: () {
				provider.updateDevice(device.copyWith(
				  name:     nameCtrl.text.trim(),
				  apiHost:  hostCtrl.text.trim(),
				  apiPath:  pathCtrl.text.trim(),
				  apiHttps: https,
				));
				Navigator.pop(ctx);
			  },
			  child: const Text('Speichern'),
			),
		  ],
		),
	  ),
	);
  }

  void _confirmDelete(BuildContext context, DeviceProvider provider) {
	showDialog(
	  context: context,
	  builder: (ctx) => AlertDialog(
		title: const Text('Gerät entfernen?'),
		content: Text('"${device.name}" wird aus der App entfernt.'),
		actions: [
		  TextButton(onPressed: () => Navigator.pop(ctx),
			  child: const Text('Abbrechen')),
		  FilledButton(
			style: FilledButton.styleFrom(
				backgroundColor: Theme.of(context).colorScheme.error),
			onPressed: () {
			  provider.removeDevice(device.id);
			  Navigator.pop(ctx);
			},
			child: const Text('Entfernen'),
		  ),
		],
	  ),
	);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
		padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
		child: Text(title,
			style: TextStyle(
				fontSize: 12,
				fontWeight: FontWeight.bold,
				color: Theme.of(context).colorScheme.primary,
				letterSpacing: 0.8)),
	  );
}
