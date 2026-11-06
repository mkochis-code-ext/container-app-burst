param(
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot "artifacts/timer-function.zip"
}

if (-not (Get-Command "dotnet" -ErrorAction SilentlyContinue)) {
    throw "Required command 'dotnet' was not found on PATH."
}

$publishDirectory = Join-Path $repoRoot "artifacts/timer-function-publish"
Remove-Item -Recurse -Force $publishDirectory -ErrorAction SilentlyContinue
Remove-Item -Force $OutputPath -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null

& dotnet publish (Join-Path $repoRoot "timer-function/TimerFunction.csproj") `
    --configuration Release `
    --output $publishDirectory `
    --nologo
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code ${LASTEXITCODE}."
}

# ZipFile writes forward-slash entry names, which the Linux Function host requires.
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $publishDirectory,
    $OutputPath,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false)

Write-Host "Function package: $OutputPath"
