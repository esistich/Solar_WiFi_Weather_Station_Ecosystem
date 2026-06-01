<?php
/**
 * config/jwt.php – HS256 JWT-Implementierung (kein Composer nötig).
 * Wird von auth-Endpunkten eingebunden.
 */

if (!defined('JWT_SECRET_VALUE')) {
	throw new RuntimeException('JWT_SECRET_VALUE nicht konfiguriert – config/auth.php einbinden');
}

define('JWT_SECRET', JWT_SECRET_VALUE);

function jwtEncode(array $payload): string
{
	$header  = _b64u(json_encode(['typ' => 'JWT', 'alg' => 'HS256']));
	$payload['iat'] = $payload['iat'] ?? time();
	$payload['exp'] = $payload['exp'] ?? (time() + JWT_TTL);
	$body    = _b64u(json_encode($payload));
	$sig     = _b64u(hash_hmac('sha256', "$header.$body", JWT_SECRET, true));
	return "$header.$body.$sig";
}

function jwtDecode(string $token): ?array
{
	$parts = explode('.', $token);
	if (count($parts) !== 3) return null;
	[$h, $b, $sig] = $parts;
	$expected = _b64u(hash_hmac('sha256', "$h.$b", JWT_SECRET, true));
	if (!hash_equals($expected, $sig)) return null;
	$payload = json_decode(_b64uDecode($b), true);
	if (!is_array($payload)) return null;
	if (isset($payload['exp']) && $payload['exp'] < time()) return null;
	return $payload;
}

function requireJwt(): array
{
	$header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
	$token  = '';
	if (str_starts_with($header, 'Bearer ')) {
		$token = substr($header, 7);
	}
	$payload = $token ? jwtDecode($token) : null;
	if (!$payload) {
		http_response_code(401);
		echo json_encode(['error' => 'Ungültiger oder abgelaufener Token'], JSON_UNESCAPED_UNICODE);
		exit;
	}
	return $payload;
}

function _b64u(string $data): string
{
	return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

function _b64uDecode(string $data): string
{
	return base64_decode(strtr($data, '-_', '+/') . str_repeat('=', (4 - strlen($data) % 4) % 4));
}
