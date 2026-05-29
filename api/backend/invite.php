<?php
/**
 * invite.php - /api/backend/?route=invite&action=create|list
 * Nur fuer eingeloggte Nutzer (JWT erforderlich).
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/jwt.php';

$action = $_GET['action'] ?? '';

function jsonOut(int $code, array $data): void
{
    http_response_code($code);
    echo json_encode($data);
    exit;
}

function getAuthHeader(): string
{
    if (!empty($_SERVER['HTTP_AUTHORIZATION']))          return $_SERVER['HTTP_AUTHORIZATION'];
    if (!empty($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) return $_SERVER['REDIRECT_HTTP_AUTHORIZATION'];
    if (function_exists('getallheaders')) {
        foreach (getallheaders() as $name => $value) {
            if (strcasecmp($name, 'Authorization') === 0) return $value;
        }
    }
    return '';
}

function requireAuth(): array
{
    $auth = getAuthHeader();
    if (!str_starts_with($auth, 'Bearer ')) {
        jsonOut(401, ['error' => 'Kein Token']);
        exit;
    }
    try {
        return jwtDecode(substr($auth, 7));
    } catch (RuntimeException $e) {
        jsonOut(401, ['error' => $e->getMessage()]);
        exit;
    }
}

match ($action) {
    // Neuen Einladungscode erstellen (einmalig verwendbar)
    'create' => (function () {
        $user = requireAuth();
        $code = bin2hex(random_bytes(16)); // 32 Zeichen, kryptografisch sicher
        $pdo  = getDb();
        $pdo->prepare(
            'INSERT INTO invite_codes (code, created_by) VALUES (?, ?)'
        )->execute([$code, $user['sub']]);

        jsonOut(201, ['invite_code' => $code]);
    })(),

    // Alle eigenen Codes auflisten
    'list' => (function () {
        $user = requireAuth();
        $pdo  = getDb();
        $stmt = $pdo->prepare(
            'SELECT code, used, created_at FROM invite_codes WHERE created_by = ? ORDER BY created_at DESC'
        );
        $stmt->execute([$user['sub']]);
        jsonOut(200, ['codes' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
    })(),

    default => jsonOut(400, ['error' => "Unbekannte Aktion: $action"]),
};