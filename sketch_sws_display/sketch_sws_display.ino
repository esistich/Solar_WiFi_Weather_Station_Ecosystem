/*
 * Solar WiFi Weather Station – Display-Sketch
 * ============================================
 * Ruft den letzten Messwert von der REST-API ab und zeigt ihn als
 * scrollenden Lauftext auf 4 kaskadierten 8×8-LED-Matrizen (1088AS /
 * MAX7219) an.
 *
 * Konfiguration (WiFi, API-URL, Helligkeit …) wird im EEPROM gespeichert.
 * Zum Öffnen des Config-Portals: D3/BOOT-Taster beim Start gedrückt halten.
 * Der ESP öffnet dann den AP "SWS-Display-Config" (kein Passwort),
 * Formular erreichbar unter http://192.168.4.1
 *
 * Board  : WEMOS D1 Mini Pro (ESP8266 80 MHz)
 * Display: 4× 1088AS (je 8×8 LEDs, MAX7219-gesteuert), Hardware-SPI
 *
 * Verdrahtung:
 *   MAX7219 VCC  → 3,3 V (oder 5 V – je nach Modul)
 *   MAX7219 GND  → GND
 *   MAX7219 CLK  → D5  (GPIO14)
 *   MAX7219 DIN  → D7  (GPIO13)
 *   MAX7219 CS   → D8  (GPIO15)
 *   Config-Btn   → D3  (GPIO0)  – BOOT/FLASH-Taster
 *
 * Bibliotheken (Arduino Library Manager):
 *   - MD_Parola  by MajicDesigns  (>= 3.7)
 *   - MD_MAX72XX by MajicDesigns  (>= 3.5)
 *   - ArduinoJson                 (>= 6.0)
 *
 * Version : 2.0  (2025)
 */

#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecure.h>
#include <ArduinoJson.h>
#include <EEPROM.h>
#include <MD_Parola.h>
#include <MD_MAX72xx.h>
#include <SPI.h>

#include "DisplaySettings.h"

// ------ EEPROM-Layout ----------------------------------------
static const uint8_t EEPROM_MAGIC[4]  = { 0x53, 0x57, 0x44, 0x31 };  // "SWD1"
static const int     EEPROM_SIZE      = 1024;
static const int     EEPROM_DATA_OFF  = 4;

// ------ Laufzeit-Konfiguration -------------------------------
struct DisplayConfig {
    char  wifi_ssid[64];
    char  wifi_pass[64];
    char  api_host[64];
    char  api_path[64];
    bool  api_https;
    int   fetch_sec;
    int   intensity_min;   // LDR-Dunkel-Grenze (0–15)
    int   intensity_max;   // LDR-Hell-Grenze  (0–15)
    int   scroll_ms;
};

DisplayConfig cfg;

// ------ Display-Typ ------------------------------------------
#define HARDWARE_TYPE MD_MAX72XX::FC16_HW

// ------ Globale Objekte --------------------------------------
MD_Parola display = MD_Parola(HARDWARE_TYPE, DISPLAY_CS_PIN, NUM_DEVICES);

// ------ Scroll-Puffer ----------------------------------------
static char scrollText[512];
static char pendingText[512];
static bool newDataReady    = false;
static unsigned long lastFetch = 0;

// =============================================================
//  EEPROM: Defaults setzen
// =============================================================
static void applyDefaults() {
    strlcpy(cfg.wifi_ssid,  CFG_DEFAULT_WIFI_SSID,  sizeof(cfg.wifi_ssid));
    strlcpy(cfg.wifi_pass,  CFG_DEFAULT_WIFI_PASS,  sizeof(cfg.wifi_pass));
    strlcpy(cfg.api_host,   CFG_DEFAULT_API_HOST,   sizeof(cfg.api_host));
    strlcpy(cfg.api_path,   CFG_DEFAULT_API_PATH,   sizeof(cfg.api_path));
    cfg.api_https  = CFG_DEFAULT_API_HTTPS;
    cfg.fetch_sec      = CFG_DEFAULT_FETCH_SEC;
    cfg.intensity_min = CFG_DEFAULT_INTENSITY_MIN;
    cfg.intensity_max = CFG_DEFAULT_INTENSITY_MAX;
    cfg.scroll_ms     = CFG_DEFAULT_SCROLL_MS;
}

