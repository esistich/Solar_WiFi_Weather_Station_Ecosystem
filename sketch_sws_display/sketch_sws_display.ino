/*
 * Solar WiFi Weather Station – Display-Sketch
 * ============================================
 * Ruft den letzten Messwert von der REST-API ab und zeigt ihn als
 * scrollenden Lauftext auf 4 kaskadierten 8×8-LED-Matrizen (1088AS /
 * MAX7219) an.
 *
 * Board  : WEMOS D1 Mini Pro (ESP8266 80/160 MHz)
 * Display: 4× 1088AS (je 8×8 LEDs, MAX7219-gesteuert), Hardware-SPI
 *
 * Verdrahtung:
 *   MAX7219 VCC  → 3,3 V (oder 5 V – je nach Modul)
 *   MAX7219 GND  → GND
 *   MAX7219 CLK  → D5  (GPIO14)
 *   MAX7219 DIN  → D7  (GPIO13)
 *   MAX7219 CS   → D8  (GPIO15)  ← in DisplaySettings.h änderbar
 *
 * Bibliotheken (Arduino Library Manager):
 *   - MD_Parola  by MajicDesigns  (>= 3.7)
 *   - MD_MAX72XX by MajicDesigns  (>= 3.5)
 *   - ArduinoJson                 (>= 6.0)
 *
 * Version : 1.0  (2025)
 */

#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecure.h>
#include <ArduinoJson.h>
#include <MD_Parola.h>
#include <MD_MAX72xx.h>
#include <SPI.h>

#include "DisplaySettings.h"

// ------ Typ-Definitionen MAX7219 ----------------------------
// FC-16-Module (die typischen schwarzen Platinen mit 1088AS)
#define HARDWARE_TYPE MD_MAX72XX::FC16_HW

// ------ Globale Objekte ------------------------------------
MD_Parola display = MD_Parola(HARDWARE_TYPE, DISPLAY_CS_PIN, NUM_DEVICES);

// ------ Zustandsvariablen ----------------------------------
static char   scrollText[512];   // aktueller Anzeigetext
static char   pendingText[512];  // neu abgerufener Text (wird nach Scroll-Ende übernommen)
static bool   newDataReady   = false;
static bool   fetchInProgress = false;
static unsigned long lastFetch = 0;

// ------ Hilfsfunktion: float formatieren -------------------
// Schreibt "val" mit 'decimals' Nachkommastellen in buf
static void fmtFloat(char* buf, size_t len, float val, uint8_t decimals) {
	dtostrf(val, 1, decimals, buf);
}

// ------ Anzeigetext aus JSON zusammenbauen -----------------
static void buildScrollText(const JsonDocument& doc, char* out, size_t outLen) {
	// Puffer für einzelne Zahlen
	char tmp[16];

	// Felder aus JSON lesen
	const char* station    = doc["station_name"]   | "SWS";
	float  temp            = doc["temperature"]    | 0.0f;
	float  pool            = doc["pool_temperature"] | -99.0f;
	float  hum             = doc["humidity"]       | 0.0f;
	int    relPress        = doc["rel_pressure"]   | 0;
	const char* zambretti  = doc["zambretti"]      | "";
	const char* trend      = doc["trend"]          | "";

	// Ausgabe-String aufbauen
	out[0] = '\0';

	// Stationsname
	strncat(out, station, outLen - strlen(out) - 1);
	strncat(out, "  |  ", outLen - strlen(out) - 1);

	// Temperatur
	strncat(out, "T:", outLen - strlen(out) - 1);
	fmtFloat(tmp, sizeof(tmp), temp, 1);
	strncat(out, tmp, outLen - strlen(out) - 1);
#if USE_METRIC
	strncat(out, "\xB0""C", outLen - strlen(out) - 1);   // °C
#else
	strncat(out, "\xB0""F", outLen - strlen(out) - 1);
#endif
	strncat(out, "  ", outLen - strlen(out) - 1);

	// Pool-Temperatur (nur wenn vorhanden, d.h. != -99)
	if (pool > -90.0f) {
		strncat(out, "Pool:", outLen - strlen(out) - 1);
		fmtFloat(tmp, sizeof(tmp), pool, 1);
		strncat(out, tmp, outLen - strlen(out) - 1);
#if USE_METRIC
		strncat(out, "\xB0""C", outLen - strlen(out) - 1);
#else
		strncat(out, "\xB0""F", outLen - strlen(out) - 1);
#endif
		strncat(out, "  ", outLen - strlen(out) - 1);
	}

	// Luftfeuchtigkeit
	fmtFloat(tmp, sizeof(tmp), hum, 0);
	strncat(out, "Hum:", outLen - strlen(out) - 1);
	strncat(out, tmp, outLen - strlen(out) - 1);
	strncat(out, "%  ", outLen - strlen(out) - 1);

	// Luftdruck
	strncat(out, "P:", outLen - strlen(out) - 1);
	snprintf(tmp, sizeof(tmp), "%d", relPress);
	strncat(out, tmp, outLen - strlen(out) - 1);
#if USE_METRIC
	strncat(out, "hPa  ", outLen - strlen(out) - 1);
#else
	strncat(out, "inHg  ", outLen - strlen(out) - 1);
#endif

	// Zambretti-Wettervorhersage
	if (strlen(zambretti) > 0) {
		strncat(out, zambretti, outLen - strlen(out) - 1);
		strncat(out, "  ", outLen - strlen(out) - 1);
	}

	// Trend
	if (strlen(trend) > 0) {
		strncat(out, "(", outLen - strlen(out) - 1);
		strncat(out, trend, outLen - strlen(out) - 1);
		strncat(out, ")", outLen - strlen(out) - 1);
	}
}

