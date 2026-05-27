<?php
/**
 * db.php – PDO-Datenbankverbindung
 *
 * Anpassen:
 *   DB_HOST  – Hostname des MySQL-Servers (oft "localhost")
 *   DB_NAME  – Name der Datenbank (z.B. "solarweather")
 *   DB_USER  – MySQL-Benutzername
 *   DB_PASS  – MySQL-Passwort
 *
 * Sicherheitshinweis: Diese Datei NICHT ins Web-Root legen, sondern
 * eine Ebene darüber oder per .htaccess vor Direktzugriff schützen:
 *   <Files "db.php">
 *       Require all denied
 *   </Files>
 */

define('DB_HOST', 'localhost');
define('DB_NAME', 'solarweather');
define('DB_USER', 'YOUR_DB_USER');
define('DB_PASS', 'YOUR_DB_PASS');
define('DB_CHARSET', 'utf8mb4');

/**
 * Gibt eine PDO-Verbindung zurück (Singleton).
 */
function getDb(): PDO
{
	static $pdo = null;

	if ($pdo === null) {
		$dsn = sprintf(
			'mysql:host=%s;dbname=%s;charset=%s',
			DB_HOST,
			DB_NAME,
			DB_CHARSET
		);
		$options = [
			PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
			PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
			PDO::ATTR_EMULATE_PREPARES   => false,
		];
		$pdo = new PDO($dsn, DB_USER, DB_PASS, $options);
	}

	return $pdo;
}
