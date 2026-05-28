/*----------------------------------------------------------------------------------------------------
  Project Name : Solar Powered WiFi Weather Station V2.7
  Features: temperature, dewpoint, dewpoint spread, heat index, humidity, absolute pressure, relative pressure, battery status and
  the famous Zambretti Forecaster (multi lingual)
  Authors: Keith Hungerford, Debasish Dutta and Marc Stähli
  Website : www.opengreenenergy.com

  Main microcontroller (ESP8266) and BME280 both sleep between measurements
  BME280 is used in single shot mode ("forced mode")
  CODE: https://github.com/3KUdelta/Solar_WiFi_Weather_Station
  INSTRUCTIONS & HARDWARE: https://www.instructables.com/id/Solar-Powered-WiFi-Weather-Station-V20/
  3D FILES: https://www.thingiverse.com/thing:3551386

  ====================================================================
  Version History (recent):

  v2.7 (Juni 2025) - Konfigurations-Portal, PHP/MySQL-API & Historien-Endpoint
  - Neues AP-Konfigurations-Portal (GPIO0 beim Boot gedrückt halten):
    - ESP8266 öffnet WLAN-Accesspoint "SWS-Config" (kein Passwort)
    - Webinterface unter 192.168.4.1 zum Einstellen von WiFi, MQTT, API,
      Temperaturkorrektur, Elevation und Schlaf-Intervall
    - Alle Einstellungen werden als JSON im EEPROM gespeichert (Magic: SWS2)
    - Settings26.h bleibt als Compile-Zeit-Fallback erhalten
    - Portal schließt sich nach 60 s automatisch (danach Neustart)
  - PHP/MySQL-REST-API (api/):
    - data.php  : POST neue Messung / GET letzten Datensatz
    - history.php: GET Historien-Daten (limit, from, to)
    - auth.php  : zentrale HTTP-Basic-Auth-Prüfung
    - schema.sql: vollständiges Datenbankschema
    - README.md : Installations- und Nutzungsdokumentation
  - Sketch-seitige API-Anbindung (sendToAPI()):
    - HTTP oder HTTPS (Laufzeit-Auswahl über cfg.api_https)
    - Basic-Auth per Base64-Encoder
  - Alle Laufzeit-Einstellungen auf cfg.*-Struct umgestellt

  v2.6 (April 2026) - Configurable sensors & robustness pass
  - Sensors: BME280 (pressure/humidity) + DS18B20 (pool temperature)
  - USE_BME280, USE_DS18B20 to enable/disable sensors
  - TEMP_SOURCE to choose canonical temperature source (SRC_BME or SRC_DAL)
  - Bugfixes:
    - getTemperature(): was reading the same DS18B20 conversion 32 times.
      Now performs a single 12-bit conversion with proper wait.
    - ReadFromMQTT(): added receive-flag and timeout-aware wait so a missing
      MQTT pressure message no longer triggers an unwanted FirstTimeRun()
      that would wipe the 6h pressure curve.
    - exit(0) on SPIFFS failure replaced with goToSleep() to prevent
      battery drain through hung WiFi.
    - reconnect(): added retry loop (3 attempts) instead of single-shot.
    - goToSleep() no longer publishes MQTT status when MQTT==false.
    - Battery voltage: now averaged over 16 ADC reads to reduce noise.
    - NTP wait loop: yield() added to prevent soft WDT reset.
    - Sprach-Hysterese (DE/DW switch) to avoid flapping at ~2°C.
    - Defensive default in Zambretti switch statements.
    - Removed double semicolon typo in case 13.
  - Style:
    - resetFunc replaced with ESP.restart() (cleaner on ESP8266).
    - Cleaned up auskommentierter Fahrenheit-Code.
  - Kept unchanged:
    - DHCP for WiFi (per user preference)
    - Fixed sleep interval (per user preference)
    - All Zambretti / trend / translation / MQTT message logic 1:1

  ////  Features :  /////////////////////////////////////////////////////////////////////////////////////////////////////////////
  // 1. Connect to Wi-Fi, and upload the data to either Blynk App and/or any MQTT broker
  // 2. Monitoring Weather parameters like Temperature, Pressure abs, Pressure MSL and Humidity.
  // 3. Extra Ports to add more Weather Sensors like UV Index, Light and Rain Guage etc.
  // 4. Remote Battery Status Monitoring
  // 5. Using Sleep mode to reduce the energy consumed
  ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  /***************************************************
   VERY IMPORTANT:
 *                                                 *
   Enter your personal settings in Settings26.h !
 *                                                 *
 **************************************************/

#include "Settings26.h"
// Note: Translation file is now included from Settings26.h (Translations/Translation_XX.h)

// =====================================================================
// Internal constants for sensor source selection (do not change)
// =====================================================================
#define SRC_BME 1
#define SRC_DAL 2

// =====================================================================
// Sensor configuration validation (compile-time)
// =====================================================================
#if !USE_BME280
  #error "USE_BME280 must be 1: the project requires the BME280 for pressure (Zambretti forecast)."
#endif

#if (TEMP_SOURCE == SRC_DAL) && !USE_DS18B20
  #warning "TEMP_SOURCE = SRC_DAL but USE_DS18B20 = 0. Falling back to BME280 temperature."
  #undef  TEMP_SOURCE
  #define TEMP_SOURCE SRC_BME
#endif

// =====================================================================
// Conditional includes (only what's actually used)
// =====================================================================
#if USE_DS18B20
  #include <OneWire.h>
  #include <DallasTemperature.h>
#endif

#include <Wire.h>                   // I2C (always needed for BME280)

#include <Adafruit_Sensor.h>
#include <Adafruit_BME280.h>
#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecure.h>
#include <ESP8266WebServer.h>       // Konfigurations-Portal
#include <EEPROM.h>                 // Persistente Einstellungen
#include <ArduinoJson.h>
#include <WiFiUdp.h>
#include "FS.h"
#include <EasyNTPClient.h>          // https://github.com/aharshac/EasyNTPClient
#include <TimeLib.h>                // https://github.com/PaulStoffregen/Time.git
// PubSubClient (MQTT) wurde entfernt – Station arbeitet ausschließlich mit REST-API

// =====================================================================
// Laufzeit-Konfiguration (geladen aus EEPROM, Fallback: CFG_DEFAULT_*)
// =====================================================================
struct StationConfig {
  char  station_name[64];
  char  wifi_ssid[64];
  char  wifi_pass[64];
  // REST-API
  bool  api_enabled;
  bool  api_https;
  char  api_host[64];
  char  api_path[64];
  int   api_port;
  char  api_user[32];
  char  api_pass[32];
  // Sonstiges
  float temp_corr;
  int   elevation;
  int   sleep_min;
};

StationConfig cfg;  // globale Instanz – überall im Sketch verwendet

