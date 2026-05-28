# Verdrahtung – SWS Display

Board: **WEMOS D1 Mini Pro** (ESP8266)

---

## Pinbelegung

| WEMOS Pin | GPIO | Funktion | Bauteil |
|-----------|------|----------|---------|
| 3V3 (oder 5V) | – | Versorgung | MAX7219 VCC |
| GND | – | Masse | MAX7219 GND, LDR-Teiler |
| D3 | GPIO0 | Config-Button | Taster gegen GND (BOOT/FLASH) |
| D5 | GPIO14 | SPI CLK | MAX7219 CLK |
| D7 | GPIO13 | SPI MOSI | MAX7219 DIN |
| D8 | GPIO15 | SPI CS | MAX7219 CS |
| A0 | ADC | LDR Helligkeitssensor | Spannungsteiler |

---

## MAX7219 / 1088AS LED-Matrix (4× kaskadiert)

```
WEMOS D1 Mini Pro     MAX7219 Modul #1     Modul #2 … #4
─────────────────     ────────────────     ─────────────
3V3 (od. 5V)  ─────  VCC              ─── VCC
GND           ─────  GND              ─── GND
D5 (GPIO14)   ─────  CLK              ─── CLK
D7 (GPIO13)   ─────  DIN
D8 (GPIO15)   ─────  CS               ─── CS

					  DOUT ────────────── DIN (Modul #2)
										  DOUT ──── DIN (#3) …
```

> CLK und CS parallel an alle Module.  
> DIN → DOUT bildet die Kaskade.  
> Modul-Typ im Sketch: `MD_MAX72XX::FC16_HW` (schwarze Standard-Module).

---

## LDR – automatische Helligkeitsregelung

```
3V3 ── LDR ──┬── A0 (WEMOS)
			 │
		   10kΩ
			 │
			GND
```

> Je heller die Umgebung, desto höher die Spannung auf A0 (0–1023) →  
> `map()` auf `intensity_min … intensity_max` (im Config-Portal einstellbar).  
> Alle 2 Sekunden wird die Helligkeit aktualisiert.  
> Der WEMOS D1 Mini Pro hat einen internen 220kΩ-Spannungsteiler auf A0;  
> der externe 10kΩ-Widerstand sorgt für ausreichende Empfindlichkeit.

---

## Config-Button (BOOT/FLASH-Taster)

```
WEMOS D1 Mini Pro
─────────────────
D3 (GPIO0) ────┤ Taster ├──── GND
```

> Interner Pull-up aktiv.  
> Beim Einschalten gedrückt halten → Config-Portal startet.  
> AP: `SWS-Display-Config` (kein Passwort) → http://192.168.4.1

---

## Übersicht (ASCII-Schaltbild)

```
		 ┌─────────────────────────┐
	3V3 ─┤                         ├─ GND
		 │   WEMOS D1 Mini Pro     │
	D3  ─┤ Config ──[Taster]─── GND│
	D5  ─┤ CLK ──────────────────────────┐
	D7  ─┤ DIN ─────────────────────┐    │   ┌─────────────────────────────┐
	D8  ─┤ CS  ──────────────────────────┼───┤ MAX7219 #1 … #4 (1088AS)   │
	A0  ─┤ ADC ──[LDR + 10kΩ]── GND │    └───┤ DIN / CLK / CS             │
		 └─────────────────────────┘        └─────────────────────────────┘
```
