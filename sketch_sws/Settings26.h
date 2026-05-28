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

/******* Sensor Configuration ************************************************
 * Choose which sensors are physically connected. The BME280 is required as
 * the project relies on its pressure sensor for the Zambretti forecast.
 * Additional sensors are optional and can be enabled or disabled here.
 ****************************************************************************/

// ---- Step 1: Which sensors are physically connected? ----
// Set to 1 if the sensor is wired up, 0 if not.
// BME280 is always required (it provides the pressure data for Zambretti).

#define USE_BME280     1     // Bosch BME280: pressure (REQUIRED), humidity, temperature
#define USE_DS18B20    1     // Dallas 18B20:  temperature only (one-wire on D7)

// ---- Step 2: Which sensor should be used for the actual readings? ----
// Pick one:  SRC_BME = BME280,  SRC_DAL = DS18B20
// (If you pick a sensor that is disabled above, the code falls back to BME280.)

#define TEMP_SOURCE    SRC_DAL    // DS18B20 (bessere thermische Entkopplung im Freien)
#define HUMI_SOURCE    SRC_BME    // BME280 (einzige verbleibende Feuchtigkeitsquelle)

/****** WiFi Settings (Compile-Zeit-Fallbacks) *****************************/

#define CFG_DEFAULT_STATION_NAME  "SWS_YourPlace"
#define CFG_DEFAULT_WIFI_SSID     "YOUR_SSID"
#define CFG_DEFAULT_WIFI_PASS     "YOUR_PASSWORD"

/****** REST-API Settings ***************************************************/
#define USE_API 1                         // REST-API-Upload aktivieren

#define CFG_DEFAULT_API_ENABLED   true
#define CFG_DEFAULT_API_HTTPS     true
#define CFG_DEFAULT_API_HOST      "timm-sander.net"
#define CFG_DEFAULT_API_PATH      "/swsapi/data.php"
#define CFG_DEFAULT_API_PORT      443
#define CFG_DEFAULT_API_USER      "NAy1b4GpuS3dEvej"
#define CFG_DEFAULT_API_PASS      "REDACTED_API_PASS"

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
