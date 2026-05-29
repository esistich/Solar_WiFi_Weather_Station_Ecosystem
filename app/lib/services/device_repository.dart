import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// Verwaltet die Geräte-Liste im lokalen Speicher (SharedPreferences).
class DeviceRepository {
  static const _key = 'devices_v1';

  Future<List<Device>> loadAll() async {
	final prefs = await SharedPreferences.getInstance();
	final raw = prefs.getString(_key);
	if (raw == null || raw.isEmpty) return [];
	return Device.decodeList(raw);
  }

  Future<void> saveAll(List<Device> devices) async {
	final prefs = await SharedPreferences.getInstance();
	await prefs.setString(_key, Device.encodeList(devices));
  }

  Future<void> add(Device device) async {
	final list = await loadAll();
	list.add(device);
	await saveAll(list);
  }

  Future<void> update(Device device) async {
	final list = await loadAll();
	final idx = list.indexWhere((d) => d.id == device.id);
	if (idx >= 0) list[idx] = device;
	await saveAll(list);
  }

  Future<void> remove(String id) async {
	final list = await loadAll();
	list.removeWhere((d) => d.id == id);
	await saveAll(list);
  }
}
