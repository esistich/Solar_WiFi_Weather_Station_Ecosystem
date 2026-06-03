import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'device_repository.dart';
import 'api_service.dart';
import 'notification_service.dart';
import 'widget_service.dart';

/// Zentraler State fuer alle Geraete, ihre aktuellen Messwerte und Sparkline-Daten.
class DeviceProvider extends ChangeNotifier {
  final DeviceRepository _repo;
  final ApiService _api;
  final NotificationService? _notifications;

  List<Device> _devices = [];
  final Map<String, Measurement?> _measurements = {};
  final Map<String, bool> _loading = {};
  final Map<String, String?> _errors = {};
  final Map<String, List<MeasurementPoint>> _sparklines = {};
  
  // Tracked alarms to prevent notification spam
  final Set<String> _activeFrostAlarms = {};
  final Set<String> _activeBatteryAlarms = {};

  List<Device> get devices => List.unmodifiable(_devices);

  Measurement? measurementFor(String deviceId) => _measurements[deviceId];
  bool isLoading(String deviceId) => _loading[deviceId] ?? false;
  String? errorFor(String deviceId) => _errors[deviceId];

  /// Letzte 24h-Temperaturpunkte fuer die Mini-Sparkline.
  List<MeasurementPoint> sparklineFor(String deviceId) =>
      _sparklines[deviceId] ?? [];

  DeviceProvider({DeviceRepository? repo, ApiService? api, NotificationService? notificationService})
      : _repo = repo ?? DeviceRepository(),
        _api = api ?? ApiService(),
        _notifications = notificationService;

  Future<void> loadDevices() async {
    _devices = await _repo.loadAll();
    notifyListeners();
    await refreshAll();
  }

  Future<void> refreshAll() async {
    await Future.wait(_devices.map((d) => refreshDevice(d.id)));
  }

  Future<void> refreshDevice(String id) async {
    final device = _devices.firstWhere(
      (d) => d.id == id,
      orElse: () => throw StateError('Geraet nicht gefunden: $id'),
    );
    
    _loading[id] = true;
    _errors[id] = null;
    notifyListeners();

    final result = await _api.fetchLatest(device);
    
    if (result.error != null) {
      _errors[id] = result.error;
    } else {
      _measurements[id] = result.data;
      
      // Widget aktualisieren
      WidgetService.updateWidget(device, result.data!);

      _checkAlarms(device, result.data!);
      _loadSparkline(device);
    }

    _loading[id] = false;
    notifyListeners();
  }

  void _checkAlarms(Device device, Measurement m) {
    // Frost-Alarm (<= 3°C)
    if (m.temperature <= 3.0) {
      _errors[device.id] = '⚠️ FROSTWARNUNG: ${m.temperature.toStringAsFixed(1)}°C';
      if (!_activeFrostAlarms.contains(device.id)) {
        _notifications?.showAlarm(
          id: device.id.hashCode + 1,
          title: 'Frostgefahr! ❄️',
          body: 'Station "${device.name}" meldet ${m.temperature.toStringAsFixed(1)}°C.',
        );
        _activeFrostAlarms.add(device.id);
      }
    } else {
      _activeFrostAlarms.remove(device.id);
    }

    // Akku-Alarm (<= 20%)
    if (m.batteryPct <= 20) {
      _errors[device.id] = '🪫 AKKU SCHWACH: ${m.batteryPct}%';
      if (!_activeBatteryAlarms.contains(device.id)) {
        _notifications?.showAlarm(
          id: device.id.hashCode + 2,
          title: 'Akku fast leer! 🪫',
          body: 'Station "${device.name}" hat nur noch ${m.batteryPct}% Akku.',
        );
        _activeBatteryAlarms.add(device.id);
      }
    } else {
      _activeBatteryAlarms.remove(device.id);
    }
  }

  Future<void> _loadSparkline(Device device) async {
    final result = await _api.fetchHistory(device, hours: 24);
    if (result.data != null) {
      _sparklines[device.id] = result.data!;
      notifyListeners();
    }
  }

  Future<void> addDevice(Device device) async {
    await _repo.add(device);
    _devices = await _repo.loadAll();
    notifyListeners();
    await refreshDevice(device.id);
  }

  Future<void> updateDevice(Device device) async {
    await _repo.update(device);
    _devices = await _repo.loadAll();
    notifyListeners();
    await refreshDevice(device.id);
  }

  Future<void> removeDevice(String id) async {
    await _repo.remove(id);
    _devices.removeWhere((d) => d.id == id);
    _measurements.remove(id);
    _loading.remove(id);
    _errors.remove(id);
    _sparklines.remove(id);
    _activeFrostAlarms.remove(id);
    _activeBatteryAlarms.remove(id);
    notifyListeners();
  }
}
