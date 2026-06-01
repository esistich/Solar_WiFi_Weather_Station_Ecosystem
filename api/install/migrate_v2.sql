-- ============================================================
-- Solar WiFi Weather Station – Migration v2
-- Neue Struktur: stations, measurement_values, metric_definitions
-- Bestehende measurements-Daten werden migriert.
--
-- REIHENFOLGE:
--   1. Dieses Skript in der Datenbank ausführen
--   2. Anschließend neue API v1 deployen
-- ============================================================

-- ----------------------------------------------------------
-- 1. Stationen-Tabelle
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `stations` (
  `id`         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `slug`       VARCHAR(64)   NOT NULL UNIQUE COMMENT 'URL-freundlicher Bezeichner (z.B. sws-garten)',
  `name`       VARCHAR(128)  NOT NULL DEFAULT 'SWS Station',
  `api_key`    VARCHAR(64)   NULL     COMMENT 'Zukünftig: stationsspezifischer API-Key',
  `settings`   JSON          NULL     COMMENT 'Remote-Config: sleep_min, temp_corr, elevation, api_path',
  `created_at` TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_slug` (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Standardstation anlegen (für bestehende Daten)
INSERT IGNORE INTO `stations` (`id`, `slug`, `name`) VALUES (1, 'sws-main', 'SWS Hauptstation');

-- ----------------------------------------------------------
-- 2. measurements – station_id + device_ts hinzufügen
-- ----------------------------------------------------------
ALTER TABLE `measurements`
  ADD COLUMN IF NOT EXISTS `station_id` INT UNSIGNED NOT NULL DEFAULT 1
	COMMENT 'FK zu stations.id' AFTER `id`,
  ADD COLUMN IF NOT EXISTS `device_ts`  DATETIME NULL
	COMMENT 'Timestamp der Station (UTC)' AFTER `station_id`,
  ADD KEY IF NOT EXISTS `idx_station_created` (`station_id`, `created_at`);

-- Bestehende Zeilen der Standardstation zuweisen
UPDATE `measurements` SET `station_id` = 1 WHERE `station_id` = 0;

-- ----------------------------------------------------------
-- 3. Metrik-Definitionen
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `metric_definitions` (
  `metric_key`    VARCHAR(64)  NOT NULL,
  `label`         VARCHAR(128) NOT NULL DEFAULT '',
  `unit`          VARCHAR(32)  NOT NULL DEFAULT '',
  `display_order` TINYINT      NOT NULL DEFAULT 99,
  `chart_color`   VARCHAR(16)  NOT NULL DEFAULT '#4e79a7',
  PRIMARY KEY (`metric_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO `metric_definitions` (`metric_key`, `label`, `unit`, `display_order`, `chart_color`) VALUES
  ('temperature',     'Temperatur Außen',  '°C',  1,  '#e15759'),
  ('pool_temperature','Temperatur Wasser', '°C',  2,  '#4e79a7'),
  ('humidity',        'Luftfeuchte',       '%',   3,  '#59a14f'),
  ('rel_pressure',    'Luftdruck (rel.)',  'hPa', 4,  '#9c755f'),
  ('abs_pressure',    'Luftdruck (abs.)',  'hPa', 5,  '#bab0ac'),
  ('battery_pct',     'Batterie',          '%',   6,  '#f28e2b'),
  ('battery_volt',    'Spannung',          'V',   7,  '#edc948'),
  ('wifi_strength',   'WLAN',             'dBm',  8,  '#76b7b2'),
  ('heat_index',      'Hitzeindex',        '°C',  9,  '#ff9da7'),
  ('dewpoint',        'Taupunkt',          '°C',  10, '#b07aa1'),
  ('trend_value',     'Drucktrend',       'hPa',  11, '#d37295');

-- ----------------------------------------------------------
-- 4. Messwerte-Tabelle (EAV)
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `measurement_values` (
  `measurement_id` INT UNSIGNED NOT NULL,
  `metric_key`     VARCHAR(64)  NOT NULL,
  `value`          VARCHAR(255) NOT NULL,
  PRIMARY KEY (`measurement_id`, `metric_key`),
  KEY `idx_metric_key` (`metric_key`),
  CONSTRAINT `fk_mv_measurement`
	FOREIGN KEY (`measurement_id`) REFERENCES `measurements`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------
-- 5. Bestehende Messdaten in measurement_values migrieren
--    (nur Felder die numerisch sind; Strings werden übersprungen)
-- ----------------------------------------------------------
INSERT IGNORE INTO `measurement_values` (`measurement_id`, `metric_key`, `value`)
  SELECT `id`, 'temperature',      `temperature`   FROM `measurements` WHERE `temperature`    IS NOT NULL;

INSERT IGNORE INTO `measurement_values` (`measurement_id`, `metric_key`, `value`)
  SELECT `id`, 'pool_temperature', `pool_temperature` FROM `measurements` WHERE `pool_temperature` IS NOT NULL;

INSERT IGNORE INTO `measurement_values` (`measurement_id`, `metric_key`, `value`)
  SELECT `id`, 'humidity',         `humidity`      FROM `measurements` WHERE `humidity`       IS NOT NULL;

INSERT IGNORE INTO `measurement_values` (`measurement_id`, `metric_key`, `value`)
  SELECT `id`, 'rel_pressure',     `rel_pressure`  FROM `measurements` WHERE `rel_pressure`   IS NOT NULL;

INSERT IGNORE INTO `measurement_values` (`measurement_id`, `metric_key`, `value`)
  SELECT `id`, 'abs_pressure',     `abs_pressure`  FROM `measurements` WHERE `abs_pressure`   IS NOT NULL;

INSERT IGNORE INTO `measurement_values` (`measurement_id`, `metric_key`, `value`)
  SELECT `id`, 'battery_pct',      `battery_pct`   FROM `measurements` WHERE `battery_pct`    IS NOT NULL;

INSERT IGNORE INTO `measurement_values` (`measurement_id`, `metric_key`, `value`)
  SELECT `id`, 'battery_volt',     `battery_volt`  FROM `measurements` WHERE `battery_volt`   IS NOT NULL;

INSERT IGNORE INTO `measurement_values` (`measurement_id`, `metric_key`, `value`)
  SELECT `id`, 'wifi_strength',    `wifi_strength` FROM `measurements` WHERE `wifi_strength`  IS NOT NULL;

INSERT IGNORE INTO `measurement_values` (`measurement_id`, `metric_key`, `value`)
  SELECT `id`, 'heat_index',       `heat_index`    FROM `measurements` WHERE `heat_index`     IS NOT NULL;

INSERT IGNORE INTO `measurement_values` (`measurement_id`, `metric_key`, `value`)
  SELECT `id`, 'dewpoint',         `dewpoint`      FROM `measurements` WHERE `dewpoint`       IS NOT NULL;

INSERT IGNORE INTO `measurement_values` (`measurement_id`, `metric_key`, `value`)
  SELECT `id`, 'trend_value',      `trend_value`   FROM `measurements` WHERE `trend_value`    IS NOT NULL;

-- ----------------------------------------------------------
-- 6. Backend-Tabellen (users, push_tokens, invite_codes)
--    Anlegen falls noch nicht vorhanden
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `users` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `email`         VARCHAR(255) NOT NULL UNIQUE,
  `password_hash` VARCHAR(255) NOT NULL,
  `role`          ENUM('user','admin') NOT NULL DEFAULT 'user',
  `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `push_tokens` (
  `token`      VARCHAR(255) NOT NULL,
  `user_id`    INT UNSIGNED NOT NULL,
  `updated_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`token`),
  KEY `idx_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `invite_codes` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `code`       VARCHAR(32)  NOT NULL UNIQUE,
  `created_by` INT UNSIGNED NOT NULL DEFAULT 0,
  `used_by`    INT UNSIGNED NULL,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `used_at`    DATETIME     NULL,
  PRIMARY KEY (`id`),
  KEY `idx_code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- Migration abgeschlossen.
-- Alte Spalten in measurements können nach Verifikation
-- mit ALTER TABLE measurements DROP COLUMN ... entfernt werden.
-- ============================================================

-- ----------------------------------------------------------
-- Bestehende users-Tabelle: role-Spalte nachrüsten (idempotent)
-- ----------------------------------------------------------
ALTER TABLE `users`
  ADD COLUMN IF NOT EXISTS `role` ENUM('user','admin') NOT NULL DEFAULT 'user' AFTER `password_hash`;

-- ----------------------------------------------------------
-- Nachträgliche Korrekturen (idempotent ausführbar)
-- ----------------------------------------------------------
-- value-Spalte auf VARCHAR erweitern damit String-Metriken
-- (pressure_state, zambretti, trend) gespeichert werden können.
ALTER TABLE `measurement_values`
  MODIFY COLUMN `value` VARCHAR(255) NOT NULL;

-- ----------------------------------------------------------
-- Alte measurements-Spalten nullable machen damit EAV-INSERTs
-- (ohne diese Felder) nicht mit "doesn't have a default value"
-- scheitern. Daten bleiben erhalten.
-- ----------------------------------------------------------
ALTER TABLE `measurements`
  MODIFY COLUMN `temperature`      DOUBLE       NULL,
  MODIFY COLUMN `pool_temperature` DOUBLE       NULL,
  MODIFY COLUMN `humidity`         DOUBLE       NULL,
  MODIFY COLUMN `rel_pressure`     DOUBLE       NULL,
  MODIFY COLUMN `abs_pressure`     DOUBLE       NULL,
  MODIFY COLUMN `pressure_state`   VARCHAR(50)  NULL,
  MODIFY COLUMN `zambretti`        VARCHAR(100) NULL,
  MODIFY COLUMN `trend`            VARCHAR(50)  NULL,
  MODIFY COLUMN `battery_volt`     DOUBLE       NULL,
  MODIFY COLUMN `battery_pct`      TINYINT      NULL,
  MODIFY COLUMN `wifi_strength`    INT          NULL,
  MODIFY COLUMN `heat_index`       DOUBLE       NULL,
  MODIFY COLUMN `dewpoint`         DOUBLE       NULL,
  MODIFY COLUMN `trend_value`     DOUBLE       NULL,
  MODIFY COLUMN `dewpoint_spread` DECIMAL(5,2) NULL;

-- ----------------------------------------------------------
-- Migration v2.2 – role-Spalte in users (idempotent)
-- Bestehende Installationen: role-Spalte nachträglich hinzufügen.
-- Bereits vorhandene Admins müssen danach im Admin-Dashboard
-- auf role='admin' gesetzt werden.
-- ----------------------------------------------------------
ALTER TABLE `users`
  ADD COLUMN IF NOT EXISTS `role` ENUM('user','admin') NOT NULL DEFAULT 'user'
  AFTER `password_hash`;

-- ----------------------------------------------------------
-- Migration v2.3 – Remote-Config: settings-Spalte in stations (idempotent)
-- ----------------------------------------------------------
ALTER TABLE `stations`
  ADD COLUMN IF NOT EXISTS `settings` JSON NULL
  COMMENT 'Remote-Config: sleep_min, temp_corr, elevation, api_path'
  AFTER `api_key`;

CREATE TABLE IF NOT EXISTS `station_errors` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `station_id` INT UNSIGNED    NOT NULL,
  `level`      ENUM('error','warning','info') NOT NULL DEFAULT 'error'
                 COMMENT 'Schweregrad: error = kritisch, warning = Warnung, info = Information',
  `code`       VARCHAR(32)     NOT NULL
                 COMMENT 'Maschinenlesbarer Kurzcode, z.B. DS18B20_FAIL, BUFFER_OVERFLOW, HTTP_ERROR',
  `message`    VARCHAR(255)    NOT NULL
                 COMMENT 'Menschenlesbare Fehlerbeschreibung',
  `context`    JSON            NULL
                 COMMENT 'Optionale Zusatzdaten als JSON (z.B. HTTP-Code, Sensorwert)',
  `created_at` TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_station_created` (`station_id`, `created_at`),
  CONSTRAINT `fk_errors_station`
    FOREIGN KEY (`station_id`) REFERENCES `stations` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

