<?php
/**
 * config/auth.example.php – Vorlage ohne echte Credentials.
 * Kopieren als auth.php und alle Werte ersetzen.
 */

define('API_USER', 'dein_station_user');
define('API_PASS', 'dein_station_passwort');

define('JWT_SECRET_VALUE', 'MINDESTENS_32_ZUFAELLIGE_ZEICHEN_HIER_EINTRAGEN');
define('JWT_TTL',          30 * 24 * 3600);

// Admin-Passwort: php -r "echo password_hash('dein_passwort', PASSWORD_BCRYPT);"
define('ADMIN_USER',      'admin');
define('ADMIN_PASS_HASH', '$2y$10$BEISPIEL_HASH_HIER_EINTRAGEN');

function sendCorsHeaders(): void
{
	header('Access-Control-Allow-Origin: *');
	header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
	header('Access-Control-Allow-Headers: Authorization, Content-Type');
	if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
		http_response_code(204);
		exit;
	}
}

function requireBasicAuth(): void
{
	$user = $_SERVER['PHP_AUTH_USER'] ?? '';
	$pass = $_SERVER['PHP_AUTH_PW']   ?? '';
	if (!hash_equals(API_USER, $user) || !hash_equals(API_PASS, $pass)) {
		header('WWW-Authenticate: Basic realm="Solar Weather Station"');
		http_response_code(401);
		echo json_encode(['error' => 'Nicht autorisiert'], JSON_UNESCAPED_UNICODE);
		exit;
	}
}

function sendJson(int $status, array $data): void
{
	if ($status !== 200) {
		$data['http_status'] = $status;
		http_response_code(200);
	}
	echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
	exit;
}
