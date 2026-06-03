# SWS Companion App – Flutter

Eine Android-App (Flutter) zur Verwaltung und Überwachung von Solar WiFi Weather Stations.

## Voraussetzungen

- Flutter SDK ≥ 3.32 → https://docs.flutter.dev/get-started/install/windows
- Android Studio oder VS Code mit Flutter-Extension
- Android SDK (wird mit Android Studio installiert)
- Firebase-Projekt (für Push-Benachrichtigungen)

## Erste Schritte

```bash
cd app

# Abhängigkeiten installieren
flutter pub get

# Firebase konfigurieren (einmalig)
# 1. Firebase Console → Projekt erstellen
# 2. Android-App registrieren (Package: net.timm_sander.sws)
# 3. google-services.json herunterladen → app/android/app/google-services.json

# Debug-Build starten
flutter run

# Release-APK bauen
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

## Projektstruktur

```
lib/
  main.dart              Einstiegspunkt, Provider-Setup, Theme
  models/
	device.dart          Gerät (Name, API-URL, ID)
	measurement.dart     Messwert + History-Punkt
	app_user.dart        Angemeldeter Nutzer (JWT)
  services/
	api_service.dart     PHP-API (data.php, history.php)
	device_repository.dart  Geräte in SharedPreferences
	device_provider.dart    ChangeNotifier State
	device_setup_service.dart  Soft-AP Setup-Flow
	auth_service.dart    Login/Register gegen Node.js-Backend
	push_service.dart    FCM-Token registrieren
  screens/
	home_screen.dart     Dashboard mit Kacheln
	detail_screen.dart   Detailansicht + History-Chart
	device_setup_screen.dart  3-Schritt Geräte-Setup
	settings_screen.dart Geräte verwalten, Account
  widgets/
	tile_card.dart       Gerätekachel
	history_chart.dart   Temperatur-Verlaufschart (fl_chart)
```

## App-Icon anpassen

Ersetze `assets/images/app_icon.png` (1024×1024 px) und führe aus:
```bash
flutter pub add --dev flutter_launcher_icons
# Icon-Konfiguration in pubspec.yaml ergänzen, dann:
dart run flutter_launcher_icons
```

## Backend verbinden

Trage die Backend-URL in `lib/services/auth_service.dart` ein:
```dart
static const String defaultBackendUrl = 'https://dein-backend.example.com';
```

Oder mach es in den App-Einstellungen konfigurierbar (SettingsScreen → Backend-URL).
