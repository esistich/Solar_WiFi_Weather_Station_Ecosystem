<?php
/**
 * Admin-Dashboard – Einstiegspunkt
 * Session-basierte Authentifizierung; kein JWT benötigt.
 */
declare(strict_types=1);

session_start();

require_once __DIR__ . '/../config/config.php';
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/../config/auth.php';

// ----- Login / Logout -----
$action = $_GET['action'] ?? '';

if ($action === 'logout') {
	session_destroy();
	header('Location: index.php');
	exit;
}

if ($action === 'login' && $_SERVER['REQUEST_METHOD'] === 'POST') {
	$inputUser = trim($_POST['username'] ?? '');
	$inputPass = $_POST['password'] ?? '';
	$loginOk   = false;

	// Primär: Admin-User aus der Datenbank (role='admin')
	try {
		$pdo  = getDb();
		$stmt = $pdo->prepare("SELECT id, password FROM users WHERE email=? AND role='admin' LIMIT 1");
		$stmt->execute([$inputUser]);
		$row = $stmt->fetch();
		if ($row && password_verify($inputPass, $row['password'])) {
			$loginOk = true;
		}
	} catch (\Throwable $e) {
		// DB nicht verfügbar → Fallback auf credentials.php
	}

	// Fallback: credentials.php (solange noch kein DB-Admin existiert)
	if (!$loginOk && defined('ADMIN_USER') && defined('ADMIN_PASS_HASH')) {
		if ($inputUser === ADMIN_USER && password_verify($inputPass, ADMIN_PASS_HASH)) {
			$loginOk = true;
		}
	}

	if ($loginOk) {
		session_regenerate_id(true);
		$_SESSION['admin'] = true;
		header('Location: index.php');
		exit;
	}
	$loginError = 'Benutzername oder Passwort falsch.';
}

$loggedIn = !empty($_SESSION['admin']);

// CSRF-Token für eingeloggte Admins generieren
if ($loggedIn && empty($_SESSION['csrf_token'])) {
	$_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}

// ----- Admin-API (JSON) -----
if ($loggedIn && str_starts_with($action, 'api/')) {
	// CSRF-Token prüfen bei state-ändernden Requests
	$reqMethod = $_SERVER['REQUEST_METHOD'];
	if (in_array($reqMethod, ['POST', 'PATCH', 'DELETE', 'PUT'], true)) {
		$csrfHeader = $_SERVER['HTTP_X_CSRF_TOKEN'] ?? '';
		if (!hash_equals($_SESSION['csrf_token'] ?? '', $csrfHeader)) {
			header('Content-Type: application/json; charset=utf-8');
			http_response_code(403);
			echo json_encode(['error' => 'Ungültiges CSRF-Token']);
			exit;
		}
	}
	require __DIR__ . '/api.php';
	exit;
}

// ----- Login-Seite -----
if (!$loggedIn): ?>
<!DOCTYPE html>
<html lang="de" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>SWS Admin – Login</title>
<link rel="stylesheet" href="https://cdn.metroui.org.ua/current/metro.css">
<link rel="stylesheet" href="https://cdn.metroui.org.ua/current/icons.css">
<link rel="stylesheet" href="assets/admin.css">
</head>
<body class="sws-login-page dark-side">
<div class="sws-login-wrap">
  <div class="card sws-login-card">
	<div class="card-header sws-login-header">
	  <span class="mif-sun fg-yellow icon"></span>
	  <span>SWS Admin</span>
	</div>
	<div class="card-content p-4">
	  <?php if (!empty($loginError)): ?>
	  <div class="alert alert-warning mb-2"><?= htmlspecialchars($loginError) ?></div>
	  <?php endif ?>
	  <form method="post" action="?action=login">
		<div class="form-group">
		  <label>Benutzername</label>
		  <input type="text" name="username" class="metro-input" autofocus autocomplete="username">
		</div>
		<div class="form-group mt-2">
		  <label>Passwort</label>
		  <input type="password" name="password" class="metro-input" autocomplete="current-password">
		</div>
		<div class="mt-4">
		  <button type="submit" class="button primary w-100">Anmelden</button>
		</div>
	  </form>
	</div>
  </div>
