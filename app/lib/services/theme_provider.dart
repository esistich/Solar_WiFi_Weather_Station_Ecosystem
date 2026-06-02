import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Verwaltet den Dark/Light-Mode und speichert die Einstellung persistent.
class ThemeProvider extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  Future<void> init() async {
	final prefs = await SharedPreferences.getInstance();
	final saved = prefs.getString(_key);
	if (saved == 'dark') {
	  _mode = ThemeMode.dark;
	} else if (saved == 'light') {
	  _mode = ThemeMode.light;
	} else {
	  _mode = ThemeMode.system;
	}
	notifyListeners();
  }

  Future<void> toggle() async {
	_mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
	final prefs = await SharedPreferences.getInstance();
	await prefs.setString(_key, _mode == ThemeMode.dark ? 'dark' : 'light');
	notifyListeners();
  }
}
