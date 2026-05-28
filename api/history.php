<?php
/**
 * history.php – Historien-Endpunkt der Solar WiFi Weather Station API
 *
 * GET /api/history.php                      → letzte 100 Einträge
 * GET /api/history.php?limit=50             → letzte 50 Einträge
 * GET /api/history.php?from=2025-01-01      → ab diesem Datum (bis heute)
 * GET /api/history.php?to=2025-06-30        → bis zu diesem Datum
 * GET /api/history.php?from=2025-01-01&to=2025-06-30&limit=500
 *
 * Parameter:
 *   limit  – Anzahl Datensätze (Standard: 100, Maximum: 1000)
 *   from   – Startdatum YYYY-MM-DD (inklusiv, bezogen auf created_at)
 *   to     – Enddatum  YYYY-MM-DD (inklusiv, bezogen auf created_at)
 *
 * Authentifizierung: HTTP Basic Auth (Credentials aus auth.php)
 *
 * Response:
 *   {
 *     "count": 42,
 *     "limit": 100,
 *     "from":  "2025-01-01",   // null wenn nicht angegeben
 *     "to":    "2025-06-30",   // null wenn nicht angegeben
 *     "data":  [ { ... }, ... ]
 *   }
 */

declare(strict_types=1);

require_once __DIR__ . '/lib/auth.php';   // Credentials + requireBasicAuth()
require_once __DIR__ . '/lib/db.php';

header('Content-Type: application/json; charset=utf-8');
sendCorsHeaders();

// Nur GET erlaubt
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
	http_response_code(405);
	echo json_encode(['error' => 'Methode nicht erlaubt'], JSON_UNESCAPED_UNICODE);
	exit;
}

requireBasicAuth();

// ---- Parameter einlesen & validieren ------------------------------------

$limit = 100;
if (isset($_GET['limit'])) {
	$limit = (int)$_GET['limit'];
	if ($limit < 1)    $limit = 1;
	if ($limit > 1000) $limit = 1000;
}

$from = null;
if (isset($_GET['from']) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $_GET['from'])) {
	$from = $_GET['from'];
}

$to = null;
if (isset($_GET['to']) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $_GET['to'])) {
	$to = $_GET['to'];
}

// ---- Abfrage aufbauen ---------------------------------------------------

$where  = [];
$params = [];

if ($from !== null) {
	$where[]        = 'created_at >= :from';
	$params[':from'] = $from . ' 00:00:00';
}
if ($to !== null) {
	$where[]      = 'created_at <= :to';
	$params[':to'] = $to . ' 23:59:59';
}

$whereClause = count($where) > 0 ? 'WHERE ' . implode(' AND ', $where) : '';

$sql = "SELECT * FROM measurements
		$whereClause
		ORDER BY id DESC
		LIMIT :limit";

// ---- Ausführen ----------------------------------------------------------

try {
	$pdo  = getDb();
	$stmt = $pdo->prepare($sql);

	// limit muss als INT gebunden werden (PDO behandelt sonst als String)
	$stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
	foreach ($params as $key => $value) {
		$stmt->bindValue($key, $value);
	}

	$stmt->execute();
	$rows = $stmt->fetchAll();

	// Numerische Felder casten
	foreach ($rows as &$row) {
		$row['id']               = (int)   $row['id'];
		$row['temperature']      = (float) $row['temperature'];
		$row['pool_temperature'] = isset($row['pool_temperature']) ? (float) $row['pool_temperature'] : null;
		$row['humidity']         = (float) $row['humidity'];
		$row['heat_index']       = (float) $row['heat_index'];
		$row['dewpoint']         = (float) $row['dewpoint'];
		$row['dewpoint_spread']  = (float) $row['dewpoint_spread'];
		$row['abs_pressure']     = (float) $row['abs_pressure'];
		$row['rel_pressure']     = (int)   $row['rel_pressure'];
		$row['trend_value']      = (float) $row['trend_value'];
		$row['accuracy']         = (int)   $row['accuracy'];
		$row['battery_volt']     = (float) $row['battery_volt'];
		$row['battery_pct']      = (int)   $row['battery_pct'];
		$row['wifi_strength']    = (int)   $row['wifi_strength'];
		$row['device_timestamp'] = (int)   $row['device_timestamp'];
	}
	unset($row);

	http_response_code(200);
	echo json_encode([
		'count' => count($rows),
		'limit' => $limit,
		'from'  => $from,
		'to'    => $to,
		'data'  => $rows,
	], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

} catch (PDOException $e) {
	http_response_code(500);
	echo json_encode(
		['error' => 'Datenbankfehler: ' . $e->getMessage()],
		JSON_UNESCAPED_UNICODE
	);
}
