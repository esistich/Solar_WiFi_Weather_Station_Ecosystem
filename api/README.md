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
├── data.php            GET letzter Messwert / POST neuer Datensatz  ← Firmware-Endpoint
├── history.php         GET Historienabfrage mit Filtern
├── status.php          GET Health-Endpoint für Home Assistant (kein Auth)
├── index.html          Platzhalter-Startseite
├── .htaccess           HTTPS-Weiterleitung + Zugriffsschutz für lib/
├── lib/
│   ├── auth.php        Credentials + requireBasicAuth() + sendCorsHeaders()
│   └── db.php          PDO-Datenbankverbindung (Singleton)
├── homeassistant/
│   └── ha_sensors.yaml Fertige Home-Assistant-Sensor-Konfiguration
├── install/
│   └── schema.sql      Datenbank-Schema (einmalig importieren)
└── README.md           Diese Datei
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
mysql -u root -p solarweather < api/install/schema.sql
```

### 3. Konfiguration anpassen

**`api/lib/db.php`** – Datenbankverbindung:

```php
define('DB_HOST', 'localhost');
define('DB_NAME', 'solarweather');
define('DB_USER', 'YOUR_DB_USER');
define('DB_PASS', 'YOUR_DB_PASS');
```

**`api/lib/auth.php`** – API-Zugangsdaten (gelten für alle Endpunkte):

```php
define('API_USER', 'NAy1b4GpuS3dEvej');
define('API_PASS', 'REDACTED_API_PASS');
```

> Diese Werte müssen mit `api_user` / `api_pass` in `Settings26.h` des Sketches übereinstimmen.

### 4. Dateien hochladen

Alle Dateien aus `api/` **inklusive Unterordner** (`lib/`, `homeassistant/`, `install/`) in das entsprechende Verzeichnis auf dem Webserver hochladen.

### 5. Sketch konfigurieren (`Settings26.h`)

Ab v2.7 werden alle Laufzeiteinstellungen als Compile-Zeit-Fallbacks definiert
und können über das **AP-Konfigurations-Portal** (GPIO0 beim Boot gedrückt halten)
jederzeit überschrieben werden:

```cpp
#define USE_API 1                          // API-Upload aktivieren

// Compile-Zeit-Fallbacks (im Portal überschreibbar):
#define CFG_DEFAULT_API_ENABLED   true
#define CFG_DEFAULT_API_HTTPS     true
#define CFG_DEFAULT_API_HOST      "timm-sander.net"
#define CFG_DEFAULT_API_PATH      "/api/data.php"
#define CFG_DEFAULT_API_PORT      443
#define CFG_DEFAULT_API_USER      "NAy1b4GpuS3dEvej"   // muss mit auth.php übereinstimmen
#define CFG_DEFAULT_API_PASS      "REDACTED_API_PASS"   // muss mit auth.php übereinstimmen
```

> HTTPS wird empfohlen. Das Zertifikat wird nicht geprüft (`setInsecure()`), die
> Übertragung ist aber verschlüsselt.

---

## Konfigurations-Portal (v2.7)

Ab v2.7 startet der Sketch beim Booten ein **WLAN-Accesspoint-Portal**, wenn der Konfigurations-Button gedrückt gehalten wird.

### Bedienung

1. **Button gedrückt halten** (D3 / GPIO0 gegen GND) und gleichzeitig **Reset** drücken (oder Spannung anlegen).
2. Der ESP8266 öffnet den WLAN-Accesspoint **`SWS-Config`** (kein Passwort).
3. Mit einem Smartphone oder PC mit diesem WLAN verbinden.
4. Browser öffnen → **`http://192.168.4.1`**
5. Alle Einstellungen konfigurieren und speichern – der ESP startet danach automatisch neu.

> Das Portal schließt sich nach **60 Sekunden** ohne Aktion automatisch und der normale Messbetrieb beginnt.
>
> Die **Status-LED (D4)** blinkt während das Portal aktiv ist (0,5 s-Takt). Nach dem Speichern blinkt sie schnell (6×) als Bestätigung.

### Im Portal konfigurierbare Einstellungen

| Einstellung | Beschreibung |
|---|---|
| WLAN SSID / Passwort | Heimnetzwerk für den Datentransfer |
| MQTT Host / Port / Topic / User / Pass | MQTT-Broker-Verbindung |
| API Host / Path / Port / User / Pass | PHP-API-Endpunkt |
| API HTTPS | TLS-Verbindung aktivieren/deaktivieren |
| Temperaturkorrektur | Offset in °C (Kompensation für Eigenerwärmung) |
| Elevation | Standorthöhe in Metern (für rel. Luftdruckberechnung) |
| Sleep-Intervall | Deep-Sleep-Zeit in Minuten |

---

## Pin-Plan – WEMOS D1 Mini Pro

| WEMOS-Pin | GPIO | Funktion | Sensor / Bauteil |
|---|---|---|---|
| **3V3** | – | Versorgung 3,3 V | BME280, SHT45 |
| **GND** | – | Masse | alle Sensoren |
| **D1** | GPIO5 | I²C SCL | BME280, SHT45 |
| **D2** | GPIO4 | I²C SDA | BME280, SHT45 |
| **D3** | GPIO0 | ⚠️ Boot-Strapping-Pin – **nicht als Button verwenden!** | – |
| **D4** | GPIO2 | Onboard-LED (nicht belegt für Portal) | – |
| **D5** | GPIO14 | Status-LED Konfigurations-Portal (externe LED, aktiv-HIGH) | LED + ~220 Ω gegen GND |
| **D6** | GPIO12 | Konfigurations-Button (gegen GND) | Taster |
| **D7** | GPIO13 | 1-Wire Data | DS18B20 (Poolsensor) |
| **A0** | ADC | Batteriespannung (Spannungsteiler) | Batteriemessung |

