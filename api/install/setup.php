<?php
/**
 * api/install/setup.php – Einmaliger Setup-Wizard (WordPress-Style)
 *
 * Schritte:
 *   1  Willkommen + Voraussetzungs-Check
 *   2  Datenbankverbindung konfigurieren + testen
 *   3  Zugangsdaten (API, Admin, JWT)
 *   4  Installation durchführen + Abschluss
 *
 * Nach erfolgreicher Installation wird .setup_done angelegt.
 * Existiert diese Datei bereits → Redirect auf ../admin/
 */

declare(strict_types=1);

// ── Schutz: Setup bereits abgeschlossen ──────────────────────────────────────
$lockFile    = __DIR__ . '/.setup_done';
$configDir   = dirname(__DIR__) . '/config';
$dbFile      = $configDir . '/db.php';
$credFile    = $configDir . '/credentials.php';
$sqlFile     = __DIR__ . '/migrate_v2.sql';

if (file_exists($lockFile)) {
	header('Location: ../admin/');
	exit;
}

// ── Hilfsfunktionen ──────────────────────────────────────────────────────────
function h(string $v): string { return htmlspecialchars($v, ENT_QUOTES); }

function checkRequirements(): array
{
	$checks = [];
	$checks[] = ['label' => 'PHP ≥ 8.1',           'ok' => version_compare(PHP_VERSION, '8.1.0', '>='), 'detail' => PHP_VERSION];
	$checks[] = ['label' => 'PDO MySQL',             'ok' => extension_loaded('pdo_mysql'),               'detail' => ''];
	$checks[] = ['label' => 'JSON-Erweiterung',      'ok' => extension_loaded('json'),                    'detail' => ''];
	$checks[] = ['label' => 'config/ beschreibbar',  'ok' => is_writable(dirname(__DIR__) . '/config'),   'detail' => dirname(__DIR__) . '/config'];
	$checks[] = ['label' => 'migrate_v2.sql vorhanden', 'ok' => file_exists(__DIR__ . '/migrate_v2.sql'), 'detail' => ''];
	return $checks;
}

function testDbConnection(string $host, string $name, string $user, string $pass): ?string
{
	try {
		$dsn = "mysql:host={$host};dbname={$name};charset=utf8mb4";
		new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
		return null; // OK
	} catch (PDOException $e) {
		return $e->getMessage();
	}
}

function runSql(string $host, string $name, string $user, string $pass, string $sqlFile): array
{
	$errors = [];
	try {
		$dsn = "mysql:host={$host};dbname={$name};charset=utf8mb4";
		$pdo = new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
		$pdo->exec("SET time_zone = '+00:00'");
		$sql = file_get_contents($sqlFile);
		// Einzelne Statements aufteilen (einfache Semikolon-Trennung)
		foreach (array_filter(array_map('trim', explode(';', $sql))) as $stmt) {
			try { $pdo->exec($stmt); }
			catch (PDOException $e) {
				// Ignoriere "already exists" (1050) und "Duplicate column" (1060)
				if (!in_array($e->errorInfo[1] ?? 0, [1050, 1060, 1061, 1091])) {
					$errors[] = $e->getMessage();
				}
			}
		}
	} catch (PDOException $e) {
		$errors[] = 'Verbindung fehlgeschlagen: ' . $e->getMessage();
	}
	return $errors;
}

