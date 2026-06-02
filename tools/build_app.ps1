# build_app.ps1
# Flutter-App bauen (Release-APK) und optional auf angeschlossenes Android-Geraet deployen.
#
# Verwendung:
#   .\tools\build_app.ps1            # nur bauen
#   .\tools\build_app.ps1 -Deploy    # bauen + auf Geraet installieren (falls verbunden)
#   .\tools\build_app.ps1 -Device emulator-5554  # gezielt ein bestimmtes Geraet
#
# Voraussetzungen:
#   - Flutter SDK unter C:\flutter\bin (oder im PATH)
#   - Android SDK / adb erreichbar (kommt mit Flutter SDK)
#   - USB-Debugging auf dem Smartphone aktiviert

param(
	[switch]$Deploy,
	[string]$Device = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Pfade
# ---------------------------------------------------------------------------
$root    = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$appDir  = Join-Path $root "app"
$outDir  = Join-Path $appDir "build\app\outputs\flutter-apk"
$apkName = "app-release.apk"
$apkPath = Join-Path $outDir $apkName

# Flutter-SDK zu PATH hinzufuegen falls nicht bereits vorhanden
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
	$env:PATH = "C:\flutter\bin;" + $env:PATH
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
	Write-Error "flutter nicht gefunden. Bitte Flutter SDK unter C:\flutter installieren oder zum PATH hinzufuegen."
	exit 1
}

# ---------------------------------------------------------------------------
# Hilfsfunktion: farbige Ausgabe
# ---------------------------------------------------------------------------
function Write-Step  { param([string]$msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$msg) Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn  { param([string]$msg) Write-Host "    [!] $msg" -ForegroundColor Yellow }
function Write-Fail  { param([string]$msg) Write-Host "    [X] $msg" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Schritt 1: pub get
# ---------------------------------------------------------------------------
Write-Step "Abhaengigkeiten aktualisieren (flutter pub get)"
Push-Location $appDir
try {
	flutter pub get
	if ($LASTEXITCODE -ne 0) { Write-Fail "flutter pub get fehlgeschlagen."; exit 1 }
	Write-Ok "pub get abgeschlossen."
} finally {
	Pop-Location
}

# ---------------------------------------------------------------------------
# Schritt 2: Release-APK bauen
# ---------------------------------------------------------------------------
Write-Step "Release-APK bauen (flutter build apk --release)"
Push-Location $appDir
try {
	flutter build apk --release
	if ($LASTEXITCODE -ne 0) { Write-Fail "Build fehlgeschlagen."; exit 1 }
} finally {
	Pop-Location
}

if (-not (Test-Path $apkPath)) {
	Write-Fail "APK nicht gefunden unter: $apkPath"
	exit 1
}

$apkSize = [math]::Round((Get-Item $apkPath).Length / 1MB, 1)
Write-Ok "APK erstellt: $apkPath ($apkSize MB)"

# ---------------------------------------------------------------------------
# Schritt 3: Deployen (optional)
# ---------------------------------------------------------------------------
if (-not $Deploy) {
	Write-Warn "Kein -Deploy angegeben – APK wird nicht installiert."
	Write-Host "`nFertig. APK liegt unter:`n  $apkPath`n" -ForegroundColor White
	exit 0
}

Write-Step "Verbundene Android-Geraete pruefen (adb devices)"

# adb liegt im Flutter-SDK
$adb = "C:\flutter\bin\cache\artifacts\platform-tools\windows\adb.exe"
if (-not (Test-Path $adb)) {
	# Fallback: adb aus PATH
	$adb = "adb"
}

$adbOut = & $adb devices 2>&1
Write-Host $adbOut

# Geraete-Liste parsen (Zeilen mit "device" am Ende, Emulator oder echtes Geraet)
$devices = $adbOut | Where-Object { $_ -match "^\S+\s+device$" } |
		   ForEach-Object { ($_ -split "\s+")[0] }

if ($devices.Count -eq 0) {
	Write-Warn "Kein Android-Geraet verbunden oder USB-Debugging nicht aktiviert."
	Write-Warn "APK manuell installieren: adb install -r `"$apkPath`""
	exit 0
}

# Zielgeraet bestimmen
$targetDevice = if ($Device -ne "") { $Device } else { $devices[0] }

if ($devices.Count -gt 1 -and $Device -eq "") {
	Write-Warn "Mehrere Geraete verbunden. Installiere auf: $targetDevice"
	Write-Warn "Anderes Geraet waehlen mit: -Device <id>"
	foreach ($d in $devices) { Write-Host "    $d" }
}

Write-Step "APK auf Geraet installieren: $targetDevice"
& $adb -s $targetDevice install -r $apkPath
if ($LASTEXITCODE -ne 0) {
	Write-Fail "Installation fehlgeschlagen."
	exit 1
}
Write-Ok "App erfolgreich auf $targetDevice installiert."

# App starten (optional, PackageName aus pubspec.yaml lesen)
$pubspec = Get-Content (Join-Path $appDir "pubspec.yaml") -Raw
if ($pubspec -match "(?m)^name:\s*(\S+)") {
	$packageBase = $Matches[1]
	# Android-Packagename aus applicationId lesen falls vorhanden
	$buildGradle = Join-Path $appDir "android\app\build.gradle"
	$appId = $packageBase  # Fallback
	if (Test-Path $buildGradle) {
		$gradle = Get-Content $buildGradle -Raw
		if ($gradle -match 'applicationId\s+"([^"]+)"') {
			$appId = $Matches[1]
		}
	}
	Write-Step "App starten: $appId"
	& $adb -s $targetDevice shell monkey -p $appId -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
	Write-Ok "App gestartet."
}

Write-Host "`nFertig.`n" -ForegroundColor Green
