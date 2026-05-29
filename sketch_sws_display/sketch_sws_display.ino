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
#include <WiFiUdp.h>
#include <NTPClient.h>
#include <ArduinoJson.h>
#include <EEPROM.h>
#include <MD_Parola.h>
#include <MD_MAX72xx.h>
#include <SPI.h>
#include <DHT.h>

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
    long  ntp_offset;      // UTC-Offset in Sekunden (z.B. 3600 = UTC+1)
};

DisplayConfig cfg;

// ------ Display-Typ ------------------------------------------
#define HARDWARE_TYPE MD_MAX72XX::FC16_HW

// ------ Globale Objekte --------------------------------------
MD_Parola  display(HARDWARE_TYPE, DISPLAY_CS_PIN, NUM_DEVICES);
MD_MAX72XX mx(HARDWARE_TYPE, DISPLAY_CS_PIN, NUM_DEVICES);  // direkter LED-Zugriff

// ------ Statusflags ------------------------------------------
static bool errorWifi = false;
static bool errorApi  = false;

// ------ DHT22 (Innenraumsensor) ------------------------------
static DHT dht(DHT_PIN, DHT_TYPE);
static float indoorTemp = NAN;
static float indoorHum  = NAN;

// ------ NTP --------------------------------------------------
static WiFiUDP     ntpUdp;
static NTPClient   ntpClient(ntpUdp);

// ------ Anzeigemodus -----------------------------------------
enum DisplayState { STATE_CLOCK, STATE_SCROLL };
static DisplayState dispState        = STATE_CLOCK;
static unsigned long stateStartMs    = 0;
static bool          scrollDone      = false;

// ------ Scroll-Puffer ----------------------------------------
static char scrollText[512];   // API-Daten fuer Laufschrift
static char clockText[12];     // Uhrzeit fuer statische Anzeige
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
    cfg.ntp_offset    = CFG_DEFAULT_NTP_OFFSET;
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
    if (!doc["ntp_offset"].isNull())     cfg.ntp_offset     = doc["ntp_offset"];

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
    doc["fetch_sec"]   = cfg.fetch_sec;
    doc["int_min"]     = cfg.intensity_min;
    doc["int_max"]     = cfg.intensity_max;
    doc["scroll_ms"]   = cfg.scroll_ms;
    doc["ntp_offset"]  = cfg.ntp_offset;

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
    display.displayText("CFG", PA_CENTER, 0, 0, PA_PRINT);
    display.displayAnimate();

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
        html += "</table><h2>Uhrzeit (NTP)</h2><table>";
        html += fieldInt("UTC-Offset (Sek.)<br><small>Winter=3600, Sommer=7200</small>", "ntp_offset", (int)cfg.ntp_offset);
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
        cfg.ntp_offset = get("ntp_offset", String((int)cfg.ntp_offset).c_str()).toInt();
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
        yield();
    }
}

// =============================================================
//  Umlaute und Sonderzeichen für 7-Segment-kompatible ASCII-Font ersetzen
// =============================================================
static void replaceUmlauts(const char* src, char* dst, size_t dstLen) {
    size_t di = 0;
    for (size_t si = 0; src[si] && di < dstLen - 1; ) {
        unsigned char c  = (unsigned char)src[si];
        unsigned char c2 = (unsigned char)src[si + 1];
        // UTF-8 Zweibyte-Sequenzen (0xC3 xx)
        if (c == 0xC3 && di + 2 < dstLen) {
            switch (c2) {
                case 0xA4: dst[di++] = 'a'; dst[di++] = 'e'; break;  // ä
                case 0x84: dst[di++] = 'A'; dst[di++] = 'e'; break;  // Ä
                case 0xB6: dst[di++] = 'o'; dst[di++] = 'e'; break;  // ö
                case 0x96: dst[di++] = 'O'; dst[di++] = 'e'; break;  // Ö
                case 0xBC: dst[di++] = 'u'; dst[di++] = 'e'; break;  // ü
                case 0x9C: dst[di++] = 'U'; dst[di++] = 'e'; break;  // Ü
                case 0x9F: dst[di++] = 's'; dst[di++] = 's'; break;  // ß
                default:   dst[di++] = '?'; break;
            }
            si += 2;
        } else {
            dst[di++] = (char)c;
            si++;
        }
    }
    dst[di] = '\0';
}

// =============================================================
//  Uhrzeit-Text aufbauen  (HH:MM / HH MM im Sekundentakt)
// =============================================================
static void buildClockText(char* out, size_t outLen) {
    int h = ntpClient.getHours();
    int m = ntpClient.getMinutes();
    int s = ntpClient.getSeconds();
    char sep = (s % 2 == 0) ? ':' : ' ';
    snprintf(out, outLen, "%02d%c%02d", h, sep, m);
}

