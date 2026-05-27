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
// Standard: D3 = GPIO0. Taste zwischen D3 und GND anschließen.
#define CONFIG_BUTTON_PIN   0       // GPIO0 = D3
#define CONFIG_AP_SSID      "SWS-Config"   // WLAN-Name des Konfigurations-APs
#define CONFIG_TIMEOUT_S    60      // Sekunden bis automatischer Neustart

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

#include "Translation_DE.h"
// #include "Translation_EN.h"

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
#define USE_SHT45      1     // Sensirion SHT45: temperature + humidity (I²C @ 0x44)

// ---- Step 2: Which sensor should be used for the actual readings? ----
// When multiple sensors are enabled, all of them are read and logged to
// Serial. But only ONE temperature source and ONE humidity source are used
// for the Zambretti forecast, MQTT, Blynk, dewpoint etc.
//
// Pick one:  SRC_BME = BME280,  SRC_DAL = DS18B20,  SRC_SHT = SHT45
// (If you pick a sensor that is disabled above, the code falls back to BME280.)

#define TEMP_SOURCE    SRC_DAL    // recommended outdoor: Dallas (better thermal buffering in sun)
#define HUMI_SOURCE    SRC_SHT    // recommended outdoor: SHT45 (PTFE membrane, integrated heater)

/******* configuration control constant for use of Blynk and/or Thingspeak **/

const String App1 = "BLYNK";         // empty string if not applicable -> "" else "BLYNK"
#define BLYNK_TEMPLATE_ID "YOUR_ID"
#define BLYNK_TEMPLATE_NAME "Solar Weather Station"
#define BLYNK_AUTH_TOKEN "YOUR_TOKEN"
//char auth[] = BLYNK_AUTH_TOKEN;

/****** WiFi Settings (Compile-Zeit-Fallbacks) *****************************/

#define CFG_DEFAULT_STATION_NAME  "SWS_YourPlace"
#define CFG_DEFAULT_WIFI_SSID     "YOUR_SSID"
#define CFG_DEFAULT_WIFI_PASS     "YOUR_PASSWORD"

/****** MQTT Settings (Compile-Zeit-Fallbacks) *****************************/

#define CFG_DEFAULT_MQTT_ENABLED      true
#define CFG_DEFAULT_MQTT_SERVER       "broker.hivemq.com"
#define CFG_DEFAULT_MQTT_PORT         1883
#define CFG_DEFAULT_MQTT_USER         ""
#define CFG_DEFAULT_MQTT_PASS         ""
#define CFG_DEFAULT_MQTT_TOPIC        "YOUR_TOPIC"
#define CFG_DEFAULT_MQTT_PRESS_TOPIC  "YOUR_TOPIC/pressure"
#define CFG_DEFAULT_MQTT_STATUS       "YOUR_TOPIC/status"

/****** REST-API Settings (Compile-Zeit-Fallbacks) **************************/

#define CFG_DEFAULT_API_ENABLED   false
#define CFG_DEFAULT_API_HTTPS     true
#define CFG_DEFAULT_API_HOST      "dein-server.de"
#define CFG_DEFAULT_API_PATH      "/api/data.php"
#define CFG_DEFAULT_API_PORT      443
#define CFG_DEFAULT_API_USER      "YOUR_API_USER"
#define CFG_DEFAULT_API_PASS      "YOUR_API_PASS"

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
