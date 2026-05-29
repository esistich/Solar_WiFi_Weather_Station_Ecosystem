<?php
/**
 * push.php – /api/backend/push.php
 * POST   ?action=register    → FCM-Token speichern   (Bearer Token)
 * DELETE ?action=unregister  → Token löschen          (Bearer Token)
 * POST   ?action=send        → Push versenden         (Bearer Token)
 *
 * Verwendet FCM HTTP v1 API mit Service-Account-OAuth2.
 * Legacy-API ist seit Juni 2024 abgeschaltet.
 *
 * Einrichtung:
 *   1. Firebase-Konsole → Projekteinstellungen → Service-Konten
 *      → "Neuen privaten Schlüssel generieren" → JSON herunterladen
 *   2. JSON-Datei als "firebase_service_account.json" NEBEN dieses
 *      Verzeichnis legen (also api/firebase_service_account.json),
 *      NICHT ins Web-Root (per .htaccess geschützt).
 *   3. FCM_PROJECT_ID unten auf die Firebase-Projekt-ID setzen
 *      (steht auch im JSON unter "project_id").
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

// ── Konfiguration ──────────────────────────────────────────────────────────
// Pfad zur Service-Account-JSON (eine Ebene oberhalb von api/backend/)
define('FCM_SA_FILE', __DIR__ . '/../swsfb-11c77-firebase-adminsdk-fbsvc-7dc4d2384c.json');
// Project-ID wird automatisch aus der JSON gelesen – kein manuelles Eintragen nötig
define('FCM_PROJECT_ID', (function () {
    if (!file_exists(FCM_SA_FILE)) return '';
    $sa = json_decode(file_get_contents(FCM_SA_FILE), true);
    return $sa['project_id'] ?? '';
})());
// ──────────────────────────────────────────────────────────────────────────

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

/**
 * Holt einen kurzlebigen OAuth2-Access-Token vom Google-Token-Endpoint.
 * Baut das JWT selbst (RS256) – kein Composer nötig, nur OpenSSL (auf one.com verfügbar).
 */
function getFcmAccessToken(): string
{
    if (!file_exists(FCM_SA_FILE)) {
        throw new RuntimeException('Service-Account-JSON nicht gefunden: ' . FCM_SA_FILE);
    }

    $sa = json_decode(file_get_contents(FCM_SA_FILE), true);
    $now = time();

    // JWT für Google-OAuth2 bauen (RS256)
    $header  = base64url(json_encode(['alg' => 'RS256', 'typ' => 'JWT']));
    $claims  = base64url(json_encode([
        'iss'   => $sa['client_email'],
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud'   => 'https://oauth2.googleapis.com/token',
        'iat'   => $now,
        'exp'   => $now + 3600,
    ]));
    $toSign = "$header.$claims";

    $key = openssl_pkey_get_private($sa['private_key']);
    if (!$key) throw new RuntimeException('Privater Schlüssel konnte nicht geladen werden');
    openssl_sign($toSign, $sig, $key, 'SHA256');
    $signedJwt = $toSign . '.' . base64url($sig);

    // Access-Token anfordern
    $ctx = stream_context_create(['http' => [
        'method'  => 'POST',
        'header'  => "Content-Type: application/x-www-form-urlencoded\r\n",
        'content' => http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion'  => $signedJwt,
        ]),
        'timeout' => 10,
    ]]);
    $response = file_get_contents('https://oauth2.googleapis.com/token', false, $ctx);
    $data     = json_decode($response, true);

    if (empty($data['access_token'])) {
        throw new RuntimeException('Kein Access-Token erhalten: ' . $response);
    }
    return $data['access_token'];
}

/**
 * Sendet eine Push-Nachricht an einen einzelnen FCM-Token (FCM v1).
 */
function sendFcmV1(string $fcmToken, string $title, string $body, array $data = []): array
{
    $accessToken = getFcmAccessToken();
    $projectId   = FCM_PROJECT_ID;
    $url         = "https://fcm.googleapis.com/v1/projects/$projectId/messages:send";

    $message = [
        'message' => [
            'token'        => $fcmToken,
            'notification' => ['title' => $title, 'body' => $body],
        ],
    ];
    if (!empty($data)) {
        // FCM v1: data-Felder müssen Strings sein
        $message['message']['data'] = array_map('strval', $data);
    }

    $ctx = stream_context_create(['http' => [
        'method'  => 'POST',
        'header'  => "Authorization: Bearer $accessToken\r\nContent-Type: application/json\r\n",
        'content' => json_encode($message),
        'timeout' => 10,
        'ignore_errors' => true,
    ]]);
    $response = file_get_contents($url, false, $ctx);
    return json_decode($response, true) ?? ['raw' => $response];
}

// ── Router ─────────────────────────────────────────────────────────────────

$action = $_GET['action'] ?? '';
$body   = json_decode(file_get_contents('php://input'), true) ?? [];

match ($action) {
    'register' => (function () use ($body) {
        ensureTable();
        $user     = requireAuth();
        $fcmToken = trim($body['fcm_token'] ?? '');
        if (!$fcmToken) jsonOut(422, ['error' => 'fcm_token fehlt']);

        getDb()->prepare(
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

        $results = [];
        foreach ($tokens as $token) {
            $results[] = sendFcmV1($token, $title, $msg, $body['data'] ?? []);
        }

        jsonOut(200, ['sent' => count($tokens), 'results' => $results]);
    })(),

    default => jsonOut(400, ['error' => "Unbekannte Aktion: $action"]),
};


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
