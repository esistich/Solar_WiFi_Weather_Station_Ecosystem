<?php
/**
 * Admin-API – JSON-Endpunkt für das Dashboard.
 * Wird von index.php eingebunden (Session bereits geprüft).
 */
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

$sub    = ltrim(str_replace('api/', '', $_GET['action'] ?? ''), '/');
$method = $_SERVER['REQUEST_METHOD'];
$pdo    = getDb();

function adminJson(int $code, mixed $data): never
{
	http_response_code($code);
	echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
	exit;
}

function bodyJson(): array
{
	$d = json_decode(file_get_contents('php://input'), true);
	return is_array($d) ? $d : [];
}

// ---- Routing ----
match (true) {

	// GET api/stations
	$sub === 'stations' && $method === 'GET' => (function () use ($pdo) {
		$rows = $pdo->query('SELECT id, slug, name, created_at FROM stations ORDER BY id')->fetchAll();
		adminJson(200, $rows);
	})(),

	// POST api/stations  { slug, name }
	$sub === 'stations' && $method === 'POST' => (function () use ($pdo) {
		$d = bodyJson();
		$slug = trim($d['slug'] ?? '');
		$name = trim($d['name'] ?? '');
		if ($slug === '' || $name === '') adminJson(422, ['error' => 'slug und name sind Pflichtfelder']);
		$s = $pdo->prepare('INSERT INTO stations (slug,name) VALUES (?,?)');
		$s->execute([$slug, $name]);
		adminJson(201, ['id' => (int)$pdo->lastInsertId(), 'slug' => $slug, 'name' => $name]);
	})(),

	// DELETE api/stations?id=X
	$sub === 'stations' && $method === 'DELETE' => (function () use ($pdo) {
		$id = (int)($_GET['id'] ?? 0);
		if ($id < 1) adminJson(422, ['error' => 'Ungültige id']);
		$pdo->prepare('DELETE FROM stations WHERE id=?')->execute([$id]);
		adminJson(200, ['ok' => true]);
	})(),

	// GET api/metrics
	$sub === 'metrics' && $method === 'GET' => (function () use ($pdo) {
		$rows = $pdo->query('SELECT * FROM metric_definitions ORDER BY display_order')->fetchAll();
		adminJson(200, $rows);
	})(),

	// POST api/metrics  { metric_key, label, unit, display_order, chart_color }
	$sub === 'metrics' && $method === 'POST' => (function () use ($pdo) {
		$d = bodyJson();
		$key = trim($d['metric_key'] ?? '');
		if ($key === '') adminJson(422, ['error' => 'metric_key fehlt']);
		$s = $pdo->prepare('INSERT INTO metric_definitions
			(metric_key,label,unit,display_order,chart_color) VALUES (?,?,?,?,?)
			ON DUPLICATE KEY UPDATE label=VALUES(label),unit=VALUES(unit),
			display_order=VALUES(display_order),chart_color=VALUES(chart_color)');
		$s->execute([
			$key,
			trim($d['label'] ?? $key),
			trim($d['unit']  ?? ''),
			(int)($d['display_order'] ?? 99),
			trim($d['chart_color']    ?? '#4e79a7'),
		]);
		adminJson(200, ['ok' => true]);
	})(),

	// DELETE api/metrics?key=X
	$sub === 'metrics' && $method === 'DELETE' => (function () use ($pdo) {
		$key = trim($_GET['key'] ?? '');
		if ($key === '') adminJson(422, ['error' => 'key fehlt']);
		$pdo->prepare('DELETE FROM metric_definitions WHERE metric_key=?')->execute([$key]);
		adminJson(200, ['ok' => true]);
	})(),

	// GET api/users
	$sub === 'users' && $method === 'GET' => (function () use ($pdo) {
		$rows = $pdo->query('SELECT id, email, created_at FROM users ORDER BY id')->fetchAll();
		adminJson(200, $rows);
	})(),

	// DELETE api/users?id=X
	$sub === 'users' && $method === 'DELETE' => (function () use ($pdo) {
		$id = (int)($_GET['id'] ?? 0);
		if ($id < 1) adminJson(422, ['error' => 'Ungültige id']);
		$pdo->prepare('DELETE FROM users WHERE id=?')->execute([$id]);
		adminJson(200, ['ok' => true]);
	})(),

	// GET api/invites
	$sub === 'invites' && $method === 'GET' => (function () use ($pdo) {
		$rows = $pdo->query('SELECT id, code, created_at, used_at FROM invite_codes ORDER BY id DESC')->fetchAll();
		adminJson(200, $rows);
	})(),

	// POST api/invites  → neuen Code erzeugen
	$sub === 'invites' && $method === 'POST' => (function () use ($pdo) {
		$code = bin2hex(random_bytes(5));
		$pdo->prepare('INSERT INTO invite_codes (code) VALUES (?)')->execute([$code]);
		adminJson(201, ['code' => $code]);
	})(),

	// DELETE api/invites?id=X
	$sub === 'invites' && $method === 'DELETE' => (function () use ($pdo) {
		$id = (int)($_GET['id'] ?? 0);
		if ($id < 1) adminJson(422, ['error' => 'Ungültige id']);
		$pdo->prepare('DELETE FROM invite_codes WHERE id=?')->execute([$id]);
		adminJson(200, ['ok' => true]);
	})(),

	// GET api/live?station=slug
	$sub === 'live' && $method === 'GET' => (function () use ($pdo) {
		$slug = trim($_GET['station'] ?? '');
		if ($slug !== '') {
			$st = $pdo->prepare('SELECT id FROM stations WHERE slug=?');
			$st->execute([$slug]);
		} else {
			$st = $pdo->query('SELECT id FROM stations ORDER BY id LIMIT 1');
		}
		$stationId = (int)($st->fetchColumn() ?: 0);
		if ($stationId === 0) adminJson(404, ['error' => 'Station nicht gefunden']);

		$m = $pdo->prepare('SELECT id, created_at FROM measurements WHERE station_id=? ORDER BY id DESC LIMIT 1');
		$m->execute([$stationId]);
		$meas = $m->fetch();
		if (!$meas) adminJson(404, ['error' => 'Keine Daten']);

		$v = $pdo->prepare('SELECT mv.metric_key, mv.value, md.label, md.unit
			FROM measurement_values mv
			LEFT JOIN metric_definitions md ON md.metric_key = mv.metric_key
			WHERE mv.measurement_id = ?
			ORDER BY COALESCE(md.display_order,99)');
		$v->execute([$meas['id']]);
		adminJson(200, [
			'station_id' => $stationId,
			'created_at' => $meas['created_at'],
			'values'     => $v->fetchAll(),
		]);
	})(),

	// POST api/credentials  { admin_password, api_user?, api_pass?, jwt_secret?, admin_pass? }
	$sub === 'credentials' && $method === 'POST' => (function () {
		$credFile = dirname(__DIR__) . '/config/credentials.php';
		$d        = json_decode(file_get_contents('php://input'), true) ?? [];

		$adminPw = trim($d['admin_password'] ?? '');
		if ($adminPw === '')                                        adminJson(400, ['error' => 'admin_password fehlt']);
		if (!defined('ADMIN_PASS_HASH') || !password_verify($adminPw, ADMIN_PASS_HASH))
			adminJson(403, ['error' => 'Ungültiges Admin-Passwort']);

		$newApiUser   = trim($d['api_user']   ?? '');
		$newApiPass   = trim($d['api_pass']   ?? '');
		$newJwtSecret = trim($d['jwt_secret'] ?? '');
		$newAdminPass = trim($d['admin_pass'] ?? '');

		if ($newApiUser === '' && $newApiPass === '' && $newJwtSecret === '' && $newAdminPass === '')
			adminJson(400, ['error' => 'Mindestens ein Feld (api_user, api_pass, jwt_secret, admin_pass) muss angegeben sein']);

		if ($newApiPass   !== '' && strlen($newApiPass)   < 12) adminJson(400, ['error' => 'api_pass muss ≥ 12 Zeichen haben']);
		if ($newAdminPass !== '' && strlen($newAdminPass) < 12) adminJson(400, ['error' => 'admin_pass muss ≥ 12 Zeichen haben']);
		if ($newJwtSecret !== '' && strlen($newJwtSecret) < 32) adminJson(400, ['error' => 'jwt_secret muss ≥ 32 Zeichen haben']);

		$esc = static fn(string $v): string => str_replace(["\\", "'"], ["\\\\", "\\'"], $v);

		$finalApiUser   = $newApiUser   !== '' ? $newApiUser   : (defined('API_USER')         ? API_USER         : '');
		$finalApiPass   = $newApiPass   !== '' ? $newApiPass   : (defined('API_PASS')         ? API_PASS         : '');
		$finalJwt       = $newJwtSecret !== '' ? $newJwtSecret : (defined('JWT_SECRET_VALUE') ? JWT_SECRET_VALUE : '');
		$finalTtl       = defined('JWT_TTL')   ? JWT_TTL       : (30 * 24 * 3600);
		$finalAdminUser = defined('ADMIN_USER')? ADMIN_USER     : 'admin';
		$finalAdminHash = $newAdminPass !== '' ? $esc(password_hash($newAdminPass, PASSWORD_BCRYPT)) : $esc(ADMIN_PASS_HASH);

		$php = "<?php\n/**\n * credentials.php – generiert am " . gmdate('Y-m-d H:i:s') . " UTC\n * NICHT committen!\n */\n\n"
			. "define('API_USER',        '{$esc($finalApiUser)}');\n"
			. "define('API_PASS',        '{$esc($finalApiPass)}');\n"
			. "define('JWT_SECRET_VALUE','{$esc($finalJwt)}');\n"
			. "define('JWT_TTL',         {$finalTtl});\n"
			. "define('ADMIN_USER',      '{$esc($finalAdminUser)}');\n"
			. "define('ADMIN_PASS_HASH', '{$finalAdminHash}');\n";

		$tmp = tempnam(dirname($credFile), '.cred_');
		if ($tmp === false || file_put_contents($tmp, $php) === false)
			adminJson(500, ['error' => 'Datei konnte nicht geschrieben werden']);
		rename($tmp, $credFile);

		$rotated = array_filter([
			$newApiUser   !== '' ? 'api_user'   : '',
			$newApiPass   !== '' ? 'api_pass'   : '',
			$newJwtSecret !== '' ? 'jwt_secret' : '',
			$newAdminPass !== '' ? 'admin_pass' : '',
		]);
		adminJson(200, ['success' => true, 'rotated' => array_values($rotated), 'rotated_at' => gmdate('Y-m-d H:i:s') . ' UTC']);
	})(),

	// GET api/errorlog?level=error&station=slug&limit=200
	$sub === 'errorlog' && $method === 'GET' => (function () use ($pdo) {
		$level   = trim($_GET['level']   ?? '');
		$stSlug  = trim($_GET['station'] ?? '');
		$limit   = min((int)($_GET['limit'] ?? 100), 500);

		$where = [];
		$bind  = [];

		if (in_array($level, ['error', 'warning', 'info'], true)) {
			$where[] = 'se.level = ?';
			$bind[]  = $level;
		}
		if ($stSlug !== '') {
			$where[] = 's.slug = ?';
			$bind[]  = $stSlug;
		}

		$sql = 'SELECT se.id, se.station_id, s.slug AS station_slug, s.name AS station_name,
					   se.level, se.code, se.message, se.context, se.created_at
				FROM station_errors se
				LEFT JOIN stations s ON s.id = se.station_id'
			. ($where ? ' WHERE ' . implode(' AND ', $where) : '')
			. ' ORDER BY se.id DESC LIMIT ' . $limit;

		$st = $pdo->prepare($sql);
		$st->execute($bind);
		$rows = $st->fetchAll();

		// JSON-Kontext dekodieren
		foreach ($rows as &$r) {
			if ($r['context'] !== null) $r['context'] = json_decode($r['context'], true);
		}
		unset($r);

		adminJson(200, $rows);
	})(),

	default => adminJson(404, ['error' => 'Unbekannte Admin-Aktion']),
};