> **DS18B20:** 4,7 kΩ Pull-up-Widerstand zwischen Data (D7) und 3V3 erforderlich.  
> **BME280-Adresse:** `0x76` (SDO → GND) oder `0x77` (SDO → 3V3).  
> **Konfigurations-Button:** einfacher Taster zwischen **D6** und GND. GPIO0 (D3) **nicht** verwenden – LOW beim Reset aktiviert den ESP8266-Flash-Bootloader.  
> **Status-LED:** externe LED an **D5**, Vorwiderstand ~220 Ω gegen GND (aktiv-HIGH).

---

## Sicherheit

### HTTP Basic Auth
Alle schreibenden (POST) und historischen (GET `/history.php`) Endpunkte sind per HTTP Basic Auth geschützt. Der öffentliche GET-Endpunkt (`/data.php`) liefert nur den letzten Messwert ohne Authentifizierung.

### HTTPS
Der Sketch nutzt `WiFiClientSecure` mit `setInsecure()` – die Verbindung ist verschlüsselt, das Zertifikat wird jedoch **nicht geprüft**. Das verhindert Lauschangriffe, schützt aber nicht vor MITM. Für höhere Sicherheit kann in `sendToAPI()` `client.setFingerprint(SHA1_HEX)` eingetragen werden.

### Direktzugriff auf PHP-Hilfsdateien sperren
`lib/auth.php` und `lib/db.php` sind durch folgende Regel in `.htaccess` vor direktem Browser-Zugriff geschützt:

```apache
<Directory "lib">
	Require all denied
</Directory>
```

---

## Endpunkte

### `GET /api/data.php` – Letzter Messwert

Liefert den neuesten Datensatz als JSON-Objekt. **Keine Authentifizierung erforderlich.**

```bash
curl https://timm-sander.net/swsapi/data.php
```

**Response `200 OK`:**
```json
{
  "id": 123,
  "created_at": "2025-06-15 14:30:00",
  "station_name": "SWS_MyPlace",
  "temperature": 21.5,
  "pool_temperature": 28.3,
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
	 https://timm-sander.net/swsapi/data.php
```

**Pflichtfelder im JSON-Body:**

| Feld | Typ | Beschreibung |
|---|---|---|
| `temperature` | float | Temperatur in °C (korrigiert) |
| `humidity` | float | Relative Luftfeuchte in % |
| `absolutepressure` | float | Absoluter Luftdruck in hPa |
| `relativepressure` | int | Relativer Luftdruck (QNH) in hPa |
| `battery` | float | Batteriespannung in V |

**Optionale Felder:** `station_name`, `pool_temperature`, `heatindex`, `dewpoint`, `dewpointspread`, `pressurestate`, `zambrettisays`, `zletter`, `trendinwords`, `trend`, `accuracy`, `batterypercentage`, `wifi_strength`, `timestamp`

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
curl -u station:passwort https://timm-sander.net/swsapi/history.php

# Letzte 50 Einträge
curl -u station:passwort "https://timm-sander.net/swsapi/history.php?limit=50"

# Bestimmter Zeitraum
curl -u station:passwort \
	 "https://timm-sander.net/swsapi/history.php?from=2025-01-01&to=2025-06-30"

# Kombiniert
curl -u station:passwort \
	 "https://timm-sander.net/swsapi/history.php?from=2025-06-01&limit=200"
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

1. `api/homeassistant/ha_sensors.yaml` in dein HA-Konfigurationsverzeichnis kopieren
2. In `ha_sensors.yaml` ersetzen:
   - `timm-sander.net/swsapi` → bereits korrekt
   - `NAy1b4GpuS3dEvej` → `NAy1b4GpuS3dEvej`
   - `REDACTED_API_PASS` → `REDACTED_API_PASS`
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

### Enthaltene Automationen (`homeassistant/ha_sensors.yaml`)

| Automation | Auslöser | Aktion |
|---|---|---|
| **Batterie niedrig** | Batterie < 20 % | Persistente Benachrichtigung |
| **Station offline** | `sensor.sws_online = offline` für 30 min | Persistente Benachrichtigung |
| **Station wieder online** | `sensor.sws_online = online` | Offline-Benachrichtigung ausblenden |

---

## Changelog

| Version | Datum | Änderung |
|---|---|---|
| 1.5 | 2025-06 | Blynk-Unterstützung vollständig entfernt; Konfig-Portal läuft jetzt ohne Zeitlimit (Neustart nur per Speichern oder Hardware-Reset) |
| 1.4 | 2025-06 | DS18B20 als Poolsensor: neues Feld `pool_temperature` |
| 1.3 | 2025-06 | Home-Assistant-Integration: `status.php` (Health-Endpoint), CORS-Header in allen Endpunkten, `data_age_s` in `data.php`, `ha_sensors.yaml` mit REST-Sensoren, Template-Sensoren und Automationen |
| 1.2 | 2025-06 | Konfigurations-Portal per Button: alle Laufzeit-Einstellungen (WiFi, MQTT, API, Elevation …) über Browser konfigurierbar und im EEPROM gespeichert |
| 1.1 | 2025-06 | `history.php` hinzugefügt (GET mit `limit`, `from`, `to`); gemeinsame `auth.php` für zentrale Credentials |
| 1.0 | 2025-06 | Initiale API: `data.php` (GET + POST), `history.php` (GET mit limit/from/to), zentrale `auth.php` |