</div>
<script src="https://cdn.metroui.org.ua/current/metro.js"></script>
</body>
</html>
<?php exit; endif; ?>
<!DOCTYPE html>
<html lang="de" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>SWS Admin</title>
<meta name="csrf-token" content="<?= htmlspecialchars($_SESSION['csrf_token'] ?? '') ?>">
<link rel="stylesheet" href="https://cdn.metroui.org.ua/current/metro.css">
<link rel="stylesheet" href="https://cdn.metroui.org.ua/current/icons.css">
<link rel="stylesheet" href="assets/admin.css">
</head>
<body class="sws-body dark-side">

<div class="sws-layout">

  <!-- ===== Sidebar ===== -->
  <nav class="sws-sidebar" id="sws-sidebar">
    <div class="sws-sidebar-logo">
      <span class="mif-sun fg-yellow"></span>
      <span>SWS Admin</span>
    </div>
    <ul class="sws-nav">
      <li><a href="#stations"    class="sws-nav-link active" data-section="stations">   <span class="mif-broadcast"></span>   Stationen</a></li>
      <li><a href="#metrics"     class="sws-nav-link"        data-section="metrics">    <span class="mif-chart-bars"></span>  Metriken</a></li>
      <li><a href="#users"       class="sws-nav-link"        data-section="users">      <span class="mif-users"></span>       Benutzer</a></li>
      <li><a href="#invites"     class="sws-nav-link"        data-section="invites">    <span class="mif-mail-forward"></span> Einladungen</a></li>
      <li class="sws-nav-divider"></li>
      <li><a href="#live"        class="sws-nav-link"        data-section="live">       <span class="mif-pulse"></span>       Live-Daten</a></li>
      <li><a href="#history"     class="sws-nav-link"        data-section="history">    <span class="mif-chart-line"></span>  Historie</a></li>
      <li><a href="#errorlog"    class="sws-nav-link"        data-section="errorlog">   <span class="mif-warning"></span>     Fehler-Log</a></li>
      <li class="sws-nav-divider"></li>
      <li><a href="#credentials" class="sws-nav-link"        data-section="credentials"><span class="mif-lock"></span>        Credentials</a></li>
      <li><a href="#ota"         class="sws-nav-link"        data-section="ota">        <span class="mif-upload"></span>      OTA-Firmware</a></li>
      <li class="sws-nav-spacer"></li>
      <li><a href="?action=logout" class="sws-nav-link sws-nav-logout"><span class="mif-exit"></span> Abmelden</a></li>
    </ul>
  </nav>

  <!-- ===== Content ===== -->
  <div class="sws-content">

    <!-- Appbar -->
    <div class="sws-appbar">
      <button class="sws-hamburger" id="nav-toggle" onclick="document.getElementById('sws-sidebar').classList.toggle('collapsed')">
        <span class="mif-menu"></span>
      </button>
      <span id="sws-page-title" class="sws-appbar-title">Stationen</span>
    </div>

    <div class="sws-page-wrap">

      <section id="stations" class="sws-section">
        <div class="sws-section-header">
          <h2 class="sws-section-title">Stationen</h2>
          <button class="button primary" onclick="openAddStation()"><span class="mif-plus"></span> Station hinzufügen</button>
        </div>
        <div id="stations-table"></div>
      </section>

      <section id="metrics" class="sws-section" style="display:none">
        <div class="sws-section-header">
          <h2 class="sws-section-title">Metriken</h2>
          <button class="button primary" onclick="openAddMetric()"><span class="mif-plus"></span> Metrik hinzufügen</button>
        </div>
        <div id="metrics-table"></div>
      </section>

      <section id="users" class="sws-section" style="display:none">
        <div class="sws-section-header">
          <h2 class="sws-section-title">Benutzer</h2>
          <button id="btn-migrate" class="button secondary"><span class="mif-cog"></span> DB-Migration</button>
        </div>
        <p class="remark">Benutzer können über Einladungscodes registrieren. Hier kannst du E-Mail, Rolle und Passwort ändern oder Konten löschen.</p>
        <div id="users-table"></div>
      </section>

      <section id="invites" class="sws-section" style="display:none">
        <div class="sws-section-header">
          <h2 class="sws-section-title">Einladungscodes</h2>
          <button class="button primary" onclick="createInvite()"><span class="mif-plus"></span> Code generieren</button>
        </div>
        <div id="invites-table"></div>
      </section>

      <section id="live" class="sws-section" style="display:none">
        <div class="sws-section-header">
          <h2 class="sws-section-title">Live-Daten</h2>
          <select id="live-station" class="select" style="width:200px"></select>
        </div>
        <div id="live-data"></div>
      </section>

      <section id="history" class="sws-section" style="display:none">
        <div class="sws-section-header">
          <h2 class="sws-section-title"><span class="mif-chart-line"></span> Historie</h2>
          <select id="history-station" class="select" style="width:200px"></select>
          <select id="history-hours" class="select" style="width:130px">
            <option value="24">Letzte 24 Stunden</option>
            <option value="72">Letzte 3 Tage</option>
            <option value="168">Letzte 7 Tage</option>
            <option value="720">Letzte 30 Tage</option>
          </select>
        </div>
        <div id="history-charts" class="sws-history-grid"></div>
      </section>

      <section id="credentials" class="sws-section" style="display:none">
        <div class="sws-section-header">
          <h2 class="sws-section-title"><span class="mif-lock"></span> Credentials rotieren</h2>
        </div>
        <p class="remark">Ändere API-Zugangsdaten, Admin-Passwort oder JWT-Secret.<br>
          Geänderte API-Zugangsdaten müssen in <code>Settings26.h</code> der Station eingetragen werden.</p>
        <div class="sws-form-wrap">
          <div id="cred-msg"></div>
          <form id="cred-form">
            <fieldset class="sws-fieldset">
              <legend>Aktuelles Admin-Passwort (zur Bestätigung)</legend>
              <div class="form-group">
                <label>Admin-Passwort <span class="fg-red">*</span></label>
                <input type="password" name="admin_password" class="metro-input" required autocomplete="current-password" placeholder="Aktuelles Passwort">
              </div>
            </fieldset>
            <fieldset class="sws-fieldset">
              <legend>API-Zugangsdaten (Station → API)</legend>
              <div class="row">
                <div class="cell-6"><div class="form-group">
                  <label>API-Benutzername</label>
                  <input type="text" name="api_user" class="metro-input" autocomplete="off" placeholder="Leer = nicht ändern">
                </div></div>
                <div class="cell-6"><div class="form-group">
                  <label>API-Passwort</label>
                  <input type="password" name="api_pass" class="metro-input" autocomplete="new-password" placeholder="min. 12 Zeichen">
                </div></div>
              </div>
            </fieldset>
            <fieldset class="sws-fieldset">
              <legend>Admin-Dashboard Login</legend>
              <div class="row">
                <div class="cell-6"><div class="form-group">
                  <label>Neues Admin-Passwort</label>
                  <input type="password" name="admin_pass" class="metro-input" autocomplete="new-password" placeholder="min. 12 Zeichen">
                </div></div>
                <div class="cell-6"><div class="form-group">
                  <label>Passwort wiederholen</label>
                  <input type="password" name="admin_pass_confirm" class="metro-input" autocomplete="new-password" placeholder="Wiederholung">
                </div></div>
              </div>
            </fieldset>
            <fieldset class="sws-fieldset">
              <legend>JWT-Secret (Flutter-App)</legend>
              <div class="form-group">
                <label>JWT-Secret</label>
                <input type="text" name="jwt_secret" class="metro-input" autocomplete="off" placeholder="Leer = nicht ändern">
                <span class="remark">Mindestens 32 Zeichen. Nach Änderung müssen alle App-Nutzer sich neu anmelden.</span>
              </div>
            </fieldset>
            <div class="sws-btn-row">
              <button type="submit" class="button success" id="cred-submit">Credentials speichern</button>
            </div>
          </form>
        </div>
      </section>

      <section id="errorlog" class="sws-section" style="display:none">
        <div class="sws-section-header">
          <h2 class="sws-section-title"><span class="mif-warning"></span> Stationsfehler</h2>
        </div>
        <div class="sws-filter-bar">
          <select id="err-level" class="select" style="width:140px"><option value="">Alle Level</option><option value="error">error</option><option value="warning">warning</option><option value="info">info</option></select>
          <select id="err-station" class="select" style="width:180px"><option value="">Alle Stationen</option></select>
          <button class="button secondary" onclick="loadErrorLog()"><span class="mif-refresh"></span> Aktualisieren</button>
        </div>
        <div id="errorlog-table"></div>
      </section>

      <section id="ota" class="sws-section" style="display:none">
        <div class="sws-section-header">
          <h2 class="sws-section-title"><span class="mif-upload"></span> OTA-Firmware</h2>
        </div>
        <div class="sws-ota-wrap">
          <div id="ota-cards" class="sws-ota-grid"></div>
          <div class="sws-ota-panel" id="ota-upload-panel">
            <div class="card-header"><span class="mif-upload"></span> Neues Firmware-Update hochladen</div>
            <div class="card-content">
              <form id="ota-upload-form" onsubmit="otaUpload(event)">
                <div class="form-group">
                  <label>Hardware / Sketch</label>
                  <select name="sketch" id="ota-sketch-select" required><option value="">– wird geladen –</option></select>
                </div>
                <div class="form-group" style="margin-top:10px">
                  <label>Neue Version</label>
                  <input type="text" name="version" id="ota-version-input" placeholder="z.B. 2.7.2" pattern="\d+\.\d+(\.\d+)?" required>
                </div>
                <div class="form-group" style="margin-top:10px">
                  <label>Firmware-Datei (.bin)</label>
                  <input type="file" name="firmware" accept=".bin" required>
                </div>
                <div class="sws-btn-row" style="margin-top:14px">
                  <button type="submit" class="button success" id="ota-submit-btn"><span class="mif-upload"></span> Hochladen &amp; aktivieren</button>
                </div>
              </form>
              <div id="ota-upload-msg" style="margin-top:8px"></div>
            </div>
          </div>
        </div>
      </section>

    </div><!-- .sws-page-wrap -->
  </div><!-- .sws-content -->
