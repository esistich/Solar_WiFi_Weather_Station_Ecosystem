/*----------------------------------------------------------------------------------------------------
  SWS Indoor Station – LilyGO TTGO T-Display (ESP32)
  BMP280 + MQ135 + MQ-Index + MQ-Detailseite + Farbskala
  Seiten:
    0 = Uhrzeit + Temperatur + Bewertung
    1 = MQ-Rohwert farbig + MQ-Index groß
    2 = MQ-Detailseite (Rohwert, Avg, Trend, Min/Max, Empfehlung)
    3 = Systemseite
----------------------------------------------------------------------------------------------------*/

#include "SettingsIndoor.h"

#include <Wire.h>
#include <Adafruit_Sensor.h>
#include <Adafruit_BMP280.h>
#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <WiFiUdp.h>
#include <EasyNTPClient.h>
#include <TimeLib.h>
#include <TFT_eSPI.h>
#include <SWSApiClient.h>

#if USE_OTA
  #include <HTTPClient.h>
  #include <HTTPUpdate.h>
  #include <WiFiClientSecure.h>
#endif

// =====================================================================
// MQ135
// =====================================================================
#define MQ135_PIN 34
int mq_raw = 0;
float mq_avg = 0;
int mq_min = 9999;
int mq_max = 0;
int mq_trend = 0;   // -1 / 0 / +1
int mq_index = 0;   // 0–100

// =====================================================================
// Konfiguration
// =====================================================================
struct StationConfig {
  char  station_name[64];
  char  wifi_ssid[64];
  char  wifi_pass[64];
  bool  api_enabled;
  bool  api_https;
  char  api_host[64];
  char  api_path[64];
  int   api_port;
  char  api_user[32];
  char  api_pass[32];
  float temp_corr;
  int   elevation;
  int   sleep_min;
  int   measure_sec;
};

StationConfig cfg;
Preferences prefs;

// =====================================================================
// Globale Messwerte
// =====================================================================
float temperature   = 0.0f;
float abs_pressure  = 0.0f;
float rel_pressure  = 0.0f;

bool wifiOk = false;
bool ntpOk  = false;
bool apiOk  = false;
bool bmpOk  = false;

unsigned long lastMeasMs = 0;

// =====================================================================
// Display
// =====================================================================
TFT_eSPI tft = TFT_eSPI(135, 240);
int currentPage = 0;
volatile bool buttonPressed = false;

#define COL_BG      TFT_BLACK
#define COL_TITLE   TFT_CYAN
#define COL_VALUE   TFT_WHITE
#define COL_GOOD    TFT_GREEN
#define COL_WARN    TFT_YELLOW
#define COL_BAD     TFT_RED

// =====================================================================
// BMP280
// =====================================================================
Adafruit_BMP280 bmp;

static bool initBMP280() {
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);

  if (!bmp.begin(0x76)) {
    if (!bmp.begin(0x77)) {
      Serial.println("BMP280 nicht gefunden!");
      return false;
    }
  }

  bmp.setSampling(
    Adafruit_BMP280::MODE_FORCED,
    Adafruit_BMP280::SAMPLING_X1,
    Adafruit_BMP280::SAMPLING_X1,
    Adafruit_BMP280::FILTER_OFF
  );

  Serial.println("BMP280 OK.");
  return true;
}

