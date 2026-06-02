<?php
/**
 * GET /v1/config  –  Remote-Konfiguration für eine Station
 *
 * Auth:    HTTP Basic Auth (gleiche Credentials wie POST /v1/data)
 * Query:   ?station=<slug>  (optional, Default: erste Station)
 *          ?mac=<mac>       (optional, Fallback auf MAC-Adresse)
 *
 * Antwort: JSON mit konfigurierbaren Feldern.
 * Fehlende Felder im DB-settings-JSON werden durch Defaults ersetzt,
 * sodass der Client immer eine vollständige Antwort erhält.
 *
 * Beispiel-Antwort:
 * {
 *   "ok": true,
 *   "station": "sws-garten",
 *   "sleep_min": 10,
 *   "temp_corr": -1.5,
 *   "elevation": 420,
 *   "api_path": "/sws/api/v1/data"
 * }
 */

declare(strict_types=1);

require_once __DIR__ . '/../config/auth.php';
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/helpers.php';

requireBasicAuth();

$pdo = getDb();

$slug = $_GET['station'] ?? null;
$mac  = $_GET['mac']     ?? null;

$station = resolveStation($pdo, $slug ?: null, $mac ?: null);
if (!$station) {
	sendJson(404, ['error' => 'Station nicht gefunden']);
	exit;
}

// Spalte "settings" könnte auf älteren Instanzen noch fehlen → graceful
$raw      = $station['settings'] ?? null;
$settings = is_string($raw) ? (json_decode($raw, true) ?? []) : [];

// Defaults – entsprechen den Compile-Zeit-Defaults im Sketch
$defaults = [
	'sleep_min' => 10,
	'temp_corr' => 0.0,
	'elevation' => 420,
	'api_path'  => '/sws/api/v1/data',
];

$merged = array_merge($defaults, $settings);

sendJson(200, [
	'ok'        => true,
	'station'   => $station['slug'],
	'sleep_min' => (int)   $merged['sleep_min'],
	'temp_corr' => (float) $merged['temp_corr'],
	'elevation' => (int)   $merged['elevation'],
	'api_path'  => (string)$merged['api_path'],
]);
