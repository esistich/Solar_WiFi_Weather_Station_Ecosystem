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
