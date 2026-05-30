<?php
/**
 * status.php – Kompatibilitaets-Shim (Legacy-Pfad /api/status.php)
 * Neuer kanonischer Endpunkt: /v1/status
 */
declare(strict_types=1);
require_once __DIR__ . '/config/db.php';
require_once __DIR__ . '/config/auth.php';
require_once __DIR__ . '/config/jwt.php';
require_once __DIR__ . '/v1/helpers.php';
header('Content-Type: application/json; charset=utf-8');
sendCorsHeaders();
require __DIR__ . '/v1/status.php';
