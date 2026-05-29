<?php
/**
 * index.php - zentraler Einstiegspunkt fuer /api/backend/
 * Routen: ?route=auth&action=register|login|logout
 *         ?route=push&action=register|unregister|send
 *         ?route=invite&action=create|list
 */
$route = $_GET['route'] ?? '';
match ($route) {
    'auth'   => require __DIR__ . '/auth.php',
    'push'   => require __DIR__ . '/push.php',
    'invite' => require __DIR__ . '/invite.php',
    default  => (function () use ($route) {
        header('Content-Type: application/json; charset=utf-8');
        http_response_code(404);
        echo json_encode(['error' => "Unbekannte Route: $route"]);
    })(),
};