// =====================================================================
// NVS
// =====================================================================
void applyDefaults() {
  strlcpy(cfg.station_name, CFG_DEFAULT_STATION_NAME, sizeof(cfg.station_name));
  strlcpy(cfg.wifi_ssid,    CFG_DEFAULT_WIFI_SSID,    sizeof(cfg.wifi_ssid));
  strlcpy(cfg.wifi_pass,    CFG_DEFAULT_WIFI_PASS,    sizeof(cfg.wifi_pass));
  cfg.api_enabled  = CFG_DEFAULT_API_ENABLED;
  cfg.api_https    = CFG_DEFAULT_API_HTTPS;
  strlcpy(cfg.api_host, CFG_DEFAULT_API_HOST, sizeof(cfg.api_host));
  strlcpy(cfg.api_path, CFG_DEFAULT_API_PATH, sizeof(cfg.api_path));
  cfg.api_port     = CFG_DEFAULT_API_PORT;
  strlcpy(cfg.api_user, CFG_DEFAULT_API_USER, sizeof(cfg.api_user));
  strlcpy(cfg.api_pass, CFG_DEFAULT_API_PASS, sizeof(cfg.api_pass));
  cfg.temp_corr    = CFG_DEFAULT_TEMP_CORR;
  cfg.elevation    = CFG_DEFAULT_ELEVATION;
  cfg.sleep_min    = CFG_DEFAULT_SLEEP_MIN;
  cfg.measure_sec  = CFG_DEFAULT_MEASURE_SEC;
}

void loadConfig() {
  applyDefaults();
  prefs.begin("sws_indoor", true);
  if (prefs.isKey("cfg_json")) {
    String json = prefs.getString("cfg_json", "");
    prefs.end();
    JsonDocument doc;
    if (deserializeJson(doc, json) == DeserializationError::Ok) {
      if (doc["station_name"].is<const char*>()) strlcpy(cfg.station_name, doc["station_name"], sizeof(cfg.station_name));
      if (doc["wifi_ssid"].is<const char*>())    strlcpy(cfg.wifi_ssid,    doc["wifi_ssid"],    sizeof(cfg.wifi_ssid));
      if (doc["wifi_pass"].is<const char*>())    strlcpy(cfg.wifi_pass,    doc["wifi_pass"],    sizeof(cfg.wifi_pass));
      if (!doc["api_enabled"].isNull())   cfg.api_enabled  = doc["api_enabled"];
      if (!doc["api_https"].isNull())     cfg.api_https    = doc["api_https"];
      if (doc["api_host"].is<const char*>()) strlcpy(cfg.api_host, doc["api_host"], sizeof(cfg.api_host));
      if (doc["api_path"].is<const char*>()) strlcpy(cfg.api_path, doc["api_path"], sizeof(cfg.api_path));
      if (!doc["api_port"].isNull())      cfg.api_port     = doc["api_port"];
      if (doc["api_user"].is<const char*>()) strlcpy(cfg.api_user, doc["api_user"], sizeof(cfg.api_user));
      if (doc["api_pass"].is<const char*>()) strlcpy(cfg.api_pass, doc["api_pass"], sizeof(cfg.api_pass));
      if (!doc["temp_corr"].isNull())     cfg.temp_corr    = doc["temp_corr"];
      if (!doc["elevation"].isNull())     cfg.elevation    = doc["elevation"];
      if (!doc["measure_sec"].isNull())   cfg.measure_sec  = doc["measure_sec"];
      return;
    }
  }
  prefs.end();
}

// =====================================================================
// MQ135 – Index, Trend, Min/Max, Avg
// =====================================================================
void updateMQ() {
  mq_raw = analogRead(MQ135_PIN);

  // Min/Max
  if (mq_raw < mq_min) mq_min = mq_raw;
  if (mq_raw > mq_max) mq_max = mq_raw;

  // Gleitender Mittelwert
  mq_avg = (mq_avg * 9 + mq_raw) / 10.0f;

  // Trend
  static float last_avg = mq_avg;
  if (mq_avg > last_avg + 5) mq_trend = +1;
  else if (mq_avg < last_avg - 5) mq_trend = -1;
  else mq_trend = 0;
  last_avg = mq_avg;

  // MQ-Index (Variante A)
  // MQ=100 → Index=100
  // MQ=400 → Index=0
  mq_index = 100 * (400 - mq_raw) / 300;
  if (mq_index < 0) mq_index = 0;
  if (mq_index > 100) mq_index = 100;
}

