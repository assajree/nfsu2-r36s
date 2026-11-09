<#
.SYNOPSIS
    Build standalone drop-in copy-paste package (nfsu2_thai_copy_paste.zip) for R36H / R36S.
.DESCRIPTION
    Creates nfsu2_thai_copy_paste.zip ready for manual drop-in installation onto MicroSD card.
#>

param(
    [string]$OutputPath = "$distDir\nfsu2_thai_copy_paste.zip"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path $scriptDir "dist"
if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

$stageDir = Join-Path $distDir "_stage_pack"
$stageNfsu2 = Join-Path $stageDir "nfsu2"
$stageGamedata = Join-Path $stageNfsu2 "gamedata"
$stageLang = Join-Path $stageGamedata "LANGUAGES"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  Building NFSU2 Thai Copy-Paste Distribution Package (PowerShell)" -ForegroundColor Cyan
Write-Host "  Target: $OutputPath" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Clean previous staging
if (Test-Path $stageDir) {
    Remove-Item $stageDir -Recurse -Force
}
New-Item -ItemType Directory -Path $stageLang -Force | Out-Null

# 2. Copy source files
Write-Host "`n[1/3] Copying pre-patched binaries and assets..." -ForegroundColor Yellow

$armSrc = Join-Path $scriptDir "ports\nfsu2\nfsu2.aarch64"
$armV10Src = Join-Path $scriptDir "ports\nfsu2\nfsu2.aarch64.v10"
$exeSrc = Join-Path $scriptDir "tools\nfsu2_thai\gamedata\SPEED2.EXE"
$thaiBinSrc = Join-Path $scriptDir "tools\nfsu2_thai\gamedata\LANGUAGES\Thailand.bin"
$langTexSrc = Join-Path $scriptDir "tools\nfsu2_thai\gamedata\LANGUAGES\LanguageTextures.bin"

if (-not (Test-Path $armSrc)) {
    throw "Source file not found: $armSrc"
}
if (-not (Test-Path $exeSrc)) {
    $exeSrc = Join-Path $scriptDir "nfsu2_thai\SPEED2.EXE"
}
if (-not (Test-Path $thaiBinSrc)) {
    $thaiBinSrc = Join-Path $scriptDir "nfsu2_thai\LANGUAGES\Thailand.bin"
}
if (-not (Test-Path $langTexSrc)) {
    $langTexSrc = Join-Path $scriptDir "ports\nfsu2\gamedata\LANGUAGES\LanguageTextures.bin"
}

Copy-Item $armSrc (Join-Path $stageNfsu2 "nfsu2.aarch64") -Force
Copy-Item $armV10Src (Join-Path $stageNfsu2 "nfsu2.aarch64.v10") -Force
Copy-Item $exeSrc (Join-Path $stageGamedata "SPEED2.EXE") -Force
Copy-Item $exeSrc (Join-Path $stageGamedata "speed2.exe") -Force
Copy-Item $thaiBinSrc (Join-Path $stageLang "Thailand.bin") -Force
if (Test-Path $langTexSrc) {
    Copy-Item $langTexSrc (Join-Path $stageLang "LanguageTextures.bin") -Force
}

# Copy Ports Images (Box Art & Thumbnail)
$stageImages = Join-Path $stageDir "images"
New-Item -ItemType Directory -Path $stageImages -Force | Out-Null
$boxArtSrc = Join-Path $scriptDir "ports\images\NFSU2-image.png"
$thumbSrc = Join-Path $scriptDir "ports\images\NFSU2-thumb.png"
if (Test-Path $boxArtSrc) { Copy-Item $boxArtSrc (Join-Path $stageImages "NFSU2-image.png") -Force }
if (Test-Path $thumbSrc) { Copy-Item $thumbSrc (Join-Path $stageImages "NFSU2-thumb.png") -Force }

# 3. Create README_INSTALL.txt
$readmeContent = @"
==============================================================================
Need for Speed: Underground 2 — Thai + Subtitles Drop-in Pack (R36H / R36S)
==============================================================================

ชุดแพตช์ภาษาไทย + ปลดล็อกคำบรรยายซับไตเติล (สำหรับ Copy-Paste วางทับได้ทันที):
- nfsu2.aarch64 & nfsu2.aarch64.v10:
  * ปลดล็อกระบบซับไตเติลภาษาไทย (Thai Subtitles) ในคัตซีนการ์ตูน (Scene01-20)
  * ปลดล็อกซับไตเติลในฉากภาพยนตร์ (In-game FMV/Movies)
- gamedata/SPEED2.EXE & speed2.exe:
  * ปลดล็อกระบบแสดงผลภาษาไทย (Thai Localization)
  * ฟอนต์ภาษาไทยคมชัด ไม่กระพริบ
- gamedata/LANGUAGES/Thailand.bin:
  * ข้อความภาษาไทยทางการ 3,924 รายการ
  * แก้ปัญหาแครชเวลาตั้งชื่อโปรไฟล์ใหม่บนคีย์บอร์ดเสมือน (vkbd / Name Entry Fix)
- gamedata/LANGUAGES/LanguageTextures.bin:
  * เทกซ์เจอร์และฟอนต์ภาษาไทยคมชัดระดับ HD (Conduit Thai Fonts)

วิธีติดตั้งง่ายๆ (Copy-Paste):
------------------------------------------------------------------------------
1. นำโฟลเดอร์ "nfsu2" และ "images" ไปวางทับในเครื่องเกมที่:
   /roms/ports/
   (หรือเปิด MicroSD Card ในคอมพิวเตอร์ แล้วลากโฟลเดอร์ nfsu2 และ images ไปวางในโฟลเดอร์ ports)
   * โฟลเดอร์ images ประกอบด้วย Box Art (NFSU2-image.png) และ Thumbnail (NFSU2-thumb.png)
   * ไม่ต้องทับไฟล์ gamelist.xml เพื่อป้องกันรายชื่อเกมเดิมสูญหาย
2. ตรวจสอบให้แน่ใจว่าในไฟล์ /roms/ports/nfsu2/nfsu2.cfg ตั้งค่าภาษาเป็น:
   NFSU2_LANG=Thai
3. เข้าเล่นเกมผ่านเมนู PORTS -> NFSU2 ได้ทันที!
==============================================================================
"@
Set-Content -Path (Join-Path $stageDir "README_INSTALL.txt") -Value $readmeContent -Encoding UTF8

# 4. Compress to ZIP
Write-Host "`n[2/3] Compressing package into ZIP archive..." -ForegroundColor Yellow
if (Test-Path $OutputPath) {
    Remove-Item $OutputPath -Force
}

Compress-Archive -Path (Join-Path $stageDir "nfsu2"), (Join-Path $stageDir "images"), (Join-Path $stageDir "README_INSTALL.txt") -DestinationPath $OutputPath -CompressionLevel Optimal

# 5. Clean up staging
Write-Host "`n[3/3] Cleaning up temporary files..." -ForegroundColor Yellow
Remove-Item $stageDir -Recurse -Force

$zipItem = Get-Item $OutputPath
$sizeMb = [math]::Round($zipItem.Length / 1MB, 2)

Write-Host "`n[SUCCESS] Package built successfully!" -ForegroundColor Green
Write-Host "  Path : $($zipItem.FullName)"
Write-Host "  Size : $sizeMb MB"
