# start-bridge.ps1 -- launch the local Gemini OpenAI-compatible bridge.
# Never prints secret values; only reads them into process environment.
param([switch]$Background)

$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$BridgeDir   = Join-Path $ProjectRoot 'vendor\gemini-web-api'
$PythonExe   = Join-Path $BridgeDir '.venv\Scripts\python.exe'
$EnvFile     = Join-Path $ProjectRoot '.env'

# --- Load .env (KEY=VALUE; skip blank / # lines; strip matching quotes) ------
if (Test-Path -LiteralPath $EnvFile) {
    foreach ($raw in Get-Content -LiteralPath $EnvFile) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $key = $line.Substring(0, $eq).Trim()
        $val = $line.Substring($eq + 1).Trim()
        if ($val.Length -ge 2) {
            $first = $val[0]
            $last  = $val[$val.Length - 1]
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $val = $val.Substring(1, $val.Length - 2)
            }
        }
        [Environment]::SetEnvironmentVariable($key, $val, 'Process')
    }
}

# Keep session cookies scoped to this checkout's .env when /v1/auth/session persists them.
# Force the project-local file even if inherited or .env values point elsewhere.
$env:GEMINI_ENV_FILE = $EnvFile

# --- Apply defaults only when the variable is not already set ---------------
if (-not $env:GEMINI_API_HOST) { $env:GEMINI_API_HOST = '127.0.0.1' }
if (-not $env:GEMINI_API_PORT) { $env:GEMINI_API_PORT = '8100' }
if (-not $env:GEMINI_API_KEY)  { $env:GEMINI_API_KEY  = 'gemini-local' }
if (-not $env:GEMINI_BACKEND)  { $env:GEMINI_BACKEND  = 'webapi' }

if ($env:GEMINI_BACKEND -ne 'chrome' -and -not $env:GEMINI_1PSID) {
    Write-Warning 'GEMINI_1PSID is empty. Copy .env.example -> .env and paste your cookies (see docs/cookie-capture.md); the bridge will fail to authenticate otherwise. Launching anyway so you can see the error.'
}

if (-not (Test-Path -LiteralPath $PythonExe)) {
    throw "Bridge python not found at '$PythonExe'. Run 'uv sync' in $BridgeDir first."
}

Write-Host "Starting Gemini bridge at http://$($env:GEMINI_API_HOST):$($env:GEMINI_API_PORT)/v1"
Write-Host "Working directory: $BridgeDir"

if ($Background) {
    try {
        $ExistingHealth = Invoke-RestMethod -Uri "http://$($env:GEMINI_API_HOST):$($env:GEMINI_API_PORT)/health" -TimeoutSec 1
    } catch { $ExistingHealth = $null }
    if ($ExistingHealth.status -eq 'ok') {
        Write-Host 'Bridge is already healthy; keeping the existing process.'
        exit 0
    }
    $StdoutLog = Join-Path $ProjectRoot 'bridge-detached.log'
    $StderrLog = Join-Path $ProjectRoot 'bridge-detached-error.log'
    $BridgeProcess = Start-Process -FilePath $PythonExe -ArgumentList @(
        '-m', 'uvicorn', 'gemini_openai.server:app',
        '--host', $env:GEMINI_API_HOST, '--port', $env:GEMINI_API_PORT
    ) -WorkingDirectory $BridgeDir -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $StdoutLog -RedirectStandardError $StderrLog
    $Ready = $false
    for ($Attempt = 0; $Attempt -lt 40; $Attempt++) {
        $BridgeProcess.Refresh()
        if ($BridgeProcess.HasExited) { break }
        try {
            $Health = Invoke-RestMethod -Uri "http://$($env:GEMINI_API_HOST):$($env:GEMINI_API_PORT)/health" -TimeoutSec 1
            if ($Health.status -eq 'ok') { $Ready = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 250
    }
    if (-not $Ready) {
        throw "Background bridge did not become healthy. See '$StderrLog'."
    }
    Write-Host "Background bridge ready (PID $($BridgeProcess.Id)). Logs: $StdoutLog"
    exit 0
}

Push-Location $BridgeDir
$BridgeExitCode = 0
try {
    & $PythonExe -m uvicorn gemini_openai.server:app `
        --host $env:GEMINI_API_HOST --port $env:GEMINI_API_PORT @args
    $BridgeExitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}
if ($BridgeExitCode -ne 0) {
    Write-Error "Gemini bridge exited with code $BridgeExitCode."
    exit $BridgeExitCode
}
