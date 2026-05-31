<?php
declare(strict_types=1);

/**
 * v1/log.php – Fehler-Log der Stationen
 *
 * POST /v1/log  – Fehler/Warnung/Info einer Station speichern (Basic Auth)
 *   Body (JSON):
 *   {
 *     "station_slug": "sws-main",   // optional, default: erste Station
 *     "level":        "error",      // "error" | "warning" | "info"  (default: "error")
 *     "code":         "DS18B20_FAIL",
 *     "message":      "Sensor lieferte keinen gueltigen Wert",
 *     "context":      { "attempt": 3, "raw": -127 }  // optional
 *   }
 *
 * GET /v1/log?station=<slug>&level=error&limit=50&from=<ISO>&to=<ISO>
 *   – Eintraege lesen (oeffentlich, kein Auth erforderlich)
 *   – Gibt neueste Eintraege zuerst zurueck
 */

$db = getDb();

// ── POST: Fehler schreiben ────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
	requireBasicAuth();

	$raw  = $GLOBALS['_shimBody'] ?? json_decode(file_get_contents('php://input'), true);
	$body = is_array($raw) ? $raw : null;

	if (!$body) {
		sendJson(400, ['error' => 'Ungültiger JSON-Body']);
	}

	// Station auflösen
	$slug    = $body['station_slug'] ?? null;
	$station = resolveStation($db, $slug);
	if (!$station) {
		// Erste Station als Fallback (Station sendet evtl. noch keinen slug)
		$row = $db->query('SELECT id, slug, name FROM stations ORDER BY id LIMIT 1')->fetch();
		$station = $row ?: null;
	}
	if (!$station) {
		sendJson(404, ['error' => 'Keine Station gefunden']);
	}

	// Eingaben validieren und säubern
	$allowedLevels = ['error', 'warning', 'info'];
	$level   = in_array($body['level'] ?? '', $allowedLevels, true) ? $body['level'] : 'error';
	$code    = isset($body['code'])    ? substr(preg_replace('/[^A-Z0-9_]/i', '_', (string)$body['code']), 0, 32)    : 'UNKNOWN';
	$message = isset($body['message']) ? substr((string)$body['message'], 0, 255) : '';
	$context = null;

	if (!empty($body['context'])) {
		$encoded = json_encode($body['context']);
		$context = ($encoded !== false) ? $encoded : null;
	}

	$stmt = $db->prepare('
		INSERT INTO station_errors (station_id, level, code, message, context)
		VALUES (:sid, :level, :code, :msg, :ctx)
	');
	$stmt->execute([
		':sid'   => $station['id'],
		':level' => $level,
		':code'  => $code,
		':msg'   => $message,
		':ctx'   => $context,
	]);

	sendJson(201, ['ok' => true, 'id' => (int)$db->lastInsertId()]);
}

// ── GET: Fehler lesen ─────────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
	$slug    = $_GET['station'] ?? null;
	$station = resolveStation($db, $slug);
	if (!$station) {
		// Fallback: erste Station
		$row     = $db->query('SELECT id, slug, name FROM stations ORDER BY id LIMIT 1')->fetch();
		$station = $row ?: null;
	}
	if (!$station) {
		sendJson(404, ['error' => 'Keine Station gefunden']);
	}

	// Filter aufbauen
	$where  = ['e.station_id = :sid'];
	$params = [':sid' => $station['id']];

	$allowedLevels = ['error', 'warning', 'info'];
	if (!empty($_GET['level']) && in_array($_GET['level'], $allowedLevels, true)) {
		$where[]          = 'e.level = :level';
		$params[':level'] = $_GET['level'];
	}

	if (!empty($_GET['code'])) {
		$where[]         = 'e.code = :code';
		$params[':code'] = strtoupper(substr((string)$_GET['code'], 0, 32));
	}

	if (!empty($_GET['from'])) {
		$where[]        = 'e.created_at >= :from';
		$params[':from'] = $_GET['from'];
	}

	if (!empty($_GET['to'])) {
		$where[]      = 'e.created_at <= :to';
		$params[':to'] = $_GET['to'];
	}

	$limit = min(500, max(1, (int)($_GET['limit'] ?? 50)));

	$sql = 'SELECT e.id, e.level, e.code, e.message, e.context, e.created_at
			FROM   station_errors e
			WHERE  ' . implode(' AND ', $where) . '
			ORDER  BY e.created_at DESC
			LIMIT  ' . $limit;

	$stmt = $db->prepare($sql);
	$stmt->execute($params);
	$rows = $stmt->fetchAll();

	// created_at → Europe/Berlin, context → Array
	foreach ($rows as &$r) {
		$utc     = new DateTimeImmutable($r['created_at'], new DateTimeZone('UTC'));
		$r['created_at'] = $utc->setTimezone(new DateTimeZone('Europe/Berlin'))->format('Y-m-d H:i:s');
		$r['context']    = $r['context'] !== null ? json_decode($r['context'], true) : null;
		$r['id']         = (int)$r['id'];
	}
	unset($r);

	sendJson(200, [
		'station' => $station['slug'],
		'count'   => count($rows),
		'entries' => $rows,
	]);
}

sendJson(405, ['error' => 'Methode nicht erlaubt']);
