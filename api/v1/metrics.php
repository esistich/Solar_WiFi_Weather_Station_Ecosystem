<?php
/**
 * v1/metrics.php – verfügbare Metriken auflisten (öffentlich)
 *
 * GET /v1/metrics?station=<slug>
 * Gibt alle Metrik-Definitionen zurück, optional gefiltert nach tatsächlich
 * vorhandenen Messwerten der Station.
 */

declare(strict_types=1);

$db = getDb();

$rows = $db->query('
	SELECT metric_key, label, unit, display_order, chart_color
	FROM   metric_definitions
	ORDER  BY display_order, metric_key
')->fetchAll();

sendJson(200, ['metrics' => $rows]);
