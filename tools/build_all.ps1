# build_all.ps1
# Synchronisiert ALLE Projektteile:
#   1. api/        -> upload/          (Server-Deployment-Paket)
#   2. sketch_sws/, sketch_sws_display/, library/ -> Arduino-Sketchbook
#   3. app/        -> APK-Build        (Flutter Release-APK)
#
# Verwendung: powershell -File tools/build_all.ps1
#             powershell -File tools/build_all.ps1 -Skip api,arduino,app

param(
	[string[]] $Skip = @()
)

$root  = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ok    = $true

function Step([string]$label, [scriptblock]$block) {
	Write-Host ""
	Write-Host "=== $label ===" -ForegroundColor Cyan
	try {
		& $block
	} catch {
		Write-Host "FEHLER in $label`: $_" -ForegroundColor Red
		$script:ok = $false
	}
}

# ── 1. Server-Paket ──────────────────────────────────────────────────────────
if ('api' -notin $Skip) {
	Step "Server-Paket  (api → upload)" {
		& powershell -File "$PSScriptRoot\build_upload.ps1"
	}
}

# ── 2. Arduino-Mirror ────────────────────────────────────────────────────────
if ('arduino' -notin $Skip) {
	Step "Arduino-Mirror  (sketches + library → Sketchbook)" {
		& powershell -File "$PSScriptRoot\sync_arduino.ps1"
	}
}

# ── 3. Flutter-APK ───────────────────────────────────────────────────────────
if ('app' -notin $Skip) {
	Step "Flutter App  (app → APK)" {
		$appDir = Join-Path $root "app"
		Push-Location $appDir
		try {
			Write-Host "flutter pub get ..." -ForegroundColor Gray
			flutter pub get
			if ($LASTEXITCODE -ne 0) { throw "flutter pub get fehlgeschlagen" }

			Write-Host "flutter build apk --release ..." -ForegroundColor Gray
			flutter build apk --release
			if ($LASTEXITCODE -ne 0) { throw "flutter build fehlgeschlagen" }

			$apk = Join-Path $appDir "build\app\outputs\flutter-apk\app-release.apk"
			if (Test-Path $apk) {
				$size = [math]::Round((Get-Item $apk).Length / 1MB, 1)
				Write-Host "APK bereit: $apk  ($size MB)" -ForegroundColor Green
			}
		} finally {
			Pop-Location
		}
	}
}

# ── Zusammenfassung ───────────────────────────────────────────────────────────
Write-Host ""
if ($ok) {
	Write-Host "Alle Schritte erfolgreich abgeschlossen." -ForegroundColor Green
} else {
	Write-Host "Mindestens ein Schritt ist fehlgeschlagen - siehe Ausgabe oben." -ForegroundColor Red
	exit 1
}
