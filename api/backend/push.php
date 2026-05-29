<?php
/**
 * push.php – /api/backend/push.php
 * POST ?action=register  → FCM-Token speichern
 * POST ?action=send      → Push an alle Token des Nutzers (intern/admin)
 * DELETE ?action=unregister → Token löschen
 *
 * FCM HTTP v1 API: Authentifizierung über Service-Account-Schlüssel oder
 * Legacy-Serverkey. Hier wird der einfachere Legacy-Weg verwendet,
 * da kein App-Server mit OAuth möglich ist.
 * Server-Key in FCM_SERVER_KEY-Umgebungsvariable oder Konstante unten eintragen.
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: POST, DELETE, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
	http_response_code(204);
	exit;
}

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/jwt.php';

define('FCM_SERVER_KEY', getenv('FCM_SERVER_KEY') ?: 'DEIN_FCM_LEGACY_SERVER_KEY');
define('FCM_ENDPOINT',   'https://fcm.googleapis.com/fcm/send');

function jsonOut(int $code, array $data): void
{
	http_response_code($code);
	echo json_encode($data);
	exit;
}

function requireAuth(): array
{
	$auth = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
	if (!str_starts_with($auth, 'Bearer ')) jsonOut(401, ['error' => 'Kein Token']);
	try {
		return jwtDecode(substr($auth, 7));
	} catch (RuntimeException $e) {
		jsonOut(401, ['error' => $e->getMessage()]);
	}
}

function ensureTable(): void
{
	$pdo = getDb();
	$pdo->exec("CREATE TABLE IF NOT EXISTS push_tokens (
		id         INT AUTO_INCREMENT PRIMARY KEY,
		user_id    INT          NOT NULL,
		fcm_token  VARCHAR(512) NOT NULL,
		created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
		UNIQUE KEY uq_token (fcm_token)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}

$action = $_GET['action'] ?? '';
$body   = json_decode(file_get_contents('php://input'), true) ?? [];

match ($action) {
	'register' => (function () use ($body) {
		ensureTable();
		$user     = requireAuth();
		$fcmToken = trim($body['fcm_token'] ?? '');
		if (!$fcmToken) jsonOut(422, ['error' => 'fcm_token fehlt']);

		$pdo = getDb();
		$pdo->prepare(
			'INSERT INTO push_tokens (user_id, fcm_token) VALUES (?, ?)
			 ON DUPLICATE KEY UPDATE user_id = VALUES(user_id)'
		)->execute([$user['sub'], $fcmToken]);

		jsonOut(200, ['message' => 'Token gespeichert']);
	})(),

	'unregister' => (function () use ($body) {
		ensureTable();
		$user     = requireAuth();
		$fcmToken = trim($body['fcm_token'] ?? '');
		if (!$fcmToken) jsonOut(422, ['error' => 'fcm_token fehlt']);

		getDb()->prepare('DELETE FROM push_tokens WHERE fcm_token = ? AND user_id = ?')
			   ->execute([$fcmToken, $user['sub']]);

		jsonOut(200, ['message' => 'Token gelöscht']);
	})(),

	'send' => (function () use ($body) {
		// Interne Route: Nur mit gültigem JWT aufrufbar (z.B. per Cron oder Webhook).
		ensureTable();
		$user  = requireAuth();
		$title = $body['title'] ?? 'SWS Benachrichtigung';
		$msg   = $body['body']  ?? '';
		if (!$msg) jsonOut(422, ['error' => 'body fehlt']);

		$pdo  = getDb();
		$stmt = $pdo->prepare('SELECT fcm_token FROM push_tokens WHERE user_id = ?');
		$stmt->execute([$user['sub']]);
		$tokens = $stmt->fetchAll(PDO::FETCH_COLUMN);

		if (empty($tokens)) jsonOut(200, ['message' => 'Keine Token registriert', 'sent' => 0]);

		$payload = json_encode([
			'registration_ids' => $tokens,
			'notification'     => ['title' => $title, 'body' => $msg],
			'data'             => $body['data'] ?? [],
		]);

		$ctx = stream_context_create(['http' => [
			'method'  => 'POST',
			'header'  => "Authorization: key=" . FCM_SERVER_KEY . "\r\nContent-Type: application/json\r\n",
			'content' => $payload,
			'timeout' => 10,
		]]);
		$response = file_get_contents(FCM_ENDPOINT, false, $ctx);
		$result   = json_decode($response, true);

		jsonOut(200, ['sent' => count($tokens), 'fcm' => $result]);
	})(),

	default => jsonOut(400, ['error' => "Unbekannte Aktion: $action"]),
};
