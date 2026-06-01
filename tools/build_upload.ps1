# build_upload.ps1
# Synchronisiert api/ -> upload/ fuer Server-Deployment.
# Dateien mit echten Credentials und temporaere Dateien werden ausgeschlossen.

$src  = (Resolve-Path (Join-Path $PSScriptRoot "..\api")).Path
$dest = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "upload")

# Dateien/Muster die NICHT hochgeladen werden sollen
# Dateien/Muster die NICHT hochgeladen werden sollen.
# excludeRelPaths: Pruefung gegen relativen Pfad (relativ zu api/).
# excludeNames: Pruefung nur gegen Dateinamen (Wildcards).
$excludeRelPaths = @(
    "config\config.php"    # Zentrale Secrets-Datei – manuell auf Server ablegen
)
$excludeNames = @(
    "*adminsdk*.json",     # Firebase Service-Account – niemals deployen
    "*firebase*.json",
    "*_diag.php",
    "diag.php",
    ".setup_done",
    "*.bin",
    ".gitkeep",
    "firmware.bin"
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
$rel = $file.FullName.Substring($src.Length).TrimStart("\/").Replace("/", "\")
$skip = $false
# Relativer Pfad-Ausschluss (z.B. config\config.php)
foreach ($p in $excludeRelPaths) {
if ($rel -eq $p) { $skip = $true; break }
}
# Dateiname-Ausschluss (Wildcards)
if (-not $skip) {
foreach ($pattern in $excludeNames) {
if ($file.Name -like $pattern) { $skip = $true; break }
}
}

	# firmware/-Unterordner: nur .bin und .gitkeep ausschliessen,
	# version.txt, .htaccess und Ordnerstruktur werden benoetigt damit die Hardware den richtigen Pfad findet
	if ($file.FullName -match [regex]::Escape("ota\firmware\") -and $file.Name -notin @("version.txt", ".htaccess")) {
		$skip = $true
	}

	if ($skip) {
		$skipped++
		return
	}

	# Zielpfad berechnen
# $rel wurde bereits oben berechnet
	$destFile = Join-Path $dest $rel
	$destDir  = Split-Path $destFile

	if (-not (Test-Path $destDir)) {
		New-Item -ItemType Directory -Path $destDir -Force | Out-Null
	}

	Copy-Item $file.FullName $destFile -Force

	# PHP-Dateien: UTF-8 BOM entfernen (Set-Content schreibt BOM, PHP verträgt das nicht)
	if ($file.Extension -eq '.php') {
		$b = [System.IO.File]::ReadAllBytes($destFile)
		if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
			[System.IO.File]::WriteAllBytes($destFile, $b[3..($b.Length-1)])
		}
	}
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
