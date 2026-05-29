import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'device_repository.dart';
import 'api_service.dart';

/// Zentraler State für alle Geräte und ihre aktuellen Messwerte.
class DeviceProvider extends ChangeNotifier {
  final DeviceRepository _repo;
  final ApiService _api;

  List<Device> _devices = [];
  final Map<String, Measurement?> _measurements = {};
  final Map<String, bool> _loading = {};
  final Map<String, String?> _errors = {};

  List<Device> get devices => List.unmodifiable(_devices);

  Measurement? measurementFor(String deviceId) => _measurements[deviceId];
  bool isLoading(String deviceId) => _loading[deviceId] ?? false;
  String? errorFor(String deviceId) => _errors[deviceId];

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
	final device = _devices.firstWhere((d) => d.id == id, orElse: () => throw StateError('Gerät nicht gefunden: $id'));
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
	notifyListeners();
  }
}
