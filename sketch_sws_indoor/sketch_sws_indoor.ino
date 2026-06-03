/*----------------------------------------------------------------------------------------------------
  SWS Indoor Station – LilyGO TTGO T-Display (ESP32)
  Sketch : sketch_sws_indoor/sketch_sws_indoor.ino

  Alle Funktionen des Hauptsketches (sketch_sws) ohne Batterie-ADC.
  Statt Deep-Sleep: kontinuierlicher Loop mit konfigurierbarem Messintervall.
  Zusaetzlich: TFT-Anzeige (ST7789 via TFT_eSPI) mit mehreren Seiten.

  Arduino-IDE Board-Einstellungen:
	Board      : ESP32 Dev Module
	PSRAM      : Disabled
	Flash Size : 4MB
	Upload Speed: 921600
	esp32-Core : 2.0.14  (TFT_eSPI unterstuetzt nur bis 2.0.14)

  Benoetigt Libraries (Arduino Library Manager):
	- TFT_eSPI          (LilyGO-Konfiguration: User_Setup aus TTGO-T-Display Repo kopieren)
	- Adafruit BME280 Library
	- Adafruit Unified Sensor
	- ArduinoJson       >= 7.x
	- EasyNTPClient
	- Time (Paul Stoffregen)
	- SWSApiClient      (aus library/SWSApiClient/ dieses Repos)
----------------------------------------------------------------------------------------------------*/

#include "SettingsIndoor.h"

#include <Wire.h>
#include <Adafruit_Sensor.h>
#include <Adafruit_BME280.h>
#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>          // ESP32-EEPROM-Ersatz (NVS)
#include <ArduinoJson.h>
#include <WiFiUdp.h>
#include <EasyNTPClient.h>
#include <TimeLib.h>
#include <TFT_eSPI.h>             // TFT-Display
#include <SWSApiClient.h>

#if USE_OTA
  #include <HTTPClient.h>
  #include <HTTPUpdate.h>
  #include <WiFiClientSecure.h>
#endif

// =====================================================================
// Vorwaerts-Deklarationen
// =====================================================================
void measurementEvent();
void sendToAPI();
void updateDisplay();
void showPage(int page);
void startConfigPortal();
void loadConfig();
void saveConfig();
void applyDefaults();
#if USE_REMOTE_CONFIG
void fetchRemoteConfig();
#endif
#if USE_OTA
void checkOTA();
#endif

// =====================================================================
// Laufzeit-Konfiguration (NVS, Fallback: CFG_DEFAULT_*)
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
  int   sleep_min;      // wird nicht genutzt (kein Sleep), bleibt fuer API-Kompatibilitaet
  int   measure_sec;
};

StationConfig cfg;
Preferences   prefs;

// =====================================================================
// Globale Messwerte
// =====================================================================
float temperature   = 0.0f;
float humidity      = 0.0f;
float abs_pressure  = 0.0f;
float rel_pressure  = 0.0f;
float dewpoint      = 0.0f;
float heatindex     = 0.0f;

// Zambretti
String pressureState  = "";
String zambrettiSays  = "";
String zambrettiLetter = "";
int    trendRaw       = 0;   // -1/0/+1

// Systemstatus
bool   wifiOk         = false;
bool   ntpOk          = false;
bool   apiOk          = false;
bool   bmeOk          = false;
unsigned long lastMeasMs = 0;

// Display
TFT_eSPI tft = TFT_eSPI();
int currentPage      = 0;
unsigned long lastPageMs = 0;
volatile bool buttonPressed = false;

// API-Client
#if USE_API
static SWSApiClient* apiClient = nullptr;

static void initApiClient() {
  delete apiClient;
  apiClient = new SWSApiClient(cfg.api_host, cfg.api_path,
							   cfg.api_user, cfg.api_pass, cfg.api_https);
  apiClient->setStationName(cfg.station_name);
  apiClient->setDeviceMac(WiFi.macAddress().c_str());
}
#endif

// =====================================================================
// NVS – Konfiguration lesen / schreiben
// =====================================================================
static void applyDefaults() {
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
  prefs.begin("sws_indoor", true);   // read-only
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
	  Serial.println("Konfiguration aus NVS geladen.");
	  return;
	}
  } else {
	prefs.end();
  }
  Serial.println("NVS leer/ungueltig – verwende Compile-Zeit-Defaults.");
}

