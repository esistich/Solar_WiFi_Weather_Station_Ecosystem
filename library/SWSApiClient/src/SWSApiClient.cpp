/**
 * SWSApiClient.cpp
 * Implementierung der SWS REST-API Arduino-Bibliothek.
 */

#include "SWSApiClient.h"

// -----------------------------------------------------------------------
// Base64-Zeichentabelle (RFC 4648)
// -----------------------------------------------------------------------
static const char _B64[] =
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

String SWSApiClient::_base64(const String& input) {
	String out;
	out.reserve(((input.length() + 2) / 3) * 4);
	const int len = (int)input.length();
	int i = 0;
	while (i < len) {
		uint8_t a = (i < len) ? (uint8_t)input[i++] : 0;
		uint8_t b = (i < len) ? (uint8_t)input[i++] : 0;
		uint8_t c = (i < len) ? (uint8_t)input[i++] : 0;
		out += _B64[a >> 2];
		out += _B64[((a & 3) << 4) | (b >> 4)];
		out += (i - 2 < len) ? _B64[((b & 15) << 2) | (c >> 6)] : '=';
		out += (i - 1 < len) ? _B64[c & 63]                      : '=';
	}
	return out;
}

// -----------------------------------------------------------------------
// Konstruktor
// -----------------------------------------------------------------------
SWSApiClient::SWSApiClient(const char* host,
						   const char* dataPath,
						   const char* user,
						   const char* pass,
						   bool        useHttps)
	: _host(host), _dataPath(dataPath),
	  _user(user), _pass(pass),
	  _useHttps(useHttps)
{
	_logPath = _deriveLogPath();
}

// -----------------------------------------------------------------------
// Fluent-API: set()
// -----------------------------------------------------------------------
SWSApiClient& SWSApiClient::set(const char* key, float value) {
	_doc[key] = value;
	return *this;
}

SWSApiClient& SWSApiClient::set(const char* key, int value) {
	_doc[key] = value;
	return *this;
}

SWSApiClient& SWSApiClient::set(const char* key, const String& value) {
	_doc[key] = value;
	return *this;
}

SWSApiClient& SWSApiClient::set(const char* key, const char* value) {
	_doc[key] = value;
	return *this;
}

SWSApiClient& SWSApiClient::setIfValid(const char* key, float value, float invalidBelow) {
	if (value > invalidBelow) {
		_doc[key] = value;
	}
	return *this;
}

// -----------------------------------------------------------------------
// Konfiguration
// -----------------------------------------------------------------------
void SWSApiClient::setStationName(const char* name) {
	_stationName = name;
}

void SWSApiClient::setDeviceMac(const char* mac) {
	_deviceMac = mac;
}

void SWSApiClient::setLogPath(const char* logPath) {
	_logPath = logPath;
}

void SWSApiClient::clear() {
	_doc.clear();
}

// -----------------------------------------------------------------------
// send()
// -----------------------------------------------------------------------
SWSResult SWSApiClient::send() {
	// Stationsname automatisch hinzufuegen wenn gesetzt
	if (_stationName.length() > 0 && !_doc.containsKey("station_name")) {
		_doc["station_name"] = _stationName;
	}
	// Geraete-MAC automatisch hinzufuegen wenn gesetzt
	if (_deviceMac.length() > 0 && !_doc.containsKey("device_mac")) {
		_doc["device_mac"] = _deviceMac;
	}

	// JSON serialisieren
	char buf[SWS_JSON_BUFFER];
	size_t written = serializeJson(_doc, buf, sizeof(buf));

	if (written == 0 || written >= sizeof(buf) - 1) {
		Serial.println(F("SWSApiClient: WARNUNG - JSON-Payload abgeschnitten! SWS_JSON_BUFFER erhoehen."));
		SWSResult r;
		r.ok       = false;
		r.httpCode = -99;
		r.response = "BUFFER_OVERFLOW";
		clear();
		return r;
	}

	Serial.printf("SWSApiClient: sende %u Bytes an %s%s\n",
				  (unsigned)written, _host.c_str(), _dataPath.c_str());

	SWSResult result = _post(_dataPath, String(buf));
	clear();
	return result;
}

// -----------------------------------------------------------------------
// logError()
// -----------------------------------------------------------------------
SWSResult SWSApiClient::logError(const char* level,
								 const char* code,
								 const char* message,
								 const char* context)
{
	JsonDocument logDoc;
	logDoc["level"]   = level;
	logDoc["code"]    = code;
	logDoc["message"] = message;
	if (context && context[0] != '\0') {
		// Kontext als rohen JSON-String einbetten
		JsonDocument ctxDoc;
		if (deserializeJson(ctxDoc, context) == DeserializationError::Ok) {
			logDoc["context"] = ctxDoc.as<JsonObject>();
		} else {
			logDoc["context"] = context;
		}
	}

	char buf[384];
	serializeJson(logDoc, buf, sizeof(buf));

	Serial.printf("SWSApiClient: log [%s] %s – %s\n", level, code, message);
	return _post(_logPath, String(buf));
}

// -----------------------------------------------------------------------
// _post() – interner HTTP-POST mit Basic-Auth
// -----------------------------------------------------------------------
SWSResult SWSApiClient::_post(const String& path, const String& jsonBody) {
	SWSResult result;
	result.ok       = false;
	result.httpCode = 0;

	String authHeader = "Basic " + _base64(_user + ":" + _pass);
	String url        = (_useHttps ? "https://" : "http://") + _host + path;

	HTTPClient http;

#ifdef ESP32
	if (_useHttps) {
		WiFiClientSecure* tlsClient = new WiFiClientSecure();
		tlsClient->setInsecure();   // Zertifikat nicht pruefen (LAN/Heimnetz)
		http.begin(*tlsClient, url);
	} else {
		WiFiClient* plainClient = new WiFiClient();
		http.begin(*plainClient, url);
	}
#else
	// ESP8266
	if (_useHttps) {
		WiFiClientSecure tlsClient;
		tlsClient.setInsecure();
		http.begin(tlsClient, url);
	} else {
		WiFiClient plainClient;
		http.begin(plainClient, url);
	}
#endif

	http.addHeader("Content-Type", "application/json");
	http.addHeader("Authorization", authHeader);
	http.setTimeout(SWS_HTTP_TIMEOUT_MS);

	int code = http.POST(const_cast<String&>(jsonBody));
	result.httpCode = code;

	if (code > 0) {
		result.ok       = (code == 200);
		result.response = http.getString();
		Serial.printf("SWSApiClient: HTTP %d – %s\n", code, result.response.c_str());
	} else {
		result.response = http.errorToString(code);
		Serial.printf("SWSApiClient: Fehler %d – %s\n", code, result.response.c_str());
	}

	http.end();
	return result;
}

// -----------------------------------------------------------------------
// _deriveLogPath() – /v1/data.php -> /v1/log.php
// -----------------------------------------------------------------------
String SWSApiClient::_deriveLogPath() const {
	// Letztes Pfadsegment durch "log.php" ersetzen
	int lastSlash = _dataPath.lastIndexOf('/');
	if (lastSlash >= 0) {
		return _dataPath.substring(0, lastSlash + 1) + "log.php";
	}
	return "/log.php";
}
