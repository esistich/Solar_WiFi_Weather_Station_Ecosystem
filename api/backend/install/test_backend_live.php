<?php
/**
 * test_backend_live.php – Live-Test des PHP-Backends
 * Aufruf im Browser: https://timm-sander.net/sws/api/backend/install/test_backend_live.php
 * Nach dem Test diese Datei vom Server löschen!
 */

// Läuft der Test vom Server selbst → lokale URL, kein TLS-Problem
$isCli    = php_sapi_name() === 'cli';
$selfHost = $_SERVER['HTTP_HOST'] ?? 'timm-sander.net';
define('BASE', "https://$selfHost/sws/api/backend/index.php");
define('TEST_EMAIL', 'test_' . time() . '@sws.local');
define('TEST_PASS',  'TestPass123!');

$ok    = 0;
$fail  = 0;
$token = null;

if (!$isCli) {
    header('Content-Type: text/plain; charset=utf-8');
}

// PHP-Fehler im Test sichtbar machen
ini_set('display_errors', '1');
error_reporting(E_ALL);

function req(string $route, string $action, array $body = [], string $bearer = ''): array
{
	$url     = BASE . "?route=$route&action=$action";
	$headers = "Content-Type: application/json\r\n";
	if ($bearer) $headers .= "Authorization: Bearer $bearer\r\n";
	$ctx = stream_context_create(['http' => [
		'method'        => 'POST',
		'header'        => $headers,
		'content'       => json_encode($body),
		'timeout'       => 10,
		'ignore_errors' => true,
	]]);
	$raw  = file_get_contents($url, false, $ctx);
	$code = 0;
	foreach ($http_response_header ?? [] as $h) {
		if (preg_match('#HTTP/\S+\s+(\d+)#', $h, $m)) $code = (int)$m[1];
	}
	$data = json_decode($raw, true) ?? ['__raw' => $raw];
	$data['__code'] = $code;
	return $data;
}

function pass(string $msg): void { global $ok;   $ok++;   echo "  [OK]   $msg\n"; }
function fail(string $msg): void { global $fail; $fail++; echo "  [FAIL] $msg\n"; }
function info(string $msg): void { echo "         $msg\n"; }

echo "\n=== Backend Live-Test ===\n";
echo "    " . BASE . "\n\n";

// ── 1. Registrierung ──────────────────────────────────────────────────────
echo "1. Registrierung\n";
$r = req('auth', 'register', ['email' => TEST_EMAIL, 'password' => TEST_PASS]);
info("HTTP {$r['__code']}");
if ($r['__code'] === 201 && !empty($r['token'])) {
	pass('Registrierung erfolgreich');
	$token = $r['token'];
	info("Token: " . substr($token, 0, 40) . '…');
} else {
	fail('Registrierung fehlgeschlagen: ' . json_encode($r));
	if ($r['__code'] === 500) info(">>> Server-Fehler: " . ($r['__raw'] ?? '(leer)'));
}

// ── 2. Doppelte Registrierung abgelehnt ───────────────────────────────────
echo "\n2. Doppelte E-Mail\n";
$r = req('auth', 'register', ['email' => TEST_EMAIL, 'password' => TEST_PASS]);
$r['__code'] === 409
	? pass("Doppelt abgelehnt (409)")
	: fail("Erwartet 409, bekommen {$r['__code']}: " . json_encode($r));

// ── 3. Login ──────────────────────────────────────────────────────────────
echo "\n3. Login\n";
$r = req('auth', 'login', ['email' => TEST_EMAIL, 'password' => TEST_PASS]);
info("HTTP {$r['__code']}");
if ($r['__code'] === 200 && !empty($r['token'])) {
	pass('Login erfolgreich');
	$token = $r['token']; // Login-Token verwenden
} else {
	fail('Login fehlgeschlagen: ' . json_encode($r));
}

// ── 4. Falsches Passwort ──────────────────────────────────────────────────
echo "\n4. Falsches Passwort\n";
$r = req('auth', 'login', ['email' => TEST_EMAIL, 'password' => 'FalschesPasswort!']);
$r['__code'] === 401
	? pass("Abgelehnt (401)")
	: fail("Erwartet 401, bekommen {$r['__code']}: " . json_encode($r));

// ── 5. Push-Token registrieren ────────────────────────────────────────────
echo "\n5. Push-Token registrieren\n";
if ($token) {
	$r = req('push', 'register', ['fcm_token' => 'test_fcm_token_dummy_' . time()], $token);
	info("HTTP {$r['__code']}");
	if ($r['__code'] === 200) {
		pass('Push-Token gespeichert');
	} else {
		fail("Fehlgeschlagen: " . json_encode($r));
		info(">>> Raw: " . ($r['__raw'] ?? '(leer)'));
	}
} else {
	fail('Kein Token vorhanden – übersprungen');
}

// ── 6. Push ohne Auth abgelehnt ───────────────────────────────────────────
echo "\n6. Push ohne Auth\n";
$r = req('push', 'register', ['fcm_token' => 'dummy'], '');
if ($r['__code'] === 401) {
	pass("Abgelehnt (401)");
} else {
	fail("Erwartet 401, bekommen {$r['__code']}: " . json_encode($r));
	info(">>> Raw: " . ($r['__raw'] ?? '(leer)'));
}

// ── 7. Logout ─────────────────────────────────────────────────────────────
echo "\n7. Logout\n";
$r = req('auth', 'logout', [], $token ?? '');
$r['__code'] === 200
	? pass('Logout erfolgreich')
	: fail("Fehlgeschlagen: " . json_encode($r));

// ── 8. Unbekannte Route ───────────────────────────────────────────────────
echo "\n8. Unbekannte Route\n";
$r = req('unknown', 'foo');
$r['__code'] === 404
	? pass("404 zurückgegeben")
	: fail("Erwartet 404, bekommen {$r['__code']}: " . json_encode($r));

// ── Ergebnis ──────────────────────────────────────────────────────────────
echo "\n================================\n";
echo "  Bestanden: $ok  |  Fehlgeschlagen: $fail\n";
echo "================================\n\n";
exit($fail > 0 ? 1 : 0);
