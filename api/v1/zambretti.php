<?php
declare(strict_types=1);

/**
 * Zambretti-Wettervorhersage – API-seitige Berechnung
 *
 * Portiert 1:1 aus dem ESP8266-Sketch (Solar_WiFi_Weather_Station_v2_6.ino).
 * Ursprüngliche Algorithmen von Keith Hungerford, Debasish Dutta, Marc Stähli.
 *
 * Ablauf:
 *   1. Letzte 12 rel_pressure-Werte der Station aus measurement_values laden
 *      (alle 30 Min. → max. 6h Historie)
 *   2. Gewichtete Druckdifferenzen berechnen → Trend (-1/0/+1)
 *   3. Zambretti-Buchstabe aus Formel + Trend bestimmen
 *   4. Text aus Tabelle nachschlagen (Deutsch)
 *   5. pressure_state, trend_raw, zambretti, zambretti_text in
 *      measurement_values der aktuellen Messung speichern
 *
 * Wird intern von data.php nach jedem POST aufgerufen.
 * Kann auch direkt abgefragt werden:
 *   GET /v1/zambretti?station=<slug>
 */

// ── Zambretti-Texte (Deutsch) ───────────────────────────────────────────────
// Index 0='A' … 25='Z', Index 26 = Akku leer
const ZAMBRETTI_TEXT = [
	'A' => 'Beständig schönes Wetter',
	'B' => 'Schönes Wetter',
	'C' => 'Wird schön',
	'D' => 'Schön, gelegentlich kurze Schauer',
	'E' => 'Schön, vereinzelt Schauer',
	'F' => 'Ziemlich schön, Besserung',
	'G' => 'Ziemlich schön, vereinzelt frühe Schauer',
	'H' => 'Ziemlich schön, Schauer möglich',
	'I' => 'Frühe Schauer, Besserung',
	'J' => 'Wechselhaft, Besserung',
	'K' => 'Ziemlich schön, Schauer wahrscheinlich',
	'L' => 'Eher unbeständig, später Aufklärung',
	'M' => 'Unbeständig, wahrscheinlich Besserung',
	'N' => 'Wechselhaft mit Aufheiterungen',
	'O' => 'Wechselhaft, gelegentliche Schauer',
	'P' => 'Wechselhaft, etwas Regen',
	'Q' => 'Unbeständig, kurze Aufheiterungen',
	'R' => 'Unbeständig, Niederschlag zeitweise',
	'S' => 'Unbeständig, Regen gelegentlich',
	'T' => 'Sehr unbeständig, zeitweise besser',
	'U' => 'Regen gelegentlich, wird schlechter',
	'V' => 'Regen zeitweise, zunehmend unbeständig',
	'W' => 'Häufiger Regen',
	'X' => 'Sehr unbeständig, Regen',
	'Y' => 'Stürmisch, möglicherweise Besserung',
	'Z' => 'Stürmisch, viel Regen',
	'0' => 'Akku schwach – keine Prognose',
];

// ── Trendtext ────────────────────────────────────────────────────────────────
const TREND_TEXTS = [
	-1 => 'Fallend',
	 0 => 'Gleichbleibend',
	 1 => 'Steigend',
];

// ── pressure_state-Schwellen (aus Sketch übernommen) ─────────────────────────
function pressureState(int $hPa): string {
	if ($hPa < 990)                     return 'Sturm';
	if ($hPa >= 990  && $hPa < 1000)   return 'Stark tiefdruckartig';
	if ($hPa >= 1000 && $hPa < 1013)   return 'Tiefdruckartig';
	if ($hPa >= 1013 && $hPa < 1025)   return 'Hochdruckartig';
	return 'Stark hochdruckartig';
}