// =====================================================================
// Messung
// =====================================================================
void measurementEvent() {
  bmp.takeForcedMeasurement();
  delay(10);

  temperature  = bmp.readTemperature() + cfg.temp_corr;
  abs_pressure = bmp.readPressure() / 100.0f;

  updateMQ();

  rel_pressure = abs_pressure * powf(
    1.0f - (0.0065f * cfg.elevation /
    (temperature + 0.0065f * cfg.elevation + 273.15f)),
    -5.257f
  );
}

// =====================================================================
// Display – Seite 0 (Hauptseite)
// =====================================================================
static void showPage0() {
  tft.fillScreen(COL_BG);

  // Uhrzeit
  tft.setTextColor(COL_VALUE, COL_BG);
  tft.setTextSize(2);
  tft.setCursor(4, 10);
  char timebuf[16];
  snprintf(timebuf, sizeof(timebuf), "%02d:%02d:%02d", hour(), minute(), second());
  tft.print(timebuf);

  // Temperatur
  char buf[16];
  snprintf(buf, sizeof(buf), "%.1f C", temperature);
  tft.setTextSize(3);
  tft.setCursor(4, 50);
  tft.print(buf);

  // Bewertung
  tft.setTextSize(2);
  tft.setCursor(4, 110);

  if (mq_index > 70) {
    tft.setTextColor(COL_GOOD, COL_BG);
    tft.print("Gut");
  } else if (mq_index > 40) {
    tft.setTextColor(COL_WARN, COL_BG);
    tft.print("Mittel");
  } else {
    tft.setTextColor(COL_BAD, COL_BG);
    tft.print("Schlecht");
  }

  tft.setTextColor(COL_VALUE, COL_BG);
  tft.setCursor(200, 120);
  tft.print("0/3");
}

// =====================================================================
// Display – Seite 1 (MQ-Index)
// =====================================================================
static void showPage1() {
  tft.fillScreen(COL_BG);

  // MQ Rohwert farbig
  uint16_t col = (mq_raw < 150) ? COL_GOOD :
                 (mq_raw < 300) ? COL_WARN :
                                   COL_BAD;

  tft.setTextColor(col, COL_BG);
  tft.setTextSize(2);
  tft.setCursor(4, 10);
  char buf[16];
  snprintf(buf, sizeof(buf), "Raw: %d", mq_raw);
  tft.print(buf);

  // MQ Index groß
  tft.setTextColor(col, COL_BG);
  tft.setTextSize(5);
  tft.setCursor(4, 50);
  snprintf(buf, sizeof(buf), "%d", mq_index);
  tft.print(buf);

  tft.setTextSize(1);
  tft.setTextColor(COL_VALUE, COL_BG);
  tft.setCursor(200, 120);
  tft.print("1/3");
}

// =====================================================================
// Display – Seite 2 (MQ-Detailseite)
// =====================================================================
static void showPage2() {
  tft.fillScreen(COL_BG);

  tft.setTextColor(COL_TITLE, COL_BG);
  tft.setCursor(4, 4);
  tft.print("MQ135 Details");

  tft.setTextColor(COL_VALUE, COL_BG);
  tft.setCursor(4, 30);
  tft.printf("Raw: %d", mq_raw);

  tft.setCursor(4, 50);
  tft.printf("Avg: %.1f", mq_avg);

  tft.setCursor(4, 70);
  tft.print("Trend: ");
  if (mq_trend > 0) tft.print("↑");
  else if (mq_trend < 0) tft.print("↓");
  else tft.print("→");

  tft.setCursor(4, 90);
  tft.printf("Min: %d  Max: %d", mq_min, mq_max);

  tft.setCursor(4, 110);
  if (mq_index > 70) tft.print("Luft OK");
  else if (mq_index > 40) tft.print("Lueften sinnvoll");
  else tft.print("Bitte lueften");

  tft.setCursor(200, 120);
  tft.print("2/3");
}

