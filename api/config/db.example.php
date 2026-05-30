<?php
/**
 * config/db.example.php – Vorlage ohne echte Credentials.
 * Kopieren als db.php und Werte anpassen.
 */

define('DB_HOST',    'localhost');
define('DB_NAME',    'deine_datenbank');
define('DB_USER',    'dein_db_user');
define('DB_PASS',    'dein_db_passwort');
define('DB_CHARSET', 'utf8mb4');

function getDb(): PDO
{
	static $pdo = null;
	if ($pdo === null) {
		$dsn = sprintf('mysql:host=%s;dbname=%s;charset=%s', DB_HOST, DB_NAME, DB_CHARSET);
		$pdo = new PDO($dsn, DB_USER, DB_PASS, [
			PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
			PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
			PDO::ATTR_EMULATE_PREPARES   => false,
		]);
	}
	return $pdo;
}
