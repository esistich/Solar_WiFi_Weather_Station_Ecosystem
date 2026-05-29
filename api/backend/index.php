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
	default   => (function () use ($route) {
		header('Content-Type: application/json; charset=utf-8');
		http_response_code(404);
		echo json_encode(['error' => "Unbekannte Route: $route"]);
	})(),
};
