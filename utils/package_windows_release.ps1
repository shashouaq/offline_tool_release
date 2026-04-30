param(
    [string]$Version = "v1",
    [string]$OutputDir = "$(Split-Path -Parent $PSScriptRoot)\output"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$packageName = "offline_tool_${Version}_windows.zip"
$packagePath = Join-Path $OutputDir $packageName
$stageDir = Join-Path $env:TEMP "offline_tool_windows_package_$([guid]::NewGuid().ToString('N'))"

function Copy-RequiredItem {
    param(
        [string]$RelativePath
    )
    $src = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $src)) {
        throw "Required path not found: $RelativePath"
    }
    $dst = Join-Path $stageDir $RelativePath
    $parent = Split-Path -Parent $dst
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

try {
    $requiredPaths = @(
        "offline_tools_v1.sh",
        "README.md",
        "conf",
        "lib",
        "docs\offline_tools_user_manual_zh_CN.md",
        "docs\offline_tools_user_manual_zh_CN.pdf",
        "docs\offline_tools_a4_quick_guide_zh_CN.pdf",
        "utils\check_lf.sh",
        "utils\check_sources.sh",
        "utils\quality_gate.sh",
        "utils\package_windows_release.ps1",
        "utils\export_manual_pdf.py",
        "utils\export_a4_quick_guide.py"
    )

    foreach ($item in $requiredPaths) {
        Copy-RequiredItem -RelativePath $item
    }

    $readme = Join-Path $stageDir "WINDOWS_USAGE.txt"
    @"
Offline Tool Windows Package

This is a clean bootstrap package for a fresh environment.

Included:
- runtime script: offline_tools_v1.sh
- required config: conf/
- required shell modules: lib/
- user manuals: docs/
- basic validation utilities: utils/

Not included:
- logs/
- output/
- generated offline bundles
- checksums or headers generated for offline bundles
- private keys or test-environment files

Recommended use:
1. Unzip this package.
2. Copy the extracted folder to a Linux host.
3. Run: bash offline_tools_v1.sh
4. Generated logs and offline bundles will be created at runtime.
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
