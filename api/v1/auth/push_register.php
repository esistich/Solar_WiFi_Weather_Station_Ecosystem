<?php
/**
 * v1/auth/push_register.php – FCM Push-Token registrieren
 *
 * POST /v1/push/register
 * Header: Authorization: Bearer <jwt>
 * Body:   {"token":"<fcm_token>"}
 */

declare(strict_types=1);

$payload = requireJwt();
$db      = getDb();
$body    = json_decode(file_get_contents('php://input'), true) ?? [];
$token   = trim($body['fcm_token'] ?? $body['token'] ?? '');

if (!$token) {
	sendJson(400, ['error' => 'token erforderlich']);
}

$db->prepare('
	INSERT INTO push_tokens (user_id, token, updated_at)
	VALUES (?, ?, NOW())
	ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), updated_at = NOW()
')->execute([$payload['sub'], $token]);

sendJson(200, ['ok' => true]);
