#requires -Version 5.1
[CmdletBinding()]
param(
  [switch]$NoPull
)

$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
  $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-ElevatedSelf {
  if (-not (Test-IsAdmin)) {
    Write-Host "Elevating to Administrator..." -ForegroundColor Yellow
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $additionalArgs = if ($NoPull) { " -NoPull" } else { "" }
    $psi.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`"" + $additionalArgs
    $psi.Verb = "runas"
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    exit 0
  }
}

function Test-Command($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

function Enable-WSL {
  Write-Host "Enabling WSL and VirtualMachinePlatform (no reboot yet)..." -ForegroundColor Cyan
  & dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
  & dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
}

function Install-DockerDesktop {
  if (Test-Command docker) { return }
  if (-not (Test-Command winget)) {
    throw "winget is not available. Install Docker Desktop manually from https://www.docker.com/products/docker-desktop/ and rerun."
  }
  Write-Host "Installing Docker Desktop via winget..." -ForegroundColor Cyan
  winget install -e --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements
}

function Start-DockerDesktop {
  $dockerExe = "$Env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
  if (Test-Path $dockerExe) {
    Write-Host "Starting Docker Desktop..." -ForegroundColor Cyan
    Start-Process -FilePath $dockerExe | Out-Null
  }
}

function Wait-For-Docker {
  Write-Host "Waiting for Docker engine to be ready..." -ForegroundColor Cyan
  $retries = 60
  for ($i=0; $i -lt $retries; $i++) {
    try {
      docker version | Out-Null
      return
    } catch {
      Start-Sleep -Seconds 3
    }
  }
  throw "Docker did not become ready in time. Please ensure Docker Desktop is running."
}

function Get-RepoRoot {
  return (Split-Path -Parent $PSScriptRoot)
}

function Ensure-EnvFile {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot
  )

  $envPath = Join-Path $RepoRoot '.env'
  $envExamplePath = Join-Path $RepoRoot '.env.example'

  if (-not (Test-Path $envPath)) {
    if (-not (Test-Path $envExamplePath)) {
      throw ".env is missing and .env.example not found at $envExamplePath"
    }
    Copy-Item $envExamplePath $envPath -Force
    Write-Host "Created .env from .env.example" -ForegroundColor Yellow
  }

  return $envPath
}

function Set-Or-GenerateEnvVar {
  param(
    [Parameter(Mandatory = $true)][string]$File,
    [Parameter(Mandatory = $true)][string]$Key,
    [Parameter(Mandatory = $true)][string]$Value
  )
  $content = Get-Content $File -Raw
  if ($content -match "(?m)^$Key=") {
    $content = [regex]::Replace($content, "(?m)^$Key=.*$", "$Key=$Value")
  } else {
    $content = $content.TrimEnd() + "`r`n$Key=$Value`r`n"
  }
  Set-Content $File -Value $content -NoNewline
}

function Ensure-EncryptionKey {
  param(
    [Parameter(Mandatory = $true)][string]$EnvPath
  )

  $envLines = Get-Content $EnvPath
  $envMap = @{}
  foreach ($line in $envLines) {
    if ($line -match '^(?<k>[^#][^=]*)=(?<v>.*)$') { $envMap[$matches.k.Trim()] = $matches.v.Trim() }
  }

  $needsGenerate = $true
  if ($envMap.ContainsKey('ENCRYPTION_KEY')) {
    $val = $envMap['ENCRYPTION_KEY']
    if (-not [string]::IsNullOrWhiteSpace($val) -and $val -ne 'CHANGE_ME_GENERATED') {
      $needsGenerate = $false
    }
  }

  if (-not $needsGenerate) { return }

  $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
  $bytes = New-Object byte[] 32
  $rng.GetBytes($bytes)
  $hex = -join ($bytes | ForEach-Object { $_.ToString('x2') })

  Set-Or-GenerateEnvVar -File $EnvPath -Key 'ENCRYPTION_KEY' -Value $hex
  Write-Host "Generated ENCRYPTION_KEY" -ForegroundColor Green
}

# --- main ---
Start-ElevatedSelf
Enable-WSL
Install-DockerDesktop
Start-DockerDesktop
Wait-For-Docker

Write-Host "==> n8n stack deploy (Docker Compose)" -ForegroundColor Cyan

if (-not (Test-Command docker)) {
  throw "Docker is not installed or not in PATH. Install Docker Desktop and retry."
}

$repoRoot = Get-RepoRoot
Push-Location $repoRoot
try {
  $envPath = Ensure-EnvFile -RepoRoot $repoRoot
  Ensure-EncryptionKey -EnvPath $envPath

  if (-not $NoPull) {
    Write-Host "==> Pulling images" -ForegroundColor Cyan
    docker compose pull
  }

  Write-Host "==> Starting containers" -ForegroundColor Cyan
  docker compose up -d

  Start-Sleep -Seconds 8

  Write-Host "==> Checking n8n logs (last 50 lines)" -ForegroundColor Cyan
  docker compose logs n8n --tail 50

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
