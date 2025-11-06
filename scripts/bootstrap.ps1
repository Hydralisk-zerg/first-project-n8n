#requires -Version 5.1
[CmdletBinding()]
param(
  [switch]$NoPull
)

$ErrorActionPreference = 'Stop'

function Is-Admin {
  $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Admin {
  if (-not (Is-Admin)) {
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

# --- main ---
Ensure-Admin
Enable-WSL
Install-DockerDesktop
Start-DockerDesktop
Wait-For-Docker

# Run project deploy
$deploy = Join-Path $PSScriptRoot 'deploy.ps1'
if (-not (Test-Path $deploy)) { throw "deploy.ps1 not found at $deploy" }
& $deploy @PSBoundParameters
