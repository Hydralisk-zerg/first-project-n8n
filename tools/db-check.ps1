param(
  [switch]$Raw
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "==> n8n DB diagnostics" -ForegroundColor Cyan
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
  $sql = @'
\echo --- workflow counts ---
SELECT count(*) AS workflow_total FROM workflow_entity;
SELECT count(*) AS active_workflows FROM workflow_entity WHERE active = true;
SELECT count(*) AS archived_workflows FROM workflow_entity WHERE "isArchived" = true;
\echo --- recent workflows ---
SELECT id, name, active, "isArchived", "updatedAt" FROM workflow_entity ORDER BY "updatedAt" DESC LIMIT 15;
\echo --- shared_workflow roles ---
SELECT "workflowId", role FROM shared_workflow LIMIT 25;
\echo --- users ---
SELECT id, email, "roleSlug" FROM "user" LIMIT 10;
\echo --- project relations ---
SELECT "projectId", "userId" FROM project_relation LIMIT 25;
\echo --- projects ---
SELECT id, name FROM project LIMIT 10;
'@

  $sqlFile = Join-Path $env:TEMP ("n8n-db-check-" + [guid]::NewGuid().ToString() + ".sql")
  Set-Content -Path $sqlFile -Value $sql -Encoding UTF8

  Write-Host "Running SQL diagnostics..." -ForegroundColor Yellow
  # Copy temp sql into mounted files to allow container access
  $leaf = Split-Path $sqlFile -Leaf
  $target = Join-Path (Get-Location) "files\$leaf"
  Copy-Item $sqlFile -Destination $target -Force
  $output = docker compose exec -T postgres psql -U n8n -d n8n -v ON_ERROR_STOP=1 -f "/files/$leaf" 2>&1

  if ($Raw) { Write-Output $output } else {
    $lines = $output -split "\r?\n"
    foreach ($l in $lines) {
      if ($l -match '^--- ' -or $l -match '^ workflow_total' -or $l -match 'shared_workflow' -or $l -match 'project_relation') {
        Write-Host $l -ForegroundColor Green
      } elseif ($l -match '^\s*[0-9a-f\-]{36}\s') {
        Write-Host $l -ForegroundColor White
      } elseif ($l -match '^ total |^ active_workflows|^ archived_workflows') {
        Write-Host $l -ForegroundColor Magenta
      }
    }
    Write-Host "(Full raw output available with -Raw)" -ForegroundColor DarkGray
  }
}
finally {
  Pop-Location
}
