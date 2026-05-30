<?php
/**
 * v1/auth/push_unregister.php – FCM Push-Token entfernen
 *
 * POST /v1/push/unregister
 * Header: Authorization: Bearer <jwt>
 * Body:   {"token":"<fcm_token>"}
 */

declare(strict_types=1);

$payload = requireJwt();
$db      = getDb();
$body    = json_decode(file_get_contents('php://input'), true) ?? [];
$token   = trim($body['token'] ?? '');

if ($token) {
	$db->prepare('DELETE FROM push_tokens WHERE user_id = ? AND token = ?')
	   ->execute([$payload['sub'], $token]);
}

sendJson(200, ['ok' => true]);
