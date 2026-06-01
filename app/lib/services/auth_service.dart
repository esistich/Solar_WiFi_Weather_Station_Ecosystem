import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// Verwaltet Login, Registrierung und JWT-Token-Persistenz.
class AuthService extends ChangeNotifier {
  static const _tokenKey = 'auth_token_v1';
  static const _userKey  = 'auth_user_v1';

  // Backend-URL – zeigt auf den v1-Router
  static const String defaultBackendUrl = 'https://timm-sander.net/sws/api/v1';

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
	  final user = await _post('auth/login', {
	  'email': email,
	  'password': password,
	});
	await _persist(user);
  }

  Future<void> register(String email, String password, String inviteCode) async {
	  final user = await _post('auth/register', {
	  'email': email,
	  'password': password,
	  'invite_code': inviteCode,
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

  Future<AppUser> _post(String path, Map<String, dynamic> body) async {
	final uri = Uri.parse('$_backendUrl/$path');
	final http.Response response;
	try {
	  response = await http
		  .post(
			uri,
			headers: {'Content-Type': 'application/json'},
			body: jsonEncode(body),
		  )
		  .timeout(const Duration(seconds: 10));
	} catch (e) {
	  throw Exception('Netzwerkfehler: $e');
	}

	// Leere Antwort abfangen (z.B. bei Netzwerk-Proxy)
	if (response.body.isEmpty) {
	  throw Exception('Keine Antwort vom Server (HTTP ${response.statusCode})');
	}

	Map<String, dynamic> json;
	try {
	  json = jsonDecode(response.body) as Map<String, dynamic>;
	} catch (_) {
	  throw Exception('Ungültige Server-Antwort (HTTP ${response.statusCode})');
	}

	if (response.statusCode >= 400) {
	  throw Exception(json['error'] ?? 'Fehler (HTTP ${response.statusCode})');
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