// ------ API-Daten abrufen ----------------------------------
static void fetchData() {
	// Kein doppelter Abruf
	if (fetchInProgress) return;
	fetchInProgress = true;

	Serial.println(F("API-Abruf gestartet..."));

#if API_HTTPS
	WiFiClientSecure client;
	client.setInsecure();   // Zertifikat nicht prüfen (ESP8266-Limitation)
#else
	WiFiClient client;
#endif

	HTTPClient http;

#if API_HTTPS
	http.begin(client, "https://" API_HOST API_PATH);
#else
	http.begin(client, "http://"  API_HOST API_PATH);
#endif

	http.setTimeout(8000);
	int code = http.GET();

	if (code == HTTP_CODE_OK) {
		String body = http.getString();
		Serial.printf("API OK (%d Bytes)\n", body.length());

		// JSON parsen
		StaticJsonDocument<1024> doc;
		DeserializationError err = deserializeJson(doc, body);

		if (!err) {
			buildScrollText(doc, pendingText, sizeof(pendingText));
			newDataReady = true;
			Serial.println(F("Anzeigetext aktualisiert."));
		} else {
			Serial.print(F("JSON-Fehler: "));
			Serial.println(err.c_str());
		}
	} else {
		Serial.printf("HTTP-Fehler: %d\n", code);
	}

	http.end();
	fetchInProgress = false;
}

// ===========================================================
//  setup()
// ===========================================================
void setup() {
	Serial.begin(74880);
	Serial.println(F("\n--- SWS Display-Sketch ---"));

	// Display initialisieren
	display.begin();
	display.setIntensity(DISPLAY_INTENSITY);
	display.displayClear();
	display.setTextAlignment(PA_LEFT);
	display.setSpeed(SCROLL_SPEED_MS);
	display.setPause(PAUSE_AFTER_MS);

	// Begrüßungstext während WiFi-Verbindung
	display.displayScroll("Connecting...", PA_LEFT, PA_SCROLL_LEFT, SCROLL_SPEED_MS);

	// WiFi verbinden
	Serial.printf("Verbinde mit %s", WIFI_SSID);
	WiFi.mode(WIFI_STA);
	WiFi.begin(WIFI_SSID, WIFI_PASS);

	unsigned long wifiStart = millis();
	while (WiFi.status() != WL_CONNECTED) {
		// Scroll-Animation während Wartezeit weiterlaufen lassen
		display.displayAnimate();
		delay(10);
		if (millis() - wifiStart > 20000) {
			// Nach 20 s Fehlermeldung – weiter versuchen
			Serial.println(F("\nWiFi-Timeout! Warte weiter..."));
			wifiStart = millis();
		}
	}

	Serial.printf("\nWiFi verbunden – IP: %s\n", WiFi.localIP().toString().c_str());

	// Sofortigen ersten Abruf anstoßen
	strncpy(scrollText, "Lade Daten...", sizeof(scrollText));
	display.displayScroll(scrollText, PA_LEFT, PA_SCROLL_LEFT, SCROLL_SPEED_MS);
	fetchData();

	if (newDataReady) {
		strncpy(scrollText, pendingText, sizeof(scrollText));
		newDataReady = false;
		display.displayScroll(scrollText, PA_LEFT, PA_SCROLL_LEFT, SCROLL_SPEED_MS);
	}

	lastFetch = millis();
}

// ===========================================================
//  loop()
// ===========================================================
void loop() {
	// Laufschrift-Animation
	if (display.displayAnimate()) {
		// Scroll-Durchgang beendet → neuen Text übernehmen falls vorhanden
		if (newDataReady) {
			strncpy(scrollText, pendingText, sizeof(scrollText));
			newDataReady = false;
		}
		// Text erneut starten
		display.displayScroll(scrollText, PA_LEFT, PA_SCROLL_LEFT, SCROLL_SPEED_MS);
	}

	// Periodischer API-Abruf (nicht blockierend während Scroll)
	if (millis() - lastFetch >= FETCH_INTERVAL_MS) {
		lastFetch = millis();
		fetchData();
	}
}