function writeDbConfig(string $file, string $host, string $name, string $user, string $pass): bool
{
	$esc = fn(string $v) => str_replace(["\\", "'"], ["\\\\", "\\'"], $v);
	$php = "<?php\n/**\n * config/db.php – Datenbankverbindung.\n * Generiert von setup.php am " . gmdate('Y-m-d H:i:s') . " UTC\n * NICHT committen!\n */\n\ndefine('DB_HOST',    '{$esc($host)}');\ndefine('DB_NAME',    '{$esc($name)}');\ndefine('DB_USER',    '{$esc($user)}');\ndefine('DB_PASS',    '{$esc($pass)}');\ndefine('DB_CHARSET', 'utf8mb4');\n\nfunction getDb(): PDO\n{\n\tstatic \$pdo = null;\n\tif (\$pdo === null) {\n\t\t\$dsn = sprintf('mysql:host=%s;dbname=%s;charset=%s', DB_HOST, DB_NAME, DB_CHARSET);\n\t\t\$pdo = new PDO(\$dsn, DB_USER, DB_PASS, [\n\t\t\tPDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,\n\t\t\tPDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,\n\t\t\tPDO::ATTR_EMULATE_PREPARES   => false,\n\t\t]);\n\t\t\$pdo->exec(\"SET time_zone = '+00:00'\");\n\t}\n\treturn \$pdo;\n}\n";
	return file_put_contents($file, $php) !== false;
}

function writeCredentials(string $file, string $apiUser, string $apiPass, string $jwtSecret, string $adminUser, string $adminPass): bool
{
	$esc       = fn(string $v) => str_replace(["\\", "'"], ["\\\\", "\\'"], $v);
	$adminHash = $esc(password_hash($adminPass, PASSWORD_BCRYPT));
	$ttl       = 30 * 24 * 3600;
	$php = "<?php\n/**\n * config/credentials.php – Zugangsdaten.\n * Generiert von setup.php am " . gmdate('Y-m-d H:i:s') . " UTC\n * NICHT committen! Rotation: Admin-Dashboard → Credentials\n */\n\ndefine('API_USER',        '{$esc($apiUser)}');\ndefine('API_PASS',        '{$esc($apiPass)}');\ndefine('JWT_SECRET_VALUE','{$esc($jwtSecret)}');\ndefine('JWT_TTL',         {$ttl});\ndefine('ADMIN_USER',      '{$esc($adminUser)}');\ndefine('ADMIN_PASS_HASH', '{$adminHash}');\n";
	return file_put_contents($file, $php) !== false;
}

function generateSecret(int $bytes = 32): string
{
	return bin2hex(random_bytes($bytes));
}

// ── Request verarbeiten ───────────────────────────────────────────────────────
$step     = (int)($_POST['step'] ?? $_GET['step'] ?? 1);
$errors   = [];
$success  = false;
$formData = [];

// Schritt 2: DB-Test oder weiter
if ($step === 2 && $_SERVER['REQUEST_METHOD'] === 'POST') {
	$dbHost = trim($_POST['db_host'] ?? 'localhost');
	$dbName = trim($_POST['db_name'] ?? '');
	$dbUser = trim($_POST['db_user'] ?? '');
	$dbPass = $_POST['db_pass'] ?? '';
	$action = $_POST['action'] ?? '';

	$formData = compact('dbHost', 'dbName', 'dbUser', 'dbPass');

	if ($dbName === '' || $dbUser === '') {
		$errors[] = 'Datenbankname und Benutzer sind Pflichtfelder.';
	} else {
		$connError = testDbConnection($dbHost, $dbName, $dbUser, $dbPass);
		if ($connError) {
			$errors[] = 'Verbindungstest fehlgeschlagen: ' . $connError;
		} elseif ($action === 'next') {
			// Weiter zu Schritt 3 – DB-Daten in Session zwischenspeichern
			session_start();
			$_SESSION['setup_db'] = compact('dbHost', 'dbName', 'dbUser', 'dbPass');
			header('Location: setup.php?step=3');
			exit;
		} else {
			$success = true; // Nur Test
		}
	}
}

