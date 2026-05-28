#pragma once

// ============================================================
//  Konfiguration: SWS Display-Sketch
//  Board: WEMOS D1 Mini Pro (ESP8266)
// ============================================================

// ------ WiFi ------------------------------------------------
#define WIFI_SSID   "Dein_WLAN_Name"
#define WIFI_PASS   "Dein_WLAN_Passwort"

// ------ API -------------------------------------------------
// GET-Endpunkt – kein Auth notwendig
#define API_HOST    "timm-sander.net"
#define API_PATH    "/swsapi/data.php"
#define API_HTTPS   true      // true = HTTPS (Port 443), false = HTTP (Port 80)

// ------ Aktualisierungsintervall ----------------------------
// Wie oft (ms) ein neuer API-Abruf gestartet wird
#define FETCH_INTERVAL_MS  60000UL   // 60 Sekunden

// ------ LED-Matrix (MAX7219 / 1088AS) -----------------------
// Hardware-SPI: CLK=D5(GPIO14), MOSI/DATA=D7(GPIO13)
#define DISPLAY_CS_PIN  15    // D8 (GPIO15) – Chip-Select
#define NUM_DEVICES      4    // Anzahl kaskadierter 8×8-Module
#define DISPLAY_INTENSITY 5   // Helligkeit 0 (dunkel) … 15 (max.)

// ------ Laufschrift -----------------------------------------
#define SCROLL_SPEED_MS  40   // ms pro Schritt (kleiner = schneller)
#define PAUSE_AFTER_MS   1500 // ms Pause am Ende des Textes

// ------ Anzeige-Einheiten -----------------------------------
// true  = °C, hPa, Pool°C
// false = °F, inHg
#define USE_METRIC  true
