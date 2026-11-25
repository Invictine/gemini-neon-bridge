# Guided first-run setup for the local Chrome-backed Gemini bridge.
[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [switch]$SkipDependencyInstall,
    [switch]$SkipChromeHandoff,
    [string]$AccountAuthuser = '',
    [string]$ProjectRoot = '',
    [string]$ApiBase = '',
    [string]$ApiKey = ''
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$BridgeDir = Join-Path $ProjectRoot 'vendor\gemini-web-api'
$EnvFile = Join-Path $ProjectRoot '.env'

function Read-EnvFile {
    $values = @{}
    if (Test-Path -LiteralPath $EnvFile) {
        foreach ($raw in Get-Content -LiteralPath $EnvFile) {
            $line = $raw.Trim()
            if (-not $line -or $line.StartsWith('#')) { continue }
            $eq = $line.IndexOf('=')
            if ($eq -lt 1) { continue }
            $key = $line.Substring(0, $eq).Trim()
            $value = $line.Substring($eq + 1).Trim()
            if ($value.Length -ge 2 -and (($value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') -or ($value[0] -eq "'" -and $value[$value.Length - 1] -eq "'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $values[$key] = $value
        }
    }
    return $values
}

function Set-EnvValue([string]$Key, [string]$Value) {
    $lines = if (Test-Path -LiteralPath $EnvFile) { @(Get-Content -LiteralPath $EnvFile) } else { @() }
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
            $lines[$i] = "$Key=$Value"
            $found = $true
        }
    }
    if (-not $found) { $lines += "$Key=$Value" }
    Set-Content -LiteralPath $EnvFile -Value $lines -Encoding utf8
}

function Invoke-Bridge([string]$Method, [string]$Path, $Body = $null) {
    $params = @{
        Method = $Method
        Uri = "$script:Base$Path"
        Headers = @{ Authorization = "Bearer $script:Key" }
        TimeoutSec = 90
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $params.ContentType = 'application/json'
        $params.Body = $Body | ConvertTo-Json -Depth 12 -Compress
    }
    return Invoke-RestMethod @params
}

Write-Host 'Neon Bridge guided Windows setup' -ForegroundColor Cyan
Write-Host 'This configures a local bridge that uses the signed-in Chrome extension.'

if (-not (Test-Path -LiteralPath $EnvFile)) {
    $example = Join-Path $ProjectRoot '.env.example'
    if (-not (Test-Path -LiteralPath $example)) { throw 'Missing .env.example; cannot create the local bridge configuration.' }
    Copy-Item -LiteralPath $example -Destination $EnvFile
    Write-Host 'Created project .env from .env.example.'
}

$envValues = Read-EnvFile
if (-not $envValues.ContainsKey('GEMINI_API_HOST')) { Set-EnvValue 'GEMINI_API_HOST' '127.0.0.1' }
if (-not $envValues.ContainsKey('GEMINI_API_PORT')) { Set-EnvValue 'GEMINI_API_PORT' '8100' }
if (-not $envValues.ContainsKey('GEMINI_API_KEY') -or -not $envValues.GEMINI_API_KEY) { Set-EnvValue 'GEMINI_API_KEY' 'gemini-local' }
Set-EnvValue 'GEMINI_BACKEND' 'chrome'
$envValues = Read-EnvFile

if (-not $SkipDependencyInstall) {
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Host 'Install Python 3.12 and uv, then rerun this script:' -ForegroundColor Yellow
        Write-Host '  Python: https://www.python.org/downloads/windows/ (enable the Python launcher)'
        Write-Host '  uv:     https://docs.astral.sh/uv/getting-started/installation/'
        throw 'Required dependency manager "uv" was not found.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $BridgeDir 'pyproject.toml'))) {
        throw "Pinned bridge dependency is missing at '$BridgeDir'. Run: git submodule update --init --recursive"
    }
    Write-Host 'Installing the pinned bridge dependencies with uv...'
    & uv sync --locked --project $BridgeDir
    if ($LASTEXITCODE -ne 0) { throw "uv sync failed with exit code $LASTEXITCODE." }
    $openCodeRoot = Join-Path $env:LOCALAPPDATA 'gemini-bridge\runtime\opencode'
    $openCodeBinary = Join-Path $openCodeRoot 'node_modules\opencode-windows-x64\bin\opencode.exe'
    if (-not (Test-Path -LiteralPath $openCodeBinary)) {
        if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
            throw 'Install Node.js with npm to set up the Gemini bridge OpenCode runtime.'
        }
        Write-Host 'Installing OpenCode 1.14.19 for the Gemini bridge provider...'
        & npm.cmd install --prefix $openCodeRoot --no-audit --no-fund opencode-ai@1.14.19
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $openCodeBinary)) {
            throw 'The OpenCode runtime installation did not produce the expected executable.'
        }
    }
}

$python = Join-Path $BridgeDir '.venv\Scripts\python.exe'
if (-not $SkipDependencyInstall -and -not (Test-Path -LiteralPath $python)) {
    throw "Bridge Python environment was not created at '$python'."
}

$hostName = $envValues.GEMINI_API_HOST
if (-not $hostName) { $hostName = '127.0.0.1' }
$port = $envValues.GEMINI_API_PORT
if (-not $port) { $port = '8100' }
$script:Key = if ($ApiKey) { $ApiKey } else { $envValues.GEMINI_API_KEY }
if (-not $script:Key) { $script:Key = 'gemini-local' }
$script:Base = if ($ApiBase) { $ApiBase.TrimEnd('/') } else { "http://${hostName}:${port}" }