// Schritt 3: Zugangsdaten → Installation
if ($step === 3 && $_SERVER['REQUEST_METHOD'] === 'POST') {
	session_start();
	$db = $_SESSION['setup_db'] ?? null;
	if (!$db) { header('Location: setup.php?step=2'); exit; }

	$apiUser   = trim($_POST['api_user']    ?? '');
	$apiPass   = $_POST['api_pass']         ?? '';
	$adminUser = trim($_POST['admin_user']  ?? 'admin');
	$adminPass = $_POST['admin_pass']       ?? '';
	$adminPass2= $_POST['admin_pass2']      ?? '';
	$jwtSecret = trim($_POST['jwt_secret']  ?? '') ?: generateSecret();

	if ($apiUser === '')              $errors[] = 'API-Benutzername ist ein Pflichtfeld.';
	if (strlen($apiPass) < 12)        $errors[] = 'API-Passwort muss mindestens 12 Zeichen haben.';
	if ($adminUser === '')            $errors[] = 'Admin-Benutzername ist ein Pflichtfeld.';
	if (strlen($adminPass) < 12)     $errors[] = 'Admin-Passwort muss mindestens 12 Zeichen haben.';
	if ($adminPass !== $adminPass2)  $errors[] = 'Admin-Passwörter stimmen nicht überein.';
	if (strlen($jwtSecret) < 32)     $errors[] = 'JWT-Secret muss mindestens 32 Zeichen haben.';

	if (empty($errors)) {
		// DB-Schema einspielen
		$sqlErrors = runSql($db['dbHost'], $db['dbName'], $db['dbUser'], $db['dbPass'], $sqlFile);
		if (!empty($sqlErrors)) {
			$errors = array_merge($errors, $sqlErrors);
		} else {
			// Konfigurationsdateien schreiben
			if (!writeDbConfig($dbFile, $db['dbHost'], $db['dbName'], $db['dbUser'], $db['dbPass'])) {
				$errors[] = 'db.php konnte nicht geschrieben werden. Prüfe Schreibrechte auf api/config/.';
			}
			if (!writeCredentials($credFile, $apiUser, $apiPass, $jwtSecret, $adminUser, $adminPass)) {
				$errors[] = 'credentials.php konnte nicht geschrieben werden. Prüfe Schreibrechte auf api/config/.';
			}
			if (empty($errors)) {
				// Lock-File setzen
				file_put_contents($lockFile, gmdate('Y-m-d H:i:s') . " UTC\n");
				session_destroy();
				header('Location: setup.php?step=4');
				exit;
			}
		}
	}
}

// Schritt 1 GET: Session starten für spätere Schritte
if ($step === 1 && $_SERVER['REQUEST_METHOD'] === 'GET') {
	if (session_status() === PHP_SESSION_NONE) session_start();
}

$requirements = checkRequirements();
$allOk        = array_reduce($requirements, fn($c, $r) => $c && $r['ok'], true);
?>
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SWS Setup – Schritt <?= $step ?></title>
<style>
:root {
  --bg:      #0f1117; --surface: #1a1d27; --border: #2d3147;
  --accent:  #f5a623; --text:    #e2e8f0; --muted:  #8892a4;
  --danger:  #e15759; --success: #59a14f;
}
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body   { font-family: system-ui, sans-serif; background: var(--bg); color: var(--text);
		 min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 2rem; }
.wizard { width: 100%; max-width: 560px; display: flex; flex-direction: column; gap: 1.5rem; }
.wizard-header { text-align: center; }
.wizard-header h1 { font-size: 1.8rem; color: var(--accent); }
.wizard-header p  { color: var(--muted); margin-top: .4rem; font-size: .9rem; }

/* Schritte-Indikatoren */
.steps { display: flex; justify-content: center; gap: 0; margin: .5rem 0; }
.step-dot { width: 32px; height: 32px; border-radius: 50%; border: 2px solid var(--border);
			display: flex; align-items: center; justify-content: center; font-size: .8rem;
			font-weight: 700; color: var(--muted); background: var(--surface); z-index: 1; }
