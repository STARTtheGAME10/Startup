<#
.SYNOPSIS
    workspace-setup für Windows 11 – prüft Apps und installiert fehlende über winget.
.DESCRIPTION
    Öffnet keine Apps (das macht nur workspace-setup.sh auf dem Ubuntu-Laptop).
.PARAMETER DryRun
    Nur anzeigen, was installiert würde.
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

function Write-Ok($msg)   { Write-Host "✔ $msg" -ForegroundColor Green }
function Write-Inst($msg) { Write-Host "⬇ $msg" -ForegroundColor Cyan }
function Write-Fail($msg) { Write-Host "✘ $msg" -ForegroundColor Red }

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Host "workspace-setup $Version (Windows)`n"

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Fail 'winget nicht gefunden. Installiere «App Installer» aus dem Microsoft Store.'
    exit 2
}
if ($DryRun) { Write-Host "! Dry-Run – es wird nichts verändert`n" -ForegroundColor Yellow }

Write-Host '== Apps prüfen ==' -ForegroundColor White
$failed = 0

foreach ($name in $Apps.Keys) {
    $id = $Apps[$name]
    winget list --id $id --exact --accept-source-agreements *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok $name
        continue
    }

    Write-Inst "$name fehlt – wird installiert ($id)"
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