if (-not $SkipChromeHandoff) {
    Write-Host ''
    Write-Host 'Chrome sign-in and extension setup' -ForegroundColor Cyan
    Write-Host '1. In Chrome, sign in at https://gemini.google.com using the Google account you want the bridge to use.'
    Write-Host '2. Open chrome://extensions, enable Developer mode, choose Load unpacked, and select:'
    Write-Host "   $(Join-Path $ProjectRoot 'vendor\gemini-web-api\extension')"
    Write-Host '3. Keep Chrome open. Return here when the extension is loaded and Gemini is signed in.'
    if (-not $NonInteractive) { Read-Host 'Press Enter when Chrome is ready' | Out-Null }
}

Write-Host "Starting bridge at $script:Base ..."
$startScript = Join-Path $PSScriptRoot 'start-bridge.ps1'
if (-not $ApiBase) {
    $powershell = (Get-Process -Id $PID).Path
    $start = Start-Process -FilePath $powershell -ArgumentList @('-NoProfile', '-File', "`"$startScript`"", '-Background') `
        -WindowStyle Hidden -Wait -PassThru
    if ($start.ExitCode -ne 0) { throw "Bridge start failed with exit code $($start.ExitCode)." }
}

$accounts = $null
$deadline = [DateTime]::UtcNow.AddSeconds(45)
do {
    try {
        $accounts = Invoke-Bridge 'Get' '/v1/accounts'
        if (@($accounts.accounts | Where-Object eligible).Count -gt 0) { break }
        if ([DateTime]::UtcNow -ge $deadline) {
            throw 'No eligible Gemini worker connected. Check Chrome sign-in and load the extension.'
        }
        Start-Sleep -Milliseconds 1000
    } catch {
        $statusCode = 0
        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
        if ($statusCode -ge 400 -and $statusCode -lt 500) {
            throw "Bridge account API rejected the request (HTTP $statusCode). Check GEMINI_API_KEY and confirm this bridge revision supports /v1/accounts."
        }
        if ([DateTime]::UtcNow -ge $deadline) {
            throw "Bridge account API is unavailable at $script:Base. Check the bridge log and confirm that this vendored revision supports /v1/accounts."
        }
        Start-Sleep -Milliseconds 1000
    }
} while ($true)

$choices = @($accounts.accounts | Where-Object { $null -ne $_.authuser })
if ($choices.Count -eq 0) { throw 'The bridge returned no signed-in Gemini accounts. Check Chrome sign-in and the loaded extension.' }
Write-Host ''
Write-Host 'Signed-in Gemini accounts:' -ForegroundColor Cyan
for ($i = 0; $i -lt $choices.Count; $i++) {
    $models = @($choices[$i].picker_models) -join ', '
    $ready = if ($choices[$i].eligible) { 'ready' } else { 'not ready' }
    Write-Host ("  {0}. authuser {1} - {2} - models: {3}" -f ($i + 1), $choices[$i].authuser, $ready, $(if ($models) { $models } else { 'not reported' }))
}
$defaultAuthuser = [string]$accounts.default_authuser
$selected = $null
if ($AccountAuthuser) {
    $selected = $choices | Where-Object { [string]$_.authuser -eq $AccountAuthuser } | Select-Object -First 1
    if (-not $selected) { throw "authuser $AccountAuthuser is not in the bridge account list." }
} elseif ($NonInteractive) {
    $selected = $choices | Where-Object { [string]$_.authuser -eq $defaultAuthuser } | Select-Object -First 1
    if (-not $selected) { $selected = $choices[0] }
} else {
    $answer = Read-Host "Choose account number (current default authuser $defaultAuthuser)"
    if (-not $answer) {
        for ($i = 0; $i -lt $choices.Count; $i++) {
            if ([string]$choices[$i].authuser -eq $defaultAuthuser) { $answer = [string]($i + 1); break }
        }
        if (-not $answer) { $answer = '1' }
    }
    $index = 0
    if (-not [int]::TryParse($answer, [ref]$index) -or $index -lt 1 -or $index -gt $choices.Count) { throw 'Account selection must be a listed number.' }
    $selected = $choices[$index - 1]
}
if (-not $selected.eligible) { throw "Selected authuser $($selected.authuser) is not ready. Keep Chrome open, check the extension, and rerun setup." }
$null = Invoke-Bridge 'Put' '/v1/accounts/default' @{ authuser = [string]$selected.authuser }
Write-Host "Selected Gemini account authuser $($selected.authuser)."

$available = @($selected.picker_models | ForEach-Object { ([string]$_).ToLowerInvariant() -replace '^gemini-4-', '' })
$defaultModel = @('neon', 'hydrogen', 'argon') | Where-Object { $available -contains $_ } | Select-Object -First 1
if (-not $defaultModel) { throw "Selected authuser $($selected.authuser) does not report an exact Gemini 4 model. Refresh accounts after the worker connects." }
$model = "gemini-4-$defaultModel"
$nonce = 'neon-setup-' + [guid]::NewGuid().ToString('N')
$probe = "Reply with exactly this marker and no other text: $nonce"
$reply = Invoke-Bridge 'Post' '/v1/chat/completions' @{
    model = $model
    messages = @(@{ role = 'user'; content = $probe })
    stream = $false
}
$content = [string]$reply.choices[0].message.content
if (-not $content -or $content -notmatch [regex]::Escape($nonce)) {
    throw 'The bridge returned a response, but it did not contain the fresh first-reply marker. Check model access and bridge logs.'
}
Write-Host 'First live Gemini reply verified through Chrome.' -ForegroundColor Green
Write-Host "Reply: $($content.Trim())"
Write-Host "Setup complete. Configure the Gemini provider in regular T3 Code (docs/t3-code-setup.md) and choose $model."
