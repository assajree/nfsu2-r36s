#!/bin/bash
# ==============================================================================
# Tool: NFSU2 Thai Language & Tools Installer for R36H (playOS)
# Script: Install_NFSU2_Thai.sh
# Description: Installs Thai localization & subtitles directly into NFSU2 game
#              and registers Language Switchers & Uninstaller in /roms/tools/
# Stem-Match: "uninstallnfsu2thai" contains "nfsu2thai" (Auto-hides nfsu2_thai)
# ==============================================================================

# 1. Root Privilege Escalation
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR="/roms/tools"

print_msg() {
    echo -e "$1"
    if [ -w /dev/tty1 ]; then
        echo -e "$1" > /dev/tty1 2>/dev/null || true
    fi
}

clear > /dev/tty1 2>/dev/null || true
clear 2>/dev/null || true

print_msg "=========================================================="
print_msg "     ติดตั้งภาษาไทย Need for Speed: Underground 2        "
print_msg "                 สำหรับเครื่อง R36H (playOS)              "
print_msg "=========================================================="
print_msg ""

# Resolve Package Directory & App Directory
if [ -d "$SCRIPT_DIR/app" ]; then
    PKG_DIR="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/nfsu2_thai/app" ]; then
    PKG_DIR="$SCRIPT_DIR/nfsu2_thai"
elif [ -d "$TOOLS_DIR/nfsu2_thai/app" ]; then
    PKG_DIR="$TOOLS_DIR/nfsu2_thai"
else
    PKG_DIR="$SCRIPT_DIR"
fi

APP_DIR="$PKG_DIR/app"

# 2. Check Game Directory (Abort if not found)
print_msg "[1/6] กำลังตรวจสอบโฟลเดอร์เกม NFSU2 ใน /roms/ports/nfsu2..."
NFSU2_DIR=""
for cand in "/roms/ports/nfsu2" "/roms2/ports/nfsu2" "/roms/ports/NFSU2" "$SCRIPT_DIR/../../ports/nfsu2" "$SCRIPT_DIR/../ports/nfsu2"; do
    if [ -d "$cand" ] && [ -d "$cand/gamedata" ]; then
        NFSU2_DIR="$(cd "$cand" && pwd)"
        break
    fi
done

if [ -z "$NFSU2_DIR" ]; then
    print_msg ""
    print_msg "  [!] ข้อผิดพลาด: ไม่พบโฟลเดอร์เกมที่ /roms/ports/nfsu2/gamedata/"
    print_msg "  -> กรุณานำไฟล์ตัวเกม PC (CARS, GLOBAL, TRACKS, SOUND, MOVIES)"
    print_msg "     มาวางไว้ที่ /roms/ports/nfsu2/gamedata/ ให้เรียบร้อยก่อนติดตั้ง"
    print_msg ""
    print_msg "=========================================================="
    print_msg "                 การติดตั้งถูกยกเลิก (Aborted)            "
    print_msg "=========================================================="
    sleep 2
    exit 1
fi
print_msg "  -> พบโฟลเดอร์เกม: $NFSU2_DIR [OK]"

GAMEDATA="$NFSU2_DIR/gamedata"
BACKUP_DIR="$NFSU2_DIR/.backup_thai"
CFG_FILE="$NFSU2_DIR/nfsu2.cfg"
mkdir -p "$BACKUP_DIR"

# 3. Backup Original Game Files
print_msg ""
print_msg "[2/6] สำรองไฟล์เกมเดิมไปยัง .backup_thai/..."
EXE="$GAMEDATA/SPEED2.EXE"
if [ ! -f "$EXE" ] && [ -f "$GAMEDATA/speed2.exe" ]; then
    EXE="$GAMEDATA/speed2.exe"
fi

if [ -f "$EXE" ] && [ ! -f "$BACKUP_DIR/SPEED2.EXE" ]; then
    cp -f "$EXE" "$BACKUP_DIR/SPEED2.EXE"
    print_msg "  -> สำรอง SPEED2.EXE เดิมเรียบร้อย [OK]"
fi

