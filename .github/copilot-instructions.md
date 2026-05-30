# Copilot Instructions

## Projektrichtlinien
- Wenn neue Arduino-Bibliotheken im Sketch verwendet werden, diese direkt per PowerShell von GitHub herunterladen und nach C:\Users\EsIst\Documents\Arduino\libraries\ installieren – nicht nur erwähnen.
- Nach jeder Änderung an Dateien im api/-Ordner automatisch den upload/-Ordner aktualisieren mit: `robocopy api upload /E /XF "db.php" "auth.php" "*adminsdk*.json" /XD "upload" "homeassistant"` – homeassistant/ gehört nicht auf den Server.

## Sicherheit & Secrets
- `app/lib/firebase_options.dart`, `app/android/google-services.json`, `api/lib/auth.php`-Credentials und alle Dateien mit API-Keys/Passwörtern dürfen niemals committet werden.
- Generierte Firebase-Dateien (`firebase_options.dart`, `google-services.json`) sind in `.gitignore` eingetragen und bleiben lokal – stattdessen `.example`-Vorlagen ohne echte Werte im Repo pflegen.
- Arduino-Sketches: WLAN-SSID und Passwort niemals im Quellcode – immer über das Config-Portal oder EEPROM-Konfiguration einlesen.
- PHP-Backend: Datenbankpasswörter und JWT-Secrets nur in serverseitigen Konfigurationsdateien außerhalb des Web-Roots oder in Umgebungsvariablen.
- Vor jedem Commit `git diff --cached` prüfen ob versehentlich Secrets im Staging-Bereich landen.

## Sprachspezifische Hinweise
### Dart / Flutter
- `firebase_options.dart` und `google-services.json` immer in `.gitignore`; FlutterFire-Konfiguration lokal regenerieren (`flutterfire configure`).
- Keinen `apiKey`, `appId` oder vergleichbare Werte als String-Literal im Dart-Code hartcodieren.

### PHP
- Credentials und Secrets aus `.env` oder einer Konfigurationsdatei außerhalb des Document-Root lesen.
- `.htaccess` für alle `lib/`-Verzeichnisse mit `Require all denied` schützen.

### Arduino / C++
- Keine WLAN-Credentials, API-Keys oder Endpunkt-URLs als Klartext in `.ino`/`.h`-Dateien – Config-Portal oder EEPROM verwenden.
- Sketch-Konfigurationsdateien mit echten Credentials in `.gitignore` aufnehmen.