# Solar WiFi Weather Station – REST API

PHP/MySQL-API zur Speicherung und Abfrage der Messdaten der Solar WiFi Weather Station.

---

## Voraussetzungen

| Komponente | Version |
|---|---|
| PHP | 8.0 oder neuer |
| MySQL / MariaDB | 8.0 / 10.5 oder neuer |
| Webserver | Apache (mod_rewrite nicht erforderlich) oder nginx |
| ESP8266-Sketch | V2.6 mit `USE_API 1` in `Settings26.h` |

---

## Dateistruktur

```
api/
├── auth.php        Credentials + requireBasicAuth() + sendCorsHeaders()
├── db.php          PDO-Datenbankverbindung (Singleton)
├── data.php        GET letzter Messwert (inkl. data_age_s)  /  POST neuer Datensatz
├── history.php     GET Historienabfrage mit Filtern
├── status.php      GET Health-Endpoint für Home Assistant (kein Auth)
├── ha_sensors.yaml Fertige Home-Assistant-Konfiguration
├── schema.sql      Datenbank-Schema (einmalig importieren)
└── README.md       Diese Datei
```

---

## Installation

### 1. Datenbank anlegen

```sql
CREATE DATABASE solarweather
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
```

### 2. Schema importieren

```bash
mysql -u root -p solarweather < api/schema.sql
```

### 3. Konfiguration anpassen

**`api/db.php`** – Datenbankverbindung:

```php
define('DB_HOST', 'localhost');
define('DB_NAME', 'solarweather');
define('DB_USER', 'YOUR_DB_USER');
define('DB_PASS', 'YOUR_DB_PASS');
```

**`api/auth.php`** – API-Zugangsdaten (gelten für alle Endpunkte):

```php
define('API_USER', 'YOUR_API_USER');
define('API_PASS', 'YOUR_API_PASS');
```

> Diese Werte müssen mit `api_user` / `api_pass` in `Settings26.h` des Sketches übereinstimmen.

### 4. Dateien hochladen

Alle Dateien aus `api/` in das entsprechende Verzeichnis auf dem Webserver hochladen.

### 5. Sketch konfigurieren (`Settings26.h`)

Ab v2.7 werden alle Laufzeiteinstellungen als Compile-Zeit-Fallbacks definiert
und können über das **AP-Konfigurations-Portal** (GPIO0 beim Boot gedrückt halten)
jederzeit überschrieben werden:

```cpp
#define USE_API 1                          // API-Upload aktivieren

// Compile-Zeit-Fallbacks (im Portal überschreibbar):
#define CFG_DEFAULT_API_ENABLED   true
#define CFG_DEFAULT_API_HTTPS     true
#define CFG_DEFAULT_API_HOST      "dein-server.de"
#define CFG_DEFAULT_API_PATH      "/api/data.php"
#define CFG_DEFAULT_API_PORT      443
#define CFG_DEFAULT_API_USER      "YOUR_API_USER"   // muss mit auth.php übereinstimmen
#define CFG_DEFAULT_API_PASS      "YOUR_API_PASS"   // muss mit auth.php übereinstimmen
```

> HTTPS wird empfohlen. Das Zertifikat wird nicht geprüft (`setInsecure()`), die
> Übertragung ist aber verschlüsselt.

---

## Sicherheit

### HTTP Basic Auth
Alle schreibenden (POST) und historischen (GET `/history.php`) Endpunkte sind per HTTP Basic Auth geschützt. Der öffentliche GET-Endpunkt (`/data.php`) liefert nur den letzten Messwert ohne Authentifizierung.

### HTTPS
Der Sketch nutzt `WiFiClientSecure` mit `setInsecure()` – die Verbindung ist verschlüsselt, das Zertifikat wird jedoch **nicht geprüft**. Das verhindert Lauschangriffe, schützt aber nicht vor MITM. Für höhere Sicherheit kann in `sendToAPI()` `client.setFingerprint(SHA1_HEX)` eingetragen werden.

### Direktzugriff auf PHP-Hilfsdateien sperren
`auth.php` und `db.php` sollten nicht direkt über den Browser erreichbar sein. Apache-Beispiel (`.htaccess` im `api/`-Verzeichnis):

```apache
<FilesMatch "^(auth|db)\.php$">
	Require all denied
</FilesMatch>
```

---

## Endpunkte

### `GET /api/data.php` – Letzter Messwert

Liefert den neuesten Datensatz als JSON-Objekt. **Keine Authentifizierung erforderlich.**

