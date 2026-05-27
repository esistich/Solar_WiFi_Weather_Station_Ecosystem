<?php
/**
 * data.php – REST-Endpunkt der Solar WiFi Weather Station API
 *
 * GET  /api/data.php          → letzter Messdatensatz als JSON (öffentlich)
 * POST /api/data.php          → neuen Messdatensatz speichern (Basic Auth erforderlich)
 *
 * HTTP Basic Auth Credentials:
 *   API_USER / API_PASS müssen mit den Einträgen in Settings26.h übereinstimmen.
 *
 * Beispielaufruf (curl):
 *   curl -u station:geheimesPasswort \
 *        -H "Content-Type: application/json" \
 *        -d '{"temperature":21.5,"humidity":55,...}' \
 *        https://dein-server.de/api/data.php
 */

declare(strict_types=1);

require_once __DIR__ . '/auth.php';   // Credentials + requireBasicAuth()
require_once __DIR__ . '/db.php';

header('Content-Type: application/json; charset=utf-8');
sendCorsHeaders();

function sendJson(int $status, array $data): void
{
	// Varnish verschluckt 4xx/5xx-Bodies – immer HTTP 200 senden,
	// Fehlercode im JSON-Feld 'http_status' transportieren.
	if ($status !== 200) {
		$data['http_status'] = $status;
	}
	http_response_code(200);
	echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
	exit;
}

// Routing

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

// ------ GET: letzten Datensatz liefern ------------------------------------
if ($method === 'GET') {
	try {
		$pdo  = getDb();
		$stmt = $pdo->query(
			'SELECT * FROM measurements ORDER BY id DESC LIMIT 1'
		);
		$row = $stmt->fetch();

		if ($row === false) {
			sendJson(404, ['error' => 'Noch keine Messdaten vorhanden']);
		}

		// Numerische Felder casten
		$row['id']               = (int)   $row['id'];
		$row['temperature']      = (float) $row['temperature'];
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

		// Alter der letzten Messung in Sekunden (nützlich für HA-Watchdog)
		$row['data_age_s'] = (int)(time() - strtotime($row['created_at']));

		sendJson(200, $row);

	} catch (PDOException $e) {
		sendJson(500, ['error' => 'Datenbankfehler: ' . $e->getMessage()]);
	}
}

// ------ POST: neuen Datensatz speichern ------------------------------------
if ($method === 'POST') {
	requireBasicAuth();

	$body = file_get_contents('php://input');
	if ($body === false || $body === '') {
		sendJson(400, ['error' => 'Leerer Request-Body']);
	}

	$d = json_decode($body, true);
	if (!is_array($d)) {
		sendJson(400, ['error' => 'Ungültiges JSON']);
	}

	// Pflichtfelder prüfen
	$required = ['temperature', 'humidity', 'absolutepressure', 'relativepressure', 'battery'];
	foreach ($required as $field) {
		if (!array_key_exists($field, $d)) {
			sendJson(422, ['error' => "Pflichtfeld fehlt: $field"]);
		}
	}

	// Felder aus dem JSON holen (Feldnamen = was der Sketch sendet)
	try {
		$pdo  = getDb();
		$stmt = $pdo->prepare('
			INSERT INTO measurements (
				station_name, temperature, humidity, heat_index,
				dewpoint, dewpoint_spread,
				abs_pressure, rel_pressure, pressure_state,
				zambretti, zambretti_letter, trend, trend_value, accuracy,
				battery_volt, battery_pct,
				wifi_strength, device_timestamp
			) VALUES (
				:station_name, :temperature, :humidity, :heat_index,
				:dewpoint, :dewpoint_spread,
				:abs_pressure, :rel_pressure, :pressure_state,
				:zambretti, :zambretti_letter, :trend, :trend_value, :accuracy,
				:battery_volt, :battery_pct,
				:wifi_strength, :device_timestamp
			)
		');

		$stmt->execute([
			':station_name'     => substr((string)($d['station_name']    ?? ''), 0, 64),
			':temperature'      => (float)($d['temperature']             ?? 0),
			':humidity'         => (float)($d['humidity']                ?? 0),
			':heat_index'       => (float)($d['heatindex']               ?? 0),
			':dewpoint'         => (float)($d['dewpoint']                ?? 0),
			':dewpoint_spread'  => (float)($d['dewpointspread']          ?? 0),
			':abs_pressure'     => (float)($d['absolutepressure']        ?? 0),
			':rel_pressure'     => (int)  ($d['relativepressure']        ?? 0),
			':pressure_state'   => substr((string)($d['pressurestate']   ?? ''), 0, 32),
			':zambretti'        => substr((string)($d['zambrettisays']   ?? ''), 0, 128),
			':zambretti_letter' => substr((string)($d['zletter']         ?? 'A'), 0, 1),
			':trend'            => substr((string)($d['trendinwords']    ?? ''), 0, 32),
			':trend_value'      => (float)($d['trend']                   ?? 0),
			':accuracy'         => (int)  ($d['accuracy']                ?? 0),
			':battery_volt'     => (float)($d['battery']                 ?? 0),
			':battery_pct'      => (int)  ($d['batterypercentage']       ?? 0),
			':wifi_strength'    => (int)  ($d['wifi_strength']           ?? 0),
			':device_timestamp' => (int)  ($d['timestamp']               ?? 0),
		]);

		sendJson(201, ['ok' => true, 'id' => (int)$pdo->lastInsertId()]);

	} catch (PDOException $e) {
		sendJson(500, ['error' => 'Datenbankfehler: ' . $e->getMessage()]);
	}
}

// Andere Methoden ablehnen
sendJson(405, ['error' => 'Methode nicht erlaubt']);
