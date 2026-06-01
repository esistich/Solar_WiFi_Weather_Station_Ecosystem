<?php
/**
 * config/auth.php - Auth-Hilfsfunktionen.
 * Enthaelt KEINE Secrets - alle Konstanten kommen aus config.php.
 * Diese Datei ist deploybar.
 */

function sendJson(int $status, array $data): void
{
http_response_code($status);
header('Content-Type: application/json; charset=utf-8');
echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
exit;
}

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
if ($user === '') {
$authHeader = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
if ($authHeader !== '' && stripos($authHeader, 'Basic ') === 0) {
$decoded = base64_decode(substr($authHeader, 6));
$parts   = explode(':', $decoded, 2);
$user    = $parts[0] ?? '';
$pass    = $parts[1] ?? '';
}
}
if (!hash_equals(API_USER, $user) || !hash_equals(API_PASS, $pass)) {
header('WWW-Authenticate: Basic realm="Solar Weather Station"');
sendJson(401, ['error' => 'Nicht autorisiert']);
}
}