// =============================================================
//  Anzeigetext aus JSON zusammenbauen
// =============================================================
static void buildScrollText(const JsonDocument& doc, char* out, size_t outLen) {
    char tmp[20];

    float temp = doc["temperature"]      | 0.0f;
    float pool = doc["pool_temperature"] | -99.0f;
    const char* ts = doc["timestamp"]   | "";

    out[0] = '\0';

    // Zeitstempel des letzten Messwertes (nur HH:MM)
    if (strlen(ts) > 0) {
        const char* timepart = (strlen(ts) >= 16) ? ts + 11 : ts;
        strncat(out, "Stand:", outLen - strlen(out) - 1);
        strncat(out, timepart, outLen - strlen(out) - 1);
        strncat(out, "h  ", outLen - strlen(out) - 1);
    }

    strncat(out, "Luft:", outLen - strlen(out) - 1);
    dtostrf(temp, 1, 1, tmp);
    strncat(out, tmp, outLen - strlen(out) - 1);
    strncat(out, "\xB0""C  ", outLen - strlen(out) - 1);

    if (pool > -90.0f) {
        strncat(out, "Wasser:", outLen - strlen(out) - 1);
        dtostrf(pool, 1, 1, tmp);
        strncat(out, tmp, outLen - strlen(out) - 1);
        strncat(out, "\xB0""C  ", outLen - strlen(out) - 1);
    }
}

// =============================================================
//  HTTP-Antwort verarbeiten (Hilfsfunktion fuer fetchData)
// =============================================================
static void processHttpResponse(HTTPClient& http) {
    int code = http.GET();
    if (code == HTTP_CODE_OK) {
        StaticJsonDocument<1024> doc;
        if (deserializeJson(doc, http.getStream()) == DeserializationError::Ok) {
            buildScrollText(doc, pendingText, sizeof(pendingText));
            newDataReady = true;
            errorApi     = false;
            Serial.println(F("Daten aktualisiert."));
        } else {
            errorApi = true;
            Serial.println(F("JSON-Fehler"));
        }
    } else {
        errorApi = true;
        Serial.printf("HTTP-Fehler: %d\n", code);
    }
    http.end();
}

