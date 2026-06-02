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
	sendJson(400, ['error' => 'slug, name und new_slug erforderlich']);
}

// Slug-Format validieren: nur Kleinbuchstaben, Ziffern und Bindestriche
if (!preg_match('/^[a-z0-9\-]+$/', $newSlug)) {
	sendJson(422, ['error' => 'new_slug darf nur a-z, 0-9 und - enthalten']);
}

$db = getDb();

// Station anhand des aktuellen Slugs suchen
$stmt = $db->prepare('SELECT id, slug, name FROM stations WHERE slug = ? LIMIT 1');
$stmt->execute([$currentSlug]);
$station = $stmt->fetch();

if (!$station) {
	sendJson(404, ['error' => "Station '$currentSlug' nicht gefunden"]);
}

// Slug-Konflikt prüfen (nur wenn Slug geändert wird)
if ($newSlug !== $currentSlug) {
	$check = $db->prepare('SELECT id FROM stations WHERE slug = ? AND id != ? LIMIT 1');
	$check->execute([$newSlug, $station['id']]);
	if ($check->fetch()) {
		sendJson(409, ['error' => "Slug '$newSlug' ist bereits vergeben"]);
	}
}

// Aktualisieren
$db->prepare('UPDATE stations SET name = ?, slug = ? WHERE id = ?')
   ->execute([$newName, $newSlug, $station['id']]);

sendJson(200, ['station' => ['id' => $station['id'], 'slug' => $newSlug, 'name' => $newName]]);
