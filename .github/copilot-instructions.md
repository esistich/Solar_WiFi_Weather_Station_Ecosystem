# Copilot Instructions

## Projektrichtlinien
- Wenn neue Arduino-Bibliotheken im Sketch verwendet werden, diese direkt per PowerShell von GitHub herunterladen und nach C:\Users\EsIst\Documents\Arduino\libraries\ installieren – nicht nur erwähnen.
- Bei jeder Aktualisierung der SWSApiClient-Bibliothek (library/SWSApiClient/) soll der Agent die Bibliothek automatisch in den Arduino-Libraries-Ordner kopieren (C:/Users/EsIst/Documents/Arduino/libraries/SWSApiClient/).
- Nach jeder Änderung an Dateien im api/-Ordner automatisch den upload/-Ordner aktualisieren mit: `robocopy api upload /E /XF "db.php" "auth.php" "*adminsdk*.json" /XD "upload" "homeassistant"` – homeassistant/ gehört nicht auf den Server.
- Nach jeder Änderung immer das passende Script ausführen: (1) api/ → `tools/build_upload.ps1` → upload/, (2) sketch_sws/ + sketch_sws_display/ + library/SWSApiClient/ → `tools/sync_arduino.ps1` → Arduino-Sketchbook, (3) app/ (Flutter) → `C:\flutter\bin\flutter build apk --release` → APK. Das zentrale Script `tools/build_all.ps1` führt alle drei Schritte durch. Einzelne Teile können mit -Skip api, -Skip arduino oder -Skip app übersprungen werden.
- SFTP-Deployment für Solar_WiFi_Weather_Station: Der vollständige Deploy-Ablauf ist IMMER:
  1. `powershell -ExecutionPolicy Bypass -File tools/build_upload.ps1` → synchronisiert api/ → upload/ (ohne Secrets)
  2. `powershell -ExecutionPolicy Bypass -File tools/deploy_server.ps1` → lädt upload/ per SFTP auf den Server hoch
  Credentials stehen in `.env` im Repo-Root: SFTP_HOST=ssh.timm-sander.net, SFTP_PORT=22, SFTP_USER=timm-sander.net, SFTP_PASS aus .env, SFTP_REMOTE_PATH=webroots/www/sws/api.
  Das Script nutzt Windows-OpenSSH `sftp`. Passwort-Auth hat früher funktioniert. Falls "Permission denied": SFTP-Passwort im Hoster-Panel prüfen und `.env` aktualisieren – NICHT nach SSH-Key suchen oder WinSCP installieren.
  Niemals nach dem Passwort fragen – es steht in der .env. Beide Schritte immer selbst ausführen, den User nie danach fragen.
- Bei Fehlern (z.B. HTTP 500) IMMER zuerst nur die zuletzt geänderten Dateien prüfen – nie sofort andere Dateien, den Server, .htaccess oder Konfigurationen untersuchen. Erst wenn die zuletzt geänderten Dateien als Ursache ausgeschlossen sind, weiter suchen.
- Niemals die .htaccess des Webspace-Roots oder WordPress-Verzeichnisses anfassen oder ändern.
- Für PHP-Fehlerdiagnose auf dem Webspace: wp-content/debug.log lesen (falls WP_DEBUG_LOG aktiv). Niemals .htaccess ändern um display_errors zu aktivieren.
- Flutter und Android SDK sind direkt auf C:\ installiert (z.B. C:\flutter und C:\Android\Sdk\). Immer diese Pfade verwenden, nie danach suchen. ADB befindet sich unter `C:\Android\Sdk\platform-tools\adb.exe`.
- Beim Bearbeiten von JavaScript-Dateien immer auf folgende Syntaxfehler prüfen bevor deployed wird: (1) `await` ohne `async` in Funktionsdeklarationen, (2) nested Backtick-Template-Literals (`` `...`x`...` `` ist ungültig — stattdessen String-Konkatenation `'x'+var+'x'` verwenden), (3) nach jedem größeren JS-Edit die kritischen Stellen mit get_file/read nochmal verifizieren.
- Für PHP-Syntax-Checks immer `C:\xampp\php\php.exe -l <datei>` verwenden, vor jedem Deploy von PHP-Dateien. PHP liegt unter `C:\xampp\php\php.exe` (XAMPP-Installation).
- Bei Zeitzonenkonvertierungen in JavaScript immer UTC+2 verwenden bzw. 'Europe/Berlin' (das deckt automatisch Sommer/Winterzeit ab). Zeitstempel aus der DB (UTC) sollen im Dashboard mit `Europe/Berlin` als Zeitzone dargestellt werden, damit automatisch zwischen CET (UTC+1) und CEST (UTC+2) umgeschaltet wird.

