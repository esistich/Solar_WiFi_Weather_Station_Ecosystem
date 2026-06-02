/**
 * BasicUsage.ino
 * Minimales Beispiel fuer die SWSApiClient-Bibliothek.
 *
 * Voraussetzungen:
 *  - ESP8266 oder ESP32
 *  - ArduinoJson >= 7
 *  - WLAN-Verbindung besteht bereits (z.B. via WiFiManager)
 */

#include <SWSApiClient.h>

// -----------------------------------------------------------------------
// Konfiguration – KEINE Klartext-Secrets in Produktionssketches!
// Verwende Settings.h oder EEPROM/LittleFS fuer echte Zugangsdaten.
// -----------------------------------------------------------------------
#define API_HOST   "meinserver.de"
#define API_PATH   "/sws/api/v1/data.php"
#define API_USER   "station"
#define API_PASS   "geheim"
#define API_HTTPS  true

SWSApiClient api(API_HOST, API_PATH, API_USER, API_PASS, API_HTTPS);

void setup() {
	Serial.begin(115200);

	// Stationsname einmalig setzen – wird bei jedem send() mitgeschickt
	api.setStationName("Teststation");

	// --- Messwerte sammeln ---
	float temperature  = 21.5f;
	float humidity     = 55.0f;
	float relPressure  = 1013.25f;
	float absPressure  = 1010.0f;
	float poolTemp     = 24.3f;   // -99 wenn kein Sensor vorhanden
	float batteryVolt  = 3.85f;
	int   batteryPct   = 88;
	int   wifiStrength = (int)WiFi.RSSI();
	long  timestamp    = 1700000000L; // UTC Unix-Timestamp

	// --- Fluent-API: Felder setzen und senden ---
	SWSResult result = api
		.set("temperature",    temperature)
		.set("humidity",       humidity)
		.set("rel_pressure",   relPressure)
		.set("abs_pressure",   absPressure)
		.setIfValid("pool_temperature", poolTemp)   // nur senden wenn > -50
		.set("battery_volt",   batteryVolt)
		.set("battery_pct",    batteryPct)
		.set("wifi_strength",  wifiStrength)
		.set("timestamp",      (int)timestamp)
		.send();

	if (result.ok) {
		Serial.println("Daten erfolgreich gesendet.");
	} else {
		Serial.printf("Fehler beim Senden (HTTP %d): %s\n",
					  result.httpCode, result.response.c_str());

		// Fehler zusaetzlich ueber die API loggen
		api.logError("error", "SEND_FAILED",
					 "Daten konnten nicht an API gesendet werden");
	}
}

void loop() {
	// Wetterstation schlaeft zwischen Messungen – loop() bleibt leer.
}
