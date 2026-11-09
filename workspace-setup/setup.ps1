<#
.SYNOPSIS
    workspace-setup fuer Windows 11 - prueft Apps und installiert fehlende ueber winget.
.DESCRIPTION
    Oeffnet keine Apps (das macht nur workspace-setup.sh auf dem Ubuntu-Laptop).
.PARAMETER DryRun
    Nur anzeigen, was installiert wuerde.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\setup.ps1
#>
param([switch]$DryRun)

$Version = '0.1.0'

# ---------- Konfiguration: Anzeigename = winget-ID ----------
$Apps = [ordered]@{
    'Firefox'     = 'Mozilla.Firefox'
    'Proton Pass' = 'Proton.ProtonPass'
    'Brave'       = 'Brave.Brave'
    'Discord'     = 'Discord.Discord'
}
# -----------------------------------------------------------

function Write-Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Inst($msg) { Write-Host "[+]  $msg" -ForegroundColor Cyan }
function Write-Fail($msg) { Write-Host "[X]  $msg" -ForegroundColor Red }

Write-Host "workspace-setup $Version (Windows)`n"

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Fail 'winget nicht gefunden. Installiere "App Installer" aus dem Microsoft Store.'
    exit 2
}
if ($DryRun) { Write-Host "! Dry-Run - es wird nichts veraendert`n" -ForegroundColor Yellow }

Write-Host '== Apps pruefen ==' -ForegroundColor White
$failed = 0

foreach ($name in $Apps.Keys) {
    $id = $Apps[$name]
    winget list --id $id --exact --accept-source-agreements *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok $name
        continue
    }

    Write-Inst "$name fehlt - wird installiert ($id)"
    if ($DryRun) {
        Write-Host "  [dry-run] winget install --id $id --exact --silent" -ForegroundColor DarkGray
        continue
    }

    winget install --id $id --exact --silent `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "$name installiert"
    } else {
        Write-Fail "${name}: Installation fehlgeschlagen (Code $LASTEXITCODE)"
        $failed++
    }
}

Write-Host ''
if ($failed -gt 0) { exit 1 }
Write-Ok 'Alles bereit'
