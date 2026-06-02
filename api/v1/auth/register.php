<?php
/**
 * v1/auth/register.php – App-Benutzer registrieren
 *
 * POST /v1/auth/register
 * Body: {"email":"...", "password":"...", "invite_code":"..."}
 */

declare(strict_types=1);

$db   = getDb();
$body = json_decode(file_get_contents('php://input'), true) ?? [];

$email  = trim($body['email']       ?? '');
$pass   = trim($body['password']    ?? '');
$invite = trim($body['invite_code'] ?? '');

if (!$email || !$pass || !$invite) {
	sendJson(400, ['error' => 'email, password und invite_code erforderlich']);
}
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
	sendJson(400, ['error' => 'Ungültige E-Mail-Adresse']);
}
if (strlen($pass) < 8) {
	sendJson(400, ['error' => 'Passwort muss mindestens 8 Zeichen haben']);
}

// Einladungscode prüfen
$inv = $db->prepare('SELECT id FROM invite_codes WHERE code = ? AND used_at IS NULL LIMIT 1');
$inv->execute([$invite]);
$invRow = $inv->fetch();
if (!$invRow) {
	sendJson(403, ['error' => 'Ungültiger oder bereits verwendeter Einladungscode']);
}

// E-Mail-Duplikat prüfen
$dup = $db->prepare('SELECT id FROM users WHERE email = ? LIMIT 1');
$dup->execute([$email]);
if ($dup->fetch()) {
	sendJson(409, ['error' => 'E-Mail bereits registriert']);
}

// Benutzer anlegen
$hash = password_hash($pass, PASSWORD_BCRYPT);
$db->prepare('INSERT INTO users (email, password) VALUES (?, ?)')->execute([$email, $hash]);
$userId = (int)$db->lastInsertId();

// Einladungscode als verwendet markieren
$db->prepare('UPDATE invite_codes SET used_at = NOW(), used_by = ? WHERE id = ?')
   ->execute([$userId, $invRow['id']]);

$token = jwtEncode(['sub' => $userId, 'email' => $email]);
sendJson(200, [
	'id'    => (string)$userId,
	'email' => $email,
	'token' => $token,
]);