if [ -f "$CFG_FILE" ] && [ ! -f "$BACKUP_DIR/nfsu2.cfg" ]; then
    cp -f "$CFG_FILE" "$BACKUP_DIR/nfsu2.cfg"
    print_msg "  -> สำรอง nfsu2.cfg เดิมเรียบร้อย [OK]"
fi

for bin_name in "nfsu2.aarch64.v10" "nfsu2.aarch64"; do
    if [ -f "$NFSU2_DIR/$bin_name" ] && [ ! -f "$BACKUP_DIR/$bin_name" ]; then
        cp -f "$NFSU2_DIR/$bin_name" "$BACKUP_DIR/$bin_name"
        print_msg "  -> สำรอง $bin_name เดิมเรียบร้อย [OK]"
    fi
done

if [ -f "$GAMEDATA/LANGUAGES/Thailand.bin" ] && [ ! -f "$BACKUP_DIR/.thailand_bin_preexisted" ]; then
    touch "$BACKUP_DIR/.thailand_bin_preexisted"
fi

# 4. Install Thailand.bin & SPEED2.EXE
print_msg ""
print_msg "[3/6] ติดตั้งไฟล์ภาษาไทย (Thailand.bin และ SPEED2.EXE)..."
mkdir -p "$GAMEDATA/LANGUAGES"
THAI_BIN_SRC=""
for cand_bin in "$PKG_DIR/gamedata/LANGUAGES/Thailand.bin" "$APP_DIR/gamedata/LANGUAGES/Thailand.bin" "$SCRIPT_DIR/gamedata/LANGUAGES/Thailand.bin" "$APP_DIR/Thailand.bin"; do
    if [ -f "$cand_bin" ]; then
        THAI_BIN_SRC="$cand_bin"
        break
    fi
done

if [ -n "$THAI_BIN_SRC" ]; then
    cp -f "$THAI_BIN_SRC" "$GAMEDATA/LANGUAGES/Thailand.bin"
    chmod 644 "$GAMEDATA/LANGUAGES/Thailand.bin" 2>/dev/null || true
    chown ark:ark "$GAMEDATA/LANGUAGES/Thailand.bin" 2>/dev/null || true
    print_msg "  -> ติดตั้ง LANGUAGES/Thailand.bin เรียบร้อย [OK]"
fi

PREPATCHED_EXE=""
for cand_exe in "$PKG_DIR/gamedata/SPEED2.EXE" "$APP_DIR/gamedata/SPEED2.EXE" "$SCRIPT_DIR/gamedata/SPEED2.EXE" "$APP_DIR/SPEED2.EXE"; do
    if [ -f "$cand_exe" ]; then
        PREPATCHED_EXE="$cand_exe"
        break
    fi
done

if [ -n "$PREPATCHED_EXE" ]; then
    cp -f "$PREPATCHED_EXE" "$GAMEDATA/SPEED2.EXE"
    cp -f "$PREPATCHED_EXE" "$GAMEDATA/speed2.exe" 2>/dev/null || true
    chmod 755 "$GAMEDATA/SPEED2.EXE" "$GAMEDATA/speed2.exe" 2>/dev/null || true
    chown ark:ark "$GAMEDATA/SPEED2.EXE" "$GAMEDATA/speed2.exe" 2>/dev/null || true
    print_msg "  -> ติดตั้ง SPEED2.EXE ภาษาไทยและซับไตเติลเรียบร้อย [OK]"
fi

# 5. Unlock ARM64 Subtitles & Configure nfsu2.cfg
print_msg ""
print_msg "[4/6] ปลดล็อกซับไตเติล ARM64 และตั้งค่าภาษาเริ่มต้น..."
for bin_file in "$NFSU2_DIR/nfsu2.aarch64.v10" "$NFSU2_DIR/nfsu2.aarch64"; do
    if [ -f "$bin_file" ] && [ "$(stat -c%s "$bin_file" 2>/dev/null)" -eq 87349296 ]; then
        python3 -c '
