import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// Verwaltet FCM-Push-Benachrichtigungen.
class PushService {
  final AuthService _auth;

  PushService(this._auth);

  Future<void> init() async {
	// Berechtigungen anfragen (Android 13+)
	await FirebaseMessaging.instance.requestPermission(
	  alert: true,
	  badge: true,
	  sound: true,
	);

	// FCM-Token beim Backend registrieren wenn angemeldet
	FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);

	if (_auth.isLoggedIn) {
	  final token = await FirebaseMessaging.instance.getToken();
	  if (token != null) await _registerToken(token);
	}

	// Vordergrund-Benachrichtigungen anzeigen
	await FirebaseMessaging.instance
		.setForegroundNotificationPresentationOptions(
	  alert: true,
	  badge: true,
	  sound: true,
	);
  }

  Future<void> _registerToken(String token) async {
	if (!_auth.isLoggedIn) return;
	final uri = Uri.parse('${_auth.backendUrl}/index.php')
		.replace(queryParameters: {'route': 'push', 'action': 'register'});
	try {
	  await http.post(
		uri,
		headers: {
		  'Content-Type': 'application/json',
		  'Authorization': 'Bearer ${_auth.currentUser!.token}',
		},
		body: jsonEncode({'fcm_token': token}),
	  );
	} catch (_) {
	  // Nicht-kritisch – wird beim nächsten Token-Refresh erneut versucht
	}
  }

  Future<void> unregister() async {
	final token = await FirebaseMessaging.instance.getToken();
	if (token == null || !_auth.isLoggedIn) return;
	final uri = Uri.parse('${_auth.backendUrl}/index.php')
		.replace(queryParameters: {'route': 'push', 'action': 'unregister'});
	try {
	  await http.delete(
		uri,
		headers: {
		  'Content-Type': 'application/json',
		  'Authorization': 'Bearer ${_auth.currentUser!.token}',
		},
		body: jsonEncode({'fcm_token': token}),
	  );
	} catch (_) {}
  }
}
