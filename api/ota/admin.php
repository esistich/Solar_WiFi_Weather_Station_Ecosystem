<?php
/**
 * OTA-Admin-Bereich
 *
 * Zeigt aktuelle Versionen aller Sketches an und erlaubt das Hochladen
 * einer neuen firmware.bin sowie das Aktualisieren der version.txt.
 *
 * Geschuetzt durch HTTP Basic Auth (gleiche Credentials wie API).
 * Aufruf: https://{host}/sws/ota/admin.php
 *
 * Neue Sketches erscheinen automatisch sobald ein Unterordner unter
 * api/ota/firmware/ angelegt wird.
 */

declare(strict_types=1);

require_once __DIR__ . '/../lib/auth.php';
require_once __DIR__ . '/../config/db.php';

requireBasicAuth();

$db           = getDb();
$firmwareBase = __DIR__ . '/firmware';
$message      = '';
$messageType  = '';
$stMessage    = '';
$stMessageType = '';

// ---- POST: Firmware oder Version hochladen ----
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
	$sketch  = preg_replace('/[^a-z0-9_\-]/', '', strtolower($_POST['sketch'] ?? ''));
	$action  = $_POST['action'] ?? '';
	$sketchDir = $firmwareBase . '/' . $sketch;

	if ($sketch === '' || !is_dir($sketchDir)) {
		$message     = 'Unbekannter Sketch-Bezeichner.';
		$messageType = 'error';
	} elseif ($action === 'upload_firmware') {
		$tmp = $_FILES['firmware']['tmp_name'] ?? '';
		if (!$tmp || !is_uploaded_file($tmp)) {
			$message     = 'Keine Datei empfangen.';
			$messageType = 'error';
		} else {
			$dest = $sketchDir . '/firmware.bin';
			if (move_uploaded_file($tmp, $dest)) {
				$message     = "firmware.bin fuer '$sketch' erfolgreich hochgeladen (" . number_format(filesize($dest) / 1024, 1) . ' KB).';
				$messageType = 'success';
			} else {
				$message     = 'Fehler beim Speichern der Datei.';
				$messageType = 'error';
			}
		}
	} elseif ($action === 'update_version') {
		$newVer = trim($_POST['version'] ?? '');
		if (!preg_match('/^\d+\.\d+(\.\d+)?$/', $newVer)) {
			$message     = 'Ungueltige Versionsnummer (erwartet: X.Y oder X.Y.Z).';
			$messageType = 'error';
		} else {
			file_put_contents($sketchDir . '/version.txt', $newVer . "\n");
			$message     = "Version fuer '$sketch' auf $newVer gesetzt.";
			$messageType = 'success';
		}
	}
}

// ---- POST: Stationsname/-Slug aendern ----
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['action'] ?? '') === 'update_station') {
	$stId   = (int)($_POST['station_id'] ?? 0);
	$stName = trim($_POST['station_name'] ?? '');
	$stSlug = trim(strtolower($_POST['station_slug'] ?? ''));

	if (!$stId) {
		$stMessage     = 'Ungueltige Station-ID.';
		$stMessageType = 'error';
	} elseif ($stName === '' || $stSlug === '') {
		$stMessage     = 'Name und Slug duerfen nicht leer sein.';
		$stMessageType = 'error';
	} elseif (!preg_match('/^[a-z0-9][a-z0-9\-]{0,62}$/', $stSlug)) {
		$stMessage     = 'Slug ungueltig (nur a-z, 0-9, Bindestrich).';
		$stMessageType = 'error';
	} else {
		$dup = $db->prepare('SELECT id FROM stations WHERE slug = ? AND id != ? LIMIT 1');
		$dup->execute([$stSlug, $stId]);
		if ($dup->fetch()) {
			$stMessage     = "Slug '$stSlug' ist bereits vergeben.";
			$stMessageType = 'error';
		} else {
			$db->prepare('UPDATE stations SET name = ?, slug = ? WHERE id = ?')
			   ->execute([$stName, $stSlug, $stId]);
			$stMessage     = "Station aktualisiert: '$stName' (slug: $stSlug).";
			$stMessageType = 'success';
		}
	}
}

// ---- Alle Sketch-Ordner einlesen ----
$sketches = [];
if (is_dir($firmwareBase)) {
	foreach (scandir($firmwareBase) as $entry) {
		if ($entry[0] === '.') continue;
		$dir = $firmwareBase . '/' . $entry;
		if (!is_dir($dir)) continue;

		$versionFile  = $dir . '/version.txt';
		$firmwareFile = $dir . '/firmware.bin';
		$sketches[]   = [
			'id'             => $entry,
			'version'        => file_exists($versionFile)  ? trim(file_get_contents($versionFile)) : '—',
			'firmware_size'  => file_exists($firmwareFile) ? filesize($firmwareFile) : null,
			'firmware_mtime' => file_exists($firmwareFile) ? filemtime($firmwareFile) : null,
		];
	}
}

// ---- Stationen aus DB laden ----
$stations = $db->query('SELECT id, slug, name FROM stations ORDER BY id')->fetchAll();

