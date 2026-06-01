<?php
/**
 * v1/helpers.php – gemeinsame Hilfsfunktionen für alle v1-Endpunkte.
 * Wird von index.php einmalig geladen.
 */
declare(strict_types=1);

if (!function_exists('resolveStation')) {
	/**
	 * Station anhand MAC (bevorzugt), dann slug, dann erste Station ermitteln.
	 * Wenn MAC übergeben und Station per slug gefunden → MAC nachträglich eintragen.
	 *
	 * @param  PDO         $db
	 * @param  string|null $slug  station_slug aus dem Request-Body
	 * @param  string|null $mac   device_mac aus dem Request-Body (normalisiert: 'aa:bb:cc:dd:ee:ff')
	 * @return array|null  ['id', 'slug', 'name', 'mac'] oder null
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

		// 3. Fallback: erste Station
		$st  = $db->query('SELECT id, slug, name, mac FROM stations ORDER BY id LIMIT 1');
		$row = $st->fetch();
		if ($row && $mac && !$row['mac']) {
			$db->prepare('UPDATE stations SET mac = ? WHERE id = ?')->execute([$mac, $row['id']]);
			$row['mac'] = $mac;
		}
		return $row ?: null;
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