```bash
curl https://dein-server.de/api/data.php
```

**Response `200 OK`:**
```json
{
  "id": 123,
  "created_at": "2025-06-15 14:30:00",
  "station_name": "SWS_MyPlace",
  "temperature": 21.5,
  "humidity": 58.3,
  "heat_index": 21.5,
  "dewpoint": 12.8,
  "dewpoint_spread": 8.7,
  "abs_pressure": 960.12,
  "rel_pressure": 1013,
  "pressure_state": "Hochdruck",
  "zambretti": "Schönes Wetter",
  "zambretti_letter": "B",
  "trend": "beständig",
  "trend_value": 0.12,
  "accuracy": 94,
  "battery_volt": 4.10,
  "battery_pct": 100,
  "wifi_strength": -67,
  "device_timestamp": 1749994200
}
```

---

### `POST /api/data.php` – Neuen Messwert speichern

Wird automatisch vom Sketch aufgerufen. **HTTP Basic Auth erforderlich.**

```bash
curl -u station:passwort \
	 -H "Content-Type: application/json" \
	 -d '{"temperature":21.5,"humidity":58.3,"absolutepressure":960.12,...}' \
	 https://dein-server.de/api/data.php
```

**Pflichtfelder im JSON-Body:**

| Feld | Typ | Beschreibung |
|---|---|---|
| `temperature` | float | Temperatur in °C (korrigiert) |
| `humidity` | float | Relative Luftfeuchte in % |
| `absolutepressure` | float | Absoluter Luftdruck in hPa |
| `relativepressure` | int | Relativer Luftdruck (QNH) in hPa |
| `battery` | float | Batteriespannung in V |

**Optionale Felder:** `station_name`, `heatindex`, `dewpoint`, `dewpointspread`, `pressurestate`, `zambrettisays`, `zletter`, `trendinwords`, `trend`, `accuracy`, `batterypercentage`, `wifi_strength`, `timestamp`

**Response `201 Created`:**
```json
{ "ok": true, "id": 124 }
```

---

### `GET /api/history.php` – Historienabruf

Liefert mehrere Datensätze als JSON-Array. **HTTP Basic Auth erforderlich.**

#### Parameter

| Parameter | Standard | Maximum | Beschreibung |
|---|---|---|---|
| `limit` | `100` | `1000` | Anzahl der zurückgegebenen Datensätze |
| `from` | – | – | Startdatum `YYYY-MM-DD` (inklusiv) |
| `to` | – | – | Enddatum `YYYY-MM-DD` (inklusiv) |

Sortierung: neueste Einträge zuerst (`ORDER BY id DESC`).

#### Beispiele

```bash
# Letzte 100 Einträge (Standard)
curl -u station:passwort https://dein-server.de/api/history.php

# Letzte 50 Einträge
curl -u station:passwort "https://dein-server.de/api/history.php?limit=50"

# Bestimmter Zeitraum
curl -u station:passwort \
	 "https://dein-server.de/api/history.php?from=2025-01-01&to=2025-06-30"

# Kombiniert
curl -u station:passwort \
	 "https://dein-server.de/api/history.php?from=2025-06-01&limit=200"
```

**Response `200 OK`:**
```json
{
  "count": 2,
  "limit": 100,
  "from": "2025-06-01",
  "to": null,
  "data": [
	{
	  "id": 124,
	  "created_at": "2025-06-15 14:40:00",
	  "temperature": 22.1,
	  ...
	},
	{
	  "id": 123,
	  "created_at": "2025-06-15 14:30:00",
	  "temperature": 21.5,
	  ...
	}
  ]
}
```

---

## Fehlercodes

| HTTP-Status | Bedeutung |
|---|---|
| `200 OK` | Erfolgreicher GET |
| `201 Created` | Datensatz erfolgreich gespeichert (POST) |
| `400 Bad Request` | Leerer Body oder ungültiges JSON |
| `401 Unauthorized` | Fehlende oder falsche Basic Auth Credentials |
| `404 Not Found` | Noch keine Messdaten vorhanden |
| `405 Method Not Allowed` | Nicht unterstützte HTTP-Methode |
| `422 Unprocessable Entity` | Pflichtfeld fehlt im JSON-Body |
| `500 Internal Server Error` | Datenbankfehler |

---

## Datenbankschema

Tabelle `measurements` (siehe `schema.sql`):