// =====================================================================
// Display – Seite 3 (System)
// =====================================================================
static void showPage3() {
  tft.fillScreen(COL_BG);

  tft.setTextColor(COL_TITLE, COL_BG);
  tft.setCursor(4, 4);
  tft.print("System");

  tft.setTextColor(COL_VALUE, COL_BG);
  tft.setCursor(4, 30);
  tft.print("WiFi: ");
  tft.print(wifiOk ? "OK" : "FEHLER");

  tft.setCursor(4, 50);
  tft.print("NTP: ");
  tft.print(ntpOk ? "OK" : "---");

  tft.setCursor(4, 70);
  tft.print("API: ");
  tft.print(apiOk ? "OK" : "---");

  tft.setCursor(4, 90);
  tft.print("BMP280: ");
  tft.print(bmpOk ? "OK" : "FEHLER");

  tft.setCursor(4, 110);
  char buf[16];
  snprintf(buf, sizeof(buf), "Int: %ds", cfg.measure_sec);
  tft.print(buf);

  tft.setCursor(200, 120);
  tft.print("3/3");
}

// =====================================================================
// Seitenumschaltung
// =====================================================================
void showPage(int page) {
  switch (page) {
    case 0: showPage0(); break;
    case 1: showPage1(); break;
    case 2: showPage2(); break;
    case 3: showPage3(); break;
  }
}

void IRAM_ATTR onDisplayButton() {
  buttonPressed = true;
}

// =====================================================================
// WiFi + NTP
// =====================================================================
static bool connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(cfg.wifi_ssid, cfg.wifi_pass);

  for (int i = 0; i < 40; i++) {
    if (WiFi.status() == WL_CONNECTED) {
      wifiOk = true;
      return true;
    }
    delay(200);
  }
  wifiOk = false;
  return false;
}

WiFiUDP ntpUDP;
EasyNTPClient ntpClient(ntpUDP, NTP_SERVER, 7200);

static void syncNTP() {
  unsigned long t = ntpClient.getUnixTime();
  if (t > 1000000000UL) {
    setTime(t);
    ntpOk = true;
  } else {
    ntpOk = false;
  }
}

// =====================================================================
// API
// =====================================================================
#if USE_API
static SWSApiClient* apiClient = nullptr;

static void initApiClient() {
  delete apiClient;
  apiClient = new SWSApiClient(cfg.api_host, cfg.api_path,
                               cfg.api_user, cfg.api_pass, cfg.api_https);
  apiClient->setStationName(cfg.station_name);
  apiClient->setDeviceMac(WiFi.macAddress().c_str());
}

void sendToAPI() {
  if (!apiClient || !cfg.api_enabled) return;

  SWSResult result = apiClient
    ->set("temperature",   temperature)
    .set("abs_pressure",  abs_pressure)
    .set("rel_pressure",  rel_pressure)

    .set("mq_raw",   mq_raw)
    .set("mq_avg",   mq_avg)
    .set("mq_index", mq_index)
    .set("mq_trend", mq_trend)
    .set("mq_min",   mq_min)
    .set("mq_max",   mq_max)

    .send();

  apiOk = result.ok;
}
#endif

// =====================================================================
// setup()
// =====================================================================
void setup() {
  Serial.begin(115200);
  delay(200);

  loadConfig();

  tft.init();
  tft.setRotation(1);
  tft.fillScreen(COL_BG);

  pinMode(DISPLAY_BUTTON_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(DISPLAY_BUTTON_PIN), onDisplayButton, FALLING);

  bmpOk = initBMP280();

  connectWiFi();
  if (wifiOk) syncNTP();

#if USE_API
  if (wifiOk && cfg.api_enabled) initApiClient();
#endif

  showPage(0);
  lastMeasMs = millis();
}

// =====================================================================
// loop()
// =====================================================================
void loop() {
  unsigned long now = millis();

  if (now - lastMeasMs >= (unsigned long)cfg.measure_sec * 1000UL) {
    lastMeasMs = now;
    if (bmpOk) {
      measurementEvent();
      showPage(currentPage);

#if USE_API
      if (wifiOk && cfg.api_enabled) sendToAPI();
#endif
    }
  }

  if (buttonPressed) {
    buttonPressed = false;
    currentPage = (currentPage + 1) % 4;
    showPage(currentPage);
  }
}