arm_patches = [
    (0x1FD660, b"\x41\xd0\x3b\xd5\x20\xa0\x40\x39\x00\x00\x00\x32\x20\xa0\x00\x39\x20\x38\x40\xb9\x00\x10\x00\x11\x20\x38\x00\xb9\xc0\x03\x5f\xd6"),
    (0x3B62EF0, b"\x58\x00\x00\x14"),
]
with open("'"$bin_file"'", "r+b") as f:
    for off, val in arm_patches:
        f.seek(off); f.write(val)
' 2>/dev/null || true
    fi
done
print_msg "  -> ปลดล็อกระบบซับไตเติลภาษาไทย (Cutscenes + Movies) [OK]"

if [ ! -f "$CFG_FILE" ]; then
    cat << 'EOF' > "$CFG_FILE"
# NFSU2 configuration for R36H / playOS
NFSU2_GRAPHICS=performance
NFSU2_FPS=30
NFSU2_LANG=Thai
NFSU2_DRAW_DIST=200
NFSU2_REGISTRY_EXTRA=""
EOF
else
    if grep -q "^NFSU2_LANG=" "$CFG_FILE"; then
        sed -i 's/^NFSU2_LANG=.*/NFSU2_LANG=Thai/' "$CFG_FILE"
    else
        echo "NFSU2_LANG=Thai" >> "$CFG_FILE"
    fi
fi
print_msg "  -> กำหนด NFSU2_LANG=Thai ใน $CFG_FILE เรียบร้อย [OK]"

