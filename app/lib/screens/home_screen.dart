import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/services.dart';
import '../widgets/widgets.dart';
import 'detail_screen.dart';
import 'device_setup_screen.dart';
import 'settings_screen.dart';

/// Haupt-Dashboard: zeigt alle registrierten Geräte als Kacheln.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _autoRefresh;

  @override
  void initState() {
	super.initState();
	// Automatisch alle 5 Minuten aktualisieren
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
	return Scaffold(
	  appBar: AppBar(
		title: const Text('SWS Companion'),
		actions: [
		  IconButton(
			icon: const Icon(Icons.refresh),
			tooltip: 'Alle aktualisieren',
			onPressed: () => context.read<DeviceProvider>().refreshAll(),
		  ),
		  IconButton(
			icon: const Icon(Icons.settings_outlined),
			tooltip: 'Einstellungen',
			onPressed: () => Navigator.push(
			  context,
			  MaterialPageRoute(builder: (_) => const SettingsScreen()),
			),
		  ),
		],
	  ),
	  body: Consumer<DeviceProvider>(
		builder: (context, provider, _) {
		  if (provider.devices.isEmpty) {
			return _EmptyState(
			  onAdd: () => _openSetup(context),
			);
		  }

		  return RefreshIndicator(
			onRefresh: provider.refreshAll,
			child: ListView.builder(
			  padding: const EdgeInsets.all(12),
			  itemCount: provider.devices.length,
			  itemBuilder: (context, index) {
				final device = provider.devices[index];
				return Padding(
				  padding: const EdgeInsets.only(bottom: 12),
				  child: TileCard(
					device: device,
					measurement: provider.measurementFor(device.id),
					loading: provider.isLoading(device.id),
					error: provider.errorFor(device.id),
					onTap: () => Navigator.push(
					  context,
					  MaterialPageRoute(
						builder: (_) => DetailScreen(device: device),
					  ),
					),
					onEdit: () => Navigator.push(
					  context,
					  MaterialPageRoute(
						builder: (_) => DeviceSetupScreen(device: device),
					  ),
					),
					onRefresh: () =>
						provider.refreshDevice(device.id),
				  ),
				);
			  },
			),
		  );
		},
	  ),
	  floatingActionButton: FloatingActionButton.extended(
		onPressed: () => _openSetup(context),
		icon: const Icon(Icons.add),
		label: const Text('Gerät hinzufügen'),
	  ),
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
		  const Text(
			'Noch keine Geräte',
			style: TextStyle(fontSize: 18, color: Colors.grey),
		  ),
		  const SizedBox(height: 8),
		  const Text(
			'Füge deine erste Wetterstation hinzu.',
			style: TextStyle(color: Colors.grey),
		  ),
		  const SizedBox(height: 24),
		  FilledButton.icon(
			onPressed: onAdd,
			icon: const Icon(Icons.add),
			label: const Text('Gerät hinzufügen'),
		  ),
		],
	  ),
	);
  }
}
