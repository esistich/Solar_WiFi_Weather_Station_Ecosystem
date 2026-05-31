# Solar WiFi Weather Station V2.7 – API Edition

Basiert auf der Arbeit von [Open Green Energy](https://www.instructables.com/id/Solar-Powered-WiFi-Weather-Station-V20/).  
Ursprüngliche Autoren: Keith Hungerford, Debasish Dutta, Marc Stähli – vielen Dank!

Fork: https://github.com/esistich/Solar_WiFi_Weather_Station  
Branch: `feature/v2.7-config-portal-api`

---

## Was ist das?

Eine Solar-betriebene WiFi-Wetterstation auf Basis des **WEMOS D1 Mini Pro (ESP8266)**.  
Die Station misst Temperatur, Luftfeuchtigkeit, Luftdruck und optional Pooltemperatur (DS18B20),  
und sendet alle Daten an eine **PHP/MySQL-REST-API**. Die **Zambretti-Wetterprognose** wird  
serverseitig berechnet. Fehler werden persistent über die API gespeichert und sind auch ohne  
Serial Monitor abrufbar.

---

## Sensoren

| Sensor  | Messung                              | Anschluss |
|---------|--------------------------------------|-----------|
| BME280  | Temperatur, Luftfeuchtigkeit, Druck  | I2C (D2/D1) |
| DS18B20 | Pooltemperatur                       | One-Wire D7 (GPIO13), 4,7 kΩ Pull-up |

---

## Repo-Struktur

```
Solar_WiFi_Weather_Station/
├── sketch_sws/
│   ├── Solar_WiFi_Weather_Station_v2_6.ino   # Haupt-Sketch
│   ├── Settings26.h                           # Nutzer-Konfiguration
│   └── Translations/
│       ├── Translation_DE.h
│       ├── Translation_EN.h
│       └── ... (IT, ES, FR, NL, NO, PL, RO, TR)
├── sketch_sws_display/
│   ├── sketch_sws_display.ino                 # Display-Sketch (LED-Matrix Laufschrift)
│   ├── DisplaySettings.h                      # WiFi, API, Pins, Helligkeit
│   └── README.md                              # Verdrahtung & Bibliotheken
├── api/
│   ├── .htaccess             # mod_rewrite: /v1/* → v1/index.php, HTTPS-Weiterleitung
│   ├── data.php              # Legacy-Shim (ältere Firmware-Clients)
│   ├── history.php           # Legacy-Shim
│   ├── status.php            # Legacy-Shim
│   ├── config/
│   │   ├── auth.php          # Basic Auth, JWT, CORS, sendJson()
│   │   ├── db.php            # PDO-Verbindung (UTC-Session)
│   │   └── jwt.php           # JWT-Hilfsfunktionen
│   ├── v1/
│   │   ├── index.php         # Zentraler v1-Router (alle Routen hier registriert)
│   │   ├── data.php          # POST Messung / GET letzter Datensatz
│   │   ├── history.php       # GET Historien-Daten (EAV-Abfrage)
│   │   ├── status.php        # GET Systemstatus
│   │   ├── stations.php      # GET/POST Stationen
│   │   ├── zambretti.php     # GET Zambretti-Prognose (serverseitig berechnet)
│   │   ├── log.php           # POST Fehler schreiben / GET Fehler lesen
│   │   └── helpers.php       # resolveStation() u.a. gemeinsame Hilfsfunktionen
│   ├── admin/                # Admin-Dashboard (Session-Auth)
│   ├── install/
│   │   └── migrate_v2.sql    # Vollständiges Datenbankschema inkl. station_errors
│   └── README.md             # API-Dokumentation
├── docs/
│   ├── IMG_2951.jpg
│   └── Node-Red-Dashboard.png
└── README.md
```

---

## Konfiguration

Alle Einstellungen in `sketch_sws/Settings26.h` (Compile-Zeit-Fallbacks).  
Zur Laufzeit per **Konfigurations-Portal** überschreibbar (im EEPROM gespeichert).

### Sprache wählen

```cpp
// sketch_sws/Settings26.h
#include "Translations/Translation_DE.h"
// #include "Translations/Translation_EN.h"
```

Sommer/Winter-Umschaltung (Regen ↔ Schnee) erfolgt automatisch anhand der gemessenen Temperatur.

### Neue Sprache hinzufügen

1. `Translation_DE.h` als `Translation_XX.h` kopieren
2. Alle Strings übersetzen, `{P}` und `{E}` Marker beibehalten
3. In `Settings26.h` das neue Include aktivieren
4. Pull Request willkommen!

---

## Konfigurations-Portal

Beim Booten **Button D6 gedrückt halten** → Station öffnet WLAN-Accesspoint **„SWS-Config"**.  
Browser öffnen: **http://192.168.4.1**

Konfigurierbar:
- WLAN-Zugangsdaten
- REST-API (Host, Pfad, Port, Benutzer, Passwort, HTTPS)
- Temperaturkorrektur, Höhe ü. NN, Schlafzeit

Das Portal läuft **ohne Zeitlimit**. Neustart nur per „Speichern" oder Hardware-Reset.

---

## REST-API (v1)

→ Vollständige Dokumentation: [`api/README.md`](api/README.md)

Deployment: `https://timm-sander.net/swsapi`

Alle Routen laufen über `api/v1/index.php` (mod_rewrite):

| Methode | Route           | Auth          | Beschreibung                          |
|---------|-----------------|---------------|---------------------------------------|
| GET     | `/v1/data`      | JWT Bearer    | Letzter Messdatensatz                 |
| POST    | `/v1/data`      | Basic Auth    | Messung hochladen                     |
| GET     | `/v1/history`   | JWT Bearer    | Historien-Daten (mit Filterparametern)|
| GET     | `/v1/status`    | JWT Bearer    | Systemstatus (DB, letzte Messung)     |
| GET     | `/v1/stations`  | JWT Bearer    | Stationsliste                         |
| GET     | `/v1/zambretti` | JWT Bearer    | Zambretti-Prognose (serverseitig)     |
| GET     | `/v1/log`       | JWT Bearer    | Stationsfehler lesen                  |
| POST    | `/v1/log`       | Basic Auth    | Fehler/Warnung von Station schreiben  |

### Fehler-Logging (`/v1/log`)

Die Station schreibt Fehler automatisch in die API, ohne dass der Serial Monitor benötigt wird.  
Einträge sind filterbar nach `level`, `code`, `from`, `to` und `limit`.

Beispiel GET:
```
GET /v1/log?level=error&limit=20
Authorization: Bearer <jwt>
```

Bekannte Fehlercodes der Station:

| Code                  | Level   | Auslöser                                      |
|-----------------------|---------|-----------------------------------------------|
| `DS18B20_INVALID`     | warning | DS18B20 liefert keinen gültigen Wert          |
| `DS18B20_FAIL_FALLBACK` | warning | Fallback auf BME280 als Aussentemperatur      |
| `BUFFER_OVERFLOW`     | error   | JSON-Payload wurde abgeschnitten              |
| `API_HTTP_ERROR`      | error   | HTTP-Fehler beim POST an `/v1/data`           |

---

## Pin-Plan

| Pin | GPIO | Funktion             |
|-----|------|----------------------|
| D1  | 5    | I2C SCL (BME280)     |
| D2  | 4    | I2C SDA (BME280)     |
| D6  | 12   | Konfig-Button (LOW)  |
| D7  | 13   | DS18B20 One-Wire     |
| A0  | –    | Batteriespannung ADC |
| RST | –    | Deep-Sleep Wake      |

---

## Zambretti-Prognose

Die [Zambretti-Wetterprognose](https://www.iquilezles.org/www/articles/zambretti/zambretti.htm)
wird **serverseitig** in `api/v1/zambretti.php` berechnet – nicht mehr auf der Station.  
Grundlage sind die letzten 12 `rel_pressure`-Werte aus der Datenbank.  
Ergebnis: `zambretti`, `zambretti_text`, `trend`, `trend_text`, `pressure_state`, `accuracy_pct`.

---

## Bibliotheken (Arduino IDE)

| Bibliothek              | Quelle                              |
|-------------------------|-------------------------------------|
| Adafruit BME280         | Arduino Library Manager             |
| Adafruit Unified Sensor | Arduino Library Manager             |
| DallasTemperature       | Arduino Library Manager             |
| OneWire                 | Arduino Library Manager             |
| EasyNTPClient           | https://github.com/aharshac/EasyNTPClient |
| Time (PaulStoffregen)   | Arduino Library Manager             |
| ArduinoJson             | Arduino Library Manager             |

---

## Fotos

![Station](docs/IMG_2951.jpg)

---

## Lizenz

Dieses Projekt basiert auf Open-Source-Arbeit und ist frei verwendbar.
