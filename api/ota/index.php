<?php
/**
 * OTA-Download-Endpunkt
 *
 * Liefert version.txt oder firmware.bin fuer einen Sketch-Identifier aus.
 * Geschuetzt durch dieselbe HTTP Basic Auth wie die restliche API.
 *
 * URL-Schema (via .htaccess RewriteRule):
 *   GET /sws/ota/{sketch}/version.txt   -> Versionsnummer (plain text)
 *   GET /sws/ota/{sketch}/firmware.bin  -> Firmware-Binary
 *
 * Dateiablage auf dem Server:
 *   api/ota/firmware/{sketch}/version.txt
 *   api/ota/firmware/{sketch}/firmware.bin
 *
 * Neue Sketches: einfach einen neuen Unterordner unter firmware/ anlegen.
 */

require_once __DIR__ . '/../config/config.php';
require_once __DIR__ . '/../config/auth.php';

requireBasicAuth();

// Sketch-ID und Dateiname aus der URL ermitteln
// Erwartet: ?sketch=sws&file=version.txt  (via .htaccess)
$sketch = preg_replace('/[^a-z0-9_\-]/', '', strtolower($_GET['sketch'] ?? ''));
$file   = $_GET['file'] ?? '';

if ($sketch === '' || !in_array($file, ['version.txt', 'firmware.bin'], true)) {
	http_response_code(400);
	exit('Ungueltige Anfrage');
}

$path = __DIR__ . '/firmware/' . $sketch . '/' . $file;

if (!file_exists($path)) {
	http_response_code(404);
	exit('Nicht gefunden');
}

if ($file === 'version.txt') {
	header('Content-Type: text/plain; charset=utf-8');
	header('Cache-Control: no-store');
	readfile($path);
} else {
	header('Content-Type: application/octet-stream');
	header('Content-Disposition: attachment; filename="firmware.bin"');
	header('Content-Length: ' . filesize($path));
	header('Cache-Control: no-store');
	readfile($path);
}