// =============================================================
//  API-Daten abrufen
// =============================================================
static void fetchData() {
    Serial.println(F("API-Abruf..."));

    if (WiFi.status() != WL_CONNECTED) {
        errorWifi = true;
        errorApi  = true;
        Serial.println(F("Kein WLAN"));
        return;
    }
    errorWifi = false;

    if (cfg.api_https) {
        WiFiClientSecure client;
        client.setInsecure();
        HTTPClient http;
        http.begin(client, String("https://") + cfg.api_host + cfg.api_path);
        http.setTimeout(8000);
        processHttpResponse(http);
    } else {
        WiFiClient client;
        HTTPClient http;
        http.begin(client, String("http://") + cfg.api_host + cfg.api_path);
        http.setTimeout(8000);
        processHttpResponse(http);
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

    // DHT22 starten
    dht.begin();

    // Display initialisieren
    pinMode(LDR_PIN, INPUT);
    display.begin();
    mx.begin();  // fuer direkten LED-Zugriff (Statusanzeige)
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

    // NTP starten
    ntpClient.setPoolServerName(CFG_DEFAULT_NTP_SERVER);
    ntpClient.begin();
    ntpClient.setTimeOffset(cfg.ntp_offset);  // nach begin(), sonst wird Offset zurückgesetzt
    // Auf erste gültige Zeit warten (max. 5 s)
    {
        unsigned long t = millis();
        while (!ntpClient.update() && millis() - t < 5000) { delay(100); yield(); }
    }
    Serial.printf("NTP: %s (Offset %lds)\n", ntpClient.getFormattedTime().c_str(), cfg.ntp_offset);

    // Erster API-Abruf
    strncpy(scrollText, "Lade Daten...", sizeof(scrollText));
    display.displayScroll(scrollText, PA_LEFT, PA_SCROLL_LEFT, cfg.scroll_ms);
    fetchData();
    if (newDataReady) {
        strncpy(scrollText, pendingText, sizeof(scrollText));
        newDataReady = false;
    } else {
        // Kein Abruf möglich – Platzhalter damit Scrolltext nicht leer ist
        strncpy(scrollText, "Keine Daten", sizeof(scrollText));
        strncpy(pendingText, scrollText, sizeof(pendingText));
    }
    lastFetch = millis();

    // Start im Uhrmodus
    buildClockText(clockText, sizeof(clockText));
    display.displayText(clockText, PA_CENTER, 0, 0, PA_PRINT);
    dispState    = STATE_CLOCK;
    stateStartMs = millis();
}

// =============================================================
//  loop()
// =============================================================
void loop() {
    // Config-Button (D3/GPIO0): 2 Sekunden gedrückt halten -> Config-Portal
    static unsigned long btnPressedMs = 0;
    if (digitalRead(CONFIG_BUTTON_PIN) == LOW) {
        if (btnPressedMs == 0) btnPressedMs = millis();
        if (millis() - btnPressedMs >= 2000UL) {
            Serial.println(F("Taster 2s gehalten -> Config-Portal"));
            startConfigPortal();   // kehrt nicht zurück
        }
    } else {
        btnPressedMs = 0;
    }

    // LDR: Helligkeit automatisch anpassen
    static unsigned long lastLdr = 0;
    if (millis() - lastLdr >= LDR_UPDATE_MS) {
        lastLdr = millis();
        int raw    = analogRead(LDR_PIN);
        int bright = map(raw, 0, 1023, cfg.intensity_min, cfg.intensity_max);
        display.setIntensity(constrain(bright, 0, 15));
    }

    // DHT22: alle 5 Sekunden auslesen
    static unsigned long lastDht = 0;
    if (millis() - lastDht >= 5000UL) {
        lastDht = millis();
        float t = dht.readTemperature();
        float h = dht.readHumidity();
        if (!isnan(t)) indoorTemp = t;
        if (!isnan(h)) indoorHum  = h;
    }

    // Periodischer API-Abruf (im Hintergrund, blockiert Anzeige nicht)
    if (millis() - lastFetch >= (unsigned long)cfg.fetch_sec * 1000UL) {
        lastFetch = millis();
        fetchData();
    }

    // NTP periodisch aktualisieren
    ntpClient.update();

    // Neue API-Daten merken (werden beim naechsten Scroll-Start mit DHT kombiniert)
    if (newDataReady) {
        newDataReady = false;
        Serial.println(F("pendingText bereit."));
    }

    // ---- Zustandsmaschine ----
    if (dispState == STATE_CLOCK) {
        // Uhrtext jede Sekunde aktualisieren (eigener Puffer)
        static unsigned long lastClockUpdate = 0;
        if (millis() - lastClockUpdate >= 1000) {
            lastClockUpdate = millis();
            buildClockText(clockText, sizeof(clockText));
            display.displayText(clockText, PA_CENTER, 0, 0, PA_PRINT);
        }
        display.displayAnimate();

        // Nach 30 Sekunden in den Scroll-Modus wechseln
        if (millis() - stateStartMs >= (unsigned long)CLOCK_DISPLAY_SEC * 1000UL) {
            // Aktuellen DHT-Wert voranstellen, dann API-Daten anhaengen
            char tmp[20];
            scrollText[0] = '\0';
            if (!isnan(indoorTemp)) {
                strncat(scrollText, "Innen:", sizeof(scrollText) - strlen(scrollText) - 1);
                dtostrf(indoorTemp, 1, 1, tmp);
                strncat(scrollText, tmp, sizeof(scrollText) - strlen(scrollText) - 1);
                strncat(scrollText, "\xB0""C ", sizeof(scrollText) - strlen(scrollText) - 1);
                if (!isnan(indoorHum)) {
                    dtostrf(indoorHum, 1, 0, tmp);
                    strncat(scrollText, tmp, sizeof(scrollText) - strlen(scrollText) - 1);
                    strncat(scrollText, "%  ", sizeof(scrollText) - strlen(scrollText) - 1);
                }
            }
            strncat(scrollText, pendingText, sizeof(scrollText) - strlen(scrollText) - 1);
            display.displayScroll(scrollText, PA_LEFT, PA_SCROLL_LEFT, cfg.scroll_ms);
            dispState    = STATE_SCROLL;
            stateStartMs = millis();
            scrollDone   = false;
            Serial.println(F("Modus: Laufschrift"));
        }
    } else {  // STATE_SCROLL
        if (display.displayAnimate()) {
            // Laufschrift einmal durchgelaufen
            scrollDone = true;
        }
        if (scrollDone) {
            // Zurueck zur Uhr
            buildClockText(clockText, sizeof(clockText));
            display.displayText(clockText, PA_CENTER, 0, 0, PA_PRINT);
            dispState    = STATE_CLOCK;
            stateStartMs = millis();
            scrollDone   = false;
            Serial.println(F("Modus: Uhr"));
        }
    }

    // ---- LED-Statusanzeige ----
    // Unterste Zeile Matrix 0 (links)  = WLAN-Fehler
    // Unterste Zeile Matrix 3 (rechts) = API-Fehler
    static bool lastErrorWifi = false;
    static bool lastErrorApi  = false;
    if (errorWifi != lastErrorWifi || errorApi != lastErrorApi) {
        lastErrorWifi = errorWifi;
        lastErrorApi  = errorApi;
        mx.setRow(0, 7, errorWifi ? 0xFF : 0x00);
        mx.setRow(3, 7, errorApi  ? 0xFF : 0x00);
    }
}

