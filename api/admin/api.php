<?php
/**
 * Admin-API â€“ JSON-Endpunkt fÃ¼r das Dashboard.
 * Wird von index.php eingebunden (Session bereits geprÃ¼ft).
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
// Letzte Aktivitaet und Firmware-Version aus letzter Messung hinzufuegen
$rows = $pdo->query(
'SELECT s.id, s.slug, s.name, s.mac, s.settings, s.created_at,
        m.created_at   AS last_seen,
        mv.value       AS fw_version
 FROM stations s
 LEFT JOIN measurements m ON m.id = (
     SELECT id FROM measurements WHERE station_id = s.id ORDER BY id DESC LIMIT 1
 )
 LEFT JOIN measurement_values mv ON mv.measurement_id = m.id AND mv.metric_key = \'fw_version\'
 ORDER BY s.id'
)->fetchAll();
foreach ($rows as &$row) {
$row['settings'] = isset($row['settings']) ? (json_decode($row['settings'], true) ?? new stdClass()) : new stdClass();
}
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

// PATCH api/stations  { id, name?, slug?, mac?, settings? }
$sub === 'stations' && $method === 'PATCH' => (function () use ($pdo) {
$d    = bodyJson();
$id   = (int)($d['id'] ?? 0);
$name = trim($d['name'] ?? '');
$slug = trim(strtolower($d['slug'] ?? ''));
if ($id < 1)      adminJson(422, ['error' => 'Ung\u00fcltige id']);
if ($name === '') adminJson(422, ['error' => 'name darf nicht leer sein']);
if ($slug === '') adminJson(422, ['error' => 'slug darf nicht leer sein']);
if (!preg_match('/^[a-z0-9][a-z0-9\-]{0,62}$/', $slug))
adminJson(422, ['error' => 'Slug ung\u00fcltig (nur a-z, 0-9, Bindestrich)']);
$dup = $pdo->prepare('SELECT id FROM stations WHERE slug=? AND id!=? LIMIT 1');
$dup->execute([$slug, $id]);
if ($dup->fetch()) adminJson(409, ['error' => "Slug '$slug' ist bereits vergeben"]);
// settings validieren und als JSON-String speichern
$settingsJson = null;
if (array_key_exists('settings', $d) && $d['settings'] !== null) {
$s = $d['settings'];
if (!is_array($s) && !is_object($s)) adminJson(422, ['error' => 'settings muss ein Objekt sein']);
$s = (array)$s;
$allowed = ['sleep_min', 'temp_corr', 'elevation', 'api_path'];
$s = array_intersect_key($s, array_flip($allowed));
$settingsJson = json_encode($s, JSON_UNESCAPED_UNICODE);
}
// MAC optional aktualisieren (null = leeren, nicht gesetzt = unver\u00e4ndert)
if (array_key_exists('mac', $d)) {
$mac = $d['mac'] ? strtolower(trim($d['mac'])) : null;
if ($settingsJson !== null) {
$pdo->prepare('UPDATE stations SET name=?, slug=?, mac=?, settings=? WHERE id=?')->execute([$name, $slug, $mac, $settingsJson, $id]);
} else {
$pdo->prepare('UPDATE stations SET name=?, slug=?, mac=? WHERE id=?')->execute([$name, $slug, $mac, $id]);
}
} else {
if ($settingsJson !== null) {
$pdo->prepare('UPDATE stations SET name=?, slug=?, settings=? WHERE id=?')->execute([$name, $slug, $settingsJson, $id]);
} else {
$pdo->prepare('UPDATE stations SET name=?, slug=? WHERE id=?')->execute([$name, $slug, $id]);
}
}
adminJson(200, ['ok' => true, 'id' => $id, 'name' => $name, 'slug' => $slug]);
})(),

	// DELETE api/stations?id=X
	$sub === 'stations' && $method === 'DELETE' => (function () use ($pdo) {
		$id = (int)($_GET['id'] ?? 0);
		if ($id < 1) adminJson(422, ['error' => 'UngÃ¼ltige id']);
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
		$rows = $pdo->query('SELECT id, email, role, created_at FROM users ORDER BY id')->fetchAll();
		adminJson(200, $rows);
	})(),

	// PATCH api/users  { id, email?, role?, password? }
	$sub === 'users' && $method === 'PATCH' => (function () use ($pdo) {
		$d        = bodyJson();
		$id       = (int)($d['id'] ?? 0);
		$email    = isset($d['email'])    ? trim($d['email'])    : null;
		$role     = isset($d['role'])     ? trim($d['role'])     : null;
		$password = isset($d['password']) ? trim($d['password']) : null;
		if ($id < 1) adminJson(422, ['error' => 'UngÃ¼ltige id']);
		if ($email !== null) {
			if (!filter_var($email, FILTER_VALIDATE_EMAIL))
				adminJson(422, ['error' => 'UngÃ¼ltige E-Mail-Adresse']);
			$dup = $pdo->prepare('SELECT id FROM users WHERE email=? AND id!=? LIMIT 1');
			$dup->execute([$email, $id]);
			if ($dup->fetch()) adminJson(409, ['error' => 'E-Mail bereits vergeben']);
			$pdo->prepare('UPDATE users SET email=? WHERE id=?')->execute([$email, $id]);
		}
		if ($role !== null) {
			if (!in_array($role, ['user', 'admin'], true))
				adminJson(422, ['error' => 'Rolle muss user oder admin sein']);
			$pdo->prepare('UPDATE users SET role=? WHERE id=?')->execute([$role, $id]);
		}
		if ($password !== null) {
			if (strlen($password) < 8)
				adminJson(422, ['error' => 'Passwort muss mindestens 8 Zeichen lang sein']);
			$hash = password_hash($password, PASSWORD_BCRYPT);
			$pdo->prepare('UPDATE users SET password_hash=? WHERE id=?')->execute([$hash, $id]);
		}
		adminJson(200, ['ok' => true, 'id' => $id]);
	})(),

	// DELETE api/users?id=X  (Admin-Account nicht lÃ¶schbar)
	$sub === 'users' && $method === 'DELETE' => (function () use ($pdo) {
		$id = (int)($_GET['id'] ?? 0);
		if ($id < 1) adminJson(422, ['error' => 'UngÃ¼ltige id']);
		$row = $pdo->prepare('SELECT role FROM users WHERE id=? LIMIT 1');
		$row->execute([$id]);
		$r = $row->fetch();
		if (!$r) adminJson(404, ['error' => 'Benutzer nicht gefunden']);
		if ($r['role'] === 'admin') adminJson(403, ['error' => 'Admin-Account kann nicht gelÃ¶scht werden']);
		$pdo->prepare('DELETE FROM users WHERE id=?')->execute([$id]);
		adminJson(200, ['ok' => true]);
	})(),

	// GET api/invites
	$sub === 'invites' && $method === 'GET' => (function () use ($pdo) {
		$rows = $pdo->query('SELECT id, code, created_at, used_at FROM invite_codes ORDER BY id DESC')->fetchAll();
		adminJson(200, $rows);
	})(),

	// POST api/invites  â†’ neuen Code erzeugen
	$sub === 'invites' && $method === 'POST' => (function () use ($pdo) {
		$code = bin2hex(random_bytes(5));
		$pdo->prepare('INSERT INTO invite_codes (code) VALUES (?)')->execute([$code]);
		adminJson(201, ['code' => $code]);
	})(),

	// DELETE api/invites?id=X
	$sub === 'invites' && $method === 'DELETE' => (function () use ($pdo) {
		$id = (int)($_GET['id'] ?? 0);
		if ($id < 1) adminJson(422, ['error' => 'UngÃ¼ltige id']);
		$pdo->prepare('DELETE FROM invite_codes WHERE id=?')->execute([$id]);
		adminJson(200, ['ok' => true]);
	})(),

	// GET api/history?station=slug&hours=24&metrics=temperature,humidity
	$sub === 'history' && $method === 'GET' => (function () use ($pdo) {
		$slug    = trim($_GET['station'] ?? '');
		$hours   = min(720, max(1, (int)($_GET['hours'] ?? 24)));
		$metrics = array_filter(array_map('trim', explode(',', $_GET['metrics'] ?? '')));
		if (empty($metrics)) {
			$metrics = ['temperature', 'pool_temperature', 'humidity', 'rel_pressure', 'battery_pct'];
		}

		if ($slug !== '') {
			$st = $pdo->prepare('SELECT id FROM stations WHERE slug=?');
			$st->execute([$slug]);
		} else {
			$st = $pdo->query('SELECT id FROM stations ORDER BY id LIMIT 1');
		}
		$stationId = (int)($st->fetchColumn() ?: 0);
		if ($stationId === 0) adminJson(404, ['error' => 'Station nicht gefunden']);

		// Messzeitpunkte im Zeitfenster laden
		$placeholders = implode(',', array_fill(0, count($metrics), '?'));
		$params = [$stationId, $hours];
		$rows = $pdo->prepare("
			SELECT m.created_at, mv.metric_key, mv.value
			FROM measurements m
			JOIN measurement_values mv ON mv.measurement_id = m.id
			WHERE m.station_id = ?
			  AND m.created_at >= DATE_SUB(UTC_TIMESTAMP(), INTERVAL ? HOUR)
			  AND mv.metric_key IN ($placeholders)
			ORDER BY m.created_at ASC
		");
		$rows->execute(array_merge($params, $metrics));
		$raw = $rows->fetchAll();

		// Metrik-Labels laden
		$lblStmt = $pdo->prepare("SELECT metric_key, label, unit FROM metric_definitions WHERE metric_key IN ($placeholders)");
		$lblStmt->execute($metrics);
		$defs = [];
		foreach ($lblStmt->fetchAll() as $d) {
			$defs[$d['metric_key']] = ['label' => $d['label'], 'unit' => $d['unit']];
		}

		// Daten nach metric_key gruppieren
		$series = [];
		foreach ($raw as $r) {
			$key = $r['metric_key'];
			if (!isset($series[$key])) {
				$series[$key] = [
					'label'  => $defs[$key]['label'] ?? $key,
					'unit'   => $defs[$key]['unit']  ?? '',
					'points' => [],
				];
			}
			$series[$key]['points'][] = ['t' => $r['created_at'], 'v' => (float)$r['value']];
		}

		adminJson(200, ['hours' => $hours, 'series' => array_values($series)]);
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
			adminJson(403, ['error' => 'UngÃ¼ltiges Admin-Passwort']);

		$newApiUser   = trim($d['api_user']   ?? '');
		$newApiPass   = trim($d['api_pass']   ?? '');
		$newJwtSecret = trim($d['jwt_secret'] ?? '');
		$newAdminPass = trim($d['admin_pass'] ?? '');

		if ($newApiUser === '' && $newApiPass === '' && $newJwtSecret === '' && $newAdminPass === '')
			adminJson(400, ['error' => 'Mindestens ein Feld (api_user, api_pass, jwt_secret, admin_pass) muss angegeben sein']);

		if ($newApiPass   !== '' && strlen($newApiPass)   < 12) adminJson(400, ['error' => 'api_pass muss â‰¥ 12 Zeichen haben']);
		if ($newAdminPass !== '' && strlen($newAdminPass) < 12) adminJson(400, ['error' => 'admin_pass muss â‰¥ 12 Zeichen haben']);
		if ($newJwtSecret !== '' && strlen($newJwtSecret) < 32) adminJson(400, ['error' => 'jwt_secret muss â‰¥ 32 Zeichen haben']);

		$esc = static fn(string $v): string => str_replace(["\\", "'"], ["\\\\", "\\'"], $v);

		$finalApiUser   = $newApiUser   !== '' ? $newApiUser   : (defined('API_USER')         ? API_USER         : '');
		$finalApiPass   = $newApiPass   !== '' ? $newApiPass   : (defined('API_PASS')         ? API_PASS         : '');
		$finalJwt       = $newJwtSecret !== '' ? $newJwtSecret : (defined('JWT_SECRET_VALUE') ? JWT_SECRET_VALUE : '');
		$finalTtl       = defined('JWT_TTL')   ? JWT_TTL       : (30 * 24 * 3600);
		$finalAdminUser = defined('ADMIN_USER')? ADMIN_USER     : 'admin';
		$finalAdminHash = $newAdminPass !== '' ? $esc(password_hash($newAdminPass, PASSWORD_BCRYPT)) : $esc(ADMIN_PASS_HASH);

		$php = "<?php\n/**\n * credentials.php â€“ generiert am " . gmdate('Y-m-d H:i:s') . " UTC\n * NICHT committen!\n */\n\n"
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

	// GET api/ota  â€“ alle Sketch-Ordner mit Version und Firmware-Info
	$sub === 'ota' && $method === 'GET' => (function () {
		$base = dirname(__DIR__) . '/ota/firmware';
		$list = [];
		if (is_dir($base)) {
			foreach (scandir($base) as $entry) {
				if ($entry[0] === '.') continue;
				$dir = $base . '/' . $entry;
				if (!is_dir($dir)) continue;
				$vf = $dir . '/version.txt';
				$bf = $dir . '/firmware.bin';
				$list[] = [
					'sketch'         => $entry,
					'sketch_path'    => 'ota/firmware/' . $entry . '/',
					'version'        => file_exists($vf) ? trim(file_get_contents($vf)) : null,
					'firmware_size'  => file_exists($bf) ? filesize($bf) : null,
					'firmware_mtime' => file_exists($bf) ? filemtime($bf) : null,
				];
			}
		}
		adminJson(200, $list);
	})(),

	// POST api/ota/version  { sketch, version }
	$sub === 'ota/version' && $method === 'POST' => (function () {
		$d      = bodyJson();
		$sketch = preg_replace('/[^a-z0-9_\-]/', '', strtolower($d['sketch'] ?? ''));
		$ver    = trim($d['version'] ?? '');
		$dir    = dirname(__DIR__) . '/ota/firmware/' . $sketch;
		if ($sketch === '' || !is_dir($dir)) adminJson(422, ['error' => 'Unbekannter Sketch']);
		if (!preg_match('/^\d+\.\d+(\.\d+)?$/', $ver)) adminJson(422, ['error' => 'Ungueltige Versionsnummer']);
		file_put_contents($dir . '/version.txt', $ver . "\n");
		adminJson(200, ['ok' => true, 'sketch' => $sketch, 'version' => $ver]);
	})(),

	// POST api/ota/upload  (multipart: sketch + firmware)
	$sub === 'ota/upload' && $method === 'POST' => (function () {
		$sketch = preg_replace('/[^a-z0-9_\-]/', '', strtolower($_POST['sketch'] ?? ''));
		$dir    = dirname(__DIR__) . '/ota/firmware/' . $sketch;
		if ($sketch === '' || !is_dir($dir)) adminJson(422, ['error' => 'Unbekannter Sketch']);
		$tmp = $_FILES['firmware']['tmp_name'] ?? '';
		if (!$tmp || !is_uploaded_file($tmp)) adminJson(422, ['error' => 'Keine Datei empfangen']);
		$dest = $dir . '/firmware.bin';
		if (!move_uploaded_file($tmp, $dest)) adminJson(500, ['error' => 'Fehler beim Speichern']);
		adminJson(200, ['ok' => true, 'sketch' => $sketch, 'size' => filesize($dest)]);
	})(),

	// POST api/migrate â€“ role-Spalte ergÃ¤nzen + Admin-User anlegen falls keiner existiert
	$sub === 'migrate' && $method === 'POST' => (function () use ($pdo) {
		$log = [];
		// role-Spalte ergÃ¤nzen falls noch nicht vorhanden
		try {
			$pdo->exec("ALTER TABLE users ADD COLUMN role VARCHAR(20) NOT NULL DEFAULT 'user'");
			$log[] = 'Spalte role angelegt';
		} catch (\PDOException $e) {
			$log[] = 'Spalte role bereits vorhanden (Ã¼bersprungen)';
		}
		// PrÃ¼fen ob Admin existiert
		$existing = $pdo->query("SELECT id FROM users WHERE role='admin' LIMIT 1")->fetchColumn();
		if (!$existing) {
			$d     = bodyJson();
			$email = trim($d['email']    ?? 'admin@local');
			$pass  = trim($d['password'] ?? '');
			if ($pass === '') adminJson(422, ['error' => 'password fÃ¼r Admin-Anlage erforderlich', 'log' => $log]);
			if (strlen($pass) < 8) adminJson(422, ['error' => 'Passwort mind. 8 Zeichen', 'log' => $log]);
			$hash = password_hash($pass, PASSWORD_BCRYPT);
			$pdo->prepare("INSERT INTO users (email, password_hash, role) VALUES (?,?,'admin')")->execute([$email, $hash]);
			$log[] = "Admin-User '$email' angelegt";
		} else {
			$log[] = 'Admin-User bereits vorhanden';
		}
		adminJson(200, ['ok' => true, 'log' => $log]);
	})(),

	default => adminJson(404, ['error' => 'Unbekannte Admin-Aktion']),
};

