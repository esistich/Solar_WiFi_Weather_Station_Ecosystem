<?php
/**
 * api/install/run_migrate.php – Einmaliger DB-Migrations-Runner
 *
 * SICHERHEIT: Dieses Script löscht sich nach erfolgreicher Ausführung selbst.
 * Nur aufrufen wenn man die DB migrieren möchte.
 * Zugriff ist durch api/install/.htaccess auf localhost beschränkt.
 */

declare(strict_types=1);

// Nur von localhost erlauben (zusätzliche Absicherung)
$allowed = ['127.0.0.1', '::1', $_SERVER['SERVER_ADDR'] ?? ''];
if (!in_array($_SERVER['REMOTE_ADDR'] ?? '', $allowed, true)) {
	// Secret-Token als Minimalschutz
	$token = $_GET['token'] ?? '';
	if ($token !== 'sws-migrate-2026') {
		http_response_code(403);
		die(json_encode(['error' => 'Forbidden']));
	}
}

header('Content-Type: text/plain; charset=utf-8');

$configDir = dirname(__DIR__) . '/config';
require_once $configDir . '/config.php';
require_once $configDir . '/db.php';

$pdo = getDb();
$sqlFile = __DIR__ . '/migrate_v2.sql';

if (!file_exists($sqlFile)) {
	die("FEHLER: migrate_v2.sql nicht gefunden\n");
}

$sql = file_get_contents($sqlFile);
// BOM entfernen
$sql = ltrim($sql, "\xEF\xBB\xBF");

// Statements aufteilen; reine Kommentar-Blöcke überspringen
$statements = array_filter(
	array_map('trim', explode(';', $sql)),
	function($s) {
		$s = trim($s);
		if ($s === '') return false;
		// Überspringe Blöcke die nur aus Kommentaren bestehen
		$noComments = preg_replace('/--[^\n]*/', '', $s);
		return trim($noComments) !== '';
	}
);

$ok  = 0;
$err = 0;
$errors = [];

foreach ($statements as $stmt) {
	if (trim($stmt) === '') continue;
	try {
		$pdo->exec($stmt);
		$ok++;
		echo "OK: " . substr(preg_replace('/\s+/', ' ', $stmt), 0, 80) . "\n";
	} catch (PDOException $e) {
		// Ignoriere "Duplicate column" etc. (idempotente Migrationen)
		$msg = $e->getMessage();
		if (str_contains($msg, 'Duplicate column') ||
			str_contains($msg, 'already exists') ||
			str_contains($msg, "Can't DROP")) {
			echo "SKIP (bereits vorhanden): " . substr($msg, 0, 100) . "\n";
		} else {
			$err++;
			$errors[] = $msg;
			echo "FEHLER: $msg\n";
			echo "  Statement: " . substr($stmt, 0, 120) . "\n";
		}
	}
}

echo "\n=== Migration abgeschlossen: $ok OK, $err Fehler ===\n";

if ($err === 0) {
	echo "Alle Tabellen angelegt/aktualisiert.\n";
	// Script selbst löschen (Sicherheit)
	@unlink(__FILE__);
	echo "Dieses Script wurde gelöscht.\n";
} else {
	echo "FEHLER aufgetreten – Script bleibt zur Diagnose erhalten.\n";
	echo implode("\n", $errors) . "\n";
}