// EEPROM-Magic-Bytes: zeigen an, dass gültige Daten gespeichert sind
static const uint8_t EEPROM_MAGIC[4] = { 0x53, 0x57, 0x53, 0x32 };  // "SWS2"
static const int     EEPROM_SIZE     = 2048;
static const int     EEPROM_DATA_OFFSET = 4;

// Compile-Zeit-Defaults in cfg schreiben (immer als Ausgangsbasis)
static void applyDefaults() {
  strlcpy(cfg.station_name,     CFG_DEFAULT_STATION_NAME,     sizeof(cfg.station_name));
  strlcpy(cfg.wifi_ssid,        CFG_DEFAULT_WIFI_SSID,        sizeof(cfg.wifi_ssid));
  strlcpy(cfg.wifi_pass,        CFG_DEFAULT_WIFI_PASS,        sizeof(cfg.wifi_pass));
  cfg.api_enabled  = CFG_DEFAULT_API_ENABLED;
  cfg.api_https    = CFG_DEFAULT_API_HTTPS;
  strlcpy(cfg.api_host,         CFG_DEFAULT_API_HOST,         sizeof(cfg.api_host));
  strlcpy(cfg.api_path,         CFG_DEFAULT_API_PATH,         sizeof(cfg.api_path));
  cfg.api_port     = CFG_DEFAULT_API_PORT;
  strlcpy(cfg.api_user,         CFG_DEFAULT_API_USER,         sizeof(cfg.api_user));
  strlcpy(cfg.api_pass,         CFG_DEFAULT_API_PASS,         sizeof(cfg.api_pass));
  cfg.temp_corr    = CFG_DEFAULT_TEMP_CORR;
  cfg.elevation    = CFG_DEFAULT_ELEVATION;
  cfg.sleep_min    = CFG_DEFAULT_SLEEP_MIN;
}

void loadConfig() {
  // Erst Defaults setzen, dann ggf. mit EEPROM-Werten überschreiben
  applyDefaults();

  EEPROM.begin(EEPROM_SIZE);

  // Magic-Bytes prüfen
  bool valid = true;
  for (int i = 0; i < 4; i++) {
    if (EEPROM.read(i) != EEPROM_MAGIC[i]) { valid = false; break; }
  }
  if (!valid) {
    Serial.println("EEPROM leer/ungültig – verwende Compile-Zeit-Defaults.");
    return;
  }

  // JSON aus EEPROM lesen
  char buf[EEPROM_SIZE - EEPROM_DATA_OFFSET];
  for (int i = 0; i < (int)sizeof(buf); i++) {
    buf[i] = (char)EEPROM.read(EEPROM_DATA_OFFSET + i);
  }
  JsonDocument doc;
  if (deserializeJson(doc, buf) != DeserializationError::Ok) {
    Serial.println("EEPROM-JSON ungültig – verwende Compile-Zeit-Defaults.");
    return;
  }

  // Nur vorhandene EEPROM-Felder überschreiben; fehlende behalten den Default
  if (doc["station_name"].is<const char*>())     strlcpy(cfg.station_name,     doc["station_name"],     sizeof(cfg.station_name));
  if (doc["wifi_ssid"].is<const char*>())        strlcpy(cfg.wifi_ssid,        doc["wifi_ssid"],        sizeof(cfg.wifi_ssid));
  if (doc["wifi_pass"].is<const char*>())        strlcpy(cfg.wifi_pass,        doc["wifi_pass"],        sizeof(cfg.wifi_pass));
  if (!doc["api_enabled"].isNull())              cfg.api_enabled  = doc["api_enabled"];
  if (!doc["api_https"].isNull())                cfg.api_https    = doc["api_https"];
  if (doc["api_host"].is<const char*>())         strlcpy(cfg.api_host,         doc["api_host"],         sizeof(cfg.api_host));
  if (doc["api_path"].is<const char*>())         strlcpy(cfg.api_path,         doc["api_path"],         sizeof(cfg.api_path));
  if (!doc["api_port"].isNull())                 cfg.api_port     = doc["api_port"];
  if (doc["api_user"].is<const char*>())         strlcpy(cfg.api_user,         doc["api_user"],         sizeof(cfg.api_user));
  if (doc["api_pass"].is<const char*>())         strlcpy(cfg.api_pass,         doc["api_pass"],         sizeof(cfg.api_pass));
  if (!doc["temp_corr"].isNull())                cfg.temp_corr    = doc["temp_corr"];
  if (!doc["elevation"].isNull())                cfg.elevation    = doc["elevation"];
  if (!doc["sleep_min"].isNull())                cfg.sleep_min    = doc["sleep_min"];

  Serial.println("Konfiguration aus EEPROM geladen.");
}

void saveConfig() {
  JsonDocument doc;
  doc["station_name"]     = cfg.station_name;
  doc["wifi_ssid"]        = cfg.wifi_ssid;
  doc["wifi_pass"]        = cfg.wifi_pass;
  doc["api_enabled"]      = cfg.api_enabled;
  doc["api_https"]        = cfg.api_https;
  doc["api_host"]         = cfg.api_host;
  doc["api_path"]         = cfg.api_path;
  doc["api_port"]         = cfg.api_port;
  doc["api_user"]         = cfg.api_user;
  doc["api_pass"]         = cfg.api_pass;
  doc["temp_corr"]        = cfg.temp_corr;
  doc["elevation"]        = cfg.elevation;
  doc["sleep_min"]        = cfg.sleep_min;

  char buf[EEPROM_SIZE - EEPROM_DATA_OFFSET];
  serializeJson(doc, buf, sizeof(buf));

  EEPROM.begin(EEPROM_SIZE);
  for (int i = 0; i < 4; i++) EEPROM.write(i, EEPROM_MAGIC[i]);
  for (int i = 0; i < (int)strlen(buf) + 1; i++) {
    EEPROM.write(EEPROM_DATA_OFFSET + i, buf[i]);
  }
  EEPROM.commit();
  Serial.println("Konfiguration im EEPROM gespeichert.");
}


#if USE_DS18B20
  #define ONE_WIRE_BUS 13            // Data wire 18d20 Sensor is plugged into port D7 @ ESP8266
  #define DS18B20_RESOLUTION 12      // 12-bit -> 0.0625°C, conversion ~750ms
#endif

Adafruit_BME280 bme;                // I2C

#if USE_DS18B20
  OneWire oneWire(ONE_WIRE_BUS);
  DallasTemperature s18d20(&oneWire);
#endif

WiFiUDP udp;
EasyNTPClient ntpClient(udp, NTP_SERVER, 0);  // reading UTC

//varialbes of measured or calculated sensor data
#if USE_DS18B20
  float measured_temp_dal;
#endif
float measured_temp_bme;
float measured_temp;
float adjusted_temp;
float measured_humi;
float measured_humi_bme;
float adjusted_humi;
float pool_temp = -88;  // DS18B20 Pooltemperatur (-88 = kein Sensor / Fehler)
float measured_pres;
float SLpressure_hPa;               // needed for rel pressure calculation
float HeatIndex;                    // Heat Index in °C
float volt;
int batterypercentage;
int rel_pressure_rounded;
double DewpointTemperature;
float DewPointSpread;               // Difference between actual temperature and dewpoint

