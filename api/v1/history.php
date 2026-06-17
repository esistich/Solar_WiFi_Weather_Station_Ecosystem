<?php
/**
 * v1/history.php – Verlaufsdaten (Basic Auth)
 *
 * GET /v1/history?station=<slug>&from=YYYY-MM-DDTHH:MM:SS&to=YYYY-MM-DDTHH:MM:SS&limit=100
 */

declare(strict_types=1);

requireJwt();

$db      = getDb();
$slug    = $_GET['station'] ?? null;
$station = resolveStation($db, $slug);
if (!$station) {
	sendJson(404, ['error' => 'Station nicht gefunden']);
}

$limit   = min((int)($_GET['limit'] ?? 100), 2000);
$from    = $_GET['from'] ?? null;
$to      = $_GET['to']   ?? null;
$metricFilter = isset($_GET['metrics'])
	? array_filter(array_map('trim', explode(',', $_GET['metrics'])))
	: null;

// Messungen im Zeitraum laden - DATE() entfernt für Präzision
$where  = ['m.station_id = :sid'];
$params = [':sid' => $station['id']];

if ($from) {
    $fromClean = str_replace('T', ' ', $from);
    $where[] = 'm.created_at >= :from';
    $params[':from'] = $fromClean;
}
if ($to) {
    $toClean = str_replace('T', ' ', $to);
    $where[] = 'm.created_at <= :to';
    $params[':to'] = $toClean;
}

$sql = 'SELECT id, created_at FROM measurements m WHERE '
	 . implode(' AND ', $where)
	 . ' ORDER BY created_at DESC LIMIT ' . $limit;

$stmt = $db->prepare($sql);
$stmt->execute($params);
$measurements = $stmt->fetchAll();

if (empty($measurements)) {
	sendJson(200, [
		'station' => $station['slug'],
		'count'   => 0,
		'from'    => $from,
		'to'      => $to,
		'data'    => [],
	]);
}

$ids = array_column($measurements, 'id');
$placeholders = implode(',', array_fill(0, count($ids), '?'));

$valSql = "
	SELECT mv.measurement_id, mv.metric_key, mv.value
	FROM   measurement_values mv
	WHERE  mv.measurement_id IN ($placeholders)
";
$valStmt = $db->prepare($valSql);
$valStmt->execute($ids);

$valueMap = [];
$allMetrics = [];
foreach ($valStmt->fetchAll() as $row) {
	$valueMap[$row['measurement_id']][$row['metric_key']] = (float)$row['value'];
	$allMetrics[$row['metric_key']] = true;
}

$data = [];
foreach (array_reverse($measurements) as $m) {
	$entry = ['created_at' => $m['created_at']];
	foreach (array_keys($allMetrics) as $key) {
		$entry[$key] = $valueMap[$m['id']][$key] ?? null;
	}
	$data[] = $entry;
}

sendJson(200, [
	'station' => $station['slug'],
	'count'   => count($data),
	'from'    => $from,
	'to'      => $to,
	'data'    => $data,
]);
