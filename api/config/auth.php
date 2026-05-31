<?php
/**
 * config/auth.php – zentrale Auth-Konfiguration.
 *
 * Basic-Auth-Credentials für die Station (POST /v1/data),
 * JWT-Secret für die App-Backend-Auth,
 * Admin-Session-Passwort für das Web-Dashboard.
 *
 * Credentials werden aus credentials.php geladen (nicht im Git).
 * Vorlage: credentials.example.php
 */

// Credentials aus externer Datei laden (nicht committen!)
$_credFile = __DIR__ . '/credentials.php';
if (!file_exists($_credFile)) {
    http_response_code(500);
    echo json_encode(['error' => 'Serverkonfiguration unvollständig: credentials.php fehlt']);
    exit;
}
require_once $_credFile;
unset($_credFile);

/**
 * CORS-Header für alle API-Endpunkte.
 */
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

/**
 * HTTP Basic Auth prüfen. Bricht mit 401 ab wenn nicht autorisiert.
 */
function requireBasicAuth(): void
{
	$user = $_SERVER['PHP_AUTH_USER'] ?? '';
	$pass = $_SERVER['PHP_AUTH_PW']   ?? '';

	// Fallback fuer CGI/FastCGI wo PHP_AUTH_* nicht gesetzt wird
	if ($user === '') {
		$authHeader = $_SERVER['HTTP_AUTHORIZATION']
			?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
			?? '';
		if ($authHeader !== '' && stripos($authHeader, 'Basic ') === 0) {
			$decoded = base64_decode(substr($authHeader, 6));
			$parts   = explode(':', $decoded, 2);
			$user    = $parts[0] ?? '';
			$pass    = $parts[1] ?? '';
		}
	}

	if (!hash_equals(API_USER, $user) || !hash_equals(API_PASS, $pass)) {
		header('WWW-Authenticate: Basic realm="Solar Weather Station"');
		http_response_code(401);
		echo json_encode(['error' => 'Nicht autorisiert'], JSON_UNESCAPED_UNICODE);
		exit;
	}
}

/**
 * JSON-Antwort senden.
 */
function sendJson(int $status, array $data): void
{
	if ($status !== 200) {
		$data['http_status'] = $status;
		http_response_code(200); // Varnish-kompatibler Workaround
	}
	echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
	exit;
}
