# check-bridge.ps1 -- verify the local Gemini bridge and required models.
param(
    [int]$Port = 0,
    [string]$ApiKey = '',
    [string]$HostName = ''
)
$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$EnvFile = Join-Path $ProjectRoot '.env'
# Match start-bridge.ps1: project .env values override inherited process values.
if (Test-Path -LiteralPath $EnvFile) {
    foreach ($raw in Get-Content -LiteralPath $EnvFile) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $key = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1).Trim()
        if ($value.Length -ge 2) {
            $first = $value[0]
            $last = $value[$value.Length - 1]
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }
        [Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
}

if (-not $env:GEMINI_API_HOST) { $env:GEMINI_API_HOST = '127.0.0.1' }
if (-not $env:GEMINI_API_PORT) { $env:GEMINI_API_PORT = '8100' }
if (-not $env:GEMINI_API_KEY) { $env:GEMINI_API_KEY = 'gemini-local' }
if ($Port -gt 0) { $env:GEMINI_API_PORT = [string]$Port }
if ($ApiKey) { $env:GEMINI_API_KEY = $ApiKey }
if ($HostName) { $env:GEMINI_API_HOST = $HostName }

$base = "http://$($env:GEMINI_API_HOST):$($env:GEMINI_API_PORT)"

function Get-BridgeJson([string]$path) {
    Invoke-RestMethod -Uri "$base$path" `
        -Headers @{ Authorization = "Bearer $($env:GEMINI_API_KEY)" } `
        -TimeoutSec 5 -ErrorAction Stop
}

Write-Host "Gemini bridge check -> $base"
Write-Host ('-' * 52)
try {
    $health = Get-BridgeJson '/health'
} catch {
    Write-Host ("{0,-22} {1}" -f 'Bridge reachable:', 'NO')
    Write-Warning "Cannot reach or authenticate to the bridge at $base. Start it with .\scripts\start-bridge.ps1 and confirm GEMINI_API_PORT and GEMINI_API_KEY in .env."
    exit 1
}
Write-Host ("{0,-22} {1}" -f 'Bridge reachable:', 'YES')

try {
    $models = Get-BridgeJson '/v1/models'
} catch {
    Write-Host ("{0,-22} {1}" -f 'Authenticated models:', 'NO')
    Write-Warning "The /v1/models request failed (including possible API-key rejection). Check GEMINI_API_KEY in .env; its value is not displayed."
    exit 1
}

$ids = @()
if ($null -ne $models -and $null -ne $models.data) {
    $ids = @($models.data | ForEach-Object { [string]$_.id } | Where-Object { $_ })
}
Write-Host ("{0,-22} {1}" -f 'Model count:', $ids.Count)
if ($ids.Count -gt 0) {
    Write-Host ''
    Write-Host 'Available model IDs:'
    foreach ($id in $ids) { Write-Host "  - $id" }
}

$required = @('gemini-4-neon', 'gemini-4-hydrogen')
$missing = @($required | Where-Object { $ids -notcontains $_ })
if ($missing.Count -gt 0) {
    Write-Warning ("Required model(s) missing: {0}. Re-apply the config.py patch and restart the bridge." -f ($missing -join ', '))
    exit 1
}
Write-Host 'OK: gemini-4-neon and gemini-4-hydrogen are advertised.'
Write-Host ('-' * 52)
exit 0
