# Verdrahtung – Solar WiFi Weather Station

Board: **WEMOS D1 Mini Pro** (ESP8266)

---

## Pinbelegung

| WEMOS Pin | GPIO | Funktion | Bauteil |
|-----------|------|----------|---------|
| 3V3 | – | Versorgung | BME280 VCC, DS18B20 VCC |
| GND | – | Masse | alle Bauteile |
| D1 | GPIO5 | I²C SCL | BME280 SCL |
| D2 | GPIO4 | I²C SDA | BME280 SDA |
| D3 | GPIO0 | Config-Button | Taster gegen GND |
| D7 | GPIO13 | OneWire Data | DS18B20 Data |

---

## BME280 (Temperatur / Luftfeuchtigkeit / Luftdruck)

```
WEMOS D1 Mini Pro     BME280
─────────────────     ──────
3V3             ────  VCC
GND             ────  GND
D1 (GPIO5)      ────  SCL
D2 (GPIO4)      ────  SDA
```

> Adresse: 0x76 (SDO → GND) oder 0x77 (SDO → VCC)

---

## DS18B20 (Pooltemperatur, OneWire)

```
WEMOS D1 Mini Pro     DS18B20
─────────────────     ───────
3V3             ────  VCC  (Pin 3)
GND             ────  GND  (Pin 1)
D7 (GPIO13)     ────  Data (Pin 2)

3V3 ── 4,7kΩ ──┬── D7 (GPIO13)
			   └── DS18B20 Data
```

> Parasite-Power-Mode nicht empfohlen – immer VCC anlegen.  
> Mehrere DS18B20 können an derselben Leitung hängen (Adressierung über ROM-Code).

---

## Config-Button

```
WEMOS D1 Mini Pro
─────────────────
D3 (GPIO0) ────┤ Taster ├──── GND
```

> Internen Pull-up aktiv (`INPUT_PULLUP`).  
> Beim Boot LOW = Config-Portal starten.

---

## Versorgung

| Betrieb | Empfehlung |
|---------|-----------|
| USB (Entwicklung) | Micro-USB direkt am WEMOS |
| Solar-Betrieb | LiPo + Solar-Laderegler → 3V3-Pin oder USB |

> Deep-Sleep-Wakeup: RST-Pin mit D0 (GPIO16) verbinden.  
> Ohne diese Verbindung wacht die Station nach dem Sleep nicht auf.

```
D0 (GPIO16) ──── RST
```

---

## Übersicht (ASCII-Schaltbild)

```
		 ┌─────────────────────────┐
	3V3 ─┤                         ├─ GND
		 │   WEMOS D1 Mini Pro     │
	RST ─┤  (ESP8266)              ├─ D0 (GPIO16)
		 │                         │        │
	 D1 ─┤ SCL ──────────────── BME280     └── RST
	 D2 ─┤ SDA ──────────────── BME280
	 D3 ─┤ Config-Btn ─[Taster]── GND
	 D7 ─┤ OneWire ─[4,7kΩ→3V3]─ DS18B20
		 └─────────────────────────┘
```