// ── Druckdifferenz → gewichteter Trend (-1 / 0 / +1) ────────────────────────
// Identische Gewichtung wie im Sketch: [0]*1.5, [1]*1, [2]/1.5 …
function calculateTrend(array $pressures): array {
	$n   = count($pressures);   // 1..12
	$p0  = $pressures[0];

	$weights = [1.5, 1.0, 1/1.5, 1/2.0, 1/2.5, 1/3.0, 1/3.5, 1/4.0, 1/4.5, 1/5.0, 1/5.5];
	$diffs   = [];
	for ($i = 0; $i < 11; $i++) {
		$diffs[] = isset($pressures[$i + 1])
			? ($p0 - $pressures[$i + 1]) * $weights[$i]
			: 0.0;
	}
	$avg = array_sum($diffs) / 11;

	if      ($avg >  3.5)                  { $trend = 1;  $text = 'Schnell steigend'; }
	elseif  ($avg >  1.5  && $avg <=  3.5) { $trend = 1;  $text = 'Steigend'; }
	elseif  ($avg >  0.25 && $avg <=  1.5) { $trend = 1;  $text = 'Langsam steigend'; }
	elseif  ($avg > -0.25 && $avg <   0.25){ $trend = 0;  $text = 'Gleichbleibend'; }
	elseif  ($avg >= -1.5 && $avg <  -0.25){ $trend = -1; $text = 'Langsam fallend'; }
	elseif  ($avg >= -3.5 && $avg <  -1.5) { $trend = -1; $text = 'Fallend'; }
	else                                   { $trend = -1; $text = 'Schnell fallend'; }

	return ['trend' => $trend, 'trend_raw' => round($avg, 3), 'trend_text' => $text];
}

// ── Zambretti-Buchstabe ──────────────────────────────────────────────────────
// Formeln identisch zum Sketch, Saisonkorrektur über Monat des Timestamps.
function zambrettiLetter(int $trend, int $relPressure, int $month): string {
	if ($trend === -1) {
		// Fallend
		$z = 0.0009746 * $relPressure * $relPressure - 2.1068 * $relPressure + 1138.7019;
		// Winter (Okt–März): Verschlechterung um 1
		if ($month < 4 || $month > 9) $z += 1;
		$z = min($z, 9.0);
		$letters = ['A','A','Z','Z','E','K','N','P','S','V','X','Z'];
		// Tabelle: case 0..9 aus Sketch
		$map = [0=>'A',1=>'A',2=>'Z',3=>'Z',4=>'E',5=>'K',6=>'N',7=>'P',8=>'V',9=>'X'];
		$idx = (int)round($z);
		return $map[$idx] ?? 'A';
	}
	if ($trend === 0) {
		// Gleichbleibend
		$z   = 138.24 - 0.133 * $relPressure;
		$map = [0=>'A',1=>'A',2=>'B',3=>'E',4=>'K',5=>'N',6=>'P',7=>'S',8=>'W',9=>'X',10=>'Z'];
		$idx = (int)round($z);
		return $map[$idx] ?? 'A';
	}
	// Steigend (trend === 1)
	$z = 142.57 - 0.1376 * $relPressure;
	// Sommer (Apr–Sep): Besserung um 1
	if ($month >= 4 && $month <= 9) $z -= 1;
	$z = max($z, 0.0);
	$map = [0=>'A',1=>'A',2=>'B',3=>'C',4=>'F',5=>'G',6=>'I',7=>'J',8=>'L',
			9=>'M',10=>'Q',11=>'T',12=>'Y',13=>'Z'];
	$idx = (int)round($z);
	return $map[$idx] ?? 'A';
}

// ── Hauptfunktion: für eine Station berechnen und in DB schreiben ─────────────
/**
 * Berechnet Zambretti-Vorhersage für eine Messung und schreibt die Werte
 * als measurement_values in die DB.
 *
 * @param PDO   $db          Datenbankverbindung
 * @param int   $stationId   ID der Station
 * @param int   $measId      ID der aktuellen Messung
 * @param int   $timestamp   Unix-UTC-Timestamp der Messung (für Monat)
 * @return array             Berechnete Zambretti-Werte
 */