---

## API-Referenz – Solar WiFi Weather Station

**Basis-URL (Produktion):** `https://timm-sander.net/sws/api`  
**Router-Datei:** `api/v1/index.php` – alle `/v1/*`-Anfragen laufen hier durch.  
**Fallback ohne mod_rewrite:** `?r=<route>` z. B. `GET /sws/api/v1/index.php?r=data`

---

### Endpunkte

| Methode | Pfad                   | Auth           | Beschreibung                        |
|---------|------------------------|----------------|-------------------------------------|
| GET     | `/v1/data`             | –              | Letzter Messdatensatz (öffentlich)  |
| POST    | `/v1/data`             | Basic Auth     | Messdaten von Station hochladen     |
| GET     | `/v1/history`          | JWT Bearer     | Verlaufsdaten (App)                 |
| GET     | `/v1/status`           | –              | Health-Check (öffentlich)           |
| GET     | `/v1/stations`         | JWT Bearer     | Stationsliste                       |
| POST    | `/v1/auth/register`    | Einladungscode | App-Benutzer registrieren           |
| POST    | `/v1/auth/login`       | –              | App-Login → JWT                     |
| POST    | `/v1/auth/logout`      | JWT Bearer     | App-Logout                          |
| POST    | `/v1/push/register`    | JWT Bearer     | FCM-Push-Token registrieren         |
| POST    | `/v1/push/unregister`  | JWT Bearer     | FCM-Push-Token entfernen            |
| POST    | `/v1/invite/create`    | Admin-Session  | Einladungscode erzeugen             |
| GET     | `/v1/invite/list`      | Admin-Session  | Einladungscodes auflisten           |

**Legacy-Shims (nur für Rückwärtskompatibilität – NICHT für neue Clients verwenden):**
- `POST /sws/api/data.php`    → Stationsupload (mappt alte Feldnamen auf v1/data)
- `GET  /sws/api/history.php` → delegiert an v1/history
- `GET  /sws/api/status.php`  → delegiert an v1/status

---

### GET /v1/data – Antwortformat
{
  "station":          "sws-garten",
  "temperature":      21.5,
  "pool_temperature": 18.3,
  "humidity":         55.2,
  "rel_pressure":     1013.4,
  "abs_pressure":     987.1,
  "pressure_state":   "Steigend",
  "zambretti":        "B",
  "trend":            1,
  "battery_pct":      82.0,
  "battery_volt":     3.95,
  "wifi_strength":    -67,
  "created_at":       "2025-07-01 14:23:00",
  "data_age_s":       45
}
- `created_at` ist **Europe/Berlin** (CEST/CET) – Display und App müssen **keine** eigene Zeitzonenumrechnung machen.
- `data_age_s` = Sekunden seit letzter Messung, immer aktuell gegen UTC berechnet.
- Fehlende Sensoren fehlen im JSON komplett (kein `null`-Wert).
- Numerische Felder: `float` bzw. `int`. String-Felder: `pressure_state`, `zambretti`, `trend`.

---

### POST /v1/data – Messdaten hochladen (Station)

**Auth:** HTTP Basic Auth (Username/Passwort aus `api/config/auth.php`)  
**Content-Type:** `application/json`
{
  "station_slug":   "sws-garten",
  "temperature":    21.5,
  "humidity":       55.2,
  "rel_pressure":   1013.4,
  "abs_pressure":   987.1,
  "pressure_state": "Steigend",
  "zambretti":      "B",
  "trend":          1,
  "battery_pct":    82.0,
  "battery_volt":   3.95,
  "wifi_strength":  -67,
  "device_ts":      "2025-07-01T12:23:00Z"
}
- `station_slug` optional – default: erste Station in der DB.
- `device_ts` optionaler UTC-Timestamp des Geräts.
- Felder `station_slug`, `station_name`, `device_ts` werden intern verwendet, nicht als Messwert gespeichert.
- Neue Sensoren einfach als neuen Key hinzufügen – kein Schema-Change nötig (EAV).
- **Antwort:** `{ "ok": true, "measurement_id": 141, "station": "sws-garten", "errors": [] }`