//variables for trend calculation
unsigned long current_timestamp;    // Actual timestamp read from NTPtime_t now;
unsigned long saved_timestamp;      // Timestamp stored in SPIFFS
float pressure_value[12];           // Array for the historical pressure values (6 hours, all 30 mins), where as pressure_value[0] is always the most recent value
float pressure_difference[12];      // Array to calculate trend with pressure differences

// variables for forcasting result
int accuracy;                       // Counter, if enough values for accurate forecasting
String ZambrettisWords;             // Final statement about weather forecast (after {P}/{E} substitution)
char z_letter;
int trend_idx;                      // Index into LANG_TRENDS[] (0..6)
int pressure_idx;                   // Index into LANG_PRESSURE[] (0..4)
// (Convenience accessors below for readability and serial debug output.)
inline const char* trend_in_words()    { return LANG_TRENDS[trend_idx]; }
inline const char* pressure_in_words() { return LANG_PRESSURE[pressure_idx]; }

// Trend index
#define TREND_RISING_FAST   0
#define TREND_RISING        1
#define TREND_RISING_SLOW   2
#define TREND_STEADY        3
#define TREND_FALLING_SLOW  4
#define TREND_FALLING       5
#define TREND_FALLING_FAST  6

// Pressure-state index constants (used with LANG_PRESSURE[])
#define PRESS_STORM_LOW     0
#define PRESS_STRONG_LOW    1
#define PRESS_LOW           2
#define PRESS_HIGH          3
#define PRESS_STRONG_HIGH   4



