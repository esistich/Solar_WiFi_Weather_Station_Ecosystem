# build_upload.ps1
# Synchronisiert api/ -> upload/ fuer Server-Deployment.
# Dateien mit echten Credentials und temporaere Dateien werden ausgeschlossen.

$src  = (Resolve-Path (Join-Path $PSScriptRoot "..\api")).Path
$dest = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "upload")

# Dateien/Muster die NICHT hochgeladen werden sollen
$exclude = @(
	"credentials.php",
	"auth.php",
	"db.php",
	"jwt.php",
	"*adminsdk*.json",
	"*firebase*.json",
	"*_diag.php",
	"diag.php",
	".setup_done",
	"*.bin",
	".gitkeep"
)

# Zielordner anlegen falls nicht vorhanden
if (-not (Test-Path $dest)) {
	New-Item -ItemType Directory -Path $dest | Out-Null
}

# Alle Dateien aus api/ kopieren (rekursiv, mit Ausnahmen)
$copied  = 0
$skipped = 0

Get-ChildItem $src -Recurse -File | ForEach-Object {
	$file = $_

	# Ausschluss pruefen
	$skip = $false
	foreach ($pattern in $exclude) {
		if ($file.Name -like $pattern) { $skip = $true; break }
	}

	# firmware/-Unterordner komplett ausschliessen (nur .gitkeep behalten)
	if ($file.FullName -match [regex]::Escape("ota\firmware\") -and $file.Name -ne ".gitkeep") {
		$skip = $true
	}

	if ($skip) {
		$skipped++
		return
	}

	# Zielpfad berechnen
	$rel      = $file.FullName.Substring($src.Length).TrimStart('\')
	$destFile = Join-Path $dest $rel
	$destDir  = Split-Path $destFile

	if (-not (Test-Path $destDir)) {
		New-Item -ItemType Directory -Path $destDir -Force | Out-Null
	}

	Copy-Item $file.FullName $destFile -Force
	$copied++
}

# Veraltete Dateien im upload/-Ordner entfernen die in api/ nicht mehr existieren
Get-ChildItem $dest -Recurse -File | ForEach-Object {
	if (-not $_.FullName.StartsWith($dest)) { return }
	$rel     = $_.FullName.Substring($dest.Length).TrimStart('\')
	$srcFile = Join-Path $src $rel
	if (-not (Test-Path $srcFile)) {
		Remove-Item $_.FullName -Force
		Write-Host "Entfernt (nicht mehr in api/): $rel"
	}
}

# Leere Verzeichnisse aufraumen
Get-ChildItem $dest -Recurse -Directory | Sort-Object FullName -Descending | ForEach-Object {
	if (-not (Get-ChildItem $_.FullName)) {
		Remove-Item $_.FullName -Force
	}
}

Write-Host "Upload-Ordner aktualisiert: $copied Dateien kopiert, $skipped ausgeschlossen."
