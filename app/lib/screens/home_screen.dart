import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/services.dart';
import '../widgets/widgets.dart';
import '../models/models.dart';
import 'detail_screen.dart';
import 'device_setup_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _autoRefresh;
  String? _selectedDeviceId; // Für Tablet-Layout

  @override
  void initState() {
    super.initState();
    _autoRefresh = Timer.periodic(
      const Duration(minutes: 5),
      (_) => context.read<DeviceProvider>().refreshAll(),
    );
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeviceProvider>();
    // Tablet/Landscape Erkennung: Breite > 900px
    final isTablet = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Solar Weather'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => provider.refreshAll(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: isTablet 
          ? _buildTabletLayout(provider) 
          : _buildMobileLayout(provider),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSetup(context),
        icon: const Icon(Icons.add),
        label: const Text('Gerät hinzufügen'),
      ),
    );
  }

  // --- MOBIL LAYOUT (Liste) ---
  Widget _buildMobileLayout(DeviceProvider provider) {
    if (provider.devices.isEmpty) return _EmptyState(onAdd: () => _openSetup(context));

    return RefreshIndicator(
      onRefresh: provider.refreshAll,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: provider.devices.length,
        itemBuilder: (context, index) {
          final device = provider.devices[index];
          return TileCard(
            device: device,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DetailScreen(device: device)),
            ),
            onRefresh: () => provider.refreshDevice(device.id),
          );
        },
      ),
    );
  }

  // --- TABLET LAYOUT (Master-Detail) ---
  Widget _buildTabletLayout(DeviceProvider provider) {
    if (provider.devices.isEmpty) return _EmptyState(onAdd: () => _openSetup(context));

    // Falls nichts ausgewählt, nimm das erste Gerät
    if (_selectedDeviceId == null && provider.devices.isNotEmpty) {
      _selectedDeviceId = provider.devices.first.id;
    }

    final selectedDevice = provider.devices.firstWhere(
      (d) => d.id == _selectedDeviceId,
      orElse: () => provider.devices.first,
    );

    return Row(
      children: [
        // Linke Spalte: Liste
        SizedBox(
          width: 350,
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: provider.devices.length,
            itemBuilder: (context, index) {
              final device = provider.devices[index];
              final isSelected = device.id == _selectedDeviceId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TileCard(
                  device: device,
                  isSelected: isSelected, // Neues Property
                  onTap: () => setState(() => _selectedDeviceId = device.id),
                  onRefresh: () => provider.refreshDevice(device.id),
                ),
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        // Rechte Spalte: Details
        Expanded(
          child: DetailScreen(key: ValueKey(_selectedDeviceId), device: selectedDevice, isEmbedded: true),
        ),
      ],
    );
  }

  void _openSetup(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DeviceSetupScreen()),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wb_cloudy_outlined, size: 72, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Noch keine Geräte', style: TextStyle(fontSize: 18, color: Colors.grey)),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Gerät hinzufügen')),
        ],
      ),
    );
  }
}