.step-dot.active  { border-color: var(--accent); color: var(--accent); }
.step-dot.done    { border-color: var(--success); background: var(--success); color: #fff; }
.step-line { flex: 1; height: 2px; background: var(--border); align-self: center; margin: 0 -1px; }
.step-line.done { background: var(--success); }

.card  { background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 2rem; }
.card h2 { font-size: 1.15rem; margin-bottom: 1.2rem; }
label  { display: flex; flex-direction: column; gap: .35rem; font-size: .85rem; color: var(--muted); margin-bottom: .9rem; }
input  { padding: .6rem .85rem; background: var(--bg); border: 1px solid var(--border);
		 border-radius: 6px; color: var(--text); font-size: .95rem; width: 100%; }
input:focus { outline: none; border-color: var(--accent); }
.hint  { font-size: .78rem; color: var(--muted); margin-top: .2rem; }
.row   { display: flex; gap: .75rem; }
.row label { flex: 1; }

button { padding: .65rem 1.4rem; border: none; border-radius: 6px; cursor: pointer;
		 font-weight: 600; font-size: .95rem; }
.btn-primary  { background: var(--accent); color: #111; }
.btn-secondary{ background: transparent; border: 1px solid var(--border); color: var(--text); }
.btn-success  { background: var(--success); color: #fff; }
.btn-row { display: flex; gap: .75rem; justify-content: flex-end; margin-top: 1rem; }

.check-list { list-style: none; display: flex; flex-direction: column; gap: .6rem; }
.check-list li { display: flex; align-items: center; gap: .6rem; font-size: .9rem; }
.check-list .icon { font-size: 1rem; }
.check-list .detail { color: var(--muted); font-size: .78rem; margin-left: auto; }

.alert { padding: .75rem 1rem; border-radius: 6px; font-size: .88rem; margin-bottom: 1rem; }
.alert-error   { background: rgba(225,87,89,.15); border: 1px solid var(--danger); color: var(--danger); }
.alert-success { background: rgba(89,161,79,.15);  border: 1px solid var(--success); color: var(--success); }
.alert ul { margin: .4rem 0 0 1.2rem; }

.success-icon { font-size: 3.5rem; text-align: center; }
.final-actions { display: flex; flex-direction: column; gap: .75rem; margin-top: 1rem; }
.final-actions a { display: block; text-align: center; padding: .75rem; border-radius: 8px;
				   text-decoration: none; font-weight: 600; }
.final-actions .btn-primary { color: #111; }
</style>
</head>
<body>
<div class="wizard">

  <!-- Header -->
  <div class="wizard-header">
	<h1>☀️ SWS API Setup</h1>
	<p>Solar WiFi Weather Station – Ersteinrichtung</p>
  </div>

  <!-- Schritt-Indikatoren -->
  <div class="steps">
	<?php
	$labels = ['1','2','3','✓'];
	for ($i = 1; $i <= 4; $i++):
	  $cls = $i < $step ? 'done' : ($i === $step ? 'active' : '');
	?>
	  <?php if ($i > 1): ?><div class="step-line <?= $i <= $step ? 'done' : '' ?>"></div><?php endif; ?>
	  <div class="step-dot <?= $cls ?>"><?= $i < $step ? '✓' : $labels[$i-1] ?></div>
	<?php endfor; ?>
  </div>

  <!-- ═══ Schritt 1: Willkommen + Voraussetzungen ════════════════════════════ -->
  <?php if ($step === 1): ?>
  <div class="card">
	<h2>Willkommen</h2>
	<p style="color:var(--muted);font-size:.9rem;margin-bottom:1.2rem">
	  Dieser Wizard richtet die Datenbank ein und erstellt alle Konfigurationsdateien.<br>
	  Danach ist das Admin-Dashboard sofort verfügbar.
	</p>

	<h2 style="font-size:1rem;margin-bottom:.8rem">Voraussetzungen</h2>
	<ul class="check-list">
	  <?php foreach ($requirements as $r): ?>
	  <li>
		<span class="icon"><?= $r['ok'] ? '✅' : '❌' ?></span>
		<span><?= h($r['label']) ?></span>
		<?php if ($r['detail']): ?><span class="detail"><?= h($r['detail']) ?></span><?php endif; ?>
	  </li>
	  <?php endforeach; ?>
	</ul>

	<?php if (!$allOk): ?>
	<div class="alert alert-error" style="margin-top:1rem">
	  Bitte behebe die Fehler bevor du fortfährst.
	</div>
	<?php endif; ?>

	<div class="btn-row">
	  <a href="setup.php?step=2">
		<button class="btn-primary" <?= $allOk ? '' : 'disabled' ?>>Weiter →</button>
	  </a>
	</div>
  </div>

  <!-- ═══ Schritt 2: Datenbank ═══════════════════════════════════════════════ -->
  <?php elseif ($step === 2): ?>
  <div class="card">
	<h2>🗄️ Datenbankverbindung</h2>

	<?php if (!empty($errors)): ?>
	<div class="alert alert-error"><ul><?php foreach($errors as $e): ?><li><?= h($e) ?></li><?php endforeach; ?></ul></div>
	<?php endif; ?>
	<?php if ($success): ?>
	<div class="alert alert-success">✅ Verbindung erfolgreich!</div>
	<?php endif; ?>

	<form method="post" action="setup.php?step=2">
	  <label>Datenbankhost
		<input type="text" name="db_host" value="<?= h($formData['dbHost'] ?? 'localhost') ?>" placeholder="localhost">
	  </label>
	  <label>Datenbankname <span style="color:var(--danger)">*</span>
		<input type="text" name="db_name" value="<?= h($formData['dbName'] ?? '') ?>" required placeholder="sws_db">
	  </label>
	  <div class="row">
		<label>Datenbankbenutzer <span style="color:var(--danger)">*</span>
		  <input type="text" name="db_user" value="<?= h($formData['dbUser'] ?? '') ?>" required placeholder="sws_user">
		</label>
		<label>Datenbankpasswort
		  <input type="password" name="db_pass" value="<?= h($formData['dbPass'] ?? '') ?>" placeholder="•••••••">
		</label>
	  </div>
	  <div class="btn-row">
		<a href="setup.php?step=1"><button type="button" class="btn-secondary">← Zurück</button></a>
		<button type="submit" name="action" value="test" class="btn-secondary">Verbindung testen</button>
		<button type="submit" name="action" value="next" class="btn-primary">Weiter →</button>
	  </div>
	</form>
  </div>

  <!-- ═══ Schritt 3: Zugangsdaten ════════════════════════════════════════════ -->
  <?php elseif ($step === 3): ?>
  <?php
	if (session_status() === PHP_SESSION_NONE) session_start();
	if (empty($_SESSION['setup_db'])) { header('Location: setup.php?step=2'); exit; }
  ?>
  <div class="card">
	<h2>🔐 Zugangsdaten</h2>

	<?php if (!empty($errors)): ?>
	<div class="alert alert-error"><ul><?php foreach($errors as $e): ?><li><?= h($e) ?></li><?php endforeach; ?></ul></div>
	<?php endif; ?>

	<form method="post" action="setup.php?step=3">

	  <p style="color:var(--muted);font-size:.82rem;margin-bottom:1.2rem">
		<strong style="color:var(--text)">API-Zugangsdaten</strong> werden in der Firmware (Settings26.h) eingetragen und von der Station beim Datensenden verwendet.
	  </p>
	  <div class="row">
		<label>API-Benutzername <span style="color:var(--danger)">*</span>
		  <input type="text" name="api_user" value="<?= h($_POST['api_user'] ?? '') ?>" required placeholder="sws_station" autocomplete="off">
		</label>
		<label>API-Passwort <span style="color:var(--danger)">*</span>
		  <input type="password" name="api_pass" required placeholder="min. 12 Zeichen" autocomplete="new-password">
		  <span class="hint">Mindestens 12 Zeichen</span>
		</label>
	  </div>

	  <hr style="border-color:var(--border);margin:1rem 0">
	  <p style="color:var(--muted);font-size:.82rem;margin-bottom:1.2rem">
		<strong style="color:var(--text)">Admin-Dashboard</strong> – Login für die Verwaltungsoberfläche.
	  </p>
	  <label>Admin-Benutzername <span style="color:var(--danger)">*</span>
		<input type="text" name="admin_user" value="<?= h($_POST['admin_user'] ?? 'admin') ?>" required autocomplete="off">
	  </label>
	  <div class="row">
		<label>Admin-Passwort <span style="color:var(--danger)">*</span>
		  <input type="password" name="admin_pass" required placeholder="min. 12 Zeichen" autocomplete="new-password">
		</label>
		<label>Passwort wiederholen <span style="color:var(--danger)">*</span>
		  <input type="password" name="admin_pass2" required placeholder="Wiederholung" autocomplete="new-password">
		</label>
	  </div>

	  <hr style="border-color:var(--border);margin:1rem 0">
	  <label>JWT-Secret
		<input type="text" name="jwt_secret" value="<?= h($_POST['jwt_secret'] ?? generateSecret()) ?>" placeholder="wird automatisch generiert" autocomplete="off">
		<span class="hint">Mindestens 32 Zeichen – für die Flutter-App. Leer lassen = automatisch generieren.</span>
	  </label>

	  <div class="btn-row">
		<a href="setup.php?step=2"><button type="button" class="btn-secondary">← Zurück</button></a>
		<button type="submit" class="btn-primary">Jetzt installieren 🚀</button>
	  </div>
	</form>
  </div>

  <!-- ═══ Schritt 4: Fertig ══════════════════════════════════════════════════ -->
  <?php elseif ($step === 4): ?>
  <div class="card" style="text-align:center">
	<div class="success-icon">🎉</div>
	<h2 style="font-size:1.4rem;margin:.8rem 0 .5rem">Installation abgeschlossen!</h2>
	<p style="color:var(--muted);font-size:.9rem;margin-bottom:1.5rem">
	  Datenbank, Konfigurationsdateien und Zugangsdaten wurden erfolgreich eingerichtet.<br>
	  Du kannst den Setup-Wizard jetzt schließen.
	</p>

	<div style="background:var(--bg);border:1px solid var(--border);border-radius:8px;padding:1rem;text-align:left;font-size:.85rem;margin-bottom:1.5rem">
	  <p style="color:var(--muted);margin-bottom:.5rem">✅ DB-Schema eingespielt (<code>migrate_v2.sql</code>)</p>
	  <p style="color:var(--muted);margin-bottom:.5rem">✅ <code>api/config/db.php</code> geschrieben</p>
	  <p style="color:var(--muted);margin-bottom:.5rem">✅ <code>api/config/credentials.php</code> geschrieben</p>
	  <p style="color:var(--muted)">✅ Setup-Lock gesetzt – Wizard ist deaktiviert</p>
	</div>

	<div style="background:rgba(245,166,35,.08);border:1px solid var(--accent);border-radius:8px;padding:1rem;text-align:left;font-size:.85rem;margin-bottom:1.5rem">
	  <p style="color:var(--accent);font-weight:700;margin-bottom:.5rem">⚠️ Nächste Schritte</p>
	  <p style="color:var(--muted);margin-bottom:.3rem">1. Trage API-Benutzername und -Passwort in <code>sketch_sws/Settings26.h</code> ein und flashe die Station.</p>
	  <p style="color:var(--muted)">2. Credentials jederzeit über <strong>Admin-Dashboard → Credentials</strong> rotieren.</p>
	</div>

	<div class="final-actions">
	  <a href="../admin/" class="btn-primary" style="background:var(--accent);color:#111">
		→ Zum Admin-Dashboard
	  </a>
	</div>
  </div>
  <?php endif; ?>

</div>
</body>
</html>