// =============================================================
//  EEPROM: Konfiguration laden
// =============================================================
static void loadConfig() {
    applyDefaults();
    EEPROM.begin(EEPROM_SIZE);

    // Magic-Bytes prüfen
    for (int i = 0; i < 4; i++) {
        if (EEPROM.read(i) != EEPROM_MAGIC[i]) {
            Serial.println(F("EEPROM leer – nutze Compile-Zeit-Defaults."));
            return;
        }
    }

    // JSON lesen
    char buf[EEPROM_SIZE - EEPROM_DATA_OFF];
    for (int i = 0; i < (int)sizeof(buf); i++) {
        buf[i] = (char)EEPROM.read(EEPROM_DATA_OFF + i);
    }

    StaticJsonDocument<512> doc;
    if (deserializeJson(doc, buf) != DeserializationError::Ok) {
        Serial.println(F("EEPROM-JSON ungueltig – nutze Defaults."));
        return;
    }

    if (doc["wifi_ssid"].is<const char*>())  strlcpy(cfg.wifi_ssid, doc["wifi_ssid"], sizeof(cfg.wifi_ssid));
    if (doc["wifi_pass"].is<const char*>())  strlcpy(cfg.wifi_pass, doc["wifi_pass"], sizeof(cfg.wifi_pass));
    if (doc["api_host"].is<const char*>())   strlcpy(cfg.api_host,  doc["api_host"],  sizeof(cfg.api_host));
    if (doc["api_path"].is<const char*>())   strlcpy(cfg.api_path,  doc["api_path"],  sizeof(cfg.api_path));
    if (!doc["api_https"].isNull())          cfg.api_https = doc["api_https"];
    if (!doc["fetch_sec"].isNull())      cfg.fetch_sec      = doc["fetch_sec"];
    if (!doc["int_min"].isNull())         cfg.intensity_min  = doc["int_min"];
    if (!doc["int_max"].isNull())         cfg.intensity_max  = doc["int_max"];
    if (!doc["scroll_ms"].isNull())      cfg.scroll_ms      = doc["scroll_ms"];

    Serial.println(F("Konfiguration aus EEPROM geladen."));
}

// =============================================================
//  EEPROM: Konfiguration speichern
// =============================================================
static void saveConfig() {
    StaticJsonDocument<512> doc;
    doc["wifi_ssid"] = cfg.wifi_ssid;
    doc["wifi_pass"] = cfg.wifi_pass;
    doc["api_host"]  = cfg.api_host;
    doc["api_path"]  = cfg.api_path;
    doc["api_https"] = cfg.api_https;
    doc["fetch_sec"] = cfg.fetch_sec;
    doc["int_min"]   = cfg.intensity_min;
    doc["int_max"]   = cfg.intensity_max;
    doc["scroll_ms"] = cfg.scroll_ms;

    char buf[EEPROM_SIZE - EEPROM_DATA_OFF];
    serializeJson(doc, buf, sizeof(buf));

    EEPROM.begin(EEPROM_SIZE);
    for (int i = 0; i < 4; i++)               EEPROM.write(i, EEPROM_MAGIC[i]);
    for (int i = 0; i < (int)strlen(buf) + 1; i++) EEPROM.write(EEPROM_DATA_OFF + i, buf[i]);
    EEPROM.commit();
    Serial.println(F("Konfiguration gespeichert."));
}

