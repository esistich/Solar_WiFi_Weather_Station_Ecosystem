import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/models.dart';
import '../services/services.dart';
import '../widgets/weather_utils.dart';
import 'device_setup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _AccountHeader(),
          
          const SizedBox(height: 16),
          _SectionTitle(title: 'Geräteverwaltung'),
          
          Consumer<DeviceProvider>(
            builder: (context, provider, _) {
              if (provider.devices.isEmpty) {
                return _EmptyDevicesPlaceholder();
              }
              return Column(
                children: provider.devices.map((d) => _ModernDeviceTile(device: d)).toList(),
              );
            },
          ),
          
          _SettingsTile(
            icon: Icons.add_circle_outline_rounded,
            title: 'Neue Station hinzufügen',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DeviceSetupScreen()),
            ),
            color: colorScheme.primary,
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Divider(height: 1),
          ),

          _SectionTitle(title: 'App & Darstellung'),
          
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) => _SettingsSwitchTile(
              icon: themeProvider.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              title: 'Dunkles Design',
              subtitle: 'Schont die Augen bei Nacht',
              value: themeProvider.isDark,
              onChanged: (_) => themeProvider.toggle(),
            ),
          ),

          _SettingsTile(
            icon: Icons.info_outline_rounded,
            title: 'Über diese App',
            subtitle: 'SWS Companion v1.0.0',
            onTap: () => _showAboutDialog(context),
          ),
          
          const SizedBox(height: 40),
          Center(
            child: Opacity(
              opacity: 0.5,
              child: Text(
                'Solar WiFi Weather Station Project',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
        ],
      ).animate().fadeIn(duration: 400.ms),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'SWS Companion',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.wb_sunny_rounded, size: 40, color: Colors.orange),
      children: [
        const Text('Eine Companion-App für das Solar WiFi Weather Station Projekt.'),
      ],
    );
  }
}

class _AccountHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthService>();
    final isLoggedIn = auth.currentUser != null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: theme.colorScheme.primary,
            child: Icon(
              isLoggedIn ? Icons.person_rounded : Icons.person_outline_rounded,
              color: theme.colorScheme.onPrimary,
              size: 32,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoggedIn ? 'Willkommen zurück' : 'Nicht angemeldet',
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
                ),
                Text(
                  isLoggedIn ? auth.currentUser!.email : 'Für Cloud-Features einloggen',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isLoggedIn)
            IconButton(
              onPressed: () => auth.logout(),
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Abmelden',
            )
          else
            FilledButton(
              onPressed: () => _showAuthBottomSheet(context, auth),
              child: const Text('Login'),
            ),
        ],
      ),
    );
  }

  void _showAuthBottomSheet(BuildContext context, AuthService auth) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AuthBottomSheet(auth: auth),
    );
  }
}

class _AuthBottomSheet extends StatefulWidget {
  final AuthService auth;
  const _AuthBottomSheet({required this.auth});

  @override
  State<_AuthBottomSheet> createState() => _AuthBottomSheetState();
}

class _AuthBottomSheetState extends State<_AuthBottomSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _inviteCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (_tabController.index == 0) {
        await widget.auth.login(_emailCtrl.text.trim(), _passCtrl.text);
      } else {
        await widget.auth.register(_emailCtrl.text.trim(), _passCtrl.text, _inviteCtrl.text.trim());
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
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24, right: 24, top: 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 20),
          TabBar(
            controller: _tabController,
            tabs: const [Tab(text: 'Anmelden'), Tab(text: 'Registrieren')],
            dividerColor: Colors.transparent,
            onTap: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _emailCtrl,
            decoration: const InputDecoration(labelText: 'E-Mail', prefixIcon: Icon(Icons.email_outlined)),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            decoration: const InputDecoration(labelText: 'Passwort', prefixIcon: Icon(Icons.lock_outline)),
            obscureText: true,
          ),
          AnimatedSize(
            duration: 300.ms,
            child: _tabController.index == 1
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    controller: _inviteCtrl,
                    decoration: const InputDecoration(labelText: 'Einladungscode', prefixIcon: Icon(Icons.vpn_key_outlined)),
                  ),
                )
              : const SizedBox.shrink(),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_tabController.index == 0 ? 'Anmelden' : 'Konto erstellen'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? color;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (color ?? Theme.of(context).colorScheme.primary).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color ?? Theme.of(context).colorScheme.primary, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: subtitle != null ? Text(subtitle!, style: const TextStyle(fontSize: 12)) : null,
      trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey),
      onTap: onTap,
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
    );
  }
}

class _ModernDeviceTile extends StatelessWidget {
  final Device device;
  const _ModernDeviceTile({required this.device});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(WeatherUtils.deviceIcon(device.iconIndex), size: 20),
      ),
      title: Text(device.name),
      subtitle: Text(device.apiHost, style: const TextStyle(fontSize: 11)),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert_rounded),
        onPressed: () => _showDeviceActions(context),
      ),
    );
  }

  void _showDeviceActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Bearbeiten'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => DeviceSetupScreen(device: device)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text('Entfernen', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                context.read<DeviceProvider>().removeDevice(device.id);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _EmptyDevicesPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Text(
        'Noch keine Stationen hinterlegt.',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontStyle: FontStyle.italic),
      ),
    );
  }
}
