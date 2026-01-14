Хочешь, я проверю, что внешний домен через Cloudflare тоже сейчас открывается (https://n8n2.node.od.ua), или тебе достаточно локального доступа?# Imports all workflow JSON files from files/workflows into the n8n container
# Run from any location; the script will switch to the repo root automatically.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    # Move to repo root (parent of scripts folder)
    if (-not $PSScriptRoot) { throw "PSScriptRoot is not set" }
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Set-Location $repoRoot

    $workflowsDir = Join-Path $repoRoot 'files/workflows'
    if (-not (Test-Path -Path $workflowsDir -PathType Container)) {
        Write-Host "Workflows folder not found: $workflowsDir" -ForegroundColor Yellow
        exit 0
    }

    $files = Get-ChildItem -Path $workflowsDir -File -Filter *.json | Sort-Object Name
    if (-not $files) {
        Write-Host "No JSON files found in $workflowsDir" -ForegroundColor Yellow
        exit 0
    }

    $imported = @()
    $failed = @()

    foreach ($f in $files) {
        $rel = [IO.Path]::GetFileName($f.FullName)
        $containerPath = "/files/workflows/$rel"

        # Validate JSON before import
        try {
            Get-Content -Raw -LiteralPath $f.FullName | ConvertFrom-Json | Out-Null
        }
        catch {
            $failed += [pscustomobject]@{ File = $rel; Error = "Invalid JSON: $($_.Exception.Message)" }
            continue
        }

        Write-Host "Importing: $rel" -ForegroundColor Cyan
        & docker compose exec -T n8n n8n import:workflow --input=$containerPath | Write-Host
        $code = $LASTEXITCODE
        if ($code -eq 0) {
            $imported += $rel
        } else {
            $failed += [pscustomobject]@{ File = $rel; Error = "n8n CLI exit code $code" }
        }
    }

    Write-Host ""; Write-Host "Import summary" -ForegroundColor Green
    Write-Host "  Imported: " -NoNewline; Write-Host $($imported.Count) -ForegroundColor Green
    Write-Host "  Failed:   " -NoNewline; Write-Host $($failed.Count) -ForegroundColor Red

    if ($failed.Count -gt 0) {
        Write-Host "\nFailures:" -ForegroundColor Red
        foreach ($e in $failed) {
            Write-Host ("  {0} -> {1}" -f $e.File, $e.Error) -ForegroundColor Red
        }
    }
}
catch {
    Write-Error $_
    exit 1
}
