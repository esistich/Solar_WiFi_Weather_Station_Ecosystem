<?php
/**
 * v1/helpers.php – gemeinsame Hilfsfunktionen für alle v1-Endpunkte.
 * Wird von index.php einmalig geladen.
 */
declare(strict_types=1);

if (!function_exists('resolveStation')) {
	/**
	 * Station anhand MAC (bevorzugt), dann slug ermitteln.
	 * Wenn MAC übergeben und Station per slug gefunden → MAC nachträglich eintragen.
	 * Wenn weder MAC noch slug bekannt sind → wird NULL zurückgegeben; der Aufrufer
	 * muss in diesem Fall eine "fallback"-Station anlegen (kein blindes Zuordnen
	 * zu einer bestehenden Station).
	 *
	 * @param  PDO         $db
	 * @param  string|null $slug  station_slug aus dem Request-Body
	 * @param  string|null $mac   device_mac aus dem Request-Body (normalisiert: 'aa:bb:cc:dd:ee:ff')
	 * @return array|null  ['id', 'slug', 'name', 'mac'] oder null wenn keine Station zugeordnet werden kann
	 */
	function resolveStation(PDO $db, ?string $slug, ?string $mac = null): ?array
	{
		// 1. Per MAC suchen (eindeutig, hardware-seitig garantiert)
		if ($mac) {
			$st = $db->prepare('SELECT id, slug, name, mac FROM stations WHERE mac = ? LIMIT 1');
			$st->execute([$mac]);
			$row = $st->fetch();
			if ($row) return $row;
		}

		// 2. Per slug suchen
		if ($slug) {
			$st = $db->prepare('SELECT id, slug, name, mac FROM stations WHERE slug = ? LIMIT 1');
			$st->execute([$slug]);
			$row = $st->fetch();
			if ($row) {
				// MAC nachträglich eintragen wenn noch nicht gesetzt
				if ($mac && !$row['mac']) {
					$db->prepare('UPDATE stations SET mac = ? WHERE id = ?')->execute([$mac, $row['id']]);
					$row['mac'] = $mac;
				}
				return $row;
			}
		}

		// 3. Kein Identifier vorhanden → null; kein Fallback auf erste Station,
		//    damit keine Fremddaten in eine bestehende Station landen.
		return null;
	}
}

if (!function_exists('resolveOrCreateFallbackStation')) {
	/**
	 * Legt eine "fallback"-Station an (slug: sws-fallback) und gibt sie zurück.
	 * Existiert sie bereits, wird die vorhandene Station zurückgegeben.
	 * Wird ausschliesslich aufgerufen wenn weder MAC noch slug bekannt sind.
	 *
	 * @param  PDO $db
	 * @return array ['id', 'slug', 'name', 'mac']
	 */
	function resolveOrCreateFallbackStation(PDO $db): array
	{
		$slug = 'sws-fallback';
		$st   = $db->prepare('SELECT id, slug, name, mac FROM stations WHERE slug = ? LIMIT 1');
		$st->execute([$slug]);
		$row = $st->fetch();
		if ($row) return $row;

		// Fallback-Station neu anlegen
		$db->prepare('INSERT INTO stations (slug, name, mac) VALUES (?, ?, NULL)')
		   ->execute([$slug, 'Fallback (kein Identifier)']);
		return [
			'id'   => (int)$db->lastInsertId(),
			'slug' => $slug,
			'name' => 'Fallback (kein Identifier)',
			'mac'  => null,
		];
	}
}

if (!function_exists('normalizeMac')) {
	/** MAC-Adresse normalisieren: 'A4:CF:12:AB:34:56' → 'a4:cf:12:ab:34:56' */
	function normalizeMac(?string $mac): ?string
	{
		if (!$mac) return null;
		$clean = strtolower(preg_replace('/[^0-9a-fA-F]/', '', $mac));
		if (strlen($clean) !== 12) return null;
		return implode(':', str_split($clean, 2));
	}
}
