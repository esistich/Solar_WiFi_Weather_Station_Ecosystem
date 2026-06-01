<?php
/**
 * config/config.example.php – Vorlage für config.php.
 *
 * Kopiere diese Datei als config.php und trage die echten Werte ein.
 * config.php wird NICHT committet und NICHT deployt.
 *
 * Auf dem Server: config.php manuell in api/config/ ablegen.
 */

// ------------------------------------------------------------------
// Datenbank
// ------------------------------------------------------------------
define('DB_HOST',    'localhost');
define('DB_NAME',    'dein_datenbankname');
define('DB_USER',    'dein_datenbankbenutzer');
define('DB_PASS',    'dein_datenbankpasswort');
define('DB_CHARSET', 'utf8mb4');

// ------------------------------------------------------------------
// HTTP Basic Auth – muss mit Settings26.h der Station übereinstimmen
// ------------------------------------------------------------------
define('API_USER', 'dein_api_benutzer');
define('API_PASS', 'dein_api_passwort');

// ------------------------------------------------------------------
// JWT für Flutter-App (mind. 32 zufällige Zeichen)
// php -r "echo bin2hex(random_bytes(32));"
// ------------------------------------------------------------------
define('JWT_SECRET_VALUE', 'mindestens_32_zufaellige_zeichen_hier_eintragen');
define('JWT_TTL',          30 * 24 * 3600); // 30 Tage in Sekunden

// ------------------------------------------------------------------
// Admin-Dashboard Login (Fallback bis DB-Admin angelegt ist)
// Hash erzeugen: php -r "echo password_hash('NeuesPasswort', PASSWORD_BCRYPT);"
// ------------------------------------------------------------------
define('ADMIN_USER',      'admin');
define('ADMIN_PASS_HASH', '$2y$10$ERSETZE_DIESEN_HASH_MIT_EINEM_ECHTEN_BCRYPT_HASH.........');
