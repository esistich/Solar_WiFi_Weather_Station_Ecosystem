import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Hier könnte man auf den Klick reagieren (z.B. App öffnen)
      },
    );
  }

  Future<void> showAlarm({required String title, required String body, int id = 0}) async {
    const androidDetails = AndroidNotificationDetails(
      'sws_alarms',
      'Wetterstation Alarme',
      channelDescription: 'Benachrichtigungen für Frost und niedrigen Akkustand',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      id,
      title,
      body,
      notificationDetails,
    );
  }
}
