import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'device_repository.dart';
import 'api_service.dart';
import 'notification_service.dart';
import 'widget_service.dart';
import 'auth_service.dart';

class DeviceProvider extends ChangeNotifier {
  final DeviceRepository _repo;
  final ApiService _api;
  final NotificationService? _notifications;
  final AuthService? _auth;

  List<Device> _devices = [];
  final Map<String, Measurement?> _measurements = {};
  final Map<String, bool> _loading = {};
  final Map<String, String?> _errors = {};
  final Map<String, List<MeasurementPoint>> _sparklines = {};
  
  final Set<String> _activeFrostAlarms = {};
  final Set<String> _activeBatteryAlarms = {};

  List<int> _activeWidgetIds = [];
  final Map<int, Map<String, dynamic>> _widgetConfigs = {};

  List<Device> get devices => List.unmodifiable(_devices);
  List<int> get activeWidgetIds => _activeWidgetIds;

  Measurement? measurementFor(String deviceId) => _measurements[deviceId];
  bool isLoading(String deviceId) => _loading[deviceId] ?? false;
  String? errorFor(String deviceId) => _errors[deviceId];

  DeviceProvider({
    DeviceRepository? repo, 
    ApiService? api, 
    NotificationService? notificationService,
    AuthService? authService,
  }) : _repo = repo ?? DeviceRepository(),
       _api = api ?? ApiService(),
       _notifications = notificationService,
       _auth = authService;

  Future<void> loadDevices() async {
    _devices = await _repo.loadAll();
    await loadWidgetConfigs();
    notifyListeners();
    await refreshAll();
  }

  Future<void> loadWidgetConfigs() async {
    _activeWidgetIds = await WidgetService.getActiveWidgetIds();
    final prefs = await SharedPreferences.getInstance();
    
    for (final id in _activeWidgetIds) {
      final raw = prefs.getString('widget_config_$id');
      if (raw != null) {
        _widgetConfigs[id] = jsonDecode(raw) as Map<String, dynamic>;
      }
    }
  }

  Future<void> setWidgetConfig(int widgetId, String deviceId, List<String> metrics) async {
    await WidgetService.saveConfig(widgetId, deviceId, metrics);
    await loadWidgetConfigs();
    notifyListeners();
    
    final device = _devices.firstWhere((d) => d.id == deviceId);
    final m = _measurements[deviceId];
    if (m != null) {
      await WidgetService.updateWidget(widgetId, device, m, metrics: metrics);
    }
  }

  Map<String, dynamic>? getConfigForWidget(int widgetId) => _widgetConfigs[widgetId];

  Future<void> refreshAll() async {
    await Future.wait(_devices.map((d) => refreshDevice(d.id)));
  }

  Future<void> refreshDevice(String id) async {
    try {
      final device = _devices.firstWhere((d) => d.id == id);
      _loading[id] = true;
      _errors[id] = null;
      notifyListeners();

      final result = await _api.fetchLatest(device);
      
      if (result.error != null) {
        _errors[id] = result.error;
      } else {
        final measurement = result.data!;
        _measurements[id] = measurement;
        
        for (final widgetId in _activeWidgetIds) {
          final config = _widgetConfigs[widgetId];
          if (config != null && config['deviceId'] == id) {
            final metrics = (config['metrics'] as List?)?.cast<String>() ?? ['humidity'];
            await WidgetService.updateWidget(widgetId, device, measurement, metrics: metrics);
          }
        }

        _checkAlarms(device, measurement);
        _loadSparkline(device);
      }
    } catch (_) {} finally {
      _loading[id] = false;
      notifyListeners();
    }
  }

  void _checkAlarms(Device device, Measurement m) {
    if (m.temperature <= 3.0) {
      _errors[device.id] = '⚠️ FROSTWARNUNG: ${m.temperature.toStringAsFixed(1)}°C';
      if (!_activeFrostAlarms.contains(device.id)) {
        _notifications?.showAlarm(id: device.id.hashCode + 1, title: 'Frostgefahr! ❄️', body: 'Station "${device.name}" meldet ${m.temperature.toStringAsFixed(1)}°C.');
        _activeFrostAlarms.add(device.id);
      }
    } else {
      _activeFrostAlarms.remove(device.id);
    }

    if (m.batteryPct <= 20) {
      _errors[device.id] = '🪫 AKKU SCHWACH: ${m.batteryPct}%';
      if (!_activeBatteryAlarms.contains(device.id)) {
        _notifications?.showAlarm(id: device.id.hashCode + 2, title: 'Akku fast leer! 🪫', body: 'Station "${device.name}" hat nur noch ${m.batteryPct}% Akku.');
        _activeBatteryAlarms.add(device.id);
      }
    } else {
      _activeBatteryAlarms.remove(device.id);
    }
  }

  Future<void> _loadSparkline(Device device) async {
    final token = _auth?.currentUser?.token;
    final result = await _api.fetchHistory(device, hours: 24, bearerToken: token);
    if (result.data != null) {
      _sparklines[device.id] = result.data!;
      notifyListeners();
    }
  }

  List<MeasurementPoint> sparklineFor(String deviceId) => _sparklines[deviceId] ?? [];

  Future<void> addDevice(Device device) async {
    await _repo.add(device);
    _devices = await _repo.loadAll();
    notifyListeners();
    await refreshDevice(device.id);
  }

  Future<ApiResult<void>> updateDevice(Device newDevice) async {
    try {
      final oldDevice = _devices.firstWhere((d) => d.id == newDevice.id, orElse: () => newDevice);
      if (oldDevice.name != newDevice.name || oldDevice.stationSlug != newDevice.stationSlug) {
        final token = _auth?.currentUser?.token;
        if (token != null) {
          final apiResult = await _api.updateStation(oldDevice, currentSlug: oldDevice.stationSlug, name: newDevice.name, newSlug: newDevice.stationSlug, bearerToken: token);
          if (apiResult.error != null) return (data: null, error: apiResult.error);
        }
      }
      await _repo.update(newDevice);
      _devices = await _repo.loadAll();
      notifyListeners();
      await refreshDevice(newDevice.id);
      return (data: null, error: null);
    } catch (e) {
      return (data: null, error: 'Interner Fehler beim Speichern: $e');
    }
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
