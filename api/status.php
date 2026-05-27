<?php
/**
 * status.php – Health-Endpoint der Solar WiFi Weather Station API
 *
 * Kein Auth erforderlich – dient als Watchdog für Home Assistant.
 *
 * GET /api/status.php
 *
 * Response:
 *   {
 *     "status":       "ok",
 *     "last_seen_s":  387,       // Sekunden seit letzter Messung
 *     "fresh":        true,      // false wenn älter als STALE_THRESHOLD_S
 *     "station_name": "SWS_...",
 *     "created_at":   "2025-06-01 12:00:00"
 *   }
 *
 * fresh = false wenn last_seen_s > STALE_THRESHOLD_S (Standard: 3× Sleep-Intervall).
 * Home Assistant kann darüber eine Offline-Warnung auslösen.
 */

declare(strict_types=1);

require_once __DIR__ . '/auth.php';   // sendCorsHeaders()
require_once __DIR__ . '/db.php';

// Schwellwert in Sekunden: nach dieser Zeit gilt die Station als "stale".
// Empfehlung: 3 × Sleep-Intervall (z.B. 3 × 600s = 1800s)
define('STALE_THRESHOLD_S', 1800);

header('Content-Type: application/json; charset=utf-8');
sendCorsHeaders();

try {
	$pdo  = getDb();
	$stmt = $pdo->query(
		'SELECT station_name, created_at FROM measurements ORDER BY id DESC LIMIT 1'
	);
	$row = $stmt->fetch();

	if ($row === false) {
		http_response_code(200);
		echo json_encode([
			'status'       => 'no_data',
			'last_seen_s'  => null,
			'fresh'        => false,
			'station_name' => null,
			'created_at'   => null,
		], JSON_UNESCAPED_UNICODE);
		exit;
	}

	$age = (int)(time() - strtotime($row['created_at']));

	http_response_code(200);
	echo json_encode([
		'status'       => 'ok',
		'last_seen_s'  => $age,
		'fresh'        => $age <= STALE_THRESHOLD_S,
		'station_name' => $row['station_name'],
		'created_at'   => $row['created_at'],
	], JSON_UNESCAPED_UNICODE);

} catch (PDOException $e) {
	http_response_code(200);
	echo json_encode([
		'status' => 'db_error',
		'error'  => $e->getMessage(),
	], JSON_UNESCAPED_UNICODE);
}
