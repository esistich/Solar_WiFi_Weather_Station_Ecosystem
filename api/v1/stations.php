<?php
/**
 * v1/stations.php – Stationsliste (Basic Auth)
 *
 * GET /v1/stations
 */

declare(strict_types=1);

requireBasicAuth();

$db   = getDb();
$rows = $db->query('SELECT id, slug, name, created_at FROM stations ORDER BY id')->fetchAll();

sendJson(200, ['stations' => $rows]);