| Spalte | Typ | Beschreibung |
|---|---|---|
| `id` | INT UNSIGNED AI | Primärschlüssel |
| `created_at` | TIMESTAMP | Serverzeit des Eintrags (automatisch) |
| `station_name` | VARCHAR(64) | Name der Station aus `Settings26.h` |
| `temperature` | DECIMAL(5,2) | °C, korrigiert per `TEMP_CORR` |
| `humidity` | DECIMAL(5,2) | % rel. Feuchte |
| `heat_index` | DECIMAL(5,2) | °C (nur über 26,7°C sinnvoll) |
| `dewpoint` | DECIMAL(5,2) | °C |
| `dewpoint_spread` | DECIMAL(5,2) | K (Temp − Taupunkt) |
| `abs_pressure` | DECIMAL(7,2) | hPa absolut (BME280) |
| `rel_pressure` | INT UNSIGNED | hPa QNH (auf Meereshöhe normiert) |
| `pressure_state` | VARCHAR(32) | z.B. „Hochdruck" |
| `zambretti` | VARCHAR(128) | Prognosetext |
| `zambretti_letter` | CHAR(1) | A–Z |
| `trend` | VARCHAR(32) | z.B. „beständig" |
| `trend_value` | DECIMAL(6,3) | hPa-Differenz (gewichtet) |
| `accuracy` | TINYINT UNSIGNED | 0–94 % |
| `battery_volt` | DECIMAL(4,2) | V |
| `battery_pct` | TINYINT UNSIGNED | 0–100 % |
| `wifi_strength` | TINYINT | dBm (RSSI) |
| `device_timestamp` | INT UNSIGNED | UNIX-Timestamp der Station (UTC) |

---

## Home Assistant Integration

Die API ist als zentraler Verbindungspunkt zwischen der Wetterstation und Home Assistant ausgelegt. Station und HA können in **verschiedenen Netzwerken** liegen – der öffentliche API-Server vermittelt.

```
SWS (ESP8266)  ──HTTPS POST──▶  api/data.php  ◀──HTTPS GET──  Home Assistant
                                api/status.php ◀──────────────  (kein Auth)
                                api/history.php◀──HTTPS GET──  (mit Auth)
```

### Schnellstart

1. `api/ha_sensors.yaml` in dein HA-Konfigurationsverzeichnis kopieren
2. In `ha_sensors.yaml` ersetzen:
   - `dein-server.de` → dein echter Hostname
   - `YOUR_API_USER` / `YOUR_API_PASS` → Werte aus `api/auth.php`
3. In `configuration.yaml` einbinden:
   ```yaml
   homeassistant:
     packages:
       sws: !include ha_sensors.yaml
   ```
4. HA neu starten

### Endpunkte für HA

| Endpunkt | Auth | Beschreibung |
|---|---|---|
| `GET /api/data.php` | Basic Auth | Letzter Messdatensatz inkl. `data_age_s` |
| `GET /api/status.php` | – | Health-Check: `fresh`, `last_seen_s` |
| `GET /api/history.php` | Basic Auth | Historische Daten (`limit`, `from`, `to`) |

### Zusatzfeld `data_age_s`

`GET /api/data.php` liefert zusätzlich:
```json
{ "data_age_s": 387 }
```
Sekunden seit der letzten Messung – nützlich für HA-Templates und Watchdog-Automationen.

### Enthaltene Automationen (`ha_sensors.yaml`)

| Automation | Auslöser | Aktion |
|---|---|---|
| **Batterie niedrig** | Batterie < 20 % | Persistente Benachrichtigung |
| **Station offline** | `sensor.sws_online = offline` für 30 min | Persistente Benachrichtigung |
| **Station wieder online** | `sensor.sws_online = online` | Offline-Benachrichtigung ausblenden |

---

## Changelog

| Version | Datum | Änderung |
|---|---|---|
| 1.3 | 2025-06 | Home-Assistant-Integration: `status.php` (Health-Endpoint), CORS-Header in allen Endpunkten, `data_age_s` in `data.php`, `ha_sensors.yaml` mit REST-Sensoren, Template-Sensoren und Automationen |
| 1.2 | 2025-06 | Konfigurations-Portal per Button: alle Laufzeit-Einstellungen (WiFi, MQTT, API, Elevation …) über Browser konfigurierbar und im EEPROM gespeichert |
| 1.1 | 2025-06 | `history.php` hinzugefügt (GET mit `limit`, `from`, `to`); gemeinsame `auth.php` für zentrale Credentials |
| 1.0 | 2025-06 | Initiale API: `data.php` (GET + POST), `history.php` (GET mit limit/from/to), zentrale `auth.php` |