// =====================================================================
// Konfigurations-Portal
// Gestartet wenn CONFIG_BUTTON_PIN beim Aufwachen LOW ist.
// Der ESP öffnet einen Access Point (SSID: SWS-Config) und stellt
// unter http://192.168.4.1 ein HTML-Formular bereit.
// Nach dem Speichern startet der ESP automatisch neu (kein Timeout).
// =====================================================================
void startConfigPortal() {
  Serial.println("\n*** Konfigurations-Portal gestartet ***");
  Serial.print("WLAN-Name: "); Serial.println(CONFIG_AP_SSID);
  Serial.println("IP: 192.168.4.1");

  // WLAN sauber in AP-Modus bringen
  WiFi.persistent(false);   // verhindert, dass softAP-Credentials im Flash gespeichert werden
  WiFi.disconnect();        // bestehende STA-Verbindung trennen (ohne Modem-Reset)
  delay(100);
  WiFi.mode(WIFI_AP);
  delay(100);
  bool apOk = WiFi.softAP(CONFIG_AP_SSID);   // kein Passwort = offener AP
  delay(500);   // AP braucht ~300–500 ms bis er sichtbar ist

  if (!apOk) {
    Serial.println("FEHLER: softAP() fehlgeschlagen! Neustart...");
    delay(1000);
    ESP.restart();
  }

  Serial.print("AP IP: ");
  Serial.println(WiFi.softAPIP());

  ESP8266WebServer server(80);

  // ---- HTML-Hilfsfunktion ----
  auto field = [](const char* label, const char* name, const char* val, int maxlen = 64) -> String {
    String s = "<tr><td><label>" + String(label) + "</label></td><td>"
               "<input name='" + name + "' value='" + String(val) + "' maxlength='" + String(maxlen) + "'></td></tr>";
    return s;
  };
  auto fieldInt = [](const char* label, const char* name, int val) -> String {
    String s = "<tr><td><label>" + String(label) + "</label></td><td>"
               "<input type='number' name='" + name + "' value='" + String(val) + "'></td></tr>";
    return s;
  };
  auto fieldFloat = [](const char* label, const char* name, float val) -> String {
    String s = "<tr><td><label>" + String(label) + "</label></td><td>"
               "<input type='number' step='0.1' name='" + name + "' value='" + String(val, 1) + "'></td></tr>";
    return s;
  };
  auto fieldCheck = [](const char* label, const char* name, bool val) -> String {
    String chk = val ? " checked" : "";
    return "<tr><td><label>" + String(label) + "</label></td><td>"
           "<input type='checkbox' name='" + String(name) + "' value='1'" + chk + "></td></tr>";
  };

  // ---- GET: Formular anzeigen ----
  server.on("/", HTTP_GET, [&]() {
    String html = R"(<!DOCTYPE html><html><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>SWS Konfiguration</title>
<style>
  body{font-family:sans-serif;max-width:540px;margin:20px auto;padding:0 12px;background:#f4f4f4}
  h1{color:#2c7a2c;font-size:1.3em}
  h2{color:#555;font-size:1em;border-bottom:1px solid #ccc;padding-bottom:4px;margin-top:20px}
  table{width:100%;border-collapse:collapse}
  td{padding:5px 4px;vertical-align:middle}
  td:first-child{width:45%;font-size:.9em;color:#333}
  input[type=text],input[type=number],input[type=password]{width:100%;padding:4px;box-sizing:border-box;border:1px solid #bbb;border-radius:3px}
  input[type=checkbox]{width:18px;height:18px}
  .btn{background:#2c7a2c;color:#fff;border:none;padding:10px 28px;border-radius:4px;font-size:1em;cursor:pointer;margin-top:16px;width:100%}
  .note{font-size:.8em;color:#888;margin-top:8px}
  .saved{background:#e8f5e9;border:1px solid #2c7a2c;padding:10px;border-radius:4px;margin-bottom:12px}
</style></head><body>
<h1>&#9728; Solar Weather Station</h1>
<h2>Konfiguration</h2>
<form method='POST' action='/save'>
<h2>WLAN</h2><table>)";

    html += field("Stationsname", "station_name", cfg.station_name);
    html += field("WLAN SSID", "wifi_ssid", cfg.wifi_ssid);
    html += field("WLAN Passwort", "wifi_pass", cfg.wifi_pass, 64);

    html += "</table><h2>REST-API</h2><table>";
    html += fieldCheck("API aktiv", "api_enabled", cfg.api_enabled);
    html += fieldCheck("HTTPS", "api_https", cfg.api_https);
    html += field("Host", "api_host", cfg.api_host);
    html += field("Pfad", "api_path", cfg.api_path);
    html += fieldInt("Port", "api_port", cfg.api_port);
    html += field("Benutzer", "api_user", cfg.api_user, 32);
    html += field("Passwort", "api_pass", cfg.api_pass, 32);

    html += "</table><h2>Sonstiges</h2><table>";
    html += fieldFloat("Temp-Korrektur (°C)", "temp_corr", cfg.temp_corr);
    html += fieldInt("Höhe ü. NN (m)", "elevation", cfg.elevation);
    html += fieldInt("Schlafzeit (min)", "sleep_min", cfg.sleep_min);

    html += R"(</table>
<button class='btn' type='submit'>Speichern &amp; Neustart</button>
<p class='note'>Nach dem Speichern startet die Station automatisch neu.</p>
</form></body></html>)";

    server.send(200, "text/html", html);
  });

  // ---- POST: Werte speichern ----
  server.on("/save", HTTP_POST, [&]() {
    auto get = [&](const char* key, const char* def) -> String {
      return server.hasArg(key) ? server.arg(key) : String(def);
    };

    strlcpy(cfg.station_name,     get("station_name",    cfg.station_name).c_str(),     sizeof(cfg.station_name));
    strlcpy(cfg.wifi_ssid,        get("wifi_ssid",       cfg.wifi_ssid).c_str(),         sizeof(cfg.wifi_ssid));
    strlcpy(cfg.wifi_pass,        get("wifi_pass",       cfg.wifi_pass).c_str(),         sizeof(cfg.wifi_pass));
    cfg.api_enabled  = server.hasArg("api_enabled");
    cfg.api_https    = server.hasArg("api_https");
    strlcpy(cfg.api_host,         get("api_host",  cfg.api_host).c_str(),  sizeof(cfg.api_host));
    strlcpy(cfg.api_path,         get("api_path",  cfg.api_path).c_str(),  sizeof(cfg.api_path));
    cfg.api_port     = get("api_port",   String(cfg.api_port).c_str()).toInt();
    strlcpy(cfg.api_user,         get("api_user",  cfg.api_user).c_str(),  sizeof(cfg.api_user));
    strlcpy(cfg.api_pass,         get("api_pass",  cfg.api_pass).c_str(),  sizeof(cfg.api_pass));
    cfg.temp_corr    = get("temp_corr",  String(cfg.temp_corr).c_str()).toFloat();
    cfg.elevation    = get("elevation",  String(cfg.elevation).c_str()).toInt();
    cfg.sleep_min    = get("sleep_min",  String(cfg.sleep_min).c_str()).toInt();
    if (cfg.sleep_min < 1) cfg.sleep_min = 1;

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

  Serial.println("Warte auf Konfiguration (kein Timeout – Neustart erfolgt nach dem Speichern)...");

  while (true) {
    server.handleClient();
    yield();
  }
  // Kein Timeout: Das Portal läuft bis der Nutzer speichert (/save → ESP.restart())
  // oder einen Hardware-Reset auslöst.
}

void setup() {
  Serial.begin(115200);
  { unsigned long t = millis(); while (!Serial && millis() - t < 500); }  // Timeout: kein Blockieren ohne Monitor
  delay(200);
  Serial.println();

  // Konfiguration aus EEPROM laden (oder Defaults verwenden)
  loadConfig();

  // Konfigurations-Portal prüfen: Button (CONFIG_BUTTON_PIN) beim Start LOW?
  pinMode(CONFIG_BUTTON_PIN, INPUT_PULLUP);
  delay(10);
  if (digitalRead(CONFIG_BUTTON_PIN) == LOW) {
    startConfigPortal();   // kehrt nicht zurück (Neustart am Ende)
  }

  Serial.print("Start of ");
  Serial.print(cfg.station_name);
  Serial.print(", Version ");
  Serial.println(Version);

  // Print the active sensor configuration for diagnostic purposes
  Serial.print("Sensors enabled: BME280=");
  Serial.print(USE_BME280 ? "Y" : "N");
  Serial.print("  DS18B20=");
  Serial.println(USE_DS18B20 ? "Y" : "N");
  Serial.print("Canonical sources: TEMP=");
  #if   TEMP_SOURCE == SRC_BME
    Serial.print("BME280");
  #elif TEMP_SOURCE == SRC_DAL
    Serial.print("DS18B20");
  #endif
  Serial.print("  HUMI=BME280");

  Serial.print("Language: ");
  Serial.println(LANG_NAME);

  //******Battery
  // FIX v2.6: averaged over 16 ADC reads to reduce ESP8266 ADC noise.

  // Voltage divider R1 = 220k+100k+220k =540k and R2=100k
  unsigned long raw_total = 0;
  for (int i = 0; i < 16; i++) {
    raw_total += analogRead(A0);
    delay(2);
  }
  volt = (raw_total / 16.0) * BATTERY_CALIB_FACTOR / 1024.0;

  Serial.print("Voltage = ");
  Serial.print(volt, 2);
  Serial.println(" V");

  batterypercentage = (volt - 3.4) * 100 / 0.7;   // 3.4 V is the lower limint set to 0%, bandwith 0.7 V
  if (batterypercentage > 100) batterypercentage = 100;
  if (batterypercentage < 0)   batterypercentage = 0;
  Serial.print("Battery charge: ");
  Serial.print(batterypercentage);
  Serial.println("%");

  // **************Application going online**********************************************

  WiFi.mode(WIFI_STA);
  WiFi.hostname(cfg.station_name); // Hostname im Netzwerk anzeigen
  WiFi.begin(cfg.wifi_ssid, cfg.wifi_pass);
  Serial.print("---> Connecting to WiFi ");
  int i = 0;
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    i++;
    if (i > 20) {
      Serial.println("Could not connect to WiFi!");
      Serial.println("Going to sleep for 10 minutes and try again.");
      if (volt > 3.4) {
        goToSleep(10);   // go to sleep and retry after 10 min
      }
      else {
        goToSleep(0);   // Batterie leer: ESP.deepSleep(0) = permanenter Schlaf, Wake nur per Reset-Pin (RST→GND)
      }
    }
    Serial.print(".");
  }
  Serial.println(" Wifi connected ok");

  Serial.println("SPIFFS Initialisierung...");
  if (!SPIFFS.begin()) {
    Serial.println("SPIFFS nicht formatiert – wird formatiert (bis zu 30 s)...");
    SPIFFS.format();
    SPIFFS.begin();
  }

  //******** GETTING THE TIME FROM NTP SERVER  ***********************************

  Serial.println("---> Now reading time from NTP Server");
  int ii = 0;
  while (!ntpClient.getUnixTime()) {
    yield();                     // FIX v2.6: feed watchdog to prevent soft WDT reset
    delay(100);
    ii++;
    if (ii > 20) {
      Serial.println("Could not connect to NTP Server!");
      Serial.println("Doing a reset now and retry a connection from scratch.");
      ESP.restart();             // FIX v2.6: cleaner than jump to address 0
    }
    Serial.print(".");
  }
  current_timestamp = ntpClient.getUnixTime();      // get UNIX timestamp (seconds from 1.1.1970 on)

  Serial.print("Current UNIX Timestamp: ");
  Serial.println(current_timestamp);

  Serial.print("Time & Date: ");
  Serial.print(hour(current_timestamp));
  Serial.print(":");
  Serial.print(minute(current_timestamp));
  Serial.print(":");
  Serial.print(second(current_timestamp));
  Serial.print("; ");
  Serial.print(day(current_timestamp));
  Serial.print(".");
  Serial.print(month(current_timestamp));
  Serial.print(".");
  Serial.print(year(current_timestamp));
  Serial.println(" Local timezone does not matter - we just need always the same timezone --> using UTC");

  //******** SENSOR INITIALISATION  ********************

  // ----- BME280 (always required for pressure) -----
  bool bme_status = bme.begin(0x76);  //address either 0x76 or 0x77
  if (!bme_status) {
    Serial.println("Could not find a valid BME280 sensor, check wiring!");
  }

  Serial.println("BME280: forced mode, 1x temperature / 1x humidity / 1x pressure oversampling, filter off");

  bme.setSampling(Adafruit_BME280::MODE_FORCED,
                  Adafruit_BME280::SAMPLING_X1, // temperature
                  Adafruit_BME280::SAMPLING_X1, // pressure
                  Adafruit_BME280::SAMPLING_X1, // humidity
                  Adafruit_BME280::FILTER_OFF   );

#if USE_DS18B20
  // ----- DS18B20 -----
  s18d20.begin();
  s18d20.setResolution(DS18B20_RESOLUTION);
  Serial.println("DS18B20 initialized at 12-bit resolution.");
#endif

measurementEvent();             // calling function to get all data from the different sensors

  ReadFromSPIFFS();

  Serial.print("Timestamp difference: ");
  Serial.println(current_timestamp - saved_timestamp);

  if (current_timestamp - saved_timestamp > 21600) {     // last save older than 6 hours -> re-initialize values
    FirstTimeRun();
  }
  else if (current_timestamp - saved_timestamp > 1700) { // it is time for pressure update (1800 sec = 30 min)

    for (int i = 11; i >= 1; i = i - 1) {
      pressure_value[i] = pressure_value[i - 1];        // shifting values one to the right
    }

    pressure_value[0] = rel_pressure_rounded;           // updating with acutal rel pressure (newest value)

    if (accuracy < 12) {
      accuracy = accuracy + 1;
    }

    WriteToSPIFFS(current_timestamp);
  }

  //**************************Calculate Zambretti Forecast*******************************************

  int accuracy_in_percent = accuracy * 94 / 12;        // 94% is the max predicion accuracy of Zambretti
  if ( volt > 3.4 ) {
    ZambrettisWords = ZambrettiSays(char(ZambrettiLetter()));
  }
  else {
    ZambrettisWords = ZambrettiSays('0');   // send Message that battery is empty
  }

  Serial.println("********************************************************");
  Serial.print("Zambretti says: ");
  Serial.print(ZambrettisWords);
  Serial.print(", ");
  Serial.println(trend_in_words());
  Serial.print("Prediction accuracy: ");
  Serial.print(accuracy_in_percent);
  Serial.println("%");
  if (accuracy < 12) {
    Serial.println("Reason: Not enough weather data yet.");
    Serial.print("We need ");
    Serial.print((12 - accuracy) / 2);
    Serial.println(" hours more to get sufficient data.");
  }
  Serial.println("********************************************************");

  #if USE_API
  if (cfg.api_enabled) sendToAPI();   // Messdaten zusätzlich an PHP/MySQL-API senden
#endif

  if (volt < 0.5) {
    Serial.println("Kein Akku erkannt (USB-Betrieb) – normaler Schlaf.");
    goToSleep(cfg.sleep_min);
  } else if (volt > 3.4) {
    goToSleep(cfg.sleep_min);
  }
  else {
    goToSleep(0);   // Batterie leer: ESP.deepSleep(0) = permanenter Schlaf, Wake nur per Reset-Pin (RST→GND)
  }
} // end of void setup()

void loop() {               //loop is not used
} // end of void loop()

void measurementEvent() {

  //Measures absolute Pressure, Temperature, Humidity, Voltage, calculate relative pressure,
  //Dewpoint, Dewpoint Spread, Heat Index, current pressure state

  // ----- BME280 (always read - needed for pressure, used as cross-check) -----
  bme.takeForcedMeasurement();
  measured_temp_bme = bme.readTemperature();
  measured_humi_bme = bme.readHumidity();
  measured_pres    = bme.readPressure() / 100.0F;

  Serial.print("Temp BME: ");
  Serial.print(measured_temp_bme);
  Serial.print("°C; Humidity BME: ");
  Serial.print(measured_humi_bme);
  Serial.println("%; ");

#if USE_DS18B20
  // ----- DS18B20 als Poolsensor -----
  measured_temp_dal = getTemperature();
  pool_temp = measured_temp_dal;  // Pooltemperatur separat speichern
  Serial.print("Pool-Temp (DS18B20): ");
  Serial.print(pool_temp);
  Serial.println("°C; ");
#endif

  // ----- Selection of canonical values per Settings26.h -----
#if   TEMP_SOURCE == SRC_BME
  measured_temp = measured_temp_bme;
#elif TEMP_SOURCE == SRC_DAL
  measured_temp = measured_temp_dal;
#endif

  measured_humi = measured_humi_bme;

  // ----- Pressure (always BME280) -----
  Serial.print("Pressure: ");
  Serial.print(measured_pres);
  Serial.print("hPa; ");

  SLpressure_hPa = (((measured_pres * 100.0) / pow((1 - ((float)(cfg.elevation)) / 44330), 5.255)) / 100.0);
  rel_pressure_rounded = (int)(SLpressure_hPa + .5);
  Serial.print("Pressure rel: ");
  Serial.print(rel_pressure_rounded);
  Serial.print("hPa; ");

  // ----- Dewpoint -----
  double a = 17.271;
  double b = 237.7;
  double tempcalc = (a * measured_temp) / (b + measured_temp) + log(measured_humi * 0.01);
  DewpointTemperature = (b * tempcalc) / (a - tempcalc);
  Serial.print("Dewpoint: ");
  Serial.print(DewpointTemperature);
  Serial.println("°C; ");

  if (cfg.temp_corr != 0.0f) {
    adjusted_temp = measured_temp + cfg.temp_corr;
    if (adjusted_temp < DewpointTemperature) adjusted_temp = DewpointTemperature; //compensation, if offset too high
    //August-Roche-Magnus approximation (http://bmcnoldy.rsmas.miami.edu/Humidity.html)
    adjusted_humi = 100 * (exp((a * DewpointTemperature) / (b + DewpointTemperature)) / exp((a * adjusted_temp) / (b + adjusted_temp)));
    if (adjusted_humi > 100) adjusted_humi = 100;
    Serial.print("Temp adjusted: ");
    Serial.print(adjusted_temp);
    Serial.print("°C; ");
    Serial.print("Humidity adjusted: ");
    Serial.print(adjusted_humi);
    Serial.print("%; ");
  }
  else
  {
    adjusted_temp = measured_temp;
    adjusted_humi = measured_humi;
  }

  // Dewpoint spread
  DewPointSpread = adjusted_temp - DewpointTemperature;
  Serial.print("Dewpoint Spread: ");
  Serial.print(DewPointSpread);
  Serial.println("°C; ");

  // Heat Index (>26.7°C only)
  if (adjusted_temp > 26.7) {
    double c1 = -8.784, c2 = 1.611, c3 = 2.338, c4 = -0.146, c5 = -1.230e-2, c6 = -1.642e-2, c7 = 2.211e-3, c8 = 7.254e-4, c9 = -2.582e-6  ;
    double T = adjusted_temp;
    double R = adjusted_humi;

    double A = (( c5 * T) + c2) * T + c1;
    double B = ((c7 * T) + c4) * T + c3;
    double C = ((c9 * T) + c8) * T + c6;
    HeatIndex = (C * R + B) * R + A;
  }
  else {
    HeatIndex = adjusted_temp;
    Serial.println("Not warm enough (less than 26.7 °C) for Heatindex");
  }
  Serial.print("HeatIndex: ");
  Serial.print(HeatIndex);
  Serial.println("°C; ");

  // Pressure state (index into LANG_PRESSURE[])
  if      (rel_pressure_rounded < 990)                                     pressure_idx = PRESS_STORM_LOW;
  else if (rel_pressure_rounded >= 990  && rel_pressure_rounded < 1000)    pressure_idx = PRESS_STRONG_LOW;
  else if (rel_pressure_rounded >= 1000 && rel_pressure_rounded < 1013)    pressure_idx = PRESS_LOW;
  else if (rel_pressure_rounded >= 1013 && rel_pressure_rounded < 1025)    pressure_idx = PRESS_HIGH;
  else                                                                     pressure_idx = PRESS_STRONG_HIGH;

  Serial.print("Pressure State: ");
  Serial.println(pressure_in_words());

} // end of void measurementEvent()

int CalculateTrend() {
  int trend;                                    // -1 falling; 0 steady; 1 raising
  Serial.println("---> Calculating trend");

  //--> giving the most recent pressure reads more weight
  pressure_difference[0]  = (pressure_value[0] - pressure_value[1])   * 1.5;
  pressure_difference[1]  = (pressure_value[0] - pressure_value[2]);
  pressure_difference[2]  = (pressure_value[0] - pressure_value[3])   / 1.5;
  pressure_difference[3]  = (pressure_value[0] - pressure_value[4])   / 2;
  pressure_difference[4]  = (pressure_value[0] - pressure_value[5])   / 2.5;
  pressure_difference[5]  = (pressure_value[0] - pressure_value[6])   / 3;
  pressure_difference[6]  = (pressure_value[0] - pressure_value[7])   / 3.5;
  pressure_difference[7]  = (pressure_value[0] - pressure_value[8])   / 4;
  pressure_difference[8]  = (pressure_value[0] - pressure_value[9])   / 4.5;
  pressure_difference[9]  = (pressure_value[0] - pressure_value[10])  / 5;
  pressure_difference[10] = (pressure_value[0] - pressure_value[11])  / 5.5;

  //--> calculating the average and storing it into [11]
  pressure_difference[11] = (  pressure_difference[0]
                               + pressure_difference[1]
                               + pressure_difference[2]
                               + pressure_difference[3]
                               + pressure_difference[4]
                               + pressure_difference[5]
                               + pressure_difference[6]
                               + pressure_difference[7]
                               + pressure_difference[8]
                               + pressure_difference[9]
                               + pressure_difference[10]) / 11;

  Serial.print("Current trend: ");
  Serial.println(pressure_difference[11]);

  if      (pressure_difference[11] >  3.5) {
    trend_idx = TREND_RISING_FAST;
    trend = 1;
  }
  else if (pressure_difference[11] >  1.5  && pressure_difference[11] <=  3.5)  {
    trend_idx = TREND_RISING;
    trend = 1;
  }
  else if (pressure_difference[11] >  0.25 && pressure_difference[11] <=  1.5)  {
    trend_idx = TREND_RISING_SLOW;
    trend = 1;
  }
  else if (pressure_difference[11] > -0.25 && pressure_difference[11] <   0.25) {
    trend_idx = TREND_STEADY;
    trend = 0;
  }
  else if (pressure_difference[11] >= -1.5 && pressure_difference[11] <  -0.25) {
    trend_idx = TREND_FALLING_SLOW;
    trend = -1;
  }
  else if (pressure_difference[11] >= -3.5 && pressure_difference[11] <  -1.5)  {
    trend_idx = TREND_FALLING;
    trend = -1;
  }
  else /* pressure_difference[11] <= -3.5 */ {
    trend_idx = TREND_FALLING_FAST;
    trend = -1;
  }

  Serial.println(trend_in_words());
  return trend;
}

char ZambrettiLetter() {
  Serial.println("---> Calculating Zambretti letter");
  int z_trend = CalculateTrend();
  // Case trend is falling
  if (z_trend == -1) {
    float zambretti = 0.0009746 * rel_pressure_rounded * rel_pressure_rounded - 2.1068 * rel_pressure_rounded + 1138.7019;
    //A Winter falling generally results in a Z value lower by 1 unit
    if (month(current_timestamp) < 4 || month(current_timestamp) > 9) zambretti = zambretti + 1;
    if (zambretti > 9) zambretti = 9;
    Serial.print("Calculated and rounded Zambretti in numbers: ");
    Serial.println(round(zambretti));
    switch (int(round(zambretti))) {
      case 0:  z_letter = 'A'; break;       //Settled Fine
      case 1:  z_letter = 'A'; break;       //Settled Fine
      case 2:  z_letter = 'B'; break;       //Fine Weather
      case 3:  z_letter = 'D'; break;       //Fine Becoming Less Settled
      case 4:  z_letter = 'H'; break;       //Fairly Fine Showers Later
      case 5:  z_letter = 'O'; break;       //Showery Becoming unsettled
      case 6:  z_letter = 'R'; break;       //Unsettled, Rain later
      case 7:  z_letter = 'U'; break;       //Rain at times, worse later
      case 8:  z_letter = 'V'; break;       //Rain at times, becoming very unsettled
      case 9:  z_letter = 'X'; break;       //Very Unsettled, Rain
      default: z_letter = 'A'; break;       //defensive default (FIX v2.6)
    }
  }
  // Case trend is steady
  if (z_trend == 0) {
    float zambretti = 138.24 - 0.133 * rel_pressure_rounded;
    Serial.print("Calculated and rounded Zambretti in numbers: ");
    Serial.println(round(zambretti));
    switch (int(round(zambretti))) {
      case 0:  z_letter = 'A'; break;       //Settled Fine
      case 1:  z_letter = 'A'; break;       //Settled Fine
      case 2:  z_letter = 'B'; break;       //Fine Weather
      case 3:  z_letter = 'E'; break;       //Fine, Possibly showers
      case 4:  z_letter = 'K'; break;       //Fairly Fine, Showers likely
      case 5:  z_letter = 'N'; break;       //Showery Bright Intervals
      case 6:  z_letter = 'P'; break;       //Changeable some rain
      case 7:  z_letter = 'S'; break;       //Unsettled, rain at times
      case 8:  z_letter = 'W'; break;       //Rain at Frequent Intervals
      case 9:  z_letter = 'X'; break;       //Very Unsettled, Rain
      case 10: z_letter = 'Z'; break;       //Stormy, much rain
      default: z_letter = 'A'; break;       //defensive default (FIX v2.6)
    }
  }
  // Case trend is rising
  if (z_trend == 1) {
    float zambretti = 142.57 - 0.1376 * rel_pressure_rounded;
    //A Summer rising, improves the prospects by 1 unit over a Winter rising
    if (month(current_timestamp) >= 4 && month(current_timestamp) <= 9) zambretti = zambretti - 1;
    if (zambretti < 0) zambretti = 0;
    Serial.print("Calculated and rounded Zambretti in numbers: ");
    Serial.println(round(zambretti));
    switch (int(round(zambretti))) {
      case 0:  z_letter = 'A'; break;       //Settled Fine
      case 1:  z_letter = 'A'; break;       //Settled Fine
      case 2:  z_letter = 'B'; break;       //Fine Weather
      case 3:  z_letter = 'C'; break;       //Becoming Fine
      case 4:  z_letter = 'F'; break;       //Fairly Fine, Improving
      case 5:  z_letter = 'G'; break;       //Fairly Fine, Possibly showers, early
      case 6:  z_letter = 'I'; break;       //Showery Early, Improving
      case 7:  z_letter = 'J'; break;       //Changeable, Improving
      case 8:  z_letter = 'L'; break;       //Rather Unsettled Clearing Later
      case 9:  z_letter = 'M'; break;       //Unsettled, Probably Improving
      case 10: z_letter = 'Q'; break;       //Unsettled, short fine Intervals
      case 11: z_letter = 'T'; break;       //Very Unsettled, Finer at times
      case 12: z_letter = 'Y'; break;       //Stormy, possibly improving
      case 13: z_letter = 'Z'; break;       //Stormy, much rain  (FIX v2.6: removed double semicolon)
      default: z_letter = 'A'; break;       //defensive default (FIX v2.6)
    }
  }
  Serial.print("This is Zambretti's famous letter: ");
  Serial.println(z_letter);
  return z_letter;
}

// ----- Seasonal precipitation word selection with hysteresis -----
// Returns true while we're in winter mode (snow), false otherwise (rain).
// Uses static state so the threshold can be crossed without flapping
// between summer and winter when the temperature hovers near 2°C.
bool isWinterMode() {
  static bool winter = false;
  if (winter && measured_temp > WINTER_THRESHOLD_HIGH) winter = false;
  if (!winter && measured_temp <= WINTER_THRESHOLD_LOW) winter = true;
  return winter;
}

// ----- Replace one occurrence of `marker` in `dest` with `replacement` -----
// Simple in-place substitution. Returns the modified String.
// We use String here because the result length varies and the call site
// only happens once per measurement cycle (no hot path).
static String replaceMarker(const String& src, const char* marker, const char* replacement) {
  String result = src;
  int pos = result.indexOf(marker);
  while (pos >= 0) {
    result = result.substring(0, pos) + replacement + result.substring(pos + strlen(marker));
    pos = result.indexOf(marker, pos + strlen(replacement));
  }
  return result;
}

String ZambrettiSays(char code) {
  // Map the Zambretti char to an array index:
  //   'A'..'Z' -> 0..25
  //   '0'      -> 26  (low battery message)
  //   anything else -> default fallback string
  int idx;
  if (code >= 'A' && code <= 'Z')      idx = code - 'A';
  else if (code == '0')                 idx = 26;
  else                                  return String(LANG_FORECAST_DEFAULT);

  // Determine the precipitation words for the current season
  bool winter = isWinterMode();
  const char* precip_p = winter ? LANG_PRECIP_P_WINTER : LANG_PRECIP_P_SUMMER;
  const char* precip_e = winter ? LANG_PRECIP_E_WINTER : LANG_PRECIP_E_SUMMER;

  // Look up the template and substitute the markers
  String result(LANG_ZAMBRETTI[idx]);
  if (result.indexOf("{P}") >= 0) result = replaceMarker(result, "{P}", precip_p);
  if (result.indexOf("{E}") >= 0) result = replaceMarker(result, "{E}", precip_e);
  return result;
}

void ReadFromSPIFFS() {
  char filename [] = "/data.txt";
  File myDataFile = SPIFFS.open(filename, "r");       // Open file for reading
  if (!myDataFile) {
    Serial.println("Failed to open file");
    FirstTimeRun();                                   // no file there -> initializing
  }

  Serial.println("---> Now reading from SPIFFS");

  String temp_data;

  temp_data = myDataFile.readStringUntil('\n');
  saved_timestamp = temp_data.toInt();
  Serial.print("Timestamp from SPIFFS: ");  Serial.println(saved_timestamp);

  temp_data = myDataFile.readStringUntil('\n');
  accuracy = temp_data.toInt();
  Serial.print("Accuracy value read from SPIFFS: ");  Serial.println(accuracy);

  Serial.print("Last 12 saved pressure values: ");
  for (int i = 0; i <= 11; i++) {
    temp_data = myDataFile.readStringUntil('\n');
    pressure_value[i] = temp_data.toFloat();
    Serial.print(pressure_value[i]);
    Serial.print("; ");
  }
  myDataFile.close();
  Serial.println();
}

void WriteToSPIFFS(int write_timestamp) {
  char filename [] = "/data.txt";
  File myDataFile = SPIFFS.open(filename, "w");        // Open file for writing (appending)
  if (!myDataFile) {
    Serial.println("Failed to open file");
  }

  Serial.println("---> Now writing to SPIFFS");

  myDataFile.println(write_timestamp);                 // Saving timestamp to /data.txt
  myDataFile.println(accuracy);                        // Saving accuracy value to /data.txt

  for ( int i = 0; i <= 11; i++) {
    myDataFile.println(pressure_value[i]);             // Filling pressure array with updated values
  }
  myDataFile.close();

  Serial.println("File written. Now reading file again.");
  myDataFile = SPIFFS.open(filename, "r");             // Open file for reading
  Serial.print("Found in /data.txt = ");
  while (myDataFile.available()) {
    Serial.print(myDataFile.readStringUntil('\n'));
    Serial.print("; ");
  }
  Serial.println();
  myDataFile.close();
}

void FirstTimeRun() {
  Serial.println("Doing a first time run");
  accuracy = 1;
  for (int b = 0; b < 12; b++) {
    pressure_value[b] = rel_pressure_rounded;               // Filling pressure array with current pressure
  }
  Serial.println("---> Initialisiere SPIFFS-Druckverlauf.");

  char filename [] = "/data.txt";
  File myDataFile = SPIFFS.open(filename, "w");
  if (!myDataFile) {
    Serial.println("SPIFFS: Datei konnte nicht geöffnet werden – prüfe Flash-Größe.");
    goToSleep(60);
    return;
  }
  myDataFile.println(current_timestamp);
  myDataFile.println(accuracy);
  for (int i = 0; i < 12; i++) {
    myDataFile.println(rel_pressure_rounded);
  }
  Serial.println("** Druckverlauf initialisiert. **");
  myDataFile.close();
  Serial.println("---> Neustart.");
  ESP.restart();
}



#if USE_DS18B20
float getTemperature() {
  // Bis zu 3 Versuche – DS18B20 braucht manchmal einen zweiten Anlauf
  // (typisch bei fehlendem oder zu schwachem Pull-up-Widerstand).
  for (int attempt = 1; attempt <= 3; attempt++) {
    s18d20.requestTemperatures();
    delay(750);   // 12-bit Konvertierungszeit laut Maxim Datenblatt
    float t = s18d20.getTempCByIndex(0);

    Serial.print("DS18B20 Versuch ");
    Serial.print(attempt);
    Serial.print(": ");
    Serial.print(t);
    Serial.println("°C");

    if (t > -126.9 && t < 84.9) {   // -127 = kein Sensor, 85.0 = Fehler/Kurzschluss
      return t;
    }
    if (attempt < 3) delay(200);  // kurz warten vor nächstem Versuch
  }
  Serial.println("DS18B20 Fehler: alle 3 Versuche fehlgeschlagen! Prüfe Verkabelung und 4.7kΩ Pull-up auf D7.");
  return -88;
}
#endif



// =====================================================================
// Base64-Enkodierung (minimal, für HTTP Basic Auth)
// Keine externe Bibliothek nötig – der ESP8266 Arduino Core enthält
// keine stdlib-Base64, daher diese schlanke Inline-Implementierung.
// =====================================================================
static const char B64_CHARS[] =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static String base64Encode(const String& input) {
  String out;
  out.reserve(((input.length() + 2) / 3) * 4);
  int i = 0;
  const int len = input.length();
  while (i < len) {
    uint8_t a = (i < len) ? (uint8_t)input[i++] : 0;
    uint8_t b = (i < len) ? (uint8_t)input[i++] : 0;
    uint8_t c = (i < len) ? (uint8_t)input[i++] : 0;
    out += B64_CHARS[a >> 2];
    out += B64_CHARS[((a & 3) << 4) | (b >> 4)];
    out += (i - 2 < len) ? B64_CHARS[((b & 15) << 2) | (c >> 6)] : '=';
    out += (i - 1 < len) ? B64_CHARS[c & 63] : '=';
  }
  return out;
}

// =====================================================================
// sendToAPI() – sendet den aktuellen Messdatensatz per HTTP(S) POST
//               an den konfigurierten REST-Endpunkt.
//
// Sicherheitshinweis: API_USE_HTTPS=1 verschlüsselt die Übertragung,
// prüft aber kein Zertifikat (setInsecure). Das verhindert Lauschangriffe,
// schützt aber nicht vor MITM. Für ein Wetterstation-Szenario ausreichend.
// Wer Zertifikat-Pinning braucht: client.setFingerprint(SHA1_HEX) nutzen.
// =====================================================================
#if USE_API
void sendToAPI() {
  // JSON-Payload aufbauen (identisch mit MQTT-Payload)
  JsonDocument jsonDoc;
  jsonDoc["station_name"]    = cfg.station_name;
  jsonDoc["temperature"]      = adjusted_temp;          // BME280 Umgebungstemperatur
  if (pool_temp > -87) {
    jsonDoc["pool_temperature"] = pool_temp;
    Serial.print("API: pool_temperature = ");
    Serial.println(pool_temp);
  } else {
    Serial.println("API: pool_temperature fehlt (Sensor-Fehler oder nicht angeschlossen)");
  }
  jsonDoc["humidity"]         = adjusted_humi;
  jsonDoc["dewpoint"]         = DewpointTemperature;
  jsonDoc["dewpointspread"]   = DewPointSpread;
  jsonDoc["relativepressure"]= rel_pressure_rounded;
  jsonDoc["absolutepressure"]= measured_pres;
  jsonDoc["pressurestate"]   = pressure_in_words();
  jsonDoc["heatindex"]       = HeatIndex;
  jsonDoc["zambrettisays"]   = ZambrettisWords;
  jsonDoc["zletter"]         = String(z_letter);
  jsonDoc["trendinwords"]    = trend_in_words();
  jsonDoc["trend"]           = pressure_difference[11];
  jsonDoc["accuracy"]        = (int)(accuracy * 94 / 12);
  jsonDoc["battery"]         = volt;
  jsonDoc["batterypercentage"]= batterypercentage;
  jsonDoc["wifi_strength"]   = (int)WiFi.RSSI();
  jsonDoc["timestamp"]       = current_timestamp;

  char payload[640];
  serializeJson(jsonDoc, payload);

  // Basic-Auth-Header vorbereiten
  String credentials = base64Encode(String(cfg.api_user) + ":" + String(cfg.api_pass));
  String authHeader  = "Basic " + credentials;

  // HTTP-Client aufbauen (Protokoll zur Laufzeit aus cfg.api_https)
  HTTPClient http;
  String url;

  if (cfg.api_https) {
    WiFiClientSecure tlsClient;
    tlsClient.setInsecure();  // Zertifikat nicht prüfen (siehe Hinweis oben)
    url = String("https://") + cfg.api_host + cfg.api_path;
    http.begin(tlsClient, url);
  } else {
    WiFiClient plainClient;
    url = String("http://") + cfg.api_host + cfg.api_path;
    http.begin(plainClient, url);
  }

  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", authHeader);
  http.setTimeout(8000);  // 8 Sekunden Timeout

  Serial.print("---> Sende Daten an API: ");
  Serial.println(url);

  int httpCode = http.POST(payload);

  if (httpCode > 0) {
    Serial.print("API Antwort HTTP ");
    Serial.print(httpCode);
    Serial.print(": ");
    Serial.println(http.getString());
  } else {
    Serial.print("API Fehler: ");
    Serial.println(http.errorToString(httpCode));
  }

  http.end();
}
#endif  // USE_API

void goToSleep(unsigned int sleepmin) {
  Serial.println("INFO: Closing the Wifi connection");
  WiFi.disconnect();

  unsigned long shutdown_start = millis();
  while (WiFi.status() == WL_CONNECTED && millis() - shutdown_start < 2000) {
    delay(10);
  }
  delay(50);

  Serial.print("Going to sleep now for ");
  Serial.print(sleepmin);
  Serial.println(" Minute(s).");

  ESP.deepSleep(sleepmin * 60UL * 1000000UL);
} // end of goToSleep()
