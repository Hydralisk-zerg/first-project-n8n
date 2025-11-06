#requires -Version 5.1
param(
  [string]$Path = 'files/workflows'
)
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
Set-Location $root

$abs = Resolve-Path $Path
Write-Host "Importing workflows from $abs" -ForegroundColor Cyan

# Import all JSON workflow files. n8n import:workflow accepts a directory.
$cmd = "n8n import:workflow --input=/$Path"
& docker compose exec -T n8n sh -lc $cmd

Write-Host 'Import complete.' -ForegroundColor Green
