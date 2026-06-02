<#
.SYNOPSIS
	Synchronisiert Sketch- und Bibliotheksdateien aus dem Repo in den Arduino-Sketchbook.

.DESCRIPTION
	Wird nach jeder relevanten Änderung an sketch_sws/ oder library/ aufgerufen –
	entweder manuell oder automatisch durch den Copilot-Agenten.

	Quellen  (Repo):
		sketch_sws/                    -> Arduino/sws/Solar_WiFi_Weather_Station_v2_6/
		library/SWSApiClient/          -> Arduino/libraries/SWSApiClient/

	Das Skript verwendet robocopy /MIR, damit gelöschte Dateien auch im Ziel
	entfernt werden.

.EXAMPLE
	.\tools\sync_arduino.ps1
#>

$repo    = Split-Path $PSScriptRoot -Parent
$arduino = "$env:USERPROFILE\Documents\Arduino"

$targets = @(
	@{
		Src = Join-Path $repo "sketch_sws"
		Dst = Join-Path $arduino "sws\Solar_WiFi_Weather_Station_v2_6"
		Exc = @("*.md")
	},
	@{
		Src = Join-Path $repo "sketch_sws_display"
		Dst = Join-Path $arduino "sws\sws_display\sketch_sws_display"
		Exc = @("*.md")
	},
	@{
		Src = Join-Path $repo "library\SWSApiClient"
		Dst = Join-Path $arduino "libraries\SWSApiClient"
		Exc = @()
	}
)

$ok = $true
foreach ($t in $targets) {
	if (-not (Test-Path $t.Src)) {
		Write-Warning "Quelle nicht gefunden: $($t.Src)"
		$ok = $false
		continue
	}

	New-Item -ItemType Directory -Force -Path $t.Dst | Out-Null

	$xcArgs = @($t.Src, $t.Dst, "/MIR", "/XD", ".git", "__pycache__", "/NP", "/NJH", "/NJS")
	if ($t.Exc.Count -gt 0) { $xcArgs += @("/XF") + $t.Exc }

	$result = & robocopy @xcArgs
	$rc = $LASTEXITCODE

	# robocopy: Exit-Code < 8 = kein Fehler (0=keine Änderung, 1-7=Änderungen kopiert)
	if ($rc -ge 8) {
		Write-Error "robocopy fehlgeschlagen (Exit $rc): $($t.Src) -> $($t.Dst)"
		$ok = $false
	} else {
		$files = (Get-ChildItem $t.Dst -Recurse -File | Measure-Object).Count
		Write-Host "OK  $($t.Dst)  ($files Dateien)"
	}
}

if ($ok) {
	Write-Host "`nSync abgeschlossen." -ForegroundColor Green
} else {
	Write-Host "`nSync mit Fehlern beendet." -ForegroundColor Red
	exit 1
}
