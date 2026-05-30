<?php
/**
 * v1/history.php – Verlaufsdaten (Basic Auth)
 *
 * GET /v1/history?station=<slug>&from=YYYY-MM-DD&to=YYYY-MM-DD&limit=100&metrics=temperature,humidity
 *
 * Response:
 * {
 *   "station": "sws-garten",
 *   "count": 42,
 *   "from": "2025-06-01",
 *   "to":   "2025-06-07",
 *   "metrics": ["temperature","humidity",...],
 *   "data": [
 *     {"created_at":"2025-06-01 08:00:00", "temperature":21.5, "humidity":55.2, ...},
 *     ...
 *   ]
 * }
 */

declare(strict_types=1);

requireBasicAuth();

$db      = getDb();
$slug    = $_GET['station'] ?? null;
$station = resolveStation($db, $slug);
if (!$station) {
	sendJson(404, ['error' => 'Station nicht gefunden']);
}

$limit   = min((int)($_GET['limit'] ?? 100), 1000);
$from    = $_GET['from'] ?? null;
$to      = $_GET['to']   ?? null;
$metricFilter = isset($_GET['metrics'])
	? array_filter(array_map('trim', explode(',', $_GET['metrics'])))
	: null;

// Messungen im Zeitraum laden
$where  = ['m.station_id = :sid'];
$params = [':sid' => $station['id']];

if ($from) { $where[] = 'DATE(m.created_at) >= :from'; $params[':from'] = $from; }
if ($to)   { $where[] = 'DATE(m.created_at) <= :to';   $params[':to']   = $to;   }

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
		'metrics' => [],
		'data'    => [],
	]);
}

$ids = array_column($measurements, 'id');
$placeholders = implode(',', array_fill(0, count($ids), '?'));

// Alle Werte für diese Messungen laden
$valSql = "
	SELECT mv.measurement_id, mv.metric_key, mv.value
	FROM   measurement_values mv
	WHERE  mv.measurement_id IN ($placeholders)
";
if ($metricFilter) {
	$mp = implode(',', array_fill(0, count($metricFilter), '?'));
	$valSql .= " AND mv.metric_key IN ($mp)";
	$valStmt = $db->prepare($valSql);
	$valStmt->execute(array_merge($ids, array_values($metricFilter)));
} else {
	$valStmt = $db->prepare($valSql);
	$valStmt->execute($ids);
}

// Werte den Messungen zuordnen
$valueMap = [];
$allMetrics = [];
foreach ($valStmt->fetchAll() as $row) {
	$valueMap[$row['measurement_id']][$row['metric_key']] = (float)$row['value'];
	$allMetrics[$row['metric_key']] = true;
}

// Ausgabe aufbauen (chronologisch sortiert)
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
	'metrics' => array_keys($allMetrics),
	'data'    => $data,
]);

// resolveStation() ist in v1/helpers.php definiert
