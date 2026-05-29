import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// Verwaltet Login, Registrierung und JWT-Token-Persistenz.
class AuthService extends ChangeNotifier {
  static const _tokenKey = 'auth_token_v1';
  static const _userKey  = 'auth_user_v1';

  // Backend-URL – zeigt auf das PHP-Backend unter /api/backend/
  static const String defaultBackendUrl = 'https://timm-sander.net/sws/api/backend';

  AppUser? _currentUser;
  String _backendUrl = defaultBackendUrl;

  AppUser? get currentUser => _currentUser;
  String get backendUrl => _backendUrl;
  bool get isLoggedIn => _currentUser != null;

  Future<void> init() async {
	final prefs = await SharedPreferences.getInstance();
	final raw = prefs.getString(_userKey);
	if (raw != null) {
	  try {
		_currentUser = AppUser.fromJson(
		  jsonDecode(raw) as Map<String, dynamic>,
		);
		notifyListeners();
	  } catch (_) {}
	}
  }

  Future<void> login(String email, String password) async {
	final user = await _post('auth', 'login', {
	  'email': email,
	  'password': password,
	});
	await _persist(user);
  }

  Future<void> register(String email, String password) async {
	final user = await _post('auth', 'register', {
	  'email': email,
	  'password': password,
	});
	await _persist(user);
  }

  Future<void> logout() async {
	_currentUser = null;
	final prefs = await SharedPreferences.getInstance();
	await prefs.remove(_tokenKey);
	await prefs.remove(_userKey);
	notifyListeners();
  }

  Future<AppUser> _post(String route, String action, Map<String, dynamic> body) async {
	final uri = Uri.parse('$_backendUrl/index.php').replace(
	  queryParameters: {'route': route, 'action': action},
	);
	final response = await http
		.post(
		  uri,
		  headers: {'Content-Type': 'application/json'},
		  body: jsonEncode(body),
		)
		.timeout(const Duration(seconds: 10));

	final json = jsonDecode(response.body) as Map<String, dynamic>;
	if (response.statusCode >= 400) {
	  throw Exception(json['error'] ?? 'Fehler beim Login');
	}
	return AppUser.fromJson(json);
  }

  Future<void> _persist(AppUser user) async {
	_currentUser = user;
	final prefs = await SharedPreferences.getInstance();
	await prefs.setString(_userKey, jsonEncode(user.toJson()));
	notifyListeners();
  }

  void setBackendUrl(String url) {
	_backendUrl = url;
	notifyListeners();
  }
}
