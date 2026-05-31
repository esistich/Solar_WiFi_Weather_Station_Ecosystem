<?php
/**
 * Admin-Dashboard – Einstiegspunkt
 * Session-basierte Authentifizierung; kein JWT benötigt.
 */
declare(strict_types=1);

session_start();

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
	$user = trim($_POST['username'] ?? '');
	$pass = $_POST['password'] ?? '';
	if ($user === ADMIN_USER && password_verify($pass, ADMIN_PASS_HASH)) {
		session_regenerate_id(true);
		$_SESSION['admin'] = true;
		header('Location: index.php');
		exit;
	}
	$loginError = 'Benutzername oder Passwort falsch.';
}

$loggedIn = !empty($_SESSION['admin']);

// ----- Admin-API (JSON) -----
if ($loggedIn && str_starts_with($action, 'api/')) {
	require __DIR__ . '/api.php';
	exit;
}

// ----- Login-Seite -----
if (!$loggedIn): ?>
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SWS Admin – Login</title>
<link rel="stylesheet" href="assets/admin.css">
</head>
<body class="login-page">
<div class="login-card">
  <h1>☀️ SWS Admin</h1>
  <?php if (!empty($loginError)): ?>
  <p class="error"><?= htmlspecialchars($loginError) ?></p>
  <?php endif ?>
  <form method="post" action="?action=login">
	<label>Benutzername<input type="text" name="username" autofocus autocomplete="username"></label>
	<label>Passwort<input type="password" name="password" autocomplete="current-password"></label>
	<button type="submit">Anmelden</button>
  </form>
</div>
</body>
</html>
<?php exit; endif; ?>
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SWS Admin</title>
<link rel="stylesheet" href="assets/admin.css">
</head>
<body>
<nav class="sidebar">
  <div class="logo">☀️ SWS Admin</div>
  <a href="#stations"  class="nav-link" data-section="stations">Stationen</a>
  <a href="#metrics"   class="nav-link" data-section="metrics">Metriken</a>
  <a href="#users"     class="nav-link" data-section="users">Benutzer</a>
  <a href="#invites"   class="nav-link" data-section="invites">Einladungen</a>
  <a href="#live"      class="nav-link" data-section="live">Live-Daten</a>
  <a href="#credentials" class="nav-link" data-section="credentials">🔐 Credentials</a>
  <a href="#errorlog"  class="nav-link" data-section="errorlog">⚠️ Fehler-Log</a>
  <a href="#ota"       class="nav-link" data-section="ota">📦 OTA-Firmware</a>
  <a href="?action=logout" class="nav-link logout">Abmelden</a>
