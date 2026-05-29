#pragma once

// ============================================================
//  Compile-Zeit-Defaults – SWS Display-Sketch
//  Alle Werte können zur Laufzeit per Config-Portal überschrieben
//  werden (EEPROM). WiFi-Zugangsdaten werden NICHT hardcodiert –
//  beim ersten Start den Config-Modus nutzen (D3/BOOT drücken).
// ============================================================

// ------ Config-Portal ---------------------------------------
// D3 (GPIO0) = eingebauter FLASH/BOOT-Taster des WEMOS D1 Mini
#define CONFIG_BUTTON_PIN   0
#define CONFIG_AP_SSID      "SWS-Display-Config"   // offener AP, kein Passwort

// ------ WiFi (bewusst leer – Eingabe über Config-Portal) ----
#define CFG_DEFAULT_WIFI_SSID   ""
#define CFG_DEFAULT_WIFI_PASS   ""

// ------ API -------------------------------------------------
#define CFG_DEFAULT_API_HOST    "timm-sander.net"
#define CFG_DEFAULT_API_PATH    "/swsapi/data.php"
#define CFG_DEFAULT_API_HTTPS   true

// ------ Aktualisierungsintervall ----------------------------
#define CFG_DEFAULT_FETCH_SEC   60        // Sekunden zwischen API-Abrufen

// ------ LED-Matrix (MAX7219 / 1088AS) -----------------------
// Hardware-SPI: CLK=D5(GPIO14), MOSI/DATA=D7(GPIO13)
#define DISPLAY_CS_PIN      15            // D8 (GPIO15) – Chip-Select
#define NUM_DEVICES          4            // Anzahl kaskadierter 8×8-Module

// ------ LDR (Helligkeitssensor) ----------------------------
// WEMOS D1 Mini: einziger Analog-Eingang A0 (0–1023)
#define LDR_PIN             A0
#define LDR_UPDATE_MS       2000UL        // Helligkeit alle 2 s aktualisieren

// Automatische Helligkeit: LDR-Rohwert → Intensity-Bereich
// Min-/Max-Werte im Config-Portal anpassbar
#define CFG_DEFAULT_INTENSITY_MIN   1     // Helligkeit bei Dunkelheit (0–15)
#define CFG_DEFAULT_INTENSITY_MAX  12     // Helligkeit bei hellem Licht (0–15)

// ------ DHT22 (Innenraumsensor) -----------------------------
// D2 (GPIO4) – Temperatur + Luftfeuchte im Display-Gehäuse
#define DHT_PIN             4
#define DHT_TYPE            DHT22

#define CFG_DEFAULT_SCROLL_MS

// ------ NTP -------------------------------------------------
#define CFG_DEFAULT_NTP_SERVER  "pool.ntp.org"
#define CFG_DEFAULT_NTP_OFFSET  3600      // UTC+1 (Winterzeit); Sommerzeit = 7200

// ------ Anzeigesteuerung ------------------------------------
#define CLOCK_DISPLAY_SEC       30        // Sekunden Uhranzeige je Phase