---

### GET /v1/history – Verlaufsdaten (App)

**Auth:** `Authorization: Bearer <JWT>`

| Parameter | Typ    | Default | Beschreibung                                        |
|-----------|--------|---------|-----------------------------------------------------|
| `station` | string | erste   | Station-Slug                                        |
| `from`    | date   | –       | Startdatum `YYYY-MM-DD`                             |
| `to`      | date   | –       | Enddatum `YYYY-MM-DD`                               |
| `limit`   | int    | 100     | Max. Datenpunkte (max. 1000)                        |
| `metrics` | string | alle    | Komma-getrennt, z. B. `temperature,humidity`        |

---

### Welcher Client nutzt welchen Endpunkt

| Client                | Auth              | Lesen                  | Schreiben           |
|-----------------------|-------------------|------------------------|---------------------|
| **Station (ESP8266)** | HTTP Basic Auth   | –                      | `POST /v1/data`     |
| **Display (ESP8266)** | keine             | `GET /v1/data`         | –                   |
| **Flutter-App**       | JWT Bearer Token  | `GET /v1/history`      | –                   |
| **Admin-Dashboard**   | PHP-Session       | `api/admin/`           | `api/admin/`        |

---

### Regeln für alle neuen Clients / Code-Änderungen

1. **Display-Sketch** liest immer `GET /v1/data` – niemals direkt `data.php`.
2. **Station-Sketch** postet immer `POST /v1/data` (Legacy `data.php` nur für alte Firmware).
3. **Flutter-App** login → JWT speichern → `Authorization: Bearer <token>` bei jedem geschützten Request mitsenden.
4. **Timestamps in der Station** immer als UTC senden; `created_at` im GET-Response kommt in Europe/Berlin zurück – nicht nochmal umrechnen.
5. **Neue Messwerte** einfach als neuen Key im POST-Body senden – kein Schema-Change nötig.
6. **HTTP-Statuscodes:** 200 OK · 400 ungültiger Body · 401 Auth fehlt/falsch · 404 Station nicht gefunden · 405 Methode nicht erlaubt.
7. **Legacy-Shims** nur für bestehende alte Geräte – neue Implementierungen immer auf `/v1/`-Pfade zeigen.

---

## Sicherheit & Secrets
- `app/lib/firebase_options.dart`, `app/android/google-services.json`, `api/config/auth.php` und alle Dateien mit API-Keys/Passwörtern dürfen niemals committet werden.
- Generierte Firebase-Dateien (`firebase_options.dart`, `google-services.json`) sind in `.gitignore` – stattdessen `.example`-Vorlagen ohne echte Werte im Repo pflegen.
- Arduino-Sketches: WLAN-SSID und Passwort niemals im Quellcode – immer über das Config-Portal oder EEPROM einlesen.
- PHP-Backend: Datenbankpasswörter und JWT-Secrets nur in serverseitigen Konfigurationsdateien außerhalb des Web-Roots oder in Umgebungsvariablen.
- Vor jedem Commit `git diff --cached` prüfen ob versehentlich Secrets im Staging-Bereich landen.

## Sprachspezifische Hinweise
### Dart / Flutter
- `firebase_options.dart` und `google-services.json` immer in `.gitignore`; FlutterFire-Konfiguration lokal regenerieren (`flutterfire configure`).
- Keinen `apiKey`, `appId` oder vergleichbare Werte als String-Literal im Dart-Code hartcodieren.

### PHP
- Credentials und Secrets aus `.env` oder einer Konfigurationsdatei außerhalb des Document-Root lesen.
- `.htaccess` für alle `lib/`-Verzeichnisse mit `Require all denied` schützen.
- Für PHP-Syntax-Checks immer `C:\xampp\php\php.exe -l <datei>` verwenden, vor jedem Deploy von PHP-Dateien.

### Arduino / C++
- Keine WLAN-Credentials, API-Keys oder Endpunkt-URLs als Klartext in `.ino`/`.h`-Dateien – Config-Portal oder EEPROM verwenden.
- Sketch-Konfigurationsdateien mit echten Credentials in `.gitignore` aufnehmen.
