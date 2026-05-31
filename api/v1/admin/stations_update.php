<?php
/**
 * v1/admin/stations_update.php - Stationsname/-Slug aendern
 *
 * PATCH /v1/admin/stations
 * Body: {"slug": "waggum", "name": "Waggum Neu", "new_slug": "waggum-neu"}
 *
 * slug     = aktueller Slug (zum Identifizieren der Station)
 * name     = neuer Anzeigename (optional)
 * new_slug = neuer Slug (optional)
 *
 * Erfordert JWT (App-Login).
 */

declare(strict_types=1);

requireJwt();

$db   = getDb();
$body = json_decode(file_get_contents('php://input'), true) ?? [];

$currentSlug = isset($body['slug'])     ? trim($body['slug'])                 : null;
$newName     = isset($body['name'])     ? trim($body['name'])                 : null;
$newSlug     = isset($body['new_slug']) ? trim(strtolower($body['new_slug'])) : null;

if (!$currentSlug) {
    sendJson(400, ['error' => 'slug (aktueller Bezeichner) erforderlich']);
}

if ($newSlug !== null && !preg_match('/^[a-z0-9][a-z0-9\-]{0,62}$/', $newSlug)) {
    sendJson(400, ['error' => 'new_slug ungueltig (nur a-z, 0-9, Bindestrich)']);
}

$st = $db->prepare('SELECT id FROM stations WHERE slug = ? LIMIT 1');
$st->execute([$currentSlug]);
$station = $st->fetch();
if (!$station) {
    sendJson(404, ['error' => "Station nicht gefunden: $currentSlug"]);
}

$id = (int)$station['id'];

if ($newSlug !== null && $newSlug !== $currentSlug) {
    $dup = $db->prepare('SELECT id FROM stations WHERE slug = ? AND id != ? LIMIT 1');
    $dup->execute([$newSlug, $id]);
    if ($dup->fetch()) {
        sendJson(409, ['error' => "Slug bereits vergeben: $newSlug"]);
    }
}

$sets   = [];
$params = [];
if ($newName !== null && $newName !== '') { $sets[] = 'name = ?'; $params[] = $newName; }
if ($newSlug !== null && $newSlug !== '') { $sets[] = 'slug = ?'; $params[] = $newSlug; }

if (empty($sets)) {
    sendJson(400, ['error' => 'Nichts zu aendern (name oder new_slug angeben)']);
}

$params[] = $id;
$db->prepare('UPDATE stations SET ' . implode(', ', $sets) . ' WHERE id = ?')->execute($params);

$row = $db->prepare('SELECT id, slug, name FROM stations WHERE id = ? LIMIT 1');
$row->execute([$id]);
sendJson(200, ['station' => $row->fetch()]);
