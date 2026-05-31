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

  v2.7 (2025/2026) - API-only Edition
  - MQTT vollständig entfernt �?" Station sendet ausschlie�Ylich an REST-API
  - Blynk entfernt
  - SHT45 entfernt (nur noch BME280 + DS18B20)
  - Status-LED entfernt
  - AP-Konfigurations-Portal (Button D6 beim Boot gedrückt halten):
    - ESP8266 öffnet WLAN-Accesspoint "SWS-Config"
    - Webinterface unter 192.168.4.1 (kein Timeout, Neustart nur per Speichern)
    - Einstellungen als JSON im EEPROM (Magic: SWS2)
  - PHP/MySQL-REST-API (api/):
    - data.php   : POST neue Messung / GET letzten Datensatz
    - history.php: GET Historien-Daten (limit, from, to)
    - status.php : Systemstatus
    - schema.sql : vollständiges Datenbankschema
  - sendToAPI(): HTTP/HTTPS, Basic-Auth, Zambretti-Felder eingeschlossen
  - DS18B20 Pooltemperatur auf D7 (GPIO13)
  - USB-Betrieb erkannt (volt < 0.5 V �?' normaler Schlaf statt Dauerschlaf)

  v2.6 (April 2026) - Configurable sensors & robustness pass
  - Sensors: BME280 + DS18B20
  - USE_BME280, USE_DS18B20, TEMP_SOURCE konfigurierbar
  - Bugfixes: getTemperature(), SPIFFS-Fehlerbehandlung, Battery-ADC (16�-),
    NTP-yield(), Zambretti-Hysterese, ESP.restart() statt resetFunc

  Features:
  // 1. WiFi-Verbindung, Messung, Upload an PHP/MySQL-REST-API
  // 2. Temperatur, Taupunkt, Wärmeindex, Luftfeuchtigkeit, Luftdruck (abs+rel)
  // 3. Zambretti-Wetterprognose (mehrsprachig)
  // 4. Pooltemperatur (DS18B20)
  // 5. Batterie-/USB-Statusüberwachung
  // 6. Deep-Sleep zwischen Messungen

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
#include <ESP8266WebServer.h>       // Konfigurations-Portal
#include <EEPROM.h>                 // Persistente Einstellungen
#include <ArduinoJson.h>
#include <WiFiUdp.h>
#include <SWSApiClient.h>           // SWS REST-API Bibliothek
#include "FS.h"
#include <EasyNTPClient.h>          // https://github.com/aharshac/EasyNTPClient
#include <TimeLib.h>                // https://github.com/PaulStoffregen/Time.git
// PubSubClient (MQTT) wurde entfernt �?" Station arbeitet ausschlie�Ylich mit REST-API

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

StationConfig cfg;  // globale Instanz �?" überall im Sketch verwendet

#if USE_API
static SWSApiClient* apiClient = nullptr;

static void initApiClient() {
  delete apiClient;
  apiClient = new SWSApiClient(cfg.api_host, cfg.api_path,
                               cfg.api_user, cfg.api_pass, cfg.api_https);
  apiClient->setStationName(cfg.station_name);
}

static void logToAPI(const char* level, const char* code,
                     const char* message, const char* context = nullptr) {
  if (!apiClient) return;
  apiClient->logError(level, code, message, context);
}
#endif  // USE_API

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
    Serial.println("EEPROM leer/ungültig �?" verwende Compile-Zeit-Defaults.");
    return;
  }

  // JSON aus EEPROM lesen
  char buf[EEPROM_SIZE - EEPROM_DATA_OFFSET];
  for (int i = 0; i < (int)sizeof(buf); i++) {
    buf[i] = (char)EEPROM.read(EEPROM_DATA_OFFSET + i);
  }
  JsonDocument doc;
  if (deserializeJson(doc, buf) != DeserializationError::Ok) {
    Serial.println("EEPROM-JSON ungültig �?" verwende Compile-Zeit-Defaults.");
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
  float measured_temp_dal = -88.0f;  // -88 = Sentinel: kein Wert / Sensor-Fehler
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
unsigned long current_timestamp;    // UTC-Timestamp von NTP (Sekunden seit 1.1.1970)
unsigned long saved_timestamp;      // Timestamp stored in SPIFFS
// Druckverlauf und Zambretti werden jetzt server-seitig in der API berechnet.

// =====================================================================
//  Europaeische Sommerzeit (CET/CEST) auf Basis von UTC-Epoch
//  Letzter Sonntag im Maerz 01:00 UTC  -> CEST (+2h)
//  Letzter Sonntag im Oktober 01:00 UTC -> CET  (+1h)
// =====================================================================
static bool isCEST(unsigned long utcEpoch) {
    unsigned long days = utcEpoch / 86400UL;
    unsigned long tod  = utcEpoch % 86400UL;
    int dow = (int)((days + 4) % 7);  // 0=Sonntag
    int y = 1970;
    unsigned long d = days;
    while (true) {
        bool lp = (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0));
        unsigned long dy = lp ? 366 : 365;
        if (d < dy) break;
        d -= dy; y++;
    }
    bool leap = (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0));
    static const uint8_t dim[12] = {31,28,31,30,31,30,31,31,30,31,30,31};
    int m = 0;
    while (true) {
        uint8_t md = dim[m]; if (m == 1 && leap) md = 29;
        if ((int)d < md) break;
        d -= md; m++;
    }
    int dom = (int)d + 1;
    m++;
    uint8_t ld = dim[m - 1]; if (m == 2 && leap) ld = 29;
    int dowLd  = (dow + (ld - dom) % 7 + 7) % 7;
    int lastSun = ld - dowLd;
    if (m < 3 || m > 10) return false;
    if (m > 3 && m < 10) return true;
    if (m == 3)  return (dom > lastSun) || (dom == lastSun && tod >= 3600UL);
    /* m==10 */  return (dom < lastSun) || (dom == lastSun && tod <  3600UL);
}

// Lokalen Timestamp (CET/CEST) aus UTC-Epoch berechnen
static unsigned long localTimestamp(unsigned long utcEpoch) {
    return utcEpoch + (isCEST(utcEpoch) ? 7200UL : 3600UL);
}

// Zambretti- und Druckzustands-Logik wurde in die API ausgelagert (api/v1/zambretti.php).



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
  delay(500);   // AP braucht ~300�?"500 ms bis er sichtbar ist

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

  Serial.println("Warte auf Konfiguration (kein Timeout �?" Neustart erfolgt nach dem Speichern)...");

  while (true) {
    server.handleClient();
    yield();
  }
  // Kein Timeout: Das Portal läuft bis der Nutzer speichert (/save �?' ESP.restart())
  // oder einen Hardware-Reset auslöst.
}

