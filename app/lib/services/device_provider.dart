import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'device_repository.dart';
import 'api_service.dart';

/// Zentraler State fuer alle Geraete, ihre aktuellen Messwerte und Sparkline-Daten.
class DeviceProvider extends ChangeNotifier {
  final DeviceRepository _repo;
  final ApiService _api;

  List<Device> _devices = [];
  final Map<String, Measurement?> _measurements = {};
  final Map<String, bool> _loading = {};
  final Map<String, String?> _errors = {};
  final Map<String, List<MeasurementPoint>> _sparklines = {};

  List<Device> get devices => List.unmodifiable(_devices);

  Measurement? measurementFor(String deviceId) => _measurements[deviceId];
  bool isLoading(String deviceId) => _loading[deviceId] ?? false;
  String? errorFor(String deviceId) => _errors[deviceId];

  /// Letzte 24h-Temperaturpunkte fuer die Mini-Sparkline (leer = noch nicht geladen).
  List<MeasurementPoint> sparklineFor(String deviceId) =>
      _sparklines[deviceId] ?? [];

  DeviceProvider({DeviceRepository? repo, ApiService? api})
      : _repo = repo ?? DeviceRepository(),
        _api = api ?? ApiService();

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

    try {
      final m = await _api.fetchLatest(device);
      _measurements[id] = m;
    } catch (e) {
      _errors[id] = e.toString();
    } finally {
      _loading[id] = false;
      notifyListeners();
    }

    // Sparkline-Daten im Hintergrund nachladen (Fehler werden still ignoriert)
    _loadSparkline(device);
  }

  /// Laedt 24h-Verlauf fuer die Sparkline (optional, kein JWT noetig).
  Future<void> _loadSparkline(Device device) async {
    try {
      final points = await _api.fetchHistory(device, hours: 24);
      _sparklines[device.id] = points;
      notifyListeners();
    } catch (_) {
      // Sparkline ist optional – kein Fehler anzeigen
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
    notifyListeners();
  }
}
