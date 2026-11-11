#!/usr/bin/env python3
"""
Build standalone drop-in copy-paste package (nfsu2_thai_copy_paste.zip) for R36H / R36S.
Supports both Windows and Linux / WSL environments.
"""

import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import sys
import zipfile

# Import sibling patch modules
SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

try:
    from patch_thai import patch_exe
    from patch_subtitles import patch_arm64_binary
    from patch_thailand_bin import patch_thailand_bin
except ImportError as e:
    print(f"[WARN] Sibling patch modules could not be imported: {e}", file=sys.stderr)
    patch_exe = None
    patch_arm64_binary = None
    patch_thailand_bin = None


def normalize_path(p) -> Path:
    """Resolve both Windows (D:\\...) and Linux/WSL (/mnt/d/...) paths across OSes."""
    s = str(p).strip()
    if os.name == "nt":
        m = re.match(r"^/mnt/([a-zA-Z])(?:/(.*))?$", s.replace("\\", "/"))
        if m:
            drive = m.group(1).upper()
            rest = (m.group(2) or "").replace("/", "\\")
            return Path(f"{drive}:\\{rest}")
    else:
        m = re.match(r"^([a-zA-Z]):[\\/](.*)$", s)
        if m:
            drive = m.group(1).lower()
            rest = m.group(2).replace("\\", "/")
            return Path(f"/mnt/{drive}/{rest}")
    return Path(s)


README_CONTENT = """==============================================================================
Need for Speed: Underground 2 — Thai + Subtitles Drop-in Pack (R36H / R36S)
==============================================================================

ชุดแพตช์ภาษาไทย + ปลดล็อกคำบรรยายซับไตเติล (สำหรับ Copy-Paste วางทับได้ทันที):
- NFSU2.sh:
  * ตัวเปิดเกมหลัก (Master Launcher) ตั้งค่าเริ่มต้นเป็นภาษาไทย (NFSU2_LANG=Thai)
  * ปรับจูนกราฟิกและแคป 30 FPS สำหรับชิปเซ็ต RK3326
- nfsu2/nfsu2.cfg:
  * กำหนดค่าภาษาเริ่มต้นเป็น Thai พร้อมโปรไฟล์ performance สำหรับ R36H / R36S
- nfsu2/nfsu2.aarch64 & nfsu2/nfsu2.aarch64.v10:
  * ปลดล็อกระบบซับไตเติลภาษาไทย (Thai Subtitles) ในคัตซีนการ์ตูน (Scene01-20)
  * ปลดล็อกซับไตเติลในฉากภาพยนตร์ (In-game FMV/Movies)
- nfsu2/gamedata/SPEED2.EXE & speed2.exe:
  * ปลดล็อกระบบแสดงผลภาษาไทย (Thai Localization)
  * ฟอนต์ภาษาไทยคมชัด ไม่กระพริบ
- nfsu2/gamedata/LANGUAGES/Thailand.bin:
  * ข้อความภาษาไทยทางการ 3,924 รายการ
  * แก้ปัญหาแครชเวลาตั้งชื่อโปรไฟล์ใหม่บนคีย์บอร์ดเสมือน (vkbd / Name Entry Fix)
- nfsu2/gamedata/LANGUAGES/LanguageTextures.bin:
  * เทกซ์เจอร์และฟอนต์ภาษาไทยคมชัดระดับ HD (Conduit Thai Fonts)
- images/:
  * Box Art (NFSU2-image.png) และ Cover Art (NFSU2-thumb.png) คมชัด

วิธีติดตั้งง่ายๆ (Copy-Paste):
------------------------------------------------------------------------------
1. นำไฟล์และโฟลเดอร์ทั้งหมด (NFSU2.sh, nfsu2, images) ไปวางทับในเครื่องเกมที่:
   /roms/ports/
   (หรือเปิด MicroSD Card ในคอมพิวเตอร์ แล้วลาก NFSU2.sh, โฟลเดอร์ nfsu2 และ images ไปวางในโฟลเดอร์ ports ตอบ Replace All เพื่อวางทับไฟล์เดิม)
   * ไม่ต้องทับไฟล์ gamelist.xml เพื่อป้องกันรายชื่อเกมเดิมสูญหาย
2. เข้าเล่นเกมผ่านเมนู PORTS -> NFSU2 ได้ทันที ภาษาไทยและซับไตเติลจะทำงานอัตโนมัติ!
==============================================================================
"""


