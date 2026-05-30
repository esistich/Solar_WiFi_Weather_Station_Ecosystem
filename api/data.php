<?php
declare(strict_types=1);

/**
 * data.php – Kompatibilitaets-Shim (Legacy-Pfad /api/data.php)
 *
 * Leitet GET/POST transparent an die neue API v1 weiter.
 * Bestehende Firmware und aeltere App-Versionen bleiben kompatibel.
 *
 * Neuer kanonischer Endpunkt: /v1/data
 */

require_once __DIR__ . '/config/db.php';
require_once __DIR__ . '/config/auth.php';
require_once __DIR__ . '/config/jwt.php';
require_once __DIR__ . '/v1/helpers.php';

header('Content-Type: application/json; charset=utf-8');
sendCorsHeaders();

// POST-Body: Sketch-Feldnamen in v1-Format uebersetzen
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $raw = json_decode(file_get_contents('php://input'), true);
    if (is_array($raw)) {
        $map = [
            'absolutepressure'  => 'abs_pressure',
            'relativepressure'  => 'rel_pressure',
            'heatindex'         => 'heat_index',
            'dewpointspread'    => 'dewpoint_spread',
            'pressurestate'     => 'pressure_state',
            'zambrettisays'     => 'zambretti',
            'zletter'           => 'zambretti_letter',
            'trendinwords'      => 'trend',
            'trend'             => 'trend_value',
            'battery'           => 'battery_volt',
            'batterypercentage' => 'battery_pct',
            'wifistrength'      => 'wifi_strength',
            'timestamp'         => 'device_ts',
        ];
        $translated = [];
        foreach ($raw as $k => $v) {
            $translated[$map[$k] ?? $k] = $v;
        }
        $GLOBALS['_shimBody'] = $translated;
    }
}

require __DIR__ . '/v1/data.php';
