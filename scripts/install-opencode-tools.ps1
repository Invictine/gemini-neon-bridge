[CmdletBinding()]
param(
    [string]$ConfigRoot = (Join-Path $env:USERPROFILE '.t3\gemini-bridge\config')
)

$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\opencode-tools\gemini_app.ts'
$toolsDirectory = Join-Path (Join-Path $ConfigRoot 'opencode') 'tools'
$destinationPath = Join-Path $toolsDirectory 'gemini_app.ts'
$ownershipMarker = '// gemini-jio-argon-opencode-tools'

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "OpenCode Gemini tool source was not found: $sourcePath"
}

$sourceContent = [System.IO.File]::ReadAllText($sourcePath)
if (-not $sourceContent.StartsWith($ownershipMarker, [System.StringComparison]::Ordinal)) {
    throw 'The source file does not contain the expected ownership marker; refusing installation.'
}

New-Item -ItemType Directory -Path $toolsDirectory -Force | Out-Null
if (Test-Path -LiteralPath $destinationPath) {
    if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
        throw "The OpenCode tool destination exists and is not a file: $destinationPath"
    }
    $existingContent = [System.IO.File]::ReadAllText($destinationPath)
    if (-not $existingContent.StartsWith($ownershipMarker, [System.StringComparison]::Ordinal)) {
        throw "The destination is an unrelated file; refusing to overwrite it: $destinationPath"
    }
    if ($existingContent -ceq $sourceContent) {
        Write-Output "OpenCode Gemini tools are already current: $destinationPath"
        return
    }
}

[System.IO.File]::WriteAllText($destinationPath, $sourceContent, [System.Text.UTF8Encoding]::new($false))
Write-Output "Installed OpenCode Gemini tools: $destinationPath"
