#requires -Version 5.1
[CmdletBinding()]
param(
  [Parameter(ParameterSetName='set', Mandatory=$true)]
  [string]$Url,

  [Parameter(ParameterSetName='info', Mandatory=$true)]
  [switch]$InfoOnly,

  [string]$Token
)

$ErrorActionPreference = 'Stop'

function Get-EnvValue([string]$Key) {
  $envFile = Join-Path $PSScriptRoot "..\.env"
  if (-not (Test-Path $envFile)) { return $null }
  $line = (Get-Content $envFile | Where-Object { $_ -match "^(?i)$Key=(.*)$" } | Select-Object -First 1)
  if (-not $line) { return $null }
  $val = $line -replace "^$Key=", ""
  $val = $val.Trim().Trim('"')
  return $val
}

if (-not $Token -or [string]::IsNullOrWhiteSpace($Token)) {
  $Token = Get-EnvValue 'TELEGRAM_TOKEN'
}

if ([string]::IsNullOrWhiteSpace($Token)) {
  throw "Telegram token not provided. Pass -Token or set TELEGRAM_TOKEN in .env"
}

$base = "https://api.telegram.org/bot$Token"

if ($PSCmdlet.ParameterSetName -eq 'info' -or $InfoOnly) {
  Write-Host "==> getWebhookInfo" -ForegroundColor Cyan
  $info = Invoke-RestMethod -Method Get -Uri "$base/getWebhookInfo"
  $info | ConvertTo-Json -Depth 5
  return
}

if ([string]::IsNullOrWhiteSpace($Url)) {
  throw "-Url is required. Copy the Production URL from the Telegram Trigger node in n8n."
}

Write-Host "==> setWebhook" -ForegroundColor Cyan
$resp = Invoke-RestMethod -Method Post -Uri "$base/setWebhook" -Body @{ url = $Url } -ContentType 'application/x-www-form-urlencoded'
$resp | ConvertTo-Json -Depth 5 | Write-Output

Write-Host "==> getWebhookInfo" -ForegroundColor Cyan
$info2 = Invoke-RestMethod -Method Get -Uri "$base/getWebhookInfo"
$info2 | ConvertTo-Json -Depth 5 | Write-Output
