<#
.SYNOPSIS
    Build playOS TOOLS distribution package (nfsu2_thai.zip) from project-local tools directory.
.DESCRIPTION
    Creates nfsu2_thai.zip inside dist/ containing root Install_NFSU2_Thai.sh and nfsu2_thai/ package.
#>

param(
    [string]$OutputPath = "D:\r36h\nfsu2\dist\nfsu2_thai.zip"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcTools = Join-Path $scriptDir "tools\nfsu2_thai"
$distDir = Join-Path $scriptDir "dist"

if (-not (Test-Path $srcTools)) {
    throw "Source directory not found: $srcTools"
}

if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

$stageDir = Join-Path $distDir "_stage_tools"
$stagePkg = Join-Path $stageDir "nfsu2_thai"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  Building NFSU2 Tools Distribution Package (PowerShell)" -ForegroundColor Cyan
Write-Host "  Source : $srcTools" -ForegroundColor Cyan
Write-Host "  Target : $OutputPath" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Clean previous staging
if (Test-Path $stageDir) {
    Remove-Item $stageDir -Recurse -Force
}
New-Item -ItemType Directory -Path $stagePkg -Force | Out-Null

# 2. Copy files to staging
Write-Host "`n[1/3] Staging tools package layout..." -ForegroundColor Yellow
Copy-Item -Path "$srcTools\*" -Destination $stagePkg -Recurse -Force
$toolsReadme = Join-Path $PSScriptRoot "tools\README.txt"
if (Test-Path $toolsReadme) {
    Copy-Item -Path $toolsReadme -Destination (Join-Path $stageDir "README.txt") -Force
}
$pkgReadme = Join-Path $stagePkg "README.txt"
if (Test-Path $pkgReadme) {
    Remove-Item $pkgReadme -Force
}

# 3. Compress to ZIP
Write-Host "`n[2/3] Compressing package into ZIP archive..." -ForegroundColor Yellow
if (Test-Path $OutputPath) {
    Remove-Item $OutputPath -Force
}

Compress-Archive -Path (Join-Path $stageDir "*") -DestinationPath $OutputPath -CompressionLevel Optimal

# 4. Clean up staging
Write-Host "`n[3/3] Cleaning up temporary files..." -ForegroundColor Yellow
Remove-Item $stageDir -Recurse -Force

$zipItem = Get-Item $OutputPath
$sizeMb = [math]::Round($zipItem.Length / 1MB, 2)

Write-Host "`n[SUCCESS] Package built successfully!" -ForegroundColor Green
Write-Host "  Path : $($zipItem.FullName)"
Write-Host "  Size : $sizeMb MB"
