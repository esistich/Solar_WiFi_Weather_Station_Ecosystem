<?php
/**
 * v1/helpers.php – gemeinsame Hilfsfunktionen für alle v1-Endpunkte.
 * Wird von index.php einmalig geladen.
 */
declare(strict_types=1);

if (!function_exists('resolveStation')) {
	function resolveStation(PDO $db, ?string $slug): ?array
	{
		if ($slug) {
			$st = $db->prepare('SELECT id, slug, name FROM stations WHERE slug = ? LIMIT 1');
			$st->execute([$slug]);
		} else {
			$st = $db->query('SELECT id, slug, name FROM stations ORDER BY id LIMIT 1');
		}
		return $st->fetch() ?: null;
	}
}
