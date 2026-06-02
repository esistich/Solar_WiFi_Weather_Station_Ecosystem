# Lädt den lokalen upload/-Spiegel per SFTP auf den Server hoch.
# Nutzt WinSCP.com (C:\Program Files (x86)\WinSCP\WinSCP.com) für Passwort-Auth.
# Zugangsdaten werden aus der .env-Datei im Repo-Root gelesen (nicht committen).

$repoRoot  = (Resolve-Path "$PSScriptRoot\..").Path
$envPath   = Join-Path $repoRoot ".env"
$winscpExe = "C:\Program Files (x86)\WinSCP\WinSCP.com"

if (-not (Test-Path $envPath)) {
    Write-Error "Keine .env-Datei gefunden unter: $envPath"; exit 1
}
if (-not (Test-Path $winscpExe)) {
    Write-Error "WinSCP.com nicht gefunden unter: $winscpExe"; exit 1
}

# .env einlesen
$cfg = @{}
Get-Content $envPath | Where-Object { $_ -match '^\s*[^#]\w+=' } | ForEach-Object {
    $parts = $_ -split '=', 2
    $cfg[$parts[0].Trim()] = $parts[1].Trim()
}

$ftpHost = $cfg['SFTP_HOST']
$ftpUser = $cfg['SFTP_USER']
$ftpPass = $cfg['SFTP_PASS']
$remote  = $cfg['SFTP_REMOTE_PATH']
$local   = Join-Path $repoRoot "upload"

if (-not $ftpHost -or -not $ftpUser -or -not $ftpPass -or -not $remote) {
    Write-Error "Fehlende Eintraege in .env (SFTP_HOST, SFTP_USER, SFTP_PASS, SFTP_REMOTE_PATH)"; exit 1
}

# Temporaeres WinSCP-Script erstellen
$script = @"
option batch abort
option confirm off
open sftp://${ftpUser}:${ftpPass}@${ftpHost}/ -hostkey=*
synchronize remote "$local" "/$remote"
exit
"@

$tmpScript = [System.IO.Path]::GetTempFileName() + ".txt"
[System.IO.File]::WriteAllText($tmpScript, $script, [System.Text.Encoding]::UTF8)

Write-Host "Starte SFTP-Upload nach ${ftpHost}:/$remote ..." -ForegroundColor Cyan

try {
    & $winscpExe /script=$tmpScript /log="$env:TEMP\winscp_deploy.log"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Upload erfolgreich abgeschlossen." -ForegroundColor Green
    } else {
        Write-Error "WinSCP beendet mit Code $LASTEXITCODE – Log: $env:TEMP\winscp_deploy.log"
        exit $LASTEXITCODE
    }
} finally {
	Remove-Item $tmpScript -ErrorAction SilentlyContinue
}