</nav>
<main class="content">
  <section id="stations"  class="section">
	<h2>Stationen</h2>
	<div id="stations-table"></div>
  </section>
  <section id="metrics"   class="section hidden">
	<h2>Metriken</h2>
	<button class="btn-add" onclick="openAddMetric()">+ Metrik hinzufügen</button>
	<div id="metrics-table"></div>
  </section>
  <section id="users"     class="section hidden">
	<h2>Benutzer</h2>
	<div id="users-table"></div>
  </section>
  <section id="invites"   class="section hidden">
	<h2>Einladungscodes</h2>
	<button class="btn-add" onclick="createInvite()">+ Code generieren</button>
	<div id="invites-table"></div>
  </section>
  <section id="live"      class="section hidden">
	<h2>Live-Daten</h2>
	<label>Station:
	  <select id="live-station"></select>
	</label>
	<div id="live-data" class="live-grid"></div>
  </section>

  <section id="credentials" class="section hidden">
	<h2>🔐 Credentials rotieren</h2>
	<p class="section-hint">Ändere API-Zugangsdaten, Admin-Passwort oder JWT-Secret direkt hier.<br>
	  Geänderte API-Zugangsdaten müssen anschließend in <code>Settings26.h</code> der Station eingetragen werden.</p>

	<div class="cred-form-wrap">
	  <div id="cred-msg"></div>
	  <form id="cred-form" class="cred-form">
		<fieldset>
		  <legend>Aktuelles Admin-Passwort (zur Bestätigung)</legend>
		  <label>Admin-Passwort <span class="req">*</span>
			<input type="password" name="admin_password" required autocomplete="current-password" placeholder="Aktuelles Passwort">
		  </label>
		</fieldset>
		<fieldset>
		  <legend>API-Zugangsdaten (Station → API)</legend>
		  <div class="form-row">
			<label>API-Benutzername
			  <input type="text" name="api_user" autocomplete="off" placeholder="Leer = nicht ändern">
			</label>
			<label>API-Passwort
			  <input type="password" name="api_pass" autocomplete="new-password" placeholder="min. 12 Zeichen">
			</label>
		  </div>
		</fieldset>
		<fieldset>
		  <legend>Admin-Dashboard Login</legend>
		  <div class="form-row">
			<label>Neues Admin-Passwort
			  <input type="password" name="admin_pass" autocomplete="new-password" placeholder="min. 12 Zeichen">
			</label>
			<label>Passwort wiederholen
			  <input type="password" name="admin_pass_confirm" autocomplete="new-password" placeholder="Wiederholung">
			</label>
		  </div>
		</fieldset>
		<fieldset>
		  <legend>JWT-Secret (Flutter-App)</legend>
		  <label>JWT-Secret
			<input type="text" name="jwt_secret" autocomplete="off" placeholder="Leer = nicht ändern">
			<span class="hint">Mindestens 32 Zeichen. Nach Änderung müssen alle App-Nutzer sich neu anmelden.</span>
		  </label>
		</fieldset>
		<div class="btn-row">
		  <button type="submit" class="btn-save" id="cred-submit">Credentials speichern</button>
		</div>
	  </form>
	</div>
  </section>

  <section id="errorlog" class="section hidden">
	<h2>⚠️ Stationsfehler</h2>
	<div class="errorlog-filter">
	  <select id="err-level"><option value="">Alle Level</option><option value="error">error</option><option value="warning">warning</option><option value="info">info</option></select>
	  <select id="err-station"><option value="">Alle Stationen</option></select>
	  <button class="btn-add" onclick="loadErrorLog()">Aktualisieren</button>
	</div>
	<div id="errorlog-table"></div>
  </section>

  <section id="ota" class="section hidden">
    <h2>&#x1F4E6; OTA-Firmware</h2>

    <div id="ota-cards"></div>

    <div class="ota-upload-panel" id="ota-upload-panel">
      <h3>&#x2B06;&#xFE0F; Neues Firmware-Update hochladen</h3>
      <form id="ota-upload-form" onsubmit="otaUpload(event)" class="ota-form">
        <label>
          Hardware / Sketch
          <select name="sketch" id="ota-sketch-select" required>
            <option value="">– wird geladen –</option>
          </select>
        </label>
        <label>
          Neue Version
          <input type="text" name="version" id="ota-version-input"
                 placeholder="z.B. 2.7.2" pattern="\d+\.\d+(\.\d+)?" required>
        </label>
        <label>
          Firmware-Datei (.bin)
          <input type="file" name="firmware" accept=".bin" required>
        </label>
        <div class="btn-row">
          <button type="submit" class="btn-save" id="ota-submit-btn">&#x1F4E4; Hochladen &amp; aktivieren</button>
        </div>
      </form>
      <div id="ota-upload-msg"></div>
    </div>
  </section>
</main>

<!-- Modal für Metrik hinzufügen/bearbeiten -->
<div id="modal" class="modal hidden">
  <div class="modal-box">
	<h3 id="modal-title">Metrik</h3>
	<form id="metric-form">
	  <input type="hidden" name="metric_key_orig">
	  <label>Key (intern, unveränderlich bei Bearbeitung)<input type="text" name="metric_key" required></label>
	  <label>Bezeichnung<input type="text" name="label" required></label>
	  <label>Einheit<input type="text" name="unit"></label>
	  <label>Reihenfolge<input type="number" name="display_order" value="99" min="0"></label>
	  <label>Farbe<input type="color" name="chart_color" value="#4e79a7"></label>
	  <div class="modal-actions">
		<button type="submit" class="btn-save">Speichern</button>
		<button type="button" onclick="closeModal()">Abbrechen</button>
	  </div>
	</form>
  </div>
</div>

<script src="assets/admin.js"></script>
</body>
</html>
