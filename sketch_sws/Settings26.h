/*----------------------------------------------------------------------------------------------------
  Project Name : Solar Powered WiFi Weather Station V2.6
  Features: temperature, dewpoint, dewpoint spread, heat index, humidity, absolute pressure, relative pressure, battery status and
  the famous Zambretti Forecaster (multi lingual)
  Authors: Keith Hungerford, Debasish Dutta and Marc Stähli
  Website : www.opengreenenergy.com */

const String Version = "2.7";

// =====================================================================
// Compile-Zeit-Fallbacks für alle Laufzeit-Einstellungen
// Diese Werte werden beim ersten Start (kein EEPROM) oder nach einem
// "Werksreset" verwendet. Im laufenden Betrieb kommen die Werte aus
// dem EEPROM (gesetzt über das Konfigurations-Portal).
// =====================================================================

/****** Konfigurations-Portal ************************************************/
// GPIO-Pin für den Konfigurations-Knopf.
// Wenn dieser Pin beim Aufwachen LOW ist, startet der ESP als Access Point
// und öffnet ein Webinterface zur Konfiguration (IP: 192.168.4.1).
// WICHTIG: GPIO0 (D3) NICHT verwenden – dieser Pin ist ein Boot-Strapping-Pin!
//          GPIO0=LOW beim Reset = ESP bootet in den Flash-Bootloader, nicht in den Sketch.
// Standard: D6 = GPIO12. Taste zwischen D6 und GND anschließen.
#define CONFIG_BUTTON_PIN   12      // GPIO12 = D6  (boot-neutral)
#define CONFIG_AP_SSID      "SWS-Config"   // WLAN-Name des Konfigurations-APs

/******* Language Selection **************************************************
 * Choose the language by including the corresponding translation file.
 * Available languages (one .h file per language in the Translations/ folder):
 *   - Translation_DE.h  : German
 *   - Translation_EN.h  : English
 *
 * Summer/winter switch (rain ↔ snow) is automatic in every language and
 * happens at runtime based on outdoor temperature. No separate "winter
 * version" of a language is needed any more.
 *
 * To add a new language: copy Translation_DE.h, translate the strings,
 * and change the include below.
 ****************************************************************************/

#include "Translations/Translation_DE.h"
// #include "Translations/Translation_EN.h"

// Indizes in LANG_PRESSURE[] - muessen mit den Translation-Dateien uebereinstimmen
#define PRESS_STORM_LOW   0   // < 990 hPa
#define PRESS_STRONG_LOW  1   // 990-999 hPa
#define PRESS_LOW         2   // 1000-1012 hPa
#define PRESS_HIGH        3   // 1013-1024 hPa
#define PRESS_STRONG_HIGH 4   // >= 1025 hPa

/******* Sensor Configuration
 * BME280 ist immer aktiv und liefert Temperatur, Luftfeuchtigkeit und Druck.
 * Der DS18B20 ist ein optionaler Zusatzfuehler (z.B. Pool, Boden, Zisterne)
 * und wird immer als "pool_temperature" an die API gesendet.
 *
 * USE_DS18B20 = 1  ->  DS18B20 angeschlossen (D7 / GPIO13, 4.7k Pull-up)
 * USE_DS18B20 = 0  ->  kein Zusatzfuehler vorhanden
 ****************************************************************************/

#define USE_DS18B20    1     // Dallas DS18B20 Zusatzfuehler (One-Wire, D7)

/****** WiFi Settings (Compile-Zeit-Fallbacks) *****************************/

#define CFG_DEFAULT_STATION_NAME  "SWS_YourPlace"
#define CFG_DEFAULT_WIFI_SSID     "YOUR_SSID"
#define CFG_DEFAULT_WIFI_PASS     "YOUR_PASSWORD"

/****** REST-API Settings ***************************************************/
#define USE_API 1                         // REST-API-Upload aktivieren

#define CFG_DEFAULT_API_ENABLED   true
#define CFG_DEFAULT_API_HTTPS     true
#define CFG_DEFAULT_API_HOST      "timm-sander.net"
#define CFG_DEFAULT_API_PATH      "/sws/api/data.php"
#define CFG_DEFAULT_API_PORT      443
#define CFG_DEFAULT_API_USER      "NAy1b4GpuS3dEvej"
#define CFG_DEFAULT_API_PASS      "REDACTED_API_PASS"

/****** OTA-Update (Over-the-Air Firmware) *********************************
 * Beim Boot wird einmalig geprueft ob eine neue Firmware verfuegbar ist.
 * Die Versionsdatei und Firmware liegen auf demselben Host wie die API:
 *   GET {api_host}/sws/ota/sws/version.txt  -> z.B. "2.7.1"
 *   GET {api_host}/sws/ota/sws/firmware.bin
 *
 * USE_OTA = 0  ->  OTA deaktiviert (Standard bis Hardware-Test bestanden)
 * USE_OTA = 1  ->  OTA-Check beim jedem Boot aktiv
 *
 * CFG_OTA_SKETCH_ID: eindeutiger Bezeichner dieses Sketches im OTA-Pfad.
 * Muss bei jedem neuen Sketch angepasst werden (z.B. "sws_display").
 ****************************************************************************/

#define USE_OTA               0          // 0 = deaktiviert, 1 = aktiv
#define CFG_OTA_BASE_PATH     "/sws/ota" // Basispfad auf dem API-Host
#define CFG_OTA_SKETCH_ID     "sws"      // Sketch-Bezeichner (Unterordner)
#define CFG_OTA_TIMEOUT_MS    5000       // Max. Wartezeit fuer Version-Check

/****** Additional Settings (Compile-Zeit-Fallbacks) ************************/

// Kalibrierungsfaktor für den Spannungsteiler am ADC (R1=540kΩ, R2=100kΩ).
// Anpassen bis der angezeigte Wert mit dem Multimeter übereinstimmt.
#define BATTERY_CALIB_FACTOR  5.2f

#define CFG_DEFAULT_TEMP_CORR     0.0f   // Manuelle Temperaturkorrektur in °C
#define CFG_DEFAULT_ELEVATION     420    // Höhe über NN in Metern
#define CFG_DEFAULT_SLEEP_MIN     10     // Deep-Sleep-Dauer in Minuten
#define NTP_SERVER "ch.pool.ntp.org"     // Bleibt compile-time (EasyNTPClient-Init)

// Temperature threshold (°C) for switching between summer (rain) and winter
// (snow) precipitation words. Hysteresis prevents flapping near 2°C.
#define WINTER_THRESHOLD_LOW   (1.5)   // below this, switch to winter precipitation
#define WINTER_THRESHOLD_HIGH  (2.5)   // above this, switch back to summer
