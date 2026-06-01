#pragma once
/**
 * SWSApiClient.h
 * Arduino-Bibliothek fuer die Solar WiFi Weather Station REST-API.
 *
 * Einfachste Verwendung:
 *   SWSApiClient api("meinserver.de", "/sws/api/v1/data.php", "user", "pass");
 *   api.set("temperature", 21.5f)
 *      .set("humidity",    55.0f)
 *      .set("battery_pct", 88)
 *      .send();
 *
 * Plattform: ESP8266 (primaer), ESP32 (kompatibel)
 * Abhaengigkeit: ArduinoJson >= 7
 */

#include <Arduino.h>
#include <ArduinoJson.h>

// Plattform-spezifische HTTP-Includes
#ifdef ESP32
  #include <WiFi.h>
  #include <HTTPClient.h>
  #include <WiFiClientSecure.h>
#else
  #include <ESP8266WiFi.h>
  #include <ESP8266HTTPClient.h>
  #include <WiFiClientSecure.h>
  #include <WiFiClient.h>
#endif

// Standard-Timeout fuer HTTP-Anfragen in Millisekunden
#ifndef SWS_HTTP_TIMEOUT_MS
  #define SWS_HTTP_TIMEOUT_MS 8000
#endif

// Maximale JSON-Payload-Groesse in Bytes
#ifndef SWS_JSON_BUFFER
  #define SWS_JSON_BUFFER 768
#endif

/**
 * Ergebnis eines API-Aufrufs.
 */
struct SWSResult {
	bool    ok;        // true wenn HTTP 200
	int     httpCode;  // HTTP-Statuscode, oder negativer ESP-Fehlercode
	String  response;  // Antwort-Body (leer bei Fehler)
};

/**
 * SWSApiClient – kapselt HTTP-POST + JSON + Basic-Auth.
 *
 * Der Client haelt intern einen JsonDocument-Puffer.
 * Nach send() bzw. sendLog() wird der Puffer automatisch geleert.
 */
class SWSApiClient {
public:
	/**
	 * Konstruktor.
	 * @param host      Hostname ohne Protokoll, z.B. "meinserver.de"
	 * @param dataPath  Pfad zum Daten-Endpunkt, z.B. "/sws/api/v1/data.php"
	 * @param user      API-Benutzername (Basic Auth)
	 * @param pass      API-Passwort     (Basic Auth)
	 * @param useHttps  true = HTTPS (kein Zertifikat-Check), false = HTTP
	 */
	SWSApiClient(const char* host,
				 const char* dataPath,
				 const char* user,
				 const char* pass,
				 bool        useHttps = true);

	// -------------------------------------------------------------------
	// Fluent-API zum Setzen von Messwerten
	// -------------------------------------------------------------------

	/** Fliesskomma-Messwert setzen (z.B. temperature, humidity). */
	SWSApiClient& set(const char* key, float value);

	/** Integer-Messwert setzen (z.B. battery_pct, wifi_strength). */
	SWSApiClient& set(const char* key, int value);

	/** String-Messwert setzen (z.B. station_name). */
	SWSApiClient& set(const char* key, const String& value);

	/** String-Messwert (C-String) setzen. */
	SWSApiClient& set(const char* key, const char* value);

	/** Optionalen Pool-Temperaturwert nur setzen wenn gueltig (> -87). */
	SWSApiClient& setIfValid(const char* key, float value, float invalidBelow = -50.0f);

	// -------------------------------------------------------------------
	// Daten senden
	// -------------------------------------------------------------------

	/**
	 * Alle gesetzten Werte als JSON-POST an den Daten-Endpunkt senden.
	 * Leert den internen Puffer nach dem Senden.
	 */
	SWSResult send();

	// -------------------------------------------------------------------
	// Fehler-Logging
	// -------------------------------------------------------------------

	/**
	 * Fehler oder Warnung an den /v1/log-Endpunkt senden.
	 * Der Log-Pfad wird automatisch aus dem dataPath abgeleitet
	 * (letztes Segment wird durch "log.php" ersetzt),
	 * oder kann explizit mit setLogPath() gesetzt werden.
	 *
	 * @param level   "error", "warning" oder "info"
	 * @param code    Maschinenlesbarer Fehlercode, z.B. "DS18B20_INVALID"
	 * @param message Lesbare Fehlermeldung
	 * @param context Optionaler JSON-Kontext-String, z.B. "{\"val\":-88}"
	 */
	SWSResult logError(const char* level,
					   const char* code,
					   const char* message,
					   const char* context = nullptr);

	/**
	 * Expliziten Log-Endpunkt-Pfad setzen.
	 * Standard: dataPath mit letztem Segment = "log.php"
	 */
	void setLogPath(const char* logPath);

	/**
	 * Stationsname setzen – wird bei jedem send() automatisch
	 * als "station_name" mitgeschickt wenn gesetzt.
	 */
	void setStationName(const char* name);

	/**
	 * Geräte-MAC setzen – wird bei jedem send() als "device_mac"
	 * mitgeschickt. Ermöglicht eindeutige Stationsidentifikation.
	 * Übergabe: WiFi.macAddress().c_str()
	 */
	void setDeviceMac(const char* mac);

	/** Interner Puffer manuell leeren. */
	void clear();

private:
	String _host;
	String _dataPath;
	String _logPath;
	String _user;
	String _pass;
	String _stationName;
	String _deviceMac;
	bool   _useHttps;

	JsonDocument _doc;

	/** HTTP-POST an beliebige URL mit Basic-Auth. */
	SWSResult _post(const String& path, const String& jsonBody);

	/** Base64-Kodierung fuer Basic-Auth-Header. */
	static String _base64(const String& input);

	/** Log-Pfad aus dataPath ableiten. */
	String _deriveLogPath() const;
};
