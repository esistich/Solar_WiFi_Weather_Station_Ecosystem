<?php
/**
 * test_jwt.php – Schnelltest für jwt.php
 * Aufruf: php test_jwt.php
 */

require_once __DIR__ . '/../jwt.php';

$ok   = 0;
$fail = 0;

function pass(string $msg): void { global $ok;   $ok++;   echo "  [OK]   $msg\n"; }
function fail(string $msg): void { global $fail; $fail++; echo "  [FAIL] $msg\n"; }

echo "\n=== JWT Test ===\n\n";

// 1. Encode + Decode Roundtrip
echo "1. Encode/Decode Roundtrip\n";
try {
	$payload = ['sub' => 42, 'email' => 'test@example.com', 'exp' => time() + 3600];
	$token   = jwtEncode($payload);
	$decoded = jwtDecode($token);

	$decoded['sub']   === 42                  ? pass('sub korrekt')   : fail("sub falsch: {$decoded['sub']}");
	$decoded['email'] === 'test@example.com'  ? pass('email korrekt') : fail("email falsch: {$decoded['email']}");
	isset($decoded['exp'])                     ? pass('exp vorhanden') : fail('exp fehlt');
} catch (Throwable $e) {
	fail('Roundtrip Exception: ' . $e->getMessage());
}

// 2. Abgelaufenes Token wird abgelehnt
echo "\n2. Abgelaufenes Token\n";
try {
	$token = jwtEncode(['sub' => 1, 'exp' => time() - 10]);
	jwtDecode($token);
	fail('Abgelaufenes Token wurde akzeptiert');
} catch (RuntimeException $e) {
	str_contains($e->getMessage(), 'abgelaufen')
		? pass('Abgelehnt: ' . $e->getMessage())
		: fail('Falscher Fehlertext: ' . $e->getMessage());
}

// 3. Manipuliertes Token wird abgelehnt
echo "\n3. Manipuliertes Token\n";
try {
	$token  = jwtEncode(['sub' => 1, 'exp' => time() + 3600]);
	$parts  = explode('.', $token);
	$parts[1] .= 'X'; // Payload verfälschen
	jwtDecode(implode('.', $parts));
	fail('Manipuliertes Token wurde akzeptiert');
} catch (RuntimeException $e) {
	str_contains($e->getMessage(), 'Signatur') || str_contains($e->getMessage(), 'ungültig')
		? pass('Abgelehnt: ' . $e->getMessage())
		: fail('Falscher Fehlertext: ' . $e->getMessage());
}

// 4. Vollständig ungültiger String
echo "\n4. Kein JWT\n";
try {
	jwtDecode('das.ist.kein.gueltiges.jwt');
	fail('Ungültiges Token wurde akzeptiert');
} catch (RuntimeException $e) {
	pass('Abgelehnt: ' . $e->getMessage());
}

// 5. Token ohne exp wird akzeptiert
echo "\n5. Token ohne exp\n";
try {
	$token   = jwtEncode(['sub' => 99]);
	$decoded = jwtDecode($token);
	$decoded['sub'] === 99 ? pass('sub korrekt, kein exp benötigt') : fail('sub falsch');
} catch (Throwable $e) {
	fail('Exception: ' . $e->getMessage());
}

// Ergebnis
echo "\n================================\n";
echo "  Bestanden: $ok  |  Fehlgeschlagen: $fail\n";
echo "================================\n\n";
exit($fail > 0 ? 1 : 0);
