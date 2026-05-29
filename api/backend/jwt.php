<?php
/**
 * jwt.php – Schlanke HS256 JWT-Implementierung (kein Composer nötig).
 */

$_jwtSecret = getenv('JWT_SECRET');
if (!$_jwtSecret) {
    // Fallback für Shared-Hosting ohne Shell-Env: Wert in einer lokalen Konfigdatei
    $cfgFile = __DIR__ . '/../../jwt_secret.php';
    if (file_exists($cfgFile)) require_once $cfgFile;
    $_jwtSecret = defined('JWT_SECRET_VALUE') ? JWT_SECRET_VALUE : null;
}
if (!$_jwtSecret) throw new RuntimeException('JWT_SECRET nicht konfiguriert');
define('JWT_SECRET', $_jwtSecret);
unset($_jwtSecret);
define('JWT_TTL',    30 * 24 * 3600); // 30 Tage

function jwtEncode(array $payload): string
{
	$header  = base64url(json_encode(['typ' => 'JWT', 'alg' => 'HS256']));
	$payload = base64url(json_encode($payload));
	$sig     = base64url(hash_hmac('sha256', "$header.$payload", JWT_SECRET, true));
	return "$header.$payload.$sig";
}

function jwtDecode(string $token): array
{
	$parts = explode('.', $token);
	if (count($parts) !== 3) throw new RuntimeException('Ungültiges Token-Format');

	[$header, $payload, $sig] = $parts;
	$expected = base64url(hash_hmac('sha256', "$header.$payload", JWT_SECRET, true));
	if (!hash_equals($expected, $sig)) throw new RuntimeException('Token-Signatur ungültig');

	$data = json_decode(base64url_decode($payload), true);
	if (isset($data['exp']) && $data['exp'] < time()) throw new RuntimeException('Token abgelaufen');

	return $data;
}

function base64url(string $data): string
{
	return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

function base64url_decode(string $data): string
{
	return base64_decode(strtr($data, '-_', '+/') . str_repeat('=', (4 - strlen($data) % 4) % 4));
}
