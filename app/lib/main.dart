import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'services/services.dart';
import 'screens/home_screen.dart';

// Hintergrund-Push-Handler (muss Top-Level sein)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final authService = AuthService();
  await authService.init();

  final pushService = PushService(authService);
  await pushService.init();

  final deviceProvider = DeviceProvider();
  await deviceProvider.loadDevices();

  runApp(
	MultiProvider(
	  providers: [
		ChangeNotifierProvider.value(value: authService),
		ChangeNotifierProvider.value(value: deviceProvider),
		Provider.value(value: pushService),
	  ],
	  child: const SwsApp(),
	),
  );
}

class SwsApp extends StatelessWidget {
  const SwsApp({super.key});

  @override
  Widget build(BuildContext context) {
	return MaterialApp(
	  title: 'SWS Companion',
	  debugShowCheckedModeBanner: false,
	  theme: ThemeData(
		useMaterial3: true,
		colorScheme: ColorScheme.fromSeed(
		  seedColor: const Color(0xFF1565C0), // kräftiges Blau
		  brightness: Brightness.light,
		),
		cardTheme: CardThemeData(
		  elevation: 2,
		  shape: RoundedRectangleBorder(
			borderRadius: BorderRadius.circular(16),
		  ),
		),
		inputDecorationTheme: InputDecorationTheme(
		  border: OutlineInputBorder(
			borderRadius: BorderRadius.circular(8),
		  ),
		  contentPadding:
			  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
		),
	  ),
	  darkTheme: ThemeData(
		useMaterial3: true,
		colorScheme: ColorScheme.fromSeed(
		  seedColor: const Color(0xFF1565C0),
		  brightness: Brightness.dark,
		),
		cardTheme: CardThemeData(
		  elevation: 2,
		  shape: RoundedRectangleBorder(
			borderRadius: BorderRadius.circular(16),
		  ),
		),
	  ),
	  home: const HomeScreen(),
	);
  }
}
