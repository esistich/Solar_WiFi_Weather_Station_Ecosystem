<?php
/**
 * v1/auth/login.php – App-Login
 *
 * POST /v1/auth/login
 * Body: {"email":"...", "password":"..."}
 */

declare(strict_types=1);

$db   = getDb();
$body = json_decode(file_get_contents('php://input'), true) ?? [];

$email = trim($body['email']    ?? '');
$pass  = trim($body['password'] ?? '');

if (!$email || !$pass) {
	sendJson(400, ['error' => 'email und password erforderlich']);
}

$stmt = $db->prepare('SELECT id, email, password_hash FROM users WHERE email = ? LIMIT 1');
$stmt->execute([$email]);
$user = $stmt->fetch();

if (!$user || !password_verify($pass, $user['password_hash'])) {
	sendJson(401, ['error' => 'Ungültige Anmeldedaten']);
}

$token = jwtEncode(['sub' => $user['id'], 'email' => $user['email']]);
sendJson(200, ['token' => $token]);