# 6. Install Tools Package & Handheld Launchers to /roms/tools/
print_msg ""
print_msg "[5/6] ติดตั้งเมนูสลับภาษาลงใน /roms/tools..."
mkdir -p "$TOOLS_DIR/nfsu2_thai"
if [ "$PKG_DIR" != "$TOOLS_DIR/nfsu2_thai" ]; then
    cp -rf "$PKG_DIR"/* "$TOOLS_DIR/nfsu2_thai/" 2>/dev/null || true
fi
chmod -R 755 "$TOOLS_DIR/nfsu2_thai" 2>/dev/null || true
chown -R ark:ark "$TOOLS_DIR/nfsu2_thai" 2>/dev/null || true

# Cleanup legacy /roms/tools/nfsu2/, Setup launcher, and old tools uninstaller
rm -rf "$TOOLS_DIR/nfsu2" 2>/dev/null || true
rm -f "$TOOLS_DIR/Setup_NFSU2_Thai.sh" "$TOOLS_DIR/images/Setup_NFSU2_Thai-thumb.png" 2>/dev/null || true
rm -f "$TOOLS_DIR/Uninstall_NFSU2_Tools.sh" "$TOOLS_DIR/nfsu2_thai/Uninstall_NFSU2_Tools.sh" 2>/dev/null || true

# Install Launchers: Thai, English, Uninstall
for launcher in "NFSU2_Language_Thai.sh" "NFSU2_Language_English.sh" "Uninstall_NFSU2_Thai.sh"; do
    SRC_L=""
    if [ -f "$APP_DIR/$launcher" ]; then
        SRC_L="$APP_DIR/$launcher"
    elif [ -f "$TOOLS_DIR/nfsu2_thai/app/$launcher" ]; then
        SRC_L="$TOOLS_DIR/nfsu2_thai/app/$launcher"
    fi
    if [ -n "$SRC_L" ]; then
        cp -f "$SRC_L" "$TOOLS_DIR/$launcher"
        chmod 755 "$TOOLS_DIR/$launcher"
        chown ark:ark "$TOOLS_DIR/$launcher" 2>/dev/null || true
        print_msg "  -> ติดตั้งเมนู: $TOOLS_DIR/$launcher"
    fi
done

# Install cover art thumbnails to /roms/tools/images/
mkdir -p "$TOOLS_DIR/images"
for thumb in "NFSU2_Language_Thai-thumb.png" "NFSU2_Language_English-thumb.png" "Uninstall_NFSU2_Thai-thumb.png"; do
    SRC_I=""
    if [ -f "$PKG_DIR/images/$thumb" ]; then
        SRC_I="$PKG_DIR/images/$thumb"
    elif [ -f "$APP_DIR/images/$thumb" ]; then
        SRC_I="$APP_DIR/images/$thumb"
    elif [ -f "$TOOLS_DIR/nfsu2_thai/images/$thumb" ]; then
        SRC_I="$TOOLS_DIR/nfsu2_thai/images/$thumb"
    fi
    if [ -n "$SRC_I" ]; then
        cp -f "$SRC_I" "$TOOLS_DIR/images/$thumb"
        chown ark:ark "$TOOLS_DIR/images/$thumb" 2>/dev/null || true
    fi
done

# Install Ports cover art (NFSU2-thumb.png) to /roms/ports/images/
PORTS_DIR="/roms/ports"
[ ! -d "$PORTS_DIR" ] && [ -d "/roms2/ports" ] && PORTS_DIR="/roms2/ports"
if [ -d "$PORTS_DIR" ]; then
    mkdir -p "$PORTS_DIR/images"
    for cand_ico in "$TOOLS_DIR/nfsu2_thai/images/NFSU2-thumb.png" "$SCRIPT_DIR/images/NFSU2-thumb.png"; do
        if [ -f "$cand_ico" ]; then
            cp -f "$cand_ico" "$PORTS_DIR/images/NFSU2-thumb.png"
            chmod 644 "$PORTS_DIR/images/NFSU2-thumb.png" 2>/dev/null || true
            chown ark:ark "$PORTS_DIR/images/NFSU2-thumb.png" 2>/dev/null || true
            print_msg "  -> ติดตั้งไอคอนเกม (Ports): $PORTS_DIR/images/NFSU2-thumb.png"
            break
        fi
    done
fi

# 7. Clean up gamelist.xml and refresh playfe
print_msg ""
print_msg "[6/6] กำลังจัดระเบียบ gamelist.xml และอัปเดตหน้าจอเมนู..."
python3 - << 'PYEOF' 2>/dev/null || true
import os
import xml.etree.ElementTree as ET

gamelist_path = "/roms/tools/gamelist.xml"
if os.path.exists(gamelist_path):
    try:
        tree = ET.parse(gamelist_path)
        root = tree.getroot()
        removed = False
        for g in list(root.findall("game")):
            p = g.find("path")
            if p is not None and p.text:
                norm_p = p.text.strip().lstrip("./")
                if norm_p.startswith("nfsu2_thai/") or norm_p.startswith("nfsu2/") or "Setup_NFSU2_Thai" in norm_p:
                    root.remove(g)
                    removed = True
        if removed:
            ET.indent(root, space="\t")
            with open(gamelist_path, "w", encoding="utf-8", newline="\n") as f:
                f.write('<?xml version="1.0"?>\n' + ET.tostring(root, encoding="unicode") + "\n")
    except Exception:
        pass
PYEOF
chown ark:ark /roms/tools/gamelist.xml 2>/dev/null || true

sync
if systemctl is-active --quiet playfe.service 2>/dev/null; then
    systemctl restart playfe.service 2>/dev/null || true
fi

print_msg ""
print_msg "=========================================================="
print_msg "      [✓] ติดตั้งภาษาไทย และเครื่องมือสำเร็จสมบูรณ์!      "
print_msg "=========================================================="
print_msg "  • ตัวเกมหลัก: แปลงภาษาไทย + ปลดล็อกซับไตเติลคัตซีน/Movie แล้ว"
print_msg "  • เมนูสลับภาษาบนเครื่อง R36H (หมวด TOOLS):"
print_msg "      1. NFSU2_Language_Thai.sh    (สลับเป็นภาษาไทย)"
print_msg "      2. NFSU2_Language_English.sh (สลับเป็นภาษาอังกฤษ)"
print_msg "      3. Uninstall_NFSU2_Thai.sh   (กู้คืนเกมเดิม + ถอนการติดตั้ง)"
print_msg "  • สามารถเข้าเล่นเกมได้ทันทีที่เมนู PORTS -> NFSU2"
print_msg "=========================================================="

sleep 1
exit 0
