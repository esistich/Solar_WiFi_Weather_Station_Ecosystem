/*----------------------------------------------------------------------------------------------------
  Project Name : SWS Indoor Station – LilyGO TTGO T-Display (ESP32)
  Board        : LilyGO TTGO T-Display (ESP32, ST7789 1.14" TFT 135x240)
  Features     : Temperatur, Feuchte, Luftdruck (BME280), Zambretti,
				 TFT-Display, Config-Portal per Button, REST-API-Upload
  Kein Akku    : Wird per USB / Netzteil betrieben – kein Batterie-ADC

  === TTGO T-Display Pinout ===
  TFT Driver   ST7789
  TFT_MOSI     19
  TFT_SCLK     18
  TFT_CS        5
  TFT_DC       16
  TFT_RST      23
  TFT_BL        4
  I2C_SDA      21   <- BME280
  I2C_SCL      22   <- BME280
  BUTTON1      35   <- Config-Portal (beim Start gedrueckt halten)
  BUTTON2       0   <- Display-Seite wechseln
----------------------------------------------------------------------------------------------------*/

const String IndoorVersion = "1.0.0";

// =====================================================================
// Konfigurations-Portal
// BUTTON1 (GPIO35) beim Start gedrueckt halten -> AP "SWSIndoor-Config"
// Webinterface unter 192.168.4.1
// =====================================================================
#define CONFIG_BUTTON_PIN   35      // GPIO35 = BUTTON1 (nur Input, kein Pullup moeglich)
#define DISPLAY_BUTTON_PIN   0      // GPIO0  = BUTTON2 (Display-Seite wechseln)
#define CONFIG_AP_SSID      "SWSIndoor-Config"

// =====================================================================
// I2C / BME280
// =====================================================================
#define I2C_SDA_PIN   21
#define I2C_SCL_PIN   22
#define BME280_ADDRESS 0x76   // alternativ 0x77

// =====================================================================
// Sprache (Translation-Dateien aus sketch_sws wiederverwenden)
// =====================================================================
#include "../sketch_sws/Translations/Translation_DE.h"
// #include "../sketch_sws/Translations/Translation_EN.h"

#define PRESS_STORM_LOW   0
#define PRESS_STRONG_LOW  1
#define PRESS_LOW         2
#define PRESS_HIGH        3
#define PRESS_STRONG_HIGH 4

// =====================================================================
// Kein DS18B20 – Indoor-Station ohne Zusatzsensor
// =====================================================================
#define USE_DS18B20  0

// =====================================================================
// WLAN – Compile-Zeit-Fallbacks
// =====================================================================
#define CFG_DEFAULT_STATION_NAME  "SWS_Indoor"
#define CFG_DEFAULT_WIFI_SSID     "YOUR_SSID"
#define CFG_DEFAULT_WIFI_PASS     "YOUR_PASSWORD"

// =====================================================================
// REST-API
// =====================================================================
#define USE_API  1

#define CFG_DEFAULT_API_ENABLED   true
#define CFG_DEFAULT_API_HTTPS     true
#define CFG_DEFAULT_API_HOST      "timm-sander.net"
#define CFG_DEFAULT_API_PATH      "/sws/api/v1/data"
#define CFG_DEFAULT_API_PORT      443
#define CFG_DEFAULT_API_USER      "NAy1b4GpuS3dEvej"
#define CFG_DEFAULT_API_PASS      "YOUR_API_PASS"   // nicht committen!

// =====================================================================
// Remote-Config
// =====================================================================
#define USE_REMOTE_CONFIG         1
#define CFG_REMOTE_CONFIG_PATH    "/sws/api/v1/config"
#define CFG_REMOTE_CONFIG_TIMEOUT 5000

// =====================================================================
// OTA
// =====================================================================
#define USE_OTA           1
#define CFG_OTA_BASE_PATH "/sws/api/ota/firmware"
#define CFG_OTA_SKETCH_ID "sws_indoor"    // eigener Unterordner auf dem Server!
#define CFG_OTA_TIMEOUT_MS 5000

// =====================================================================
// Allgemein
// =====================================================================
#define CFG_DEFAULT_TEMP_CORR    0.0f  // Temperaturkorrektur in Grad C
#define CFG_DEFAULT_ELEVATION    420   // Hoehe ueber NN in Metern
#define CFG_DEFAULT_SLEEP_MIN    0     // 0 = kein Deep-Sleep (USB-Betrieb)
#define CFG_DEFAULT_MEASURE_SEC  30    // Messintervall in Sekunden
#define NTP_SERVER               "ch.pool.ntp.org"

#define WINTER_THRESHOLD_LOW   (1.5)
#define WINTER_THRESHOLD_HIGH  (2.5)

// =====================================================================
// Display
// =====================================================================
#define DISPLAY_PAGE_COUNT   3    // 0=Haupt  1=Druck+Zambretti  2=System
#define DISPLAY_AUTO_CYCLE   0    // 1=automatisch blaettern, 0=nur per Button
#define DISPLAY_CYCLE_SEC   10    // Sekunden pro Seite bei Auto-Cycle
#define TFT_BL_PIN           4    // Hintergrundbeleuchtung (PWM)
