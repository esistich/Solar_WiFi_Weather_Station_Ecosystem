<?php
/**
 * index.php – zentraler Einstiegspunkt für /api/backend/
 * Leitet anhand des GET-Parameters `route` weiter.
 *
 * Routen:
 *   /api/backend/?route=auth&action=register|login|logout
 *   /api/backend/?route=push&action=register|unregister|send
 */

$route = $_GET['route'] ?? '';

match ($route) {
	'auth'    => require __DIR__ . '/auth.php',
	'push'    => require __DIR__ . '/push.php',
	'diag'    => (function () {
		header('Content-Type: application/json; charset=utf-8');
		// Diagnose: push.php Syntax und Abhängigkeiten prüfen
		$saFile = __DIR__ . '/../swsfb-11c77-firebase-adminsdk-fbsvc-7dc4d2384c.json';
		$jwtFile = __DIR__ . '/../jwt_secret.php';
		echo json_encode([
			'php_version'       => PHP_VERSION,
			'openssl'           => extension_loaded('openssl'),
			'pdo_mysql'         => extension_loaded('pdo_mysql'),
			'sa_file_exists'    => file_exists($saFile),
			'sa_file_readable'  => is_readable($saFile),
			'jwt_secret_exists' => file_exists($jwtFile),
			'push_php_exists'   => file_exists(__DIR__ . '/push.php'),
		]);
	})(),
	default => (function () use ($route) {
		header('Content-Type: application/json; charset=utf-8');
		http_response_code(404);
		echo json_encode(['error' => "Unbekannte Route: $route"]);
	})(),
};