def find_source_file(candidates):
    for c in candidates:
        norm = normalize_path(c)
        if norm.exists():
            return norm
    return None


def build_package(output_zip: Path = None):
    dist_dir = SCRIPT_DIR / "dist"
    dist_dir.mkdir(parents=True, exist_ok=True)
    if not output_zip:
        output_zip = dist_dir / "nfsu2_thai_copy_paste.zip"
    else:
        output_zip = normalize_path(output_zip)

    print("==================================================================")
    print("  Building NFSU2 Thai Copy-Paste Distribution Package")
    print(f"  Target: {output_zip}")
    print("==================================================================")

    # 1. Locate Source Assets
    launcher_src = find_source_file([
        SCRIPT_DIR / "ports" / "NFSU2.sh",
        SCRIPT_DIR / "NFSU2.sh",
    ])
    cfg_src = find_source_file([
        SCRIPT_DIR / "ports" / "nfsu2" / "nfsu2.cfg",
        SCRIPT_DIR / "nfsu2.cfg",
    ])
    arm64_v10_src = find_source_file([
        SCRIPT_DIR / "ports" / "nfsu2" / "nfsu2.aarch64.v10",
        SCRIPT_DIR / "publish" / "nfsu2_thai_copy_paste" / "nfsu2" / "nfsu2.aarch64.v10",
        SCRIPT_DIR / "ports" / "nfsu2" / "nfsu2.aarch64",
    ])
    exe_src = find_source_file([
        SCRIPT_DIR / "tools" / "nfsu2_thai" / "gamedata" / "SPEED2.EXE",
        SCRIPT_DIR / "nfsu2_thai" / "SPEED2.EXE",
        SCRIPT_DIR / "ports" / "nfsu2" / "gamedata" / "SPEED2.EXE",
    ])
    thai_bin_src = find_source_file([
        SCRIPT_DIR / "tools" / "nfsu2_thai" / "gamedata" / "LANGUAGES" / "Thailand.bin",
        SCRIPT_DIR / "nfsu2_thai" / "LANGUAGES" / "Thailand.bin",
        SCRIPT_DIR / "ports" / "nfsu2" / "gamedata" / "LANGUAGES" / "Thailand.bin",
    ])
    lang_tex_src = find_source_file([
        SCRIPT_DIR / "tools" / "nfsu2_thai" / "gamedata" / "LANGUAGES" / "LanguageTextures.bin",
        SCRIPT_DIR / "ports" / "nfsu2" / "gamedata" / "LANGUAGES" / "LanguageTextures.bin",
        SCRIPT_DIR / "game" / "v1" / "LANGUAGES" / "LanguageTextures.bin",
    ])

    missing = []
    if not launcher_src: missing.append("NFSU2.sh")
    if not cfg_src: missing.append("nfsu2.cfg")
    if not arm64_v10_src: missing.append("nfsu2.aarch64.v10")
    if not exe_src: missing.append("SPEED2.EXE")
    if not thai_bin_src: missing.append("Thailand.bin")

    if missing:
        print(f"[ERROR] Missing required source files: {', '.join(missing)}", file=sys.stderr)
        return False

    stage_dir = dist_dir / "_stage_build"
    if stage_dir.exists():
        shutil.rmtree(stage_dir)
    stage_nfsu2 = stage_dir / "nfsu2"
    stage_gamedata = stage_nfsu2 / "gamedata"
    stage_lang = stage_gamedata / "LANGUAGES"
    stage_lang.mkdir(parents=True, exist_ok=True)

    print(f"\n[1/4] Copying files to staging directory...")
    # Master Launcher (NFSU2.sh) at root of ports
    target_launcher = stage_dir / "NFSU2.sh"
    launcher_bytes = launcher_src.read_bytes().replace(b"\r\n", b"\n")
    target_launcher.write_bytes(launcher_bytes)

    # Runtime Configuration (nfsu2/nfsu2.cfg)
    target_cfg = stage_nfsu2 / "nfsu2.cfg"
    cfg_bytes = cfg_src.read_bytes().replace(b"\r\n", b"\n")
    target_cfg.write_bytes(cfg_bytes)

    # ARM64 binaries (v10 for US retail v1.0 No-CD 4,788,224 bytes)
    target_arm64 = stage_nfsu2 / "nfsu2.aarch64"
    target_arm64_v10 = stage_nfsu2 / "nfsu2.aarch64.v10"
    shutil.copy2(arm64_v10_src, target_arm64)
    shutil.copy2(arm64_v10_src, target_arm64_v10)

    # SPEED2.EXE
    target_exe = stage_gamedata / "SPEED2.EXE"
    target_exe_lower = stage_gamedata / "speed2.exe"
    shutil.copy2(exe_src, target_exe)
    shutil.copy2(exe_src, target_exe_lower)

    # Thailand.bin
    target_thai_bin = stage_lang / "Thailand.bin"
    shutil.copy2(thai_bin_src, target_thai_bin)

    # LanguageTextures.bin
    if lang_tex_src:
        shutil.copy2(lang_tex_src, stage_lang / "LanguageTextures.bin")

    # Ports Images (Box Art & Thumbnail - Safe Copy-Paste)
    stage_images = stage_dir / "images"
    stage_images.mkdir(parents=True, exist_ok=True)
    boxart_src = find_source_file([
        SCRIPT_DIR / "ports" / "images" / "NFSU2-image.png",
        SCRIPT_DIR / "tools" / "nfsu2_thai" / "images" / "NFSU2-image.png",
    ])
    thumb_src = find_source_file([
        SCRIPT_DIR / "ports" / "images" / "NFSU2-thumb.png",
        SCRIPT_DIR / "tools" / "nfsu2_thai" / "images" / "NFSU2-thumb.png",
    ])
    if boxart_src:
        shutil.copy2(boxart_src, stage_images / "NFSU2-image.png")
    if thumb_src:
        shutil.copy2(thumb_src, stage_images / "NFSU2-thumb.png")

    # README_INSTALL.txt
    readme_path = stage_dir / "README_INSTALL.txt"
    readme_path.write_text(README_CONTENT, encoding="utf-8")

    # 2. Verify and Auto-Patch
    print(f"\n[2/4] Verifying and auto-patching binaries...")
    if patch_arm64_binary:
        patch_arm64_binary(target_arm64)
        patch_arm64_binary(target_arm64_v10)
    if patch_exe:
        patch_exe(target_exe, target_exe)
        patch_exe(target_exe_lower, target_exe_lower)
    if patch_thailand_bin:
        patch_thailand_bin(target_thai_bin)

    # 3. Create ZIP Archive
    print(f"\n[3/4] Compressing into {output_zip.name}...")
    if output_zip.exists():
        output_zip.unlink()

    with zipfile.ZipFile(output_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zipf:
        for root, dirs, files in os.walk(stage_dir):
            for file in files:
                full_path = Path(root) / file
                rel_path = full_path.relative_to(stage_dir)
                arcname = str(rel_path).replace("\\", "/")
                zinfo = zipfile.ZipInfo.from_file(full_path, arcname=arcname)
                # Ensure Linux execution permissions for .sh scripts and ELF binaries
                if arcname.endswith(".sh") or "nfsu2.aarch64" in arcname:
                    zinfo.external_attr = (0o755 << 16) | 0o100000
                else:
                    zinfo.external_attr = (0o644 << 16) | 0o100000
                with open(full_path, "rb") as f_in:
                    zipf.writestr(zinfo, f_in.read(), compress_type=zipfile.ZIP_DEFLATED)

    # 4. Cleanup and Report
    print(f"\n[4/4] Cleaning temporary staging directory...")
    shutil.rmtree(stage_dir, ignore_errors=True)

    size_mb = output_zip.stat().st_size / (1024 * 1024)
    print(f"\n[SUCCESS] Package generated successfully:")
    print(f"  Path : {output_zip}")
    print(f"  Size : {size_mb:.2f} MB")
    return True


def main():
    parser = argparse.ArgumentParser(description="Build NFSU2 Thai Copy-Paste Distribution Pack for R36S/R36H.")
    parser.add_argument("-o", "--output", type=normalize_path, help="Custom output zip path")
    args = parser.parse_args()

    success = build_package(args.output)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