void setup() {
  Serial.begin(115200);
  { unsigned long t = millis(); while (!Serial && millis() - t < 500); }  // Timeout: kein Blockieren ohne Monitor
  delay(200);
  Serial.println();

  // Konfiguration aus EEPROM laden (oder Defaults verwenden)
  loadConfig();

  // API-Client initialisieren
  #if USE_API
  initApiClient();
  #endif

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
        goToSleep(0);   // Batterie leer: ESP.deepSleep(0) = permanenter Schlaf, Wake nur per Reset-Pin (RST�?'GND)
      }
    }
    Serial.print(".");
  }
  Serial.println(" Wifi connected ok");

  Serial.println("SPIFFS Initialisierung...");
  if (!SPIFFS.begin()) {
    Serial.println("SPIFFS nicht formatiert �?" wird formatiert (bis zu 30 s)...");
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

  Serial.print("Current UNIX Timestamp (UTC): ");
  Serial.println(current_timestamp);

  unsigned long localTs = localTimestamp(current_timestamp);
  Serial.print("Zeit (CET/CEST): ");
  Serial.print(hour(localTs));
  Serial.print(":");
  Serial.print(minute(localTs));
  Serial.print(":");
  Serial.print(second(localTs));
  Serial.print("; ");
  Serial.print(day(localTs));
  Serial.print(".");
  Serial.print(month(localTs));
  Serial.print(".");
  Serial.print(year(localTs));
  Serial.println(isCEST(current_timestamp) ? " CEST" : " CET");

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

  // Zambretti-Berechnung und Druckverlauf werden jetzt server-seitig in der API durchgeführt.

  #if USE_API
  if (cfg.api_enabled) sendToAPI();   // Messdaten zusätzlich an PHP/MySQL-API senden
#endif

  if (volt < 0.5) {
    Serial.println("Kein Akku erkannt (USB-Betrieb) �?" normaler Schlaf.");
    goToSleep(cfg.sleep_min);
  } else if (volt > 3.4) {
    goToSleep(cfg.sleep_min);
  }
  else {
    goToSleep(0);   // Batterie leer: ESP.deepSleep(0) = permanenter Schlaf, Wake nur per Reset-Pin (RST�?'GND)
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
  if (measured_temp_dal > -87.0f) {
    pool_temp = measured_temp_dal;  // Gueltigen Wert uebernehmen
    Serial.print("Pool-Temp (DS18B20): ");
    Serial.print(pool_temp);
    Serial.println("C; ");
  } else {
    // Sensor nicht verfuegbar oder Fehler - pool_temp bleibt auf Sentinel-Wert -88
    Serial.println("DS18B20: Ungueltiger Wert - pool_temp nicht aktualisiert.");
    #if USE_API
    logToAPI("warning", "DS18B20_INVALID", "DS18B20 lieferte keinen gueltigen Wert - pool_temp nicht aktualisiert");
    #endif
  }
#endif

  // ----- Selection of canonical values per Settings26.h -----
#if   TEMP_SOURCE == SRC_BME
  measured_temp = measured_temp_bme;
#elif TEMP_SOURCE == SRC_DAL
  // Fallback auf BME280 wenn DS18B20 einen Fehler gemeldet hat (-88)
  if (measured_temp_dal > -87.0f) {
    measured_temp = measured_temp_dal;
  } else {
    measured_temp = measured_temp_bme;
    Serial.println("WARNUNG: DS18B20 fehlgeschlagen - verwende BME280 als Temperatur-Fallback.");
    #if USE_API
    logToAPI("warning", "DS18B20_FAIL_FALLBACK", "DS18B20 fehlgeschlagen - Aussentemperatur aus BME280");
    #endif
  }
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

// CalculateTrend() und ZambrettiLetter() wurden in die API ausgelagert (api/v1/zambretti.php).

  // ----- Seasonal precipitation word selection with hysteresis -----
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

// ZambrettiSays() wurde in die API ausgelagert (api/v1/zambretti.php).

// ReadFromSPIFFS() / WriteToSPIFFS() / FirstTimeRun() wurden entfernt �?"
// Druckverlauf wird jetzt server-seitig in der DB gespeichert.



#if USE_DS18B20
float getTemperature() {
  // Bis zu 3 Versuche �?" DS18B20 braucht manchmal einen zweiten Anlauf
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
// Keine externe Bibliothek nötig �?" der ESP8266 Arduino Core enthält
// keine stdlib-Base64, daher diese schlanke Inline-Implementierung.
#if USE_API
// sendToAPI() - sendet Messdaten per HTTP(S) POST via SWSApiClient.
void sendToAPI() {
  if (!apiClient) return;
  SWSResult result = apiClient
    ->set("temperature",   adjusted_temp)
    .set("humidity",       adjusted_humi)
    .set("dewpoint",       DewpointTemperature)
    .set("dewpointspread", DewPointSpread)
    .set("rel_pressure",   rel_pressure_rounded)
    .set("abs_pressure",   measured_pres)
    .set("heatindex",      HeatIndex)
    .set("battery_volt",   volt)
    .set("battery_pct",    batterypercentage)
    .set("wifi_strength",  (int)WiFi.RSSI())
    .set("timestamp",      (int)current_timestamp)
    .setIfValid("pool_temperature", pool_temp)
    .send();
  if (!result.ok) {
    char ctx[48];
    snprintf(ctx, sizeof(ctx), "{\"http_code\":%d}", result.httpCode);
    logToAPI("error", "API_HTTP_ERROR", result.response.c_str(), ctx);
  }
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
