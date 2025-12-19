#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# Move to repo root
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# Ensure output directory exists (host path)
$outDir = Join-Path $root 'files\workflows'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

Write-Host 'Exporting all n8n workflows to files/workflows ...' -ForegroundColor Cyan

# Run export inside the n8n container. /files is bind-mounted to host ./files
# --separate writes one file per workflow; --pretty formats JSON
$cmd = 'n8n export:workflow --all --pretty --separate --output=/files/workflows'

# Use -T to disable TTY to work in non-interactive shells
& docker compose exec -T n8n sh -lc $cmd

Write-Host "Done. Files are in: $outDir" -ForegroundColor Green
