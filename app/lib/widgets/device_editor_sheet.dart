import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'weather_utils.dart';

/// Zentrales, vereinheitlichtes Bearbeitungsfenster für Stationen.
class DeviceEditorSheet extends StatefulWidget {
  final Device device;
  const DeviceEditorSheet({super.key, required this.device});

  @override
  State<DeviceEditorSheet> createState() => _DeviceEditorSheetState();
}

class _DeviceEditorSheetState extends State<DeviceEditorSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _slugCtrl;
  late TextEditingController _hostCtrl;
  late TextEditingController _pathCtrl;
  late TextEditingController _userCtrl;
  late TextEditingController _passCtrl;
  late bool _https;
  late int _iconIndex;
  
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.device;
    _nameCtrl = TextEditingController(text: d.name);
    _slugCtrl = TextEditingController(text: d.stationSlug);
    _hostCtrl = TextEditingController(text: d.apiHost);
    _pathCtrl = TextEditingController(text: d.apiPath);
    _userCtrl = TextEditingController(text: d.apiUser);
    _passCtrl = TextEditingController(text: d.apiPassword);
    _https = d.apiHttps;
    _iconIndex = d.iconIndex;
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _slugCtrl, _hostCtrl, _pathCtrl, _userCtrl, _passCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    final provider = context.read<DeviceProvider>();
    final updated = widget.device.copyWith(
      name: _nameCtrl.text.trim(),
      stationSlug: _slugCtrl.text.trim().toLowerCase(),
      apiHost: _hostCtrl.text.trim(),
      apiPath: _pathCtrl.text.trim(),
      apiUser: _userCtrl.text.trim(),
      apiPassword: _passCtrl.text,
      apiHttps: _https,
      iconIndex: _iconIndex,
    );

    final result = await provider.updateDevice(updated);

    if (mounted) {
      if (result.error != null) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error!), backgroundColor: Colors.red),
        );
      } else {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Änderungen erfolgreich gespeichert.')),
        );
      }
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 20),
            Text('Station konfigurieren', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            
            TextField(controller: _nameCtrl, enabled: !_isSaving, decoration: const InputDecoration(labelText: 'Anzeigename')),
            const SizedBox(height: 12),
            TextField(controller: _slugCtrl, enabled: !_isSaving, decoration: const InputDecoration(labelText: 'Station Slug (API)')),
            
            const Divider(height: 40),
            Text('API-EINSTELLUNGEN', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey)),
            const SizedBox(height: 12),
            
            TextField(controller: _hostCtrl, enabled: !_isSaving, decoration: const InputDecoration(labelText: 'Server Adresse')),
            const SizedBox(height: 12),
            TextField(controller: _pathCtrl, enabled: !_isSaving, decoration: const InputDecoration(labelText: 'API Pfad')),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _https,
              onChanged: _isSaving ? null : (v) => setState(() => _https = v),
              title: const Text('HTTPS verwenden'),
              contentPadding: EdgeInsets.zero,
            ),
            
            const Divider(height: 40),
            Text('SYMBOL', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey)),
            const SizedBox(height: 12),
            _IconPicker(selected: _iconIndex, onChanged: (i) => setState(() => _iconIndex = i)),
            
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Änderungen speichern'),
            ),
          ],
        ),
      ),
    );
  }
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
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSelected ? Colors.blue : Colors.grey.withOpacity(0.3), width: 2),
            ),
            child: Icon(WeatherUtils.deviceIcons[i], color: isSelected ? Colors.blue : Colors.grey, size: 20),
          ),
        );
      }),
    );
  }
}
