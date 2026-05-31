<?php
/**
 * POST /v1/admin/rotate-password
 *
 * Rotiert API_USER, API_PASS und/oder JWT_SECRET_VALUE in credentials.php.
 * Erfordert Admin-Session-Auth (ADMIN_USER / ADMIN_PASS_HASH aus credentials.php).
 *
 * Request-Body (JSON):
 *   {
 *     "admin_password": "aktuelles Admin-Passwort",
 *     "api_user":       "neuer API-Benutzername",   // optional
 *     "api_pass":       "neues API-Passwort",        // optional
 *     "jwt_secret":     "neues JWT-Secret",          // optional
 *     "admin_pass":     "neues Admin-Passwort"        // optional
 *   }
 *
 * Mindestens eines der optionalen Felder muss gesetzt sein.
 * Das neue credentials.php wird atomar (via tempnam + rename) geschrieben.
 */

declare(strict_types=1);

$credFile = dirname(__DIR__, 2) . '/config/credentials.php';

// ── Admin-Passwort prüfen ────────────────────────────────────────────────────
$body = json_decode(file_get_contents('php://input'), true) ?? [];

$adminPassword = trim($body['admin_password'] ?? '');
if ($adminPassword === '') {
	sendJson(400, ['error' => 'admin_password fehlt']);
}

if (!defined('ADMIN_PASS_HASH') || !password_verify($adminPassword, ADMIN_PASS_HASH)) {
	http_response_code(403);
	echo json_encode(['error' => 'Ungültiges Admin-Passwort'], JSON_UNESCAPED_UNICODE);
	exit;
}

// ── Eingabe validieren ───────────────────────────────────────────────────────
$newApiUser   = trim($body['api_user']   ?? '');
$newApiPass   = trim($body['api_pass']   ?? '');
$newJwtSecret = trim($body['jwt_secret'] ?? '');
$newAdminPass = trim($body['admin_pass'] ?? '');

if ($newApiUser === '' && $newApiPass === '' && $newJwtSecret === '' && $newAdminPass === '') {
	sendJson(400, ['error' => 'Mindestens eines der Felder api_user, api_pass, jwt_secret oder admin_pass muss angegeben werden']);
}

if ($newApiPass !== '' && strlen($newApiPass) < 12) {
	sendJson(400, ['error' => 'api_pass muss mindestens 12 Zeichen haben']);
}
if ($newJwtSecret !== '' && strlen($newJwtSecret) < 32) {
	sendJson(400, ['error' => 'jwt_secret muss mindestens 32 Zeichen haben']);
}
if ($newAdminPass !== '' && strlen($newAdminPass) < 12) {
	sendJson(400, ['error' => 'admin_pass muss mindestens 12 Zeichen haben']);
}

// ── Aktuelle Werte lesen (Fallback auf Konstanten) ───────────────────────────
$currentApiUser   = defined('API_USER')        ? API_USER        : '';
$currentApiPass   = defined('API_PASS')        ? API_PASS        : '';
$currentJwtSecret = defined('JWT_SECRET_VALUE') ? JWT_SECRET_VALUE : '';
$currentJwtTtl    = defined('JWT_TTL')         ? JWT_TTL         : (30 * 24 * 3600);
$currentAdminUser = defined('ADMIN_USER')      ? ADMIN_USER      : 'admin';

// ── Neue Werte zusammenstellen ────────────────────────────────────────────────
$finalApiUser   = $newApiUser   !== '' ? $newApiUser   : $currentApiUser;
$finalApiPass   = $newApiPass   !== '' ? $newApiPass   : $currentApiPass;
$finalJwtSecret = $newJwtSecret !== '' ? $newJwtSecret : $currentJwtSecret;
$finalAdminHash = $newAdminPass !== '' ? password_hash($newAdminPass, PASSWORD_BCRYPT) : ADMIN_PASS_HASH;

// ── credentials.php atomar schreiben ─────────────────────────────────────────
$escaped = static function (string $v): string {
	return str_replace(["\\", "'"], ["\\\\", "\\'"], $v);
};

$php = <<<PHP
<?php
/**
 * credentials.php – NICHT committen! Steht in .gitignore.
 * Vorlage: credentials.example.php
 * Zuletzt rotiert: {$rotatedAt}
 */

// HTTP Basic Auth – muss mit Settings26.h der Station übereinstimmen
define('API_USER', '{$escaped($finalApiUser)}');
define('API_PASS', '{$escaped($finalApiPass)}');

// JWT für Flutter-App
define('JWT_SECRET_VALUE', '{$escaped($finalJwtSecret)}');
define('JWT_TTL',          {$currentJwtTtl});

// Admin-Dashboard Login
define('ADMIN_USER',      '{$escaped($currentAdminUser)}');
define('ADMIN_PASS_HASH', '{$escaped($finalAdminHash)}');
PHP;

// Timestamp einfügen
$rotatedAt = gmdate('Y-m-d H:i:s') . ' UTC';
$php       = str_replace('{$rotatedAt}', $rotatedAt, $php);

$tmpFile = tempnam(dirname($credFile), 'cred_');
if ($tmpFile === false || file_put_contents($tmpFile, $php) === false) {
	sendJson(500, ['error' => 'credentials.php konnte nicht geschrieben werden']);
}
if (!rename($tmpFile, $credFile)) {
	@unlink($tmpFile);
	sendJson(500, ['error' => 'credentials.php konnte nicht ersetzt werden (rename fehlgeschlagen)']);
}

// ── Antwort ──────────────────────────────────────────────────────────────────
$changed = [];
if ($newApiUser   !== '') $changed[] = 'api_user';
if ($newApiPass   !== '') $changed[] = 'api_pass';
if ($newJwtSecret !== '') $changed[] = 'jwt_secret';
if ($newAdminPass !== '') $changed[] = 'admin_pass';

sendJson(200, [
	'success'    => true,
	'rotated'    => $changed,
	'rotated_at' => $rotatedAt,
	'note'       => 'Station-Firmware Settings26.h aktualisieren falls api_user oder api_pass geändert wurde',
]);
