<?php
/**
 * v1/admin/stations.php – Station bearbeiten (JWT Bearer)
 *
 * PATCH /v1/admin/stations
 * Body: {"slug":"<aktueller-slug>","name":"<neuer-name>","new_slug":"<neuer-slug>"}
 */

declare(strict_types=1);

$payload = requireJwt();

$raw  = file_get_contents('php://input');
$body = json_decode($raw ?: '{}', true) ?? [];

$currentSlug = trim($body['slug']     ?? '');
$newName     = trim($body['name']     ?? '');
$newSlug     = trim($body['new_slug'] ?? '');

if (!$currentSlug || !$newName || !$newSlug) {
	sendJson(400, ['error' => 'Daten unvollständig (Name/Slug erforderlich)']);
}

// Slug-Format validieren
if (!preg_match('/^[a-z0-9\-]+$/', $newSlug)) {
	sendJson(422, ['error' => 'Slug darf nur Kleinbuchstaben, Zahlen und Bindestriche enthalten']);
}

$db = getDb();

// 1. Suche Station (bevorzugt nach Slug, Fallback nach Name falls Slug leer war)
$stmt = $db->prepare('SELECT id, slug, name FROM stations WHERE slug = ? OR (slug = "" AND name = ?) LIMIT 1');
$stmt->execute([$currentSlug, $newName]);
$station = $stmt->fetch();

if (!$station) {
	sendJson(404, ['error' => "Station '$currentSlug' wurde auf dem Server nicht gefunden."]);
}

// 2. Slug-Konflikt prüfen
if ($newSlug !== $station['slug']) {
	$check = $db->prepare('SELECT id FROM stations WHERE slug = ? AND id != ? LIMIT 1');
	$check->execute([$newSlug, $station['id']]);
	if ($check->fetch()) {
		sendJson(409, ['error' => "Der Bezeichner '$newSlug' wird bereits verwendet."]);
	}
}

// 3. Aktualisieren
try {
    $db->prepare('UPDATE stations SET name = ?, slug = ? WHERE id = ?')
       ->execute([$newName, $newSlug, $station['id']]);

    sendJson(200, ['station' => ['id' => $station['id'], 'slug' => $newSlug, 'name' => $newName]]);
} catch (Exception $e) {
    sendJson(500, ['error' => 'Datenbankfehler beim Speichern.']);
}