void saveConfig() {
  JsonDocument doc;
  doc["station_name"] = cfg.station_name;
  doc["wifi_ssid"]    = cfg.wifi_ssid;
  doc["wifi_pass"]    = cfg.wifi_pass;
  doc["api_enabled"]  = cfg.api_enabled;
  doc["api_https"]    = cfg.api_https;
  doc["api_host"]     = cfg.api_host;
  doc["api_path"]     = cfg.api_path;
  doc["api_port"]     = cfg.api_port;
  doc["api_user"]     = cfg.api_user;
  doc["api_pass"]     = cfg.api_pass;
  doc["temp_corr"]    = cfg.temp_corr;
  doc["elevation"]    = cfg.elevation;
  doc["measure_sec"]  = cfg.measure_sec;
  String json;
  serializeJson(doc, json);
  prefs.begin("sws_indoor", false);
  prefs.putString("cfg_json", json);
  prefs.end();
  Serial.println("Konfiguration in NVS gespeichert.");
}

// =====================================================================
// Config-Portal (Access Point + Webserver)
// =====================================================================
void startConfigPortal() {
  Serial.println("Starte Konfigurations-Portal...");

  // Display: Hinweis anzeigen
  tft.fillScreen(TFT_NAVY);
  tft.setTextColor(TFT_WHITE, TFT_NAVY);
  tft.setTextSize(1);
  tft.setCursor(4, 8);
  tft.println("=== Config-Portal ===");
  tft.setCursor(4, 28);
  tft.println("WLAN: " + String(CONFIG_AP_SSID));
  tft.setCursor(4, 48);
  tft.println("IP: 192.168.4.1");

  WiFi.mode(WIFI_AP);
  WiFi.softAP(CONFIG_AP_SSID);
  delay(200);

  WebServer server(80);

  auto field = [](const char* label, const char* name, const char* val, int maxlen = 64) -> String {
	return "<tr><td><label>" + String(label) + "</label></td><td>"
		   "<input type='text' name='" + String(name) + "' value='" + String(val)
		   + "' maxlength='" + String(maxlen) + "'></td></tr>";
  };
  auto fieldInt = [](const char* label, const char* name, int val) -> String {
	return "<tr><td><label>" + String(label) + "</label></td><td>"
		   "<input type='number' name='" + String(name) + "' value='" + String(val) + "'></td></tr>";
  };
  auto fieldFloat = [](const char* label, const char* name, float val) -> String {
	return "<tr><td><label>" + String(label) + "</label></td><td>"
		   "<input type='text' name='" + String(name) + "' value='" + String(val, 1) + "'></td></tr>";
  };
  auto fieldCheck = [](const char* label, const char* name, bool val) -> String {
	String chk = val ? " checked" : "";
	return "<tr><td><label>" + String(label) + "</label></td><td>"
		   "<input type='checkbox' name='" + String(name) + "' value='1'" + chk + "></td></tr>";
  };

  server.on("/", HTTP_GET, [&]() {
	String html = R"(<!DOCTYPE html><html><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>SWS Indoor Konfiguration</title>
<style>
  body{font-family:sans-serif;max-width:540px;margin:20px auto;padding:0 12px;background:#f4f4f4}
  h1{color:#1a5276;font-size:1.3em}
  h2{color:#555;font-size:1em;border-bottom:1px solid #ccc;padding-bottom:4px;margin-top:20px}
  table{width:100%;border-collapse:collapse}
  td{padding:5px 4px;vertical-align:middle}
  td:first-child{width:45%;font-size:.9em;color:#333}
  input[type=text],input[type=number],input[type=password]{width:100%;padding:4px;box-sizing:border-box;border:1px solid #bbb;border-radius:3px}
  input[type=checkbox]{width:18px;height:18px}
  .btn{background:#1a5276;color:#fff;border:none;padding:10px 28px;border-radius:4px;font-size:1em;cursor:pointer;margin-top:16px;width:100%}
  .note{font-size:.8em;color:#888;margin-top:8px}
</style></head><body>
<h1>&#9728; SWS Indoor Station</h1>
<h2>Konfiguration</h2>
<form method='POST' action='/save'>
<h2>WLAN</h2><table>)";

	html += field("Stationsname",    "station_name", cfg.station_name);
	html += field("WLAN SSID",       "wifi_ssid",    cfg.wifi_ssid);
	html += field("WLAN Passwort",   "wifi_pass",    cfg.wifi_pass, 64);

	html += "</table><h2>REST-API</h2><table>";
	html += fieldCheck("API aktiv",  "api_enabled",  cfg.api_enabled);
	html += fieldCheck("HTTPS",      "api_https",    cfg.api_https);
	html += field("Host",            "api_host",     cfg.api_host);
	html += field("Pfad",            "api_path",     cfg.api_path);
	html += fieldInt("Port",         "api_port",     cfg.api_port);
	html += field("Benutzer",        "api_user",     cfg.api_user, 32);
	html += field("Passwort",        "api_pass",     cfg.api_pass, 32);

	html += "</table><h2>Sonstiges</h2><table>";
	html += fieldFloat("Temp-Korrektur (°C)", "temp_corr",   cfg.temp_corr);
	html += fieldInt("Höhe ü. NN (m)",        "elevation",   cfg.elevation);
	html += fieldInt("Messintervall (s)",      "measure_sec", cfg.measure_sec);

	html += R"(</table>
<button class='btn' type='submit'>Speichern &amp; Neustart</button>
<p class='note'>Nach dem Speichern startet die Station automatisch neu.</p>
</form></body></html>)";

	server.send(200, "text/html", html);
  });

  server.on("/save", HTTP_POST, [&]() {
	auto get = [&](const char* key, const char* def) -> String {
	  return server.hasArg(key) ? server.arg(key) : String(def);
	};
	strlcpy(cfg.station_name, get("station_name", cfg.station_name).c_str(), sizeof(cfg.station_name));
	strlcpy(cfg.wifi_ssid,    get("wifi_ssid",    cfg.wifi_ssid).c_str(),    sizeof(cfg.wifi_ssid));
	strlcpy(cfg.wifi_pass,    get("wifi_pass",    cfg.wifi_pass).c_str(),    sizeof(cfg.wifi_pass));
	cfg.api_enabled  = server.hasArg("api_enabled");
	cfg.api_https    = server.hasArg("api_https");
	strlcpy(cfg.api_host, get("api_host", cfg.api_host).c_str(), sizeof(cfg.api_host));
	strlcpy(cfg.api_path, get("api_path", cfg.api_path).c_str(), sizeof(cfg.api_path));
	cfg.api_port     = get("api_port", String(cfg.api_port).c_str()).toInt();
	strlcpy(cfg.api_user, get("api_user", cfg.api_user).c_str(), sizeof(cfg.api_user));
	strlcpy(cfg.api_pass, get("api_pass", cfg.api_pass).c_str(), sizeof(cfg.api_pass));
	cfg.temp_corr    = get("temp_corr",   String(cfg.temp_corr).c_str()).toFloat();
	cfg.elevation    = get("elevation",   String(cfg.elevation).c_str()).toInt();
	cfg.measure_sec  = get("measure_sec", String(cfg.measure_sec).c_str()).toInt();
	if (cfg.measure_sec < 5) cfg.measure_sec = 5;

	saveConfig();

	server.send(200, "text/html",
	  "<!DOCTYPE html><html><head><meta charset='utf-8'>"
	  "<meta http-equiv='refresh' content='3;url=/'></head><body>"
	  "<p style='font-family:sans-serif;margin:20px'>"
	  "&#10003; Gespeichert. Neustart in 3 Sekunden...</p></body></html>");
	delay(500);
	ESP.restart();
  });

  server.begin();
  Serial.println("Config-Portal aktiv (kein Timeout – Neustart nach Speichern).");
  while (true) { server.handleClient(); yield(); }
}

// =====================================================================
// BME280
// =====================================================================
Adafruit_BME280 bme;

static bool initBME280() {
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  if (!bme.begin(BME280_ADDRESS)) {
	// Fallback: andere Adresse versuchen
	if (!bme.begin(BME280_ADDRESS == 0x76 ? 0x77 : 0x76)) {
	  Serial.println("BME280 nicht gefunden!");
	  return false;
	}
  }
  bme.setSampling(Adafruit_BME280::MODE_FORCED,
				  Adafruit_BME280::SAMPLING_X1,
				  Adafruit_BME280::SAMPLING_X1,
				  Adafruit_BME280::SAMPLING_X1,
				  Adafruit_BME280::FILTER_OFF);
  Serial.println("BME280 OK.");
  return true;
}

// =====================================================================
// Zambretti-Logik (aus Hauptsketch uebernommen)
// =====================================================================
// Einfache Drucktrend-Puffer (letzte 3 Messungen)
static float pressureBuf[3] = {0, 0, 0};
static int   pressureBufIdx = 0;
static bool  pressureBufFull = false;

static void pushPressure(float p) {
  pressureBuf[pressureBufIdx] = p;
  pressureBufIdx = (pressureBufIdx + 1) % 3;
  if (pressureBufIdx == 0) pressureBufFull = true;
}

static int calcTrend() {
  if (!pressureBufFull) return 0;
  float oldest = pressureBuf[pressureBufIdx];
  float newest = pressureBuf[(pressureBufIdx + 2) % 3];
  float delta  = newest - oldest;
  if (delta >  0.5f) return  1;
  if (delta < -0.5f) return -1;
  return 0;
}

static String pressureStateStr(float p) {
  if (p < 990)  return LANG_PRESSURE[PRESS_STORM_LOW];
  if (p < 1000) return LANG_PRESSURE[PRESS_STRONG_LOW];
  if (p < 1013) return LANG_PRESSURE[PRESS_LOW];
  if (p < 1025) return LANG_PRESSURE[PRESS_HIGH];
  return LANG_PRESSURE[PRESS_STRONG_HIGH];
}

// Vereinfachter Zambretti (Buchstabe A–Z aus Druck + Trend)
static String zambretti(float p, int trend, float tempC) {
  // Sommer/Winter-Umschaltung
  static bool winterMode = false;
  if (tempC < WINTER_THRESHOLD_LOW)  winterMode = true;
  if (tempC > WINTER_THRESHOLD_HIGH) winterMode = false;

  int z = 0;
  if (trend > 0) {                          // steigend
	z = (int)((1050.0f - p) / 22.0f);
  } else if (trend < 0) {                   // fallend
	z = (int)((1050.0f - p) / 18.0f) + 12;
  } else {                                  // stabil
	z = (int)((1050.0f - p) / 20.0f) + 6;
  }
  z = constrain(z, 0, 25);

  // Buchstabe und Vorhersage-Text aus Translation
  char letter[2] = { (char)('A' + z), '\0' };
  String ltr = String(letter);

  // LANG_ZAMBRETTI ist ein Array[26] in den Translation-Dateien
  String forecast = LANG_ZAMBRETTI[z];
  // Winter: Regen-Wort durch Schnee-Wort ersetzen (falls in Translation definiert)
#ifdef LANG_RAIN_WORD
  if (winterMode) {
	forecast.replace(LANG_RAIN_WORD, LANG_SNOW_WORD);
  }
#endif
  zambrettiLetter = ltr;
  return forecast;
}

// =====================================================================
// Messung
// =====================================================================
void measurementEvent() {
  bme.takeForcedMeasurement();
  delay(10);

  temperature  = bme.readTemperature() + cfg.temp_corr;
  humidity     = bme.readHumidity();
  abs_pressure = bme.readPressure() / 100.0f;

  // Relative Lufdruck (Barometrische Hoehenkorrektur)
  rel_pressure = abs_pressure * powf(1.0f - (0.0065f * cfg.elevation / (temperature + 0.0065f * cfg.elevation + 273.15f)), -5.257f);

  // Taupunkt
  float a = 17.27f, b = 237.7f;
  float alpha = ((a * temperature) / (b + temperature)) + logf(humidity / 100.0f);
  dewpoint    = (b * alpha) / (a - alpha);

  // Waermeindex (gilt ab 27°C und 40% rel. Feuchte)
  if (temperature >= 27.0f && humidity >= 40.0f) {
	float T = temperature, H = humidity;
	heatindex = -8.784695f + 1.61139411f*T + 2.338549f*H
				- 0.14611605f*T*H - 0.01230809f*T*T
				- 0.01642482f*H*H + 0.00221173f*T*T*H
				+ 0.00072546f*T*H*H - 0.00000358f*T*T*H*H;
  } else {
	heatindex = temperature;
  }

  // Drucktrend und Zambretti
  pushPressure(rel_pressure);
  trendRaw     = calcTrend();
  pressureState = pressureStateStr(rel_pressure);
  zambrettiSays = zambretti(rel_pressure, trendRaw, temperature);

  Serial.printf("T=%.1f°C  H=%.1f%%  abs=%.1f hPa  rel=%.1f hPa  Trend=%d  Z=%s\n",
				temperature, humidity, abs_pressure, rel_pressure, trendRaw, zambrettiLetter.c_str());
}

// =====================================================================
// API-Upload
// =====================================================================
void sendToAPI() {
#if USE_API
  if (!apiClient || !cfg.api_enabled) return;

  apiClient->clearFields();
  apiClient->addField("temperature",   temperature);
  apiClient->addField("humidity",      humidity);
  apiClient->addField("abs_pressure",  abs_pressure);
  apiClient->addField("rel_pressure",  rel_pressure);
  apiClient->addField("dewpoint",      dewpoint);
  // Kein battery_pct / battery_volt – Station laeuft an USB

  bool ok = apiClient->sendMeasurement();
  apiOk   = ok;
  Serial.println(ok ? "API-Upload OK." : "API-Upload FEHLER.");
#endif
}

// =====================================================================
// WiFi
// =====================================================================
static bool connectWiFi() {
  Serial.print("WLAN verbinden mit ");
  Serial.print(cfg.wifi_ssid);
  WiFi.mode(WIFI_STA);
  WiFi.begin(cfg.wifi_ssid, cfg.wifi_pass);
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 40) {
	delay(500);
	Serial.print(".");
	attempts++;
  }
  wifiOk = (WiFi.status() == WL_CONNECTED);
  Serial.println(wifiOk ? "\nWLAN OK." : "\nWLAN FEHLER.");
  return wifiOk;
}

// =====================================================================
// NTP
// =====================================================================
WiFiUDP    ntpUdp;
EasyNTPClient ntpClient(ntpUdp, NTP_SERVER, 7200);  // UTC+2 (Europe/Berlin CEST)

static void syncNTP() {
  ntpClient.update();
  unsigned long t = ntpClient.getUnixTime();
  if (t > 1000000000UL) {
	setTime(t);
	ntpOk = true;
	Serial.println("NTP synchronisiert.");
  } else {
	ntpOk = false;
	Serial.println("NTP Fehler.");
  }
}

// =====================================================================
// Remote-Config
// =====================================================================
#if USE_REMOTE_CONFIG
void fetchRemoteConfig() {
  String proto = cfg.api_https ? "https" : "http";
  String url   = proto + "://" + cfg.api_host + CFG_REMOTE_CONFIG_PATH
				 + "?station=" + cfg.station_name
				 + "&mac="     + WiFi.macAddress();
  Serial.print("RemoteConfig: ");
  Serial.println(url);

  WiFiClientSecure sc; sc.setInsecure();
  WiFiClient       pc;
  WiFiClient* wc = cfg.api_https ? (WiFiClient*)&sc : (WiFiClient*)&pc;

  HTTPClient http;
  http.setTimeout(CFG_REMOTE_CONFIG_TIMEOUT);
  http.begin(*wc, url);
  if (strlen(cfg.api_user) > 0) http.setAuthorization(cfg.api_user, cfg.api_pass);

  int code = http.GET();
  if (code != 200) { http.end(); return; }

  JsonDocument doc;
  if (deserializeJson(doc, http.getString()) != DeserializationError::Ok || !doc["ok"].as<bool>()) {
	http.end(); return;
  }
  http.end();

  bool changed = false;
  if (!doc["sleep_min"].isNull())   { /* ignoriert – kein Sleep */ }
  if (!doc["temp_corr"].isNull())   { float v = doc["temp_corr"]; if (fabsf(v-cfg.temp_corr)>0.01f) { cfg.temp_corr=v; changed=true; } }
  if (!doc["elevation"].isNull())   { int   v = doc["elevation"]; if (v>=0 && v!=cfg.elevation)      { cfg.elevation=v; changed=true; } }
  if (!doc["measure_sec"].isNull()) { int   v = doc["measure_sec"]; if (v>=5 && v!=cfg.measure_sec)  { cfg.measure_sec=v; changed=true; } }
  if (!doc["api_path"].isNull()) {
	const char* v = doc["api_path"]; if (v && strncmp(v,cfg.api_path,sizeof(cfg.api_path))!=0) { strlcpy(cfg.api_path,v,sizeof(cfg.api_path)); changed=true; }
  }
  if (changed) { saveConfig(); initApiClient(); Serial.println("RemoteConfig: Einstellungen uebernommen."); }
  else           Serial.println("RemoteConfig: Keine Aenderungen.");
}
#endif

// =====================================================================
// OTA
// =====================================================================
#if USE_OTA
void checkOTA() {
  String url = (cfg.api_https ? "https" : "http");
  url += "://";
  url += cfg.api_host;
  url += CFG_OTA_BASE_PATH;
  url += "/";
  url += CFG_OTA_SKETCH_ID;
  url += "/version.txt";

  WiFiClientSecure sc; sc.setInsecure();
  WiFiClient       pc;
  WiFiClient* wc = cfg.api_https ? (WiFiClient*)&sc : (WiFiClient*)&pc;

  HTTPClient http;
  http.setTimeout(CFG_OTA_TIMEOUT_MS);
  http.begin(*wc, url);
  int code = http.GET();
  if (code != 200) { http.end(); return; }
  String serverVer = http.getString();
  serverVer.trim();
  http.end();

  Serial.print("OTA: Lokal="); Serial.print(IndoorVersion);
  Serial.print(" Server=");    Serial.println(serverVer);

  if (serverVer == IndoorVersion) return;

  String binUrl = (cfg.api_https ? "https" : "http");
  binUrl += "://"; binUrl += cfg.api_host;
  binUrl += CFG_OTA_BASE_PATH; binUrl += "/"; binUrl += CFG_OTA_SKETCH_ID; binUrl += "/firmware.bin";

  Serial.println("OTA: Starte Update...");
  tft.fillScreen(TFT_NAVY);
  tft.setTextColor(TFT_WHITE, TFT_NAVY);
  tft.setCursor(4, 30); tft.println("OTA Update...");
  tft.setCursor(4, 50); tft.println(serverVer);

  WiFiClientSecure sc2; sc2.setInsecure();
  t_httpUpdate_return ret = httpUpdate.update(sc2, binUrl);
  if (ret == HTTP_UPDATE_OK) {
	Serial.println("OTA OK – Neustart.");
	ESP.restart();
  } else {
	Serial.printf("OTA Fehler: %d\n", (int)ret);
  }
}
#endif

// =====================================================================
// TFT-Display
// =====================================================================
// Farben (16-Bit RGB565)
#define COL_BG      TFT_BLACK
#define COL_TITLE   TFT_CYAN
#define COL_VALUE   TFT_WHITE
#define COL_UNIT    TFT_DARKGREY
#define COL_GOOD    TFT_GREEN
#define COL_WARN    TFT_YELLOW
#define COL_BAD     TFT_RED

static void tftLabel(int x, int y, const char* label, uint16_t col = COL_UNIT) {
  tft.setTextColor(col, COL_BG);
  tft.setTextSize(1);
  tft.setCursor(x, y);
  tft.print(label);
}

static void tftValue(int x, int y, const char* val, uint16_t col = COL_VALUE, int size = 2) {
  tft.setTextColor(col, COL_BG);
  tft.setTextSize(size);
  tft.setCursor(x, y);
  tft.print(val);
}

// Seite 0: Haupt (Temp, Feuchte, Taupunkt)
static void showPage0() {
  tft.fillScreen(COL_BG);

  // Titelzeile
  tft.setTextColor(COL_TITLE, COL_BG);
  tft.setTextSize(1);
  tft.setCursor(4, 4);
  tft.print(cfg.station_name);
  tft.setCursor(4, 15);
  if (wifiOk) {
	char buf[20];
	snprintf(buf, sizeof(buf), "%02d:%02d", hour(), minute());
	tft.print(buf);
  } else {
	tft.print("Offline");
  }

  // Temperatur gross
  char buf[16];
  snprintf(buf, sizeof(buf), "%.1f", temperature);
  tftValue(4, 34, buf, COL_VALUE, 3);
  tftLabel(4 + strlen(buf)*18 + 2, 44, " C");

  // Feuchte
  tftLabel(4, 80, "Feuchte");
  snprintf(buf, sizeof(buf), "%.1f %%", humidity);
  tftValue(4, 90, buf);

  // Taupunkt
  tftLabel(90, 80, "Taupunkt");
  snprintf(buf, sizeof(buf), "%.1f C", dewpoint);
  tftValue(90, 90, buf);

  // Statuszeile unten
  tft.setTextSize(1);
  tft.setTextColor(apiOk ? COL_GOOD : COL_WARN, COL_BG);
  tft.setCursor(4, 122);
  tft.print(apiOk ? "API OK" : "API --");
  tft.setTextColor(COL_UNIT, COL_BG);
  tft.setCursor(60, 122);
  tft.print("1/3");
}

// Seite 1: Druck + Zambretti
static void showPage1() {
  tft.fillScreen(COL_BG);

  tft.setTextColor(COL_TITLE, COL_BG);
  tft.setTextSize(1);
  tft.setCursor(4, 4);
  tft.print("Luftdruck & Prognose");

  char buf[32];
  snprintf(buf, sizeof(buf), "%.1f hPa rel", rel_pressure);
  tftValue(4, 20, buf);

  snprintf(buf, sizeof(buf), "%.1f hPa abs", abs_pressure);
  tftLabel(4, 44, buf);

  // Trend-Pfeil
  const char* arrow = (trendRaw > 0) ? "^ steigend" : (trendRaw < 0) ? "v fallend" : "- stabil";
  uint16_t arrowCol = (trendRaw > 0) ? COL_GOOD : (trendRaw < 0) ? COL_BAD : COL_VALUE;
  tftLabel(4, 58, pressureState.c_str(), arrowCol);

  // Zambretti
  tft.setTextColor(COL_UNIT, COL_BG);
  tft.setTextSize(1);
  tft.setCursor(4, 76);
  tft.print("Zambretti ");
  tft.setTextColor(COL_TITLE, COL_BG);
  tft.print(zambrettiLetter);

  tft.setTextColor(COL_VALUE, COL_BG);
  tft.setCursor(4, 90);
  // Langen Text umbrechen
  String zs = zambrettiSays;
  if (zs.length() > 21) {
	tft.println(zs.substring(0, 21));
	tft.setCursor(4, 102);
	tft.print(zs.substring(21));
  } else {
	tft.print(zs);
  }

  tft.setTextColor(COL_UNIT, COL_BG);
  tft.setCursor(60, 122);
  tft.print("2/3");
}

// Seite 2: Systeminfo
static void showPage2() {
  tft.fillScreen(COL_BG);

  tft.setTextColor(COL_TITLE, COL_BG);
  tft.setTextSize(1);
  tft.setCursor(4, 4);
  tft.print("System");

  char buf[32];
  snprintf(buf, sizeof(buf), "v%s", IndoorVersion.c_str());
  tftLabel(4, 18, buf);

  tftLabel(4, 32, "WLAN:");
  tft.setTextColor(wifiOk ? COL_GOOD : COL_BAD, COL_BG);
  tft.setCursor(50, 32);
  tft.print(wifiOk ? "OK" : "FEHLER");

  tftLabel(4, 44, "NTP:");
  tft.setTextColor(ntpOk ? COL_GOOD : COL_WARN, COL_BG);
  tft.setCursor(50, 44);
  tft.print(ntpOk ? "OK" : "---");

  tftLabel(4, 56, "API:");
  tft.setTextColor(apiOk ? COL_GOOD : COL_WARN, COL_BG);
  tft.setCursor(50, 56);
  tft.print(apiOk ? "OK" : "---");

  tftLabel(4, 68, "BME280:");
  tft.setTextColor(bmeOk ? COL_GOOD : COL_BAD, COL_BG);
  tft.setCursor(60, 68);
  tft.print(bmeOk ? "OK" : "FEHLER");

  tftLabel(4, 80, "SSID:");
  tft.setTextColor(COL_VALUE, COL_BG);
  tft.setCursor(4, 90);
  tft.print(cfg.wifi_ssid);

  snprintf(buf, sizeof(buf), "Interval: %ds", cfg.measure_sec);
  tftLabel(4, 104, buf);

  tft.setTextColor(COL_UNIT, COL_BG);
  tft.setCursor(60, 122);
  tft.print("3/3");
}

void showPage(int page) {
  switch (page) {
	case 0: showPage0(); break;
	case 1: showPage1(); break;
	case 2: showPage2(); break;
  }
}

// =====================================================================
// Button-ISR (BUTTON2 = Seite wechseln)
// =====================================================================
static volatile unsigned long lastBtnMs = 0;

void IRAM_ATTR onDisplayButton() {
  unsigned long now = millis();
  if (now - lastBtnMs > 200) {   // Entprellung 200ms
	lastBtnMs     = now;
	buttonPressed = true;
  }
}

// =====================================================================
// setup()
// =====================================================================
void setup() {
  Serial.begin(115200);
  { unsigned long t = millis(); while (!Serial && millis()-t < 500); }
  delay(200);
  Serial.println();

  // Konfiguration laden
  loadConfig();

  // TFT initialisieren
  tft.init();
  tft.setRotation(1);            // Querformat 240x135
  tft.fillScreen(COL_BG);
  ledcSetup(0, 5000, 8);         // PWM fuer Hintergrundbeleuchtung
  ledcAttachPin(TFT_BL_PIN, 0);
  ledcWrite(0, 200);             // Helligkeit 0–255

  tft.setTextColor(COL_TITLE, COL_BG);
  tft.setTextSize(1);
  tft.setCursor(4, 10);
  tft.println("SWS Indoor Station");
  tft.setCursor(4, 24);
  tft.println("Booting...");

  Serial.printf("SWS Indoor v%s  Station: %s\n", IndoorVersion.c_str(), cfg.station_name);

  // Config-Portal: BUTTON1 (GPIO35) – kein interner Pullup moeglich (Input-Only)
  // Externer Pullup (10k nach 3.3V) empfohlen; ohne Pullup ist der Pin undefiniert!
  pinMode(CONFIG_BUTTON_PIN, INPUT);
  delay(20);
  if (digitalRead(CONFIG_BUTTON_PIN) == LOW) {
	startConfigPortal();   // kehrt nicht zurueck
  }

  // Display-Button (BUTTON2 = GPIO0, Pullup integriert)
  pinMode(DISPLAY_BUTTON_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(DISPLAY_BUTTON_PIN), onDisplayButton, FALLING);

  // BME280
  bmeOk = initBME280();
  if (!bmeOk) {
	tft.fillScreen(COL_BG);
	tft.setTextColor(COL_BAD, COL_BG);
	tft.setCursor(4, 20);
	tft.println("BME280 FEHLER!");
	tft.setCursor(4, 40);
	tft.println("SDA=21 SCL=22");
	tft.setCursor(4, 60);
	tft.println("Adresse 0x76/0x77?");
  }

  // WLAN
  tft.setTextColor(COL_VALUE, COL_BG);
  tft.setCursor(4, 38);
  tft.print("WLAN...");
  connectWiFi();

  if (wifiOk) {
	tft.setCursor(4, 52);
	tft.print("NTP...");
	syncNTP();

#if USE_API
	initApiClient();
#endif

#if USE_REMOTE_CONFIG
	fetchRemoteConfig();
#endif

#if USE_OTA
	checkOTA();
#endif
  }

  Serial.println("Setup abgeschlossen.");
  lastMeasMs = 0;   // sofort erste Messung ausloesen
}

// =====================================================================
// loop()
// =====================================================================
void loop() {
  unsigned long now = millis();

  // Display-Button verarbeiten
  if (buttonPressed) {
	buttonPressed = false;
	currentPage   = (currentPage + 1) % DISPLAY_PAGE_COUNT;
	showPage(currentPage);
	lastPageMs = now;
  }

  // Auto-Cycle
#if DISPLAY_AUTO_CYCLE
  if (now - lastPageMs >= (unsigned long)DISPLAY_CYCLE_SEC * 1000UL) {
	currentPage = (currentPage + 1) % DISPLAY_PAGE_COUNT;
	showPage(currentPage);
	lastPageMs  = now;
  }
#endif

  // Messung + Upload
  if (now - lastMeasMs >= (unsigned long)cfg.measure_sec * 1000UL) {
	lastMeasMs = now;

	if (bmeOk) {
	  measurementEvent();
	}

	// WLAN-Reconnect falls verloren
	if (WiFi.status() != WL_CONNECTED) {
	  wifiOk = false;
	  connectWiFi();
	  if (wifiOk) {
		syncNTP();
#if USE_API
		initApiClient();
#endif
	  }
	}

	if (wifiOk && bmeOk) {
	  sendToAPI();
	}

	// Display aktualisieren
	showPage(currentPage);
  }

  delay(10);
  yield();
}