function calculateAndStoreZambretti(PDO $db, int $stationId, int $measId, int $timestamp): array {
	// Letzte 12 rel_pressure-Werte (neueste zuerst, max. 6h zurück)
	$stmt = $db->prepare("
		SELECT mv.value
		FROM   measurement_values mv
		JOIN   measurements m ON m.id = mv.measurement_id
		WHERE  m.station_id  = :sid
		  AND  mv.metric_key = 'rel_pressure'
		  AND  m.created_at  >= UTC_TIMESTAMP() - INTERVAL 6 HOUR
		ORDER  BY m.created_at DESC
		LIMIT  12
	");
	$stmt->execute([':sid' => $stationId]);
	$rows = $stmt->fetchAll(PDO::FETCH_COLUMN);

	// Strings → float
	$pressures = array_map('floatval', $rows);
	$n         = count($pressures);

	// accuracy: 1..12 (94 % bei 12 Werten – identisch zum Sketch)
	$accuracy    = max(1, $n);
	$accuracyPct = (int)($accuracy * 94 / 12);

	// Aktuelle Messung braucht mindestens einen Wert
	if (empty($pressures)) {
		return ['error' => 'Keine Druckwerte vorhanden'];
	}

	$relPressure = (int)round($pressures[0]);
	$month       = (int)gmdate('n', $timestamp);

	// Trend berechnen
	$trendData = calculateTrend($pressures);

	// Zambretti-Buchstabe
	$letter = zambrettiLetter($trendData['trend'], $relPressure, $month);

	// Text
	$text  = ZAMBRETTI_TEXT[$letter]  ?? 'Unbekannt';
	$state = pressureState($relPressure);

	// Werte in measurement_values schreiben (upsert via REPLACE)
	$toStore = [
		'zambretti'      => $letter,
		'zambretti_text' => $text,
		'trend'          => (string)$trendData['trend'],
		'trend_raw'      => (string)$trendData['trend_raw'],
		'trend_text'     => $trendData['trend_text'],
		'pressure_state' => $state,
		'accuracy_pct'   => (string)$accuracyPct,
	];

	$ins = $db->prepare("
		INSERT INTO measurement_values (measurement_id, metric_key, value)
		VALUES (:mid, :key, :val)
		ON DUPLICATE KEY UPDATE value = VALUES(value)
	");

	// metric_definitions sicherstellen (ON DUPLICATE KEY UPDATE = no-op)
	$meta = $db->prepare("
		INSERT IGNORE INTO metric_definitions (metric_key, label, unit, display_order)
		VALUES (:key, :label, :unit, :ord)
	");

	$metaDefs = [
		'zambretti'      => ['Zambretti-Buchstabe', '',    50],
		'zambretti_text' => ['Wetterprognose',      '',    51],
		'trend'          => ['Drucktrend (num.)',   '',    52],
		'trend_raw'      => ['Drucktrend (Wert)',   'hPa', 53],
		'trend_text'     => ['Drucktrend (Text)',   '',    54],
		'pressure_state' => ['Druckzustand',        '',    55],
		'accuracy_pct'   => ['Prognosegenauigkeit', '%',   56],
	];

	foreach ($toStore as $key => $val) {
		$ins->execute([':mid' => $measId, ':key' => $key, ':val' => $val]);
		if (isset($metaDefs[$key])) {
			[$label, $unit, $ord] = $metaDefs[$key];
			$meta->execute([':key' => $key, ':label' => $label, ':unit' => $unit, ':ord' => $ord]);
		}
	}

	return array_merge(['letter' => $letter, 'text' => $text, 'accuracy_pct' => $accuracyPct], $trendData);
}

// ── Direkter GET-Endpunkt: GET /v1/zambretti?station=<slug> ──────────────────
if (basename(__FILE__) === basename($_SERVER['SCRIPT_FILENAME'] ?? '')) {
	require_once __DIR__ . '/../config/config.php';
	require_once __DIR__ . '/../config/db.php';
	require_once __DIR__ . '/../config/auth.php';
	require_once __DIR__ . '/helpers.php';
	sendCorsHeaders();

	if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
		sendJson(405, ['error' => 'Nur GET erlaubt']);
	}

	$db      = getDb();
	$slug    = $_GET['station'] ?? null;
	$station = resolveStation($db, $slug);
	if (!$station) sendJson(404, ['error' => 'Station nicht gefunden']);

	// Letzte Messung dieser Station laden
	$row = $db->prepare("SELECT id, UNIX_TIMESTAMP(created_at) AS ts FROM measurements WHERE station_id = :sid ORDER BY created_at DESC LIMIT 1");
	$row->execute([':sid' => $station['id']]);
	$meas = $row->fetch();
	if (!$meas) sendJson(404, ['error' => 'Keine Messung vorhanden']);

	$result = calculateAndStoreZambretti($db, (int)$station['id'], (int)$meas['id'], (int)$meas['ts']);
	sendJson(200, array_merge(['station' => $station['slug']], $result));
}