</div><!-- .sws-layout -->

<!-- Edit-Modal -->
<div id="edit-modal" class="sws-modal-overlay" style="display:none">
  <div class="dialog sws-dialog" role="dialog">
    <div class="dialog-title" id="edit-modal-title">Bearbeiten</div>
    <div class="dialog-content">
      <div id="edit-modal-msg" class="sws-msg-err"></div>
      <form id="edit-modal-form"></form>
    </div>
    <div class="dialog-actions">
      <button type="submit" form="edit-modal-form" class="button success">Speichern</button>
      <button type="button" id="edit-modal-close" class="button secondary">Abbrechen</button>
    </div>
  </div>
</div>

<!-- Metrik-Modal -->
<div id="modal" class="sws-modal-overlay" style="display:none">
  <div class="dialog sws-dialog" role="dialog">
    <div class="dialog-title" id="modal-title">Metrik</div>
    <div class="dialog-content">
      <form id="metric-form">
        <input type="hidden" name="metric_key_orig">
        <div class="form-group"><label>Key</label><input type="text" name="metric_key" class="metro-input" required></div>
        <div class="form-group mt-2"><label>Bezeichnung</label><input type="text" name="label" class="metro-input" required></div>
        <div class="form-group mt-2"><label>Einheit</label><input type="text" name="unit" class="metro-input"></div>
        <div class="form-group mt-2"><label>Reihenfolge</label><input type="number" name="display_order" class="metro-input" value="99" min="0"></div>
        <div class="form-group mt-2"><label>Farbe</label><input type="color" name="chart_color" value="#4e79a7"></div>
      </form>
    </div>
    <div class="dialog-actions">
      <button type="submit" form="metric-form" class="button success">Speichern</button>
      <button type="button" onclick="closeModal()" class="button secondary">Abbrechen</button>
    </div>
  </div>
</div>

<script src="https://cdn.metroui.org.ua/current/metro.js"></script>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns@3/dist/chartjs-adapter-date-fns.bundle.min.js"></script>
<script src="assets/admin.js"></script>
</body>
</html>
