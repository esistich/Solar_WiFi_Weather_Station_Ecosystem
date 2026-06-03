import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:workmanager/workmanager.dart';
import 'firebase_options.dart';
import 'services/services.dart';
import 'screens/home_screen.dart';

// --- HINTERGRUND-TASKS (Workmanager) ---

const String syncTaskName = "net.timm_sander.sws.syncTask";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // 1. Dienste initialisieren (separater Isolate!)
    final notificationService = NotificationService();
    await notificationService.init();

    final repo = DeviceRepository();
    final api = ApiService();
    
    try {
      final devices = await repo.loadAll();
      for (final device in devices) {
        final result = await api.fetchLatest(device);
        if (result.data != null) {
          final m = result.data!;
          
          // Widget im Hintergrund aktualisieren
          await WidgetService.updateWidget(device, m);

          if (m.temperature <= 3.0) {
            await notificationService.showAlarm(
              id: device.id.hashCode + 1,
              title: 'Frostwarnung (Hintergrund) ❄️',
              body: '${device.name}: ${m.temperature.toStringAsFixed(1)}°C',
            );
          }
          if (m.batteryPct <= 20) {
            await notificationService.showAlarm(
              id: device.id.hashCode + 2,
              title: 'Akku schwach (Hintergrund) 🪫',
              body: '${device.name}: ${m.batteryPct}%',
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Background Task Error: $e");
    }

    return Future.value(true);
  });
}

// Hintergrund-Push-Handler (Firebase)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 1. Workmanager initialisieren
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );
  
  // Task alle 15 Minuten registrieren (Android Minimum)
  await Workmanager().registerPeriodicTask(
    "1",
    syncTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
  );

  // Firebase Background Handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  final authService = AuthService();
  await authService.init();

  final pushService = PushService(authService);
  await pushService.init();

  final notificationService = NotificationService();
  await notificationService.init();

  final deviceProvider = DeviceProvider(notificationService: notificationService);
  await deviceProvider.loadDevices();

  final themeProvider = ThemeProvider();
  await themeProvider.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authService),
        ChangeNotifierProvider.value(value: deviceProvider),
        Provider.value(value: pushService),
        Provider.value(value: notificationService),
        ChangeNotifierProvider.value(value: themeProvider),
      ],
      child: const SwsApp(),
    ),
  );
}

class SwsApp extends StatelessWidget {
  const SwsApp({super.key});

  static const _defaultSeedColor = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeProvider>().mode;

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: 'SWS Companion',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: _buildTheme(Brightness.light, lightDynamic),
          darkTheme: _buildTheme(Brightness.dark, darkDynamic),
          home: const HomeScreen(),
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness, ColorScheme? dynamicScheme) {
    final colorScheme = dynamicScheme?.harmonized() ??
        ColorScheme.fromSeed(
          seedColor: _defaultSeedColor,
          brightness: brightness,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.4),
            width: 1,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: colorScheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
    );
  }
}
