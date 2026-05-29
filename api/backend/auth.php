<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/jwt.php';
$action = $_GET['action'] ?? '';
$body   = json_decode(file_get_contents('php://input'), true) ?? [];
function jsonOut(int $code, array $data): void { http_response_code($code); echo json_encode($data); exit; }
function ensureTable(): void {
    $pdo = getDb();
    $pdo->exec("CREATE TABLE IF NOT EXISTS users (id INT AUTO_INCREMENT PRIMARY KEY, email VARCHAR(255) NOT NULL UNIQUE, password VARCHAR(255) NOT NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    $pdo->exec("CREATE TABLE IF NOT EXISTS invite_codes (id INT AUTO_INCREMENT PRIMARY KEY, code VARCHAR(64) NOT NULL UNIQUE, used TINYINT(1) NOT NULL DEFAULT 0, created_by INT NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}
match ($action) {
    'register' => (function () use ($body) {
        ensureTable();
        $email      = trim($body['email']       ?? '');
        $password   = trim($body['password']    ?? '');
        $inviteCode = trim($body['invite_code'] ?? '');
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($password) < 8) jsonOut(422, ['error' => 'E-Mail ungueltig oder Passwort zu kurz']);
        if (!$inviteCode) jsonOut(403, ['error' => 'Einladungscode erforderlich']);
        $pdo  = getDb();
        $stmt = $pdo->prepare('SELECT id, used FROM invite_codes WHERE code = ?');
        $stmt->execute([$inviteCode]);
        $invite = $stmt->fetch();
        if (!$invite)        jsonOut(403, ['error' => 'Ungueltiger Einladungscode']);
        if ($invite['used']) jsonOut(403, ['error' => 'Einladungscode bereits verwendet']);
        $stmt = $pdo->prepare('SELECT id FROM users WHERE email = ?');
        $stmt->execute([$email]);
        if ($stmt->fetch()) jsonOut(409, ['error' => 'E-Mail bereits registriert']);
        $hash = password_hash($password, PASSWORD_BCRYPT);
        $pdo->prepare('INSERT INTO users (email, password) VALUES (?, ?)')->execute([$email, $hash]);
        $id = (int) $pdo->lastInsertId();
        $pdo->prepare('UPDATE invite_codes SET used = 1 WHERE id = ?')->execute([$invite['id']]);
        $token = jwtEncode(['sub' => $id, 'email' => $email, 'exp' => time() + JWT_TTL]);
        jsonOut(201, ['token' => $token, 'email' => $email]);
    })(),
    'login' => (function () use ($body) {
        ensureTable();
        $email    = trim($body['email']    ?? '');
        $password = trim($body['password'] ?? '');
        $pdo  = getDb();
        $stmt = $pdo->prepare('SELECT id, password FROM users WHERE email = ?');
        $stmt->execute([$email]);
        $row  = $stmt->fetch();
        if (!$row || !password_verify($password, $row['password'])) jsonOut(401, ['error' => 'E-Mail oder Passwort falsch']);
        $token = jwtEncode(['sub' => $row['id'], 'email' => $email, 'exp' => time() + JWT_TTL]);
        jsonOut(200, ['token' => $token, 'email' => $email]);
    })(),
    'logout' => (function () { jsonOut(200, ['message' => 'Abgemeldet']); })(),
    default => jsonOut(400, ['error' => "Unbekannte Aktion: $action"]),
};