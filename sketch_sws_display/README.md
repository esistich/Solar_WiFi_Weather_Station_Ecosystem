# SWS Display-Sketch

Zeigt den letzten Messwert der Solar WiFi Weather Station als scrollenden
Lauftext auf 4 kaskadierten 8×8-LED-Matrizen (1088AS / MAX7219) an.

---

## Hardware

| Komponente | Details |
|------------|---------|
| Board | WEMOS D1 Mini Pro (ESP8266) |
| Display-Module | 4× 1088AS (8×8 LEDs, MAX7219 intern) |
| Verbindung | SPI (Hardware) |

### Verdrahtung

```
WEMOS D1 Mini Pro    MAX7219-Modul (Kette)
─────────────────    ─────────────────────
3V3 (oder 5V)   ──── VCC
GND             ──── GND
D5  (GPIO14)    ──── CLK
D7  (GPIO13)    ──── DIN
D8  (GPIO15)    ──── CS
```

> Beim Kaskadieren: DOUT des ersten Moduls → DIN des zweiten usw.  
> VCC je nach Modul-Spezifikation: die meisten 1088AS-Module vertragen 3,3 V und 5 V.

---

## Konfiguration

Alle Einstellungen in **`DisplaySettings.h`** anpassen:

| Konstante | Bedeutung | Standard |
|-----------|-----------|---------|
| `WIFI_SSID` | WLAN-Name | – |
| `WIFI_PASS` | WLAN-Passwort | – |
| `API_HOST` | Hostname der API | `timm-sander.net` |
| `API_PATH` | Pfad zum Endpoint | `/swsapi/data.php` |
| `API_HTTPS` | HTTPS nutzen | `true` |
| `FETCH_INTERVAL_MS` | Abruf-Intervall (ms) | `60000` |
| `DISPLAY_CS_PIN` | CS-Pin (GPIO) | `15` (D8) |
| `NUM_DEVICES` | Anzahl 8×8-Module | `4` |
| `DISPLAY_INTENSITY` | Helligkeit (0–15) | `5` |
| `SCROLL_SPEED_MS` | Scroll-Geschwindigkeit (ms/Schritt) | `40` |

---

## Bibliotheken

Arduino Library Manager:

| Library | Autor | Version |
|---------|-------|---------|
| **MD_Parola** | MajicDesigns | ≥ 3.7 |
| **MD_MAX72XX** | MajicDesigns | ≥ 3.5 |
| **ArduinoJson** | Benoit Blanchon | ≥ 6.0 |

> `ESP8266WiFi`, `ESP8266HTTPClient`, `WiFiClientSecure` sind Teil des
> ESP8266 Arduino-Core und müssen nicht extra installiert werden.

---

## Angezeigter Text (Beispiel)

```
SWS  |  T:23.4°C  Pool:28.1°C  Hum:58%  P:1013hPa  Mostly Cloudy  (Falling)
```

Die Reihenfolge der Felder:

1. Stationsname
2. Außentemperatur
3. Pool-Temperatur *(wird übersprungen, wenn kein DS18B20 verbaut)*
4. Luftfeuchtigkeit
5. Relativdruck
6. Zambretti-Wettervorhersage
7. Drucktend (in Klammern)

---

## Board-Einstellungen (Arduino IDE)

| Einstellung | Wert |
|-------------|------|
| Board | LOLIN(WEMOS) D1 mini Pro |
| Upload Speed | 921600 |
| CPU Frequency | 80 MHz |
| Flash Size | 16MB (FS:14MB OTA:992KB) |
