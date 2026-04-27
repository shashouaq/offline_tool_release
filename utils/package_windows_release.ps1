param(
    [string]$Version = "v1",
    [string]$OutputDir = "$(Split-Path -Parent $PSScriptRoot)\output"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$packageName = "offline_tool_${Version}_windows.zip"
$packagePath = Join-Path $OutputDir $packageName
$stageDir = Join-Path $env:TEMP "offline_tool_windows_package_$([guid]::NewGuid().ToString('N'))"

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

$excludeDirs = @('\output\', '\temp\', '\logs\', '\backup\')
$excludeFiles = @('.git', '.gitignore')

try {
    Get-ChildItem -LiteralPath $repoRoot -Force | ForEach-Object {
        $src = $_.FullName
        $relative = $src.Substring($repoRoot.Length)

        foreach ($excluded in $excludeDirs) {
            if ($relative.StartsWith($excluded, [System.StringComparison]::OrdinalIgnoreCase)) {
                return
            }
        }
        if ($excludeFiles -contains $_.Name) {
            return
        }

        $dst = Join-Path $stageDir $_.Name
        if ($_.PSIsContainer) {
            Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
        } else {
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }

    $readme = Join-Path $stageDir "WINDOWS_USAGE.txt"
    @"
Offline Tool Windows Package

This package is intended to be unpacked on Windows and copied to the target
Linux download host when package collection is needed.

Recommended use:
1. Unzip this package.
2. Copy the folder to a Linux host with network access to the target OS repo.
3. Run: bash offline_tools_v1.sh

Notes:
- Do not store private SSH keys in this package.
- output, temp, logs, and backup folders are intentionally excluded.
- Generated offline bundles will be created under output on the Linux host.
"@ | Set-Content -LiteralPath $readme -Encoding UTF8

    if (Test-Path -LiteralPath $packagePath) {
        Remove-Item -LiteralPath $packagePath -Force
    }
    Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $packagePath -Force
    Write-Host "Created $packagePath"
} finally {
    if (Test-Path -LiteralPath $stageDir) {
        Remove-Item -LiteralPath $stageDir -Recurse -Force
    }
}