?><!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>OTA-Verwaltung – SWS</title>
<style>
  body { font-family: sans-serif; max-width: 860px; margin: 40px auto; padding: 0 16px; color: #222; }
  h1   { font-size: 1.4rem; margin-bottom: 4px; }
  h2   { font-size: 1.1rem; margin: 32px 0 8px; border-bottom: 1px solid #ddd; padding-bottom: 4px; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 16px; }
  th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid #eee; }
  th { background: #f5f5f5; font-weight: 600; }
  .ok   { color: #2a7a2a; font-weight: 600; }
  .warn { color: #b06000; }
  .msg-success { background: #e6f4ea; border: 1px solid #b7dfb8; padding: 10px 14px; border-radius: 4px; margin-bottom: 20px; }
  .msg-error   { background: #fdecea; border: 1px solid #f5c6c6; padding: 10px 14px; border-radius: 4px; margin-bottom: 20px; }
  form  { display: inline; }
  .card { border: 1px solid #ddd; border-radius: 6px; padding: 16px 20px; margin-bottom: 20px; }
  .card h3 { margin: 0 0 12px; font-size: 1rem; }
  input[type=text], input[type=file] { padding: 5px 8px; border: 1px solid #bbb; border-radius: 3px; }
  input[type=text].slug { width: 160px; }
  input[type=text].stname { width: 220px; }
  button { padding: 6px 16px; background: #0057a8; color: #fff; border: none; border-radius: 3px; cursor: pointer; }
  button:hover { background: #004080; }
  .sep { color: #bbb; margin: 0 6px; }
  small { color: #888; }
</style>
</head>
<body>

<h1>OTA-Firmware-Verwaltung</h1>
<p><small>Firmware-Updates fuer alle SWS-Sketches verwalten. Basic Auth entspricht der API.</small></p>

<?php if ($message !== ''): ?>
<div class="msg-<?= $messageType ?>">
  <?= htmlspecialchars($message) ?>
</div>
<?php endif; ?>

<h2>Aktuelle Versionen</h2>
<table>
  <tr><th>Sketch</th><th>Version</th><th>firmware.bin</th><th>Zuletzt geaendert</th></tr>
  <?php foreach ($sketches as $s): ?>
  <tr>
	<td><strong><?= htmlspecialchars($s['id']) ?></strong></td>
	<td class="ok"><?= htmlspecialchars($s['version']) ?></td>
	<td><?= $s['firmware_size'] !== null
		  ? number_format($s['firmware_size'] / 1024, 1) . ' KB'
		  : '<span class="warn">nicht vorhanden</span>' ?></td>
	<td><?= $s['firmware_mtime'] !== null
		  ? date('d.m.Y H:i', $s['firmware_mtime'])
		  : '—' ?></td>
  </tr>
  <?php endforeach; ?>
  <?php if (empty($sketches)): ?>
  <tr><td colspan="4"><em>Keine Sketch-Ordner gefunden unter api/ota/firmware/</em></td></tr>
  <?php endif; ?>
</table>

<?php foreach ($sketches as $s): ?>
<div class="card">
  <h3><?= htmlspecialchars($s['id']) ?> – Version: <?= htmlspecialchars($s['version']) ?></h3>

  <form method="post" enctype="multipart/form-data">
	<input type="hidden" name="sketch" value="<?= htmlspecialchars($s['id']) ?>">
	<input type="hidden" name="action" value="upload_firmware">
	<label>Neue firmware.bin hochladen:</label><br><br>
	<input type="file" name="firmware" accept=".bin" required>
	<button type="submit">Hochladen</button>
  </form>

  <hr style="margin:14px 0; border:none; border-top:1px solid #eee;">

  <form method="post">
	<input type="hidden" name="sketch" value="<?= htmlspecialchars($s['id']) ?>">
	<input type="hidden" name="action" value="update_version">
	<label>Versionsnummer setzen:</label><br><br>
	<input type="text" name="version" value="<?= htmlspecialchars($s['version']) ?>" pattern="\d+\.\d+(\.\d+)?" placeholder="z.B. 2.7.1" required>
	<button type="submit">Speichern</button>
  </form>
</div>
<?php endforeach; ?>

<h2>Neuen Sketch hinzufuegen</h2>
<p>Einfach einen neuen Ordner unter <code>api/ota/firmware/{sketch-id}/</code> anlegen
und dort eine <code>version.txt</code> (Inhalt: Versionsnummer) ablegen.<br>
Der neue Sketch erscheint beim naechsten Seitenaufruf automatisch.</p>

<h2>Stationen</h2>
<?php if ($stMessage !== ''): ?>
<div class="msg-<?= $stMessageType ?>">
  <?= htmlspecialchars($stMessage) ?>
</div>
<?php endif; ?>

<?php if (empty($stations)): ?>
<p><em>Keine Stationen in der Datenbank.</em></p>
<?php else: ?>
<table>
  <tr><th>ID</th><th>Slug</th><th>Name</th><th>Aktion</th></tr>
  <?php foreach ($stations as $st): ?>
  <tr>
    <td><?= htmlspecialchars((string)$st['id']) ?></td>
    <td><?= htmlspecialchars($st['slug']) ?></td>
    <td><?= htmlspecialchars($st['name']) ?></td>
    <td>
      <form method="post" style="display:flex;gap:6px;align-items:center;flex-wrap:wrap">
        <input type="hidden" name="action" value="update_station">
        <input type="hidden" name="station_id" value="<?= (int)$st['id'] ?>">
        <input type="text" class="stname" name="station_name" value="<?= htmlspecialchars($st['name']) ?>" placeholder="Name" required>
        <input type="text" class="slug"   name="station_slug" value="<?= htmlspecialchars($st['slug']) ?>" placeholder="slug" pattern="[a-z0-9][a-z0-9\-]{0,62}" required>
        <button type="submit">Speichern</button>
      </form>
    </td>
  </tr>
  <?php endforeach; ?>
</table>
<?php endif; ?>

<p style="margin-top:40px;color:#aaa;font-size:0.85rem">
  SWS OTA-Admin &bull; <?= date('d.m.Y H:i') ?>
</p>
</body>
</html>
