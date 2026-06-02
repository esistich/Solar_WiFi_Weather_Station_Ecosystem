<?php
/**
 * api/v1/index.php – zentraler Router der SWS API v1.
 *
 * Routen:
 *   GET  /v1/data                  – letzter Messdatensatz (öffentlich)
 *   POST /v1/data                  – Messdaten speichern (Basic Auth)
 *   GET  /v1/history               – Verlaufsdaten (JWT Bearer)
 *   GET  /v1/status                – Health-Check (öffentlich)
 *   GET  /v1/stations              – Stationsliste (JWT Bearer)
 *   GET  /v1/metrics               – Metrik-Definitionen (öffentlich)
 *   GET  /v1/zambretti             – Zambretti-Prognose (öffentlich)
 *   GET|POST /v1/log               – Stations-Fehlerlog (öffentlich GET, Basic Auth POST)
 *   POST /v1/auth/register         – App-Benutzer registrieren (Einladungscode)
 *   POST /v1/auth/login            – App-Login → JWT
 *   POST /v1/auth/logout           – App-Logout (JWT Bearer)
 *   POST /v1/push/register         – FCM-Push-Token registrieren (JWT Bearer)
 *   POST /v1/push/unregister       – FCM-Push-Token entfernen (JWT Bearer)
 *   POST /v1/invite/create         – Einladungscode erstellen (Admin-Session)
 *   GET  /v1/invite/list           – Einladungscodes auflisten (Admin-Session)
 */

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

$configDir = dirname(__DIR__) . '/config';
require_once $configDir . '/config.php';
require_once $configDir . '/db.php';
require_once $configDir . '/auth.php';
require_once $configDir . '/jwt.php';
require_once __DIR__ . '/helpers.php';

// Pfad ermitteln
// Fallback: ?r=route falls mod_rewrite nicht greift
$uri    = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
$uri    = preg_replace('#^.*?/v1#', '', $uri);
$uri    = '/' . trim($uri, '/');
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

// Query-String-Fallback: /v1/index.php?r=status → /status
if ($uri === '/' || $uri === '/index.php') {
    $r = trim($_GET['r'] ?? '', '/');
    if ($r !== '') $uri = '/' . $r;
}

sendCorsHeaders();

// Routing-Tabelle
$routes = [
	'GET /data'            => __DIR__ . '/data.php',
	'POST /data'           => __DIR__ . '/data.php',
	'GET /config'          => __DIR__ . '/config.php',
	'GET /history'         => __DIR__ . '/history.php',
	'GET /status'          => __DIR__ . '/status.php',
	'GET /zambretti'       => __DIR__ . '/zambretti.php',
	'GET /log'             => __DIR__ . '/log.php',
	'POST /log'            => __DIR__ . '/log.php',
	'GET /stations'        => __DIR__ . '/stations.php',
	'POST /auth/register'  => __DIR__ . '/auth/register.php',
	'POST /auth/login'     => __DIR__ . '/auth/login.php',
	'POST /auth/logout'    => __DIR__ . '/auth/logout.php',
	// Alias-Routen (WAF-freundlich, identische Handler)
	'POST /user/signin'    => __DIR__ . '/auth/login.php',
	'POST /user/signup'    => __DIR__ . '/auth/register.php',
	'POST /user/signout'   => __DIR__ . '/auth/logout.php',
	'POST /push/register'  => __DIR__ . '/auth/push_register.php',
	'POST /push/unregister' => __DIR__ . '/auth/push_unregister.php',
	'POST /invite/create'  => __DIR__ . '/auth/invite_create.php',
	'GET /invite/list'     => __DIR__ . '/auth/invite_list.php',
	'GET /metrics'              => __DIR__ . '/metrics.php',
	'PATCH /admin/stations'     => __DIR__ . '/admin/stations.php',
];

$key = "$method $uri";
if (isset($routes[$key]) && file_exists($routes[$key])) {
	require $routes[$key];
	exit;
}

// 404
http_response_code(404);
echo json_encode(['error' => "Unbekannte Route: $method $uri"], JSON_UNESCAPED_UNICODE);
