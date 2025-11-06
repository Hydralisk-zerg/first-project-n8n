#requires -Version 5.1
param(
    [switch]$NoPull
)

$ErrorActionPreference = 'Stop'

Write-Host "==> n8n stack deploy (Docker Compose)" -ForegroundColor Cyan

# 1) Prereqs
function Test-Command($name) {
    $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

if (-not (Test-Command docker)) {
    Write-Error "Docker is not installed or not in PATH. Install Docker Desktop and retry."
}

if (-not (Test-Command "docker-compose")) {
    # Newer Docker uses `docker compose`; acceptable
    if (-not (Test-Command "docker")) { throw "Docker missing" }
}

# 2) Ensure .env exists (create from template if missing)
$envPath = Join-Path $PSScriptRoot "..\.env"
$envExamplePath = Join-Path $PSScriptRoot "..\.env.example"

if (-not (Test-Path $envPath)) {
    if (-not (Test-Path $envExamplePath)) {
        Write-Error ".env is missing and .env.example not found."
    }
    Copy-Item $envExamplePath $envPath -Force
    Write-Host "Created .env from .env.example" -ForegroundColor Yellow
}

# 3) Generate ENCRYPTION_KEY if placeholder
function Set-Or-GenerateEnvVar([string]$file, [string]$key, [string]$value) {
    $content = Get-Content $file -Raw
    if ($content -match "(?m)^$key=") {
        $content = [regex]::Replace($content, "(?m)^$key=.*$", "$key=$value")
    } else {
        $content = $content.TrimEnd() + "`r`n$key=$value`r`n"
    }
    Set-Content $file -Value $content -NoNewline
}

# Read .env into a hashtable
$envLines = Get-Content $envPath
$envMap = @{}
foreach ($line in $envLines) {
    if ($line -match '^(?<k>[^#][^=]*)=(?<v>.*)$') { $envMap[$matches.k.Trim()] = $matches.v.Trim() }
}

# Generate a random encryption key if it's obviously a placeholder
if ($envMap.ContainsKey('ENCRYPTION_KEY')) {
    if ($envMap['ENCRYPTION_KEY'] -eq 'CHANGE_ME_GENERATED' -or [string]::IsNullOrWhiteSpace($envMap['ENCRYPTION_KEY'])) {
        # 32 bytes random hex
        $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
        $bytes = New-Object byte[] 32
        $rng.GetBytes($bytes)
        $hex = -join ($bytes | ForEach-Object { $_.ToString('x2') })
        Set-Or-GenerateEnvVar $envPath 'ENCRYPTION_KEY' $hex
        Write-Host "Generated ENCRYPTION_KEY" -ForegroundColor Green
    }
} else {
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $bytes = New-Object byte[] 32
    $rng.GetBytes($bytes)
    $hex = -join ($bytes | ForEach-Object { $_.ToString('x2') })
    Add-Content $envPath "ENCRYPTION_KEY=$hex"
    Write-Host "Added ENCRYPTION_KEY to .env" -ForegroundColor Green
}

# 4) Docker compose up
Push-Location (Join-Path $PSScriptRoot "..")
try {
    if (-not $NoPull) {
        Write-Host "==> Pulling images" -ForegroundColor Cyan
        docker compose pull
    }

    Write-Host "==> Starting containers" -ForegroundColor Cyan
    docker compose up -d

    # Optional: brief wait for startup
    Start-Sleep -Seconds 8

    Write-Host "==> Checking n8n logs (last 50 lines)" -ForegroundColor Cyan
    docker compose logs n8n --tail 50

    # Print useful info
    $envVars = Get-Content $envPath | Where-Object { $_ -match '^(N8N_WEBHOOK_URL|N8N_EDITOR_BASE_URL)=' }
    Write-Host "" 
    Write-Host "n8n should be available at:" -ForegroundColor Green
    foreach ($v in $envVars) { Write-Host "  $v" }
    Write-Host "" 
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "- Open the n8n Editor URL and activate your workflow." 
    Write-Host "- Copy the Telegram Trigger Production URL and set the webhook in Telegram." 
}
finally {
    Pop-Location
}
