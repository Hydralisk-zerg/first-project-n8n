# Обновляет owner и выводит новые данные.
[CmdletBinding()]
param(
    [string]$Email = 'admin@n8n.local',
    [string]$Password = 'NewP@ssw0rd2025!'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    $Hash = docker compose exec -T n8n node -e "const bcrypt=require('/usr/local/lib/node_modules/n8n/node_modules/bcryptjs'); console.log(bcrypt.hashSync(process.argv[1], 10));" "$Password"
    $sql = "UPDATE public.""user"" SET email = '$Email', password = '$Hash', disabled = false;"
    Write-Host "Running: psql -c '$sql'"

    docker compose exec -T postgres psql -U n8n -d n8n -c $sql | Out-Null

    Write-Host "Email: $Email"
    Write-Host "Пароль: $Password"
}
finally {
    Pop-Location
}