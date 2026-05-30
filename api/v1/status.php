<?php
/**
 * v1/status.php – Health-Check (öffentlich)
 *
 * GET /v1/status?station=<slug>
 */

declare(strict_types=1);

$db      = getDb();
$slug    = $_GET['station'] ?? null;
$station = resolveStation($db, $slug);

if (!$station) {
	sendJson(200, ['status' => 'no_station', 'fresh' => false]);
}

$row = $db->prepare('SELECT created_at FROM measurements WHERE station_id = ? ORDER BY created_at DESC LIMIT 1');
$row->execute([$station['id']]);
$last = $row->fetch();

if (!$last) {
	sendJson(200, ['status' => 'no_data', 'station' => $station['slug'], 'fresh' => false]);
}

$ageS  = (int)(time() - strtotime($last['created_at']));
$fresh = $ageS < (3 * 3600); // älter als 3 Stunden = stale

sendJson(200, [
	'status'       => 'ok',
	'station'      => $station['slug'],
	'station_name' => $station['name'],
	'last_seen_s'  => $ageS,
	'fresh'        => $fresh,
	'created_at'   => $last['created_at'],
]);

// resolveStation() ist in v1/helpers.php definiert