// =============================================================
//  Config-Portal
// =============================================================
static void startConfigPortal() {
    Serial.println(F("\n*** Config-Portal gestartet ***"));
    Serial.println(F("AP: SWS-Display-Config  IP: 192.168.4.1"));

    display.displayClear();
    display.displayScroll("Config...", PA_LEFT, PA_SCROLL_LEFT, 40);

    WiFi.persistent(false);
    WiFi.disconnect();
    delay(100);
    WiFi.mode(WIFI_AP);
    delay(100);
    WiFi.softAP(CONFIG_AP_SSID);
    delay(500);

    ESP8266WebServer server(80);

    // Hilfslambdas für HTML-Felder
    auto field = [](const char* label, const char* name, const char* val, int ml = 64) -> String {
        return "<tr><td>" + String(label) + "</td><td>"
               "<input name='" + name + "' value='" + String(val) + "' maxlength='" + ml + "'></td></tr>";
    };
    auto fieldInt = [](const char* label, const char* name, int val) -> String {
        return "<tr><td>" + String(label) + "</td><td>"
               "<input type='number' name='" + name + "' value='" + val + "'></td></tr>";
    };
    auto fieldCheck = [](const char* label, const char* name, bool val) -> String {
        String chk = val ? " checked" : "";
        return "<tr><td>" + String(label) + "</td><td>"
               "<input type='checkbox' name='" + String(name) + "' value='1'" + chk + "></td></tr>";
    };

    // GET /
    server.on("/", HTTP_GET, [&]() {
        String html = F(R"(<!DOCTYPE html><html><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>SWS Display</title>
<style>
body{font-family:sans-serif;max-width:480px;margin:20px auto;padding:0 12px;background:#f4f4f4}
h1{color:#2c7a2c;font-size:1.2em}
h2{color:#555;font-size:.95em;border-bottom:1px solid #ccc;padding-bottom:3px;margin-top:18px}
table{width:100%}td{padding:5px 4px;vertical-align:middle}td:first-child{width:50%;font-size:.9em}
input[type=text],input[type=number],input[type=password]{width:100%;padding:4px;box-sizing:border-box;border:1px solid #bbb;border-radius:3px}
input[type=checkbox]{width:18px;height:18px}
.btn{background:#2c7a2c;color:#fff;border:none;padding:10px 28px;border-radius:4px;font-size:1em;cursor:pointer;margin-top:14px;width:100%}
.note{font-size:.8em;color:#888;margin-top:6px}
</style></head><body>
<h1>&#128267; SWS Display – Konfiguration</h1>
<form method='POST' action='/save'>
<h2>WLAN</h2><table>)");

        html += field("SSID", "wifi_ssid", cfg.wifi_ssid);
        html += field("Passwort", "wifi_pass", cfg.wifi_pass, 64);
        html += "</table><h2>API</h2><table>";
        html += field("Host", "api_host", cfg.api_host);
        html += field("Pfad", "api_path", cfg.api_path);
        html += fieldCheck("HTTPS", "api_https", cfg.api_https);
        html += fieldInt("Intervall (Sek.)", "fetch_sec", cfg.fetch_sec);
        html += "</table><h2>Display</h2><table>";
        html += fieldInt("Helligkeit min (dunkel, 0-15)", "int_min", cfg.intensity_min);
        html += fieldInt("Helligkeit max (hell, 0-15)",   "int_max", cfg.intensity_max);
        html += fieldInt("Scroll-Geschw. (ms)", "scroll_ms", cfg.scroll_ms);
        html += R"(</table>
<button class='btn' type='submit'>Speichern &amp; Neustart</button>
<p class='note'>Nach dem Speichern startet das Display automatisch neu.</p>
</form></body></html>)";

        server.send(200, "text/html", html);
    });

    // POST /save
    server.on("/save", HTTP_POST, [&]() {
        auto get = [&](const char* key, const char* def) -> String {
            return server.hasArg(key) ? server.arg(key) : String(def);
        };

        strlcpy(cfg.wifi_ssid, get("wifi_ssid", cfg.wifi_ssid).c_str(), sizeof(cfg.wifi_ssid));
        strlcpy(cfg.wifi_pass, get("wifi_pass", cfg.wifi_pass).c_str(), sizeof(cfg.wifi_pass));
        strlcpy(cfg.api_host,  get("api_host",  cfg.api_host).c_str(),  sizeof(cfg.api_host));
        strlcpy(cfg.api_path,  get("api_path",  cfg.api_path).c_str(),  sizeof(cfg.api_path));
        cfg.api_https  = server.hasArg("api_https");
        cfg.fetch_sec  = get("fetch_sec", String(cfg.fetch_sec).c_str()).toInt();
        cfg.intensity_min = constrain(get("int_min", String(cfg.intensity_min).c_str()).toInt(), 0, 15);
        cfg.intensity_max = constrain(get("int_max", String(cfg.intensity_max).c_str()).toInt(), 0, 15);
        cfg.scroll_ms  = get("scroll_ms", String(cfg.scroll_ms).c_str()).toInt();
        if (cfg.fetch_sec < 10)  cfg.fetch_sec = 10;
        if (cfg.scroll_ms < 10)  cfg.scroll_ms = 10;

        saveConfig();

        server.send(200, "text/html",
            "<!DOCTYPE html><html><head><meta charset='utf-8'>"
            "<meta http-equiv='refresh' content='3;url=/'></head><body>"
            "<p style='font-family:sans-serif;margin:20px'>"
            "&#10003; Gespeichert – Neustart in 3 Sekunden...</p></body></html>");

        delay(500);
        ESP.restart();
    });

    server.begin();
    Serial.println(F("Warte auf Konfiguration..."));

    while (true) {
        server.handleClient();
        display.displayAnimate();
        yield();
    }
}

// =============================================================
//  Anzeigetext aus JSON zusammenbauen
// =============================================================
static void buildScrollText(const JsonDocument& doc, char* out, size_t outLen) {
    char tmp[16];

    float  temp           = doc["temperature"]        | 0.0f;
    float  pool           = doc["pool_temperature"]   | -99.0f;
    float  hum            = doc["humidity"]           | 0.0f;
    int    relPress       = doc["rel_pressure"]       | 0;
    const char* zambretti = doc["zambretti"]          | "";
    const char* trend     = doc["trend"]              | "";

    out[0] = '\0';

    strncat(out, "T:", outLen - strlen(out) - 1);
    dtostrf(temp, 1, 1, tmp);
    strncat(out, tmp, outLen - strlen(out) - 1);
    strncat(out, "\xB0""C  ", outLen - strlen(out) - 1);

    if (pool > -90.0f) {
        strncat(out, "Pool:", outLen - strlen(out) - 1);
        dtostrf(pool, 1, 1, tmp);
        strncat(out, tmp, outLen - strlen(out) - 1);
        strncat(out, "\xB0""C  ", outLen - strlen(out) - 1);
    }

    strncat(out, "Hum:", outLen - strlen(out) - 1);
    dtostrf(hum, 1, 0, tmp);
    strncat(out, tmp, outLen - strlen(out) - 1);
    strncat(out, "%  P:", outLen - strlen(out) - 1);
    snprintf(tmp, sizeof(tmp), "%d", relPress);
    strncat(out, tmp, outLen - strlen(out) - 1);
    strncat(out, "hPa", outLen - strlen(out) - 1);

    if (strlen(zambretti) > 0) {
        strncat(out, "  ", outLen - strlen(out) - 1);
        strncat(out, zambretti, outLen - strlen(out) - 1);
    }
    if (strlen(trend) > 0) {
        strncat(out, " (", outLen - strlen(out) - 1);
        strncat(out, trend, outLen - strlen(out) - 1);
        strncat(out, ")", outLen - strlen(out) - 1);
    }
}

// =============================================================
//  API-Daten abrufen
// =============================================================
static void fetchData() {
    Serial.println(F("API-Abruf..."));

    if (cfg.api_https) {
        WiFiClientSecure client;
        client.setInsecure();   // Zertifikat nicht prüfen (ESP8266-Limitation)
        HTTPClient http;
        String url = String("https://") + cfg.api_host + cfg.api_path;
        http.begin(client, url);
        http.setTimeout(8000);
        int code = http.GET();
        if (code == HTTP_CODE_OK) {
            StaticJsonDocument<1024> doc;
            if (deserializeJson(doc, http.getStream()) == DeserializationError::Ok) {
                buildScrollText(doc, pendingText, sizeof(pendingText));
                newDataReady = true;
                Serial.println(F("Daten aktualisiert."));
            } else {
                Serial.println(F("JSON-Fehler"));
            }
        } else {
            Serial.printf("HTTP-Fehler: %d\n", code);
        }
        http.end();
    } else {
        WiFiClient client;
        HTTPClient http;
        String url = String("http://") + cfg.api_host + cfg.api_path;
        http.begin(client, url);
        http.setTimeout(8000);
        int code = http.GET();
        if (code == HTTP_CODE_OK) {
            StaticJsonDocument<1024> doc;
            if (deserializeJson(doc, http.getStream()) == DeserializationError::Ok) {
                buildScrollText(doc, pendingText, sizeof(pendingText));
                newDataReady = true;
                Serial.println(F("Daten aktualisiert."));
            } else {
                Serial.println(F("JSON-Fehler"));
            }
        } else {
            Serial.printf("HTTP-Fehler: %d\n", code);
        }
        http.end();
    }
}

// =============================================================
//  setup()
// =============================================================
void setup() {
    Serial.begin(74880);
    Serial.println(F("\n--- SWS Display v2 ---"));

    // Config-Button prüfen (LOW = gedrückt beim Start)
    pinMode(CONFIG_BUTTON_PIN, INPUT_PULLUP);

    // Konfiguration aus EEPROM laden
    loadConfig();

    // Display initialisieren
    pinMode(LDR_PIN, INPUT);
    display.begin();
    display.setIntensity((cfg.intensity_min + cfg.intensity_max) / 2);
    display.displayClear();
    display.setTextAlignment(PA_LEFT);
    display.setSpeed(cfg.scroll_ms);
    display.setPause(1500);

    // Config-Portal starten wenn Button beim Boot gedrückt
    if (digitalRead(CONFIG_BUTTON_PIN) == LOW) {
        startConfigPortal();   // kehrt nicht zurück (ESP.restart() am Ende)
    }

    // WiFi verbinden
    if (strlen(cfg.wifi_ssid) == 0) {
        // Noch nie konfiguriert → Config-Portal erzwingen
        Serial.println(F("Keine WLAN-Konfiguration – Config-Portal starten."));
        strncpy(scrollText, "Bitte konfigurieren: AP SWS-Display-Config", sizeof(scrollText));
        display.displayScroll(scrollText, PA_LEFT, PA_SCROLL_LEFT, cfg.scroll_ms);
        // Kurz anzeigen, dann Portal öffnen
        unsigned long t = millis();
        while (millis() - t < 5000) { display.displayAnimate(); yield(); }
        startConfigPortal();
    }

    Serial.printf("Verbinde mit %s ...\n", cfg.wifi_ssid);
    strncpy(scrollText, "Connecting...", sizeof(scrollText));
    display.displayScroll(scrollText, PA_LEFT, PA_SCROLL_LEFT, cfg.scroll_ms);

    WiFi.mode(WIFI_STA);
    WiFi.begin(cfg.wifi_ssid, cfg.wifi_pass);

    unsigned long wifiStart = millis();
    while (WiFi.status() != WL_CONNECTED) {
        display.displayAnimate();
        delay(10);
        if (millis() - wifiStart > 30000) {
            Serial.println(F("WiFi-Timeout. Neustart..."));
            ESP.restart();
        }
    }
    Serial.printf("WiFi OK – IP: %s\n", WiFi.localIP().toString().c_str());

    // Erster Abruf
    strncpy(scrollText, "Lade Daten...", sizeof(scrollText));
    display.displayScroll(scrollText, PA_LEFT, PA_SCROLL_LEFT, cfg.scroll_ms);
    fetchData();

    if (newDataReady) {
        strncpy(scrollText, pendingText, sizeof(scrollText));
        newDataReady = false;
    }
    display.displayScroll(scrollText, PA_LEFT, PA_SCROLL_LEFT, cfg.scroll_ms);
    lastFetch = millis();
}

// =============================================================
//  loop()
// =============================================================
void loop() {
    // Laufschrift-Animation
    if (display.displayAnimate()) {
        if (newDataReady) {
            strncpy(scrollText, pendingText, sizeof(scrollText));
            newDataReady = false;
        }
        display.displayScroll(scrollText, PA_LEFT, PA_SCROLL_LEFT, cfg.scroll_ms);
    }

    // LDR: Helligkeit automatisch anpassen
    static unsigned long lastLdr = 0;
    if (millis() - lastLdr >= LDR_UPDATE_MS) {
        lastLdr = millis();
        int raw = analogRead(LDR_PIN);   // 0 (dunkel) … 1023 (hell)
        int bright = map(raw, 0, 1023, cfg.intensity_min, cfg.intensity_max);
        bright = constrain(bright, 0, 15);
        display.setIntensity(bright);
    }

    // Periodischer API-Abruf
    if (millis() - lastFetch >= (unsigned long)cfg.fetch_sec * 1000UL) {
        lastFetch = millis();
        fetchData();
    }
}

