-- ============================================================
-- Solar WiFi Weather Station – Datenbank-Schema
-- Datenbank vorher anlegen, z.B.:
--   CREATE DATABASE solarweather CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
-- Dann diese Datei importieren:
--   mysql -u root -p solarweather < schema.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS `measurements` (
  `id`                  INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  `created_at`          TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Identifikation
  `station_name`        VARCHAR(64)      NOT NULL DEFAULT '',

  -- Temperatur & Feuchte
  `temperature`         DECIMAL(5,2)     NOT NULL COMMENT 'Temperatur in °C (korrigiert)',
  `humidity`            DECIMAL(5,2)     NOT NULL COMMENT 'Relative Luftfeuchte in %',
  `heat_index`          DECIMAL(5,2)     NOT NULL COMMENT 'Hitzeindex in °C',
  `dewpoint`            DECIMAL(5,2)     NOT NULL COMMENT 'Taupunkt in °C',
  `dewpoint_spread`     DECIMAL(5,2)     NOT NULL COMMENT 'Taupunktdifferenz in K',

  -- Luftdruck
  `abs_pressure`        DECIMAL(7,2)     NOT NULL COMMENT 'Absoluter Luftdruck in hPa',
  `rel_pressure`        INT UNSIGNED     NOT NULL COMMENT 'Relativer Luftdruck (QNH) in hPa',
  `pressure_state`      VARCHAR(32)      NOT NULL DEFAULT '' COMMENT 'Druckzustand (Tief, Hoch …)',

  -- Zambretti-Prognose
  `zambretti`           VARCHAR(128)     NOT NULL DEFAULT '' COMMENT 'Zambretti-Text',
  `zambretti_letter`    CHAR(1)          NOT NULL DEFAULT 'A',
  `trend`               VARCHAR(32)      NOT NULL DEFAULT '' COMMENT 'Trendtext (steigend …)',
  `trend_value`         DECIMAL(6,3)     NOT NULL DEFAULT 0 COMMENT 'Numerischer Trend (hPa-Differenz)',
  `accuracy`            TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Prognosegenauigkeit in %',

  -- Batterie
  `battery_volt`        DECIMAL(4,2)     NOT NULL COMMENT 'Batteriespannung in V',
  `battery_pct`         TINYINT UNSIGNED NOT NULL COMMENT 'Batterieladung in %',

  -- Sonstiges
  `wifi_strength`       TINYINT          NOT NULL DEFAULT 0 COMMENT 'WLAN RSSI in dBm',
  `device_timestamp`    INT UNSIGNED     NOT NULL DEFAULT 0 COMMENT 'UNIX-Timestamp der Station (UTC)',

  PRIMARY KEY (`id`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
