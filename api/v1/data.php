<?php
/**
 * v1/data.php – Messdaten-Endpunkt (dynamische Metriken via EAV)
 *
 * GET  /v1/data?station=<slug>   – letzter Messdatensatz (öffentlich)
 *                                  ohne station= → erste/einzige Station
 * POST /v1/data                  – neuen Messdatensatz speichern (Basic Auth)
 *
 * POST-Body (JSON) – alle Felder außer station_slug sind dynamisch:
 * {
 *   "station_slug": "sws-garten",   // optional, default: erste Station
 *   "device_ts":    1234567890,      // Unix-Timestamp des Geräts (optional)
 *   "temperature":  21.5,
 *   "humidity":     55.2,
 *   "rel_pressure": 1013.4,
 *   ...beliebig weitere Metriken...
 * }
 */

declare(strict_types=1);

$db = getDb();

// ── GET: letzter Messdatensatz ────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
	$slug    = $_GET['station'] ?? null;
	$station = resolveStation($db, $slug);
	if (!$station) {
		sendJson(404, ['error' => 'Station nicht gefunden']);
	}

	// Letzte Messung
	$meas = $db->prepare('
		SELECT id, created_at, device_ts
		FROM   measurements
		WHERE  station_id = ?
		ORDER  BY created_at DESC
		LIMIT  1
	');
	$meas->execute([$station['id']]);
	$row = $meas->fetch();

	if (!$row) {
		sendJson(200, ['station' => $station['slug'], 'data' => null]);
	}

	// created_at liegt in UTC – fuer Ausgabe in Europe/Berlin konvertieren
	$utcDt   = new DateTimeImmutable($row['created_at'], new DateTimeZone('UTC'));
	$localDt = $utcDt->setTimezone(new DateTimeZone('Europe/Berlin'));
	$row['created_at'] = $localDt->format('Y-m-d H:i:s');
	// data_age_s immer gegen UTC berechnen (time() ist UTC)
	$ageS = max(0, (int)(time() - $utcDt->getTimestamp()));

	$values = loadValues($db, $row['id']);

	sendJson(200, array_merge(
		['station' => $station['slug'], 'station_name' => $station['name']],
		$values,
		['created_at' => $row['created_at'], 'data_age_s' => $ageS]
	));
}

// ── POST: Messdaten speichern ─────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
	requireBasicAuth();

	// Shim hat den Body bereits gelesen und uebersetzt – Global bevorzugen
	$raw  = $GLOBALS['_shimBody'] ?? json_decode(file_get_contents('php://input'), true);
	$body = is_array($raw) ? $raw : null;

	if (!$body) {
		sendJson(400, ['error' => 'Ungültiger JSON-Body']);
	}

	// Station bestimmen / anlegen
	$slug    = $body['station_slug'] ?? null;
	$station = resolveStation($db, $slug);
	if (!$station) {
		// Automatisch anlegen wenn noch keine Station existiert
		$name = $body['station_name'] ?? ($slug ?? 'SWS Station 1');
		$slug = $slug ?? 'sws-' . substr(md5($name . time()), 0, 6);
		$db->prepare('INSERT INTO stations (slug, name) VALUES (?, ?)')->execute([$slug, $name]);
		$station = ['id' => (int)$db->lastInsertId(), 'slug' => $slug, 'name' => $name];
	}

	$deviceTs = isset($body['device_ts']) ? (int)$body['device_ts'] : null;

	// Messung anlegen
	$stmt = $db->prepare('INSERT INTO measurements (station_id, device_ts) VALUES (?, FROM_UNIXTIME(?))');
	$stmt->execute([$station['id'], $deviceTs]);
	$measId = (int)$db->lastInsertId();

	// Reservierte Keys die keine Metriken sind
	$skip = ['station_slug', 'station_name', 'device_ts'];

	// Alle übrigen Felder als Metriken speichern
	$stmtVal  = $db->prepare('INSERT INTO measurement_values (measurement_id, metric_key, value) VALUES (?, ?, ?)');
	$stmtMeta = $db->prepare('
		INSERT INTO metric_definitions (metric_key, label, unit, display_order)
		VALUES (?, ?, ?, 99)
		ON DUPLICATE KEY UPDATE metric_key = metric_key
	');

	// Standard-Labels für bekannte Metriken
	$knownLabels = [
		'temperature'    => ['Temperatur Außen',  '°C'],
		'pool_temperature'=> ['Temperatur Wasser', '°C'],
		'humidity'       => ['Luftfeuchte',        '%'],
		'rel_pressure'   => ['Luftdruck (rel.)',   'hPa'],
		'abs_pressure'   => ['Luftdruck (abs.)',   'hPa'],
		'pressure_state' => ['Drucktrend',         ''],
		'zambretti'      => ['Zambretti',          ''],
		'trend'          => ['Drucktrend num.',    ''],
		'battery_pct'    => ['Batterie',           '%'],
		'battery_volt'   => ['Spannung',           'V'],
		'wifi_strength'  => ['WLAN',               'dBm'],
	];

	$errors = [];
	foreach ($body as $key => $val) {
		if (in_array($key, $skip, true)) continue;
		if (!is_numeric($val) && !is_string($val)) continue;

		[$label, $unit] = $knownLabels[$key] ?? [ucfirst(str_replace('_', ' ', $key)), ''];
		try {
			$stmtMeta->execute([$key, $label, $unit]);
		} catch (Throwable $e) {
			$errors[] = "meta[$key]: " . $e->getMessage();
		}
		try {
			$stmtVal->execute([$measId, $key, is_numeric($val) ? (string)(float)$val : (string)$val]);
		} catch (Throwable $e) {
			$errors[] = "val[$key]: " . $e->getMessage();
		}
	}

	sendJson(200, ['ok' => true, 'measurement_id' => $measId, 'station' => $station['slug'], 'errors' => $errors]);
}

sendJson(405, ['error' => 'Methode nicht erlaubt']);

// ── Hilfsfunktionen ───────────────────────────────────────────────────────────

// resolveStation() ist in v1/helpers.php definiert

function loadValues(PDO $db, int $measId): array
{
	$stmt = $db->prepare('
		SELECT mv.metric_key, mv.value, md.unit
		FROM   measurement_values mv
		LEFT   JOIN metric_definitions md ON md.metric_key = mv.metric_key
		WHERE  mv.measurement_id = ?
	');
	$stmt->execute([$measId]);
	$result = [];
	foreach ($stmt->fetchAll() as $row) {
		$result[$row['metric_key']] = is_numeric($row['value']) ? round((float)$row['value'], 4) : $row['value'];
	}
	return $result;
}
