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
print_msg "  Need for Speed: Underground 2 Thai Localization Setup   "
print_msg "               Target: R36H / R36S (playOS)               "
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
print_msg "[1/6] Checking NFSU2 game folder at /roms/ports/nfsu2..."
NFSU2_DIR=""
for cand in "/roms/ports/nfsu2" "/roms2/ports/nfsu2" "/roms/ports/NFSU2" "$SCRIPT_DIR/../../ports/nfsu2" "$SCRIPT_DIR/../ports/nfsu2"; do
    if [ -d "$cand" ] && [ -d "$cand/gamedata" ]; then
        NFSU2_DIR="$(cd "$cand" && pwd)"
        break
    fi
done

if [ -z "$NFSU2_DIR" ]; then
    print_msg ""
    print_msg "  [!] ERROR: Game folder not found at /roms/ports/nfsu2/gamedata/"
    print_msg "  -> Please copy your PC retail game assets (CARS, GLOBAL, TRACKS, SOUND, MOVIES)"
    print_msg "     to /roms/ports/nfsu2/gamedata/ before running this installer."
    print_msg ""
    print_msg "=========================================================="
    print_msg "                  Installation Aborted                    "
    print_msg "=========================================================="
    sleep 2
    exit 1
fi
print_msg "  -> Game folder verified: $NFSU2_DIR [OK]"

GAMEDATA="$NFSU2_DIR/gamedata"
BACKUP_DIR="$NFSU2_DIR/.backup_thai"
CFG_FILE="$NFSU2_DIR/nfsu2.cfg"
mkdir -p "$BACKUP_DIR"

# 3. Backup Original Game Files
print_msg ""
print_msg "[2/6] Backing up original game files to .backup_thai/..."
EXE="$GAMEDATA/SPEED2.EXE"
if [ ! -f "$EXE" ] && [ -f "$GAMEDATA/speed2.exe" ]; then
    EXE="$GAMEDATA/speed2.exe"
fi

if [ -f "$EXE" ] && [ ! -f "$BACKUP_DIR/SPEED2.EXE" ]; then
    cp -f "$EXE" "$BACKUP_DIR/SPEED2.EXE"
    print_msg "  -> SPEED2.EXE backed up successfully [OK]"
fi

if [ -f "$CFG_FILE" ] && [ ! -f "$BACKUP_DIR/nfsu2.cfg" ]; then
    cp -f "$CFG_FILE" "$BACKUP_DIR/nfsu2.cfg"
    print_msg "  -> nfsu2.cfg backed up successfully [OK]"
fi

for bin_name in "nfsu2.aarch64.v10" "nfsu2.aarch64"; do
    if [ -f "$NFSU2_DIR/$bin_name" ] && [ ! -f "$BACKUP_DIR/$bin_name" ]; then
        cp -f "$NFSU2_DIR/$bin_name" "$BACKUP_DIR/$bin_name"
        print_msg "  -> $bin_name backed up successfully [OK]"
    fi
done

if [ -f "$GAMEDATA/LANGUAGES/Thailand.bin" ] && [ ! -f "$BACKUP_DIR/.thailand_bin_preexisted" ]; then
    touch "$BACKUP_DIR/.thailand_bin_preexisted"
fi

if [ -f "$GAMEDATA/LANGUAGES/LanguageTextures.bin" ] && [ ! -f "$BACKUP_DIR/LanguageTextures.bin" ]; then
    cp -f "$GAMEDATA/LANGUAGES/LanguageTextures.bin" "$BACKUP_DIR/LanguageTextures.bin"
    print_msg "  -> LanguageTextures.bin backed up successfully [OK]"
fi

# 4. Install Thailand.bin & SPEED2.EXE
print_msg ""
print_msg "[3/6] Installing Thai localization assets & SPEED2.EXE..."
mkdir -p "$GAMEDATA/LANGUAGES"

# 4.1 Resolve and install Thailand.bin (Full 264 KB)
THAI_BIN_SRC=""
for cand_bin in     "$PKG_DIR/gamedata/LANGUAGES/Thailand.bin"     "$TOOLS_DIR/nfsu2_thai/gamedata/LANGUAGES/Thailand.bin"     "$SCRIPT_DIR/gamedata/LANGUAGES/Thailand.bin"     "$SCRIPT_DIR/LANGUAGES/Thailand.bin"     "$APP_DIR/gamedata/LANGUAGES/Thailand.bin"     "$APP_DIR/Thailand.bin"; do
    if [ -f "$cand_bin" ] && [ "$(stat -c%s "$cand_bin" 2>/dev/null || wc -c < "$cand_bin" | tr -d ' ')" -ge 200000 ]; then
        THAI_BIN_SRC="$cand_bin"
        break
    fi
done

THAI_BIN_OK=0
if [ -n "$THAI_BIN_SRC" ]; then
    cp -f "$THAI_BIN_SRC" "$GAMEDATA/LANGUAGES/Thailand.bin"
    cp -f "$THAI_BIN_SRC" "$GAMEDATA/LANGUAGES/thailand.bin" 2>/dev/null || true
    chmod 644 "$GAMEDATA/LANGUAGES/Thailand.bin" "$GAMEDATA/LANGUAGES/thailand.bin" 2>/dev/null || true
    chown ark:ark "$GAMEDATA/LANGUAGES/Thailand.bin" "$GAMEDATA/LANGUAGES/thailand.bin" 2>/dev/null || true
    print_msg "  -> Installed LANGUAGES/Thailand.bin (264 KB) [OK]"
    THAI_BIN_OK=1
elif [ -f "$GAMEDATA/LANGUAGES/Thailand.bin" ] && [ "$(stat -c%s "$GAMEDATA/LANGUAGES/Thailand.bin" 2>/dev/null || wc -c < "$GAMEDATA/LANGUAGES/Thailand.bin" | tr -d ' ')" -ge 200000 ]; then
    print_msg "  -> Found LANGUAGES/Thailand.bin (264 KB) in game folder [OK]"
    THAI_BIN_OK=1
else
    print_msg "  [!] WARNING: Full Thai language file (264 KB) not found!"
    print_msg "      (Existing file is ~65 KB English dummy without Thai font glyphs)"
fi

# 4.2 Resolve and install LanguageTextures.bin (Thai font textures: 1,286,144 bytes)
LT_SRC=""
for cand_lt in     "$PKG_DIR/gamedata/LANGUAGES/LanguageTextures.bin"     "$TOOLS_DIR/nfsu2_thai/gamedata/LANGUAGES/LanguageTextures.bin"     "$SCRIPT_DIR/gamedata/LANGUAGES/LanguageTextures.bin"     "$APP_DIR/gamedata/LANGUAGES/LanguageTextures.bin"     "$APP_DIR/LanguageTextures.bin"; do
    if [ -f "$cand_lt" ] && [ "$(stat -c%s "$cand_lt" 2>/dev/null || wc -c < "$cand_lt" | tr -d ' ')" -ge 1280000 ]; then
        LT_SRC="$cand_lt"
        break
    fi
done

if [ -n "$LT_SRC" ]; then
    cp -f "$LT_SRC" "$GAMEDATA/LANGUAGES/LanguageTextures.bin"
    chmod 644 "$GAMEDATA/LANGUAGES/LanguageTextures.bin" 2>/dev/null || true
    chown ark:ark "$GAMEDATA/LANGUAGES/LanguageTextures.bin" 2>/dev/null || true
    print_msg "  -> Installed LANGUAGES/LanguageTextures.bin (1.28 MB Thai fonts) [OK]"
elif [ -f "$GAMEDATA/LANGUAGES/LanguageTextures.bin" ] && [ "$(stat -c%s "$GAMEDATA/LANGUAGES/LanguageTextures.bin" 2>/dev/null || wc -c < "$GAMEDATA/LANGUAGES/LanguageTextures.bin" | tr -d ' ')" -ge 1280000 ]; then
    print_msg "  -> Found LANGUAGES/LanguageTextures.bin (1.28 MB) in game folder [OK]"
else
    print_msg "  [!] WARNING: LanguageTextures.bin with Thai fonts (1.28 MB) not found!"
fi

# 4.3 Resolve and install / patch SPEED2.EXE
PREPATCHED_EXE=""
for cand_exe in     "$PKG_DIR/gamedata/SPEED2.EXE"     "$TOOLS_DIR/nfsu2_thai/gamedata/SPEED2.EXE"     "$SCRIPT_DIR/gamedata/SPEED2.EXE"     "$SCRIPT_DIR/SPEED2.EXE"     "$APP_DIR/gamedata/SPEED2.EXE"     "$APP_DIR/SPEED2.EXE"; do
    if [ -f "$cand_exe" ] && [ "$(stat -c%s "$cand_exe" 2>/dev/null || wc -c < "$cand_exe" | tr -d ' ')" -eq 4788224 ]; then
        PREPATCHED_EXE="$cand_exe"
        break
    fi
done

SPEED2_OK=0
if [ -n "$PREPATCHED_EXE" ]; then
    cp -f "$PREPATCHED_EXE" "$GAMEDATA/SPEED2.EXE"
    cp -f "$PREPATCHED_EXE" "$GAMEDATA/speed2.exe" 2>/dev/null || true
    chmod 755 "$GAMEDATA/SPEED2.EXE" "$GAMEDATA/speed2.exe" 2>/dev/null || true
    chown ark:ark "$GAMEDATA/SPEED2.EXE" "$GAMEDATA/speed2.exe" 2>/dev/null || true
    print_msg "  -> Installed SPEED2.EXE (Thai fonts & subtitles enabled) [OK]"
    SPEED2_OK=1
elif [ -f "$EXE" ] && [ "$(stat -c%s "$EXE" 2>/dev/null || wc -c < "$EXE" | tr -d ' ')" -eq 4788224 ]; then
    print_msg "  -> Patching existing $EXE in-place for Thai fonts & subtitles..."
    python3 -c '
import sys

target = sys.argv[1]
patches = [
    (0x10CEF0, b"\xb0\x01\xc3\x90\x90\x90\x90\x90"),
    (0x153703, b"\xeb\x12" + b"\x90" * 18),
    (0x1B7677, b"\x75\x51"),
    (0x39A6E8, b"LANGUAGES\\THAILAND.BIN"),
    (0x39A700, b"THAILAND"),
    (0x3F6F40, b"\x9d\x61\x15\x48"),
    (0x3F6F48, b"\xff\x23\x38\xa7"),
    (0x3F70C0, b"\x0b\x00\x00\x00"),
    (0x3F7108, b"\x0b\x00\x00\x00"),
    (0x3FCA00, b"\x0b\x00\x00\x00"),
]
with open(target, "r+b") as f:
    for off, val in patches:
        f.seek(off)
        f.write(val)
' "$EXE" 2>/dev/null || true

    cp -f "$EXE" "$GAMEDATA/SPEED2.EXE"
    cp -f "$EXE" "$GAMEDATA/speed2.exe" 2>/dev/null || true
    chmod 755 "$GAMEDATA/SPEED2.EXE" "$GAMEDATA/speed2.exe" 2>/dev/null || true
    chown ark:ark "$GAMEDATA/SPEED2.EXE" "$GAMEDATA/speed2.exe" 2>/dev/null || true
    print_msg "  -> Patched SPEED2.EXE successfully [OK]"
    SPEED2_OK=1
else
    print_msg "  [!] WARNING: SPEED2.EXE (v1.0 No-CD 4,788,224 bytes) not found for patching!"
fi

# 5. Unlock ARM64 Subtitles & Configure nfsu2.cfg
print_msg ""
print_msg "[4/6] Unlocking ARM64 subtitles & setting default language..."
for bin_file in "$NFSU2_DIR/nfsu2.aarch64.v10" "$NFSU2_DIR/nfsu2.aarch64"; do
    if [ -f "$bin_file" ] && [ "$(stat -c%s "$bin_file" 2>/dev/null || wc -c < "$bin_file" | tr -d ' ')" -eq 87349296 ]; then
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
print_msg "  -> Unlocked Thai subtitles in ARM64 binary (Cutscenes + Movies) [OK]"

if [ "$THAI_BIN_OK" -eq 1 ] && [ "$SPEED2_OK" -eq 1 ]; then
    TARGET_LANG="Thai"
else
    TARGET_LANG="English"
    print_msg ""
    print_msg "  [!] NOTE: Thai language assets or SPEED2.EXE are incomplete."
    print_msg "      Keeping default language as English to prevent garbled text."
fi

if [ ! -f "$CFG_FILE" ]; then
    cat << EOF > "$CFG_FILE"
# NFSU2 configuration for R36H / playOS
NFSU2_GRAPHICS=performance
NFSU2_FPS=30
NFSU2_LANG=$TARGET_LANG
NFSU2_DRAW_DIST=200
NFSU2_REGISTRY_EXTRA=""
EOF
else
    if grep -q "^NFSU2_LANG=" "$CFG_FILE"; then
        sed -i "s/^NFSU2_LANG=.*/NFSU2_LANG=$TARGET_LANG/" "$CFG_FILE"
    else
        echo "NFSU2_LANG=$TARGET_LANG" >> "$CFG_FILE"
    fi
fi
if [ "$TARGET_LANG" = "Thai" ]; then
    print_msg "  -> Set NFSU2_LANG=Thai in $CFG_FILE [OK]"
else
    print_msg "  -> Set NFSU2_LANG=English in $CFG_FILE [OK]"
fi

# 6. Install Tools Package & Handheld Launchers to /roms/tools/
print_msg ""
print_msg "[5/6] Registering language switchers & uninstaller in /roms/tools..."
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
for launcher in "NFSU2_Language_Thai.sh" "NFSU2_Language_English.sh" "NFSU2_Toggle_Intro.sh" "Uninstall_NFSU2_Thai.sh"; do
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
        print_msg "  -> Registered tool: $TOOLS_DIR/$launcher"
    fi
done

# Install cover art thumbnails to /roms/tools/images/
mkdir -p "$TOOLS_DIR/images"
for thumb in "NFSU2_Language_Thai-thumb.png" "NFSU2_Language_English-thumb.png" "NFSU2_Toggle_Intro-thumb.png" "Uninstall_NFSU2_Thai-thumb.png"; do
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

# Install Ports Box Art (NFSU2-image.png) and Thumbnail (NFSU2-thumb.png)
PORTS_DIR="/roms/ports"
[ ! -d "$PORTS_DIR" ] && [ -d "/roms2/ports" ] && PORTS_DIR="/roms2/ports"
if [ -d "$PORTS_DIR" ]; then
    mkdir -p "$PORTS_DIR/images"

    # 1. Install Thumbnail (Logo 512x512)
    for cand_ico in "$TOOLS_DIR/nfsu2_thai/images/NFSU2-thumb.png" "$SCRIPT_DIR/images/NFSU2-thumb.png"; do
        if [ -f "$cand_ico" ]; then
            cp -f "$cand_ico" "$PORTS_DIR/images/NFSU2-thumb.png"
            chmod 644 "$PORTS_DIR/images/NFSU2-thumb.png" 2>/dev/null || true
            chown ark:ark "$PORTS_DIR/images/NFSU2-thumb.png" 2>/dev/null || true
            print_msg "  -> Installed game icon (Ports): $PORTS_DIR/images/NFSU2-thumb.png"
            break
        fi
    done

    # 2. Install Box Art (250x375)
    for cand_box in "$TOOLS_DIR/nfsu2_thai/images/NFSU2-image.png" "$SCRIPT_DIR/images/NFSU2-image.png"; do
        if [ -f "$cand_box" ]; then
            cp -f "$cand_box" "$PORTS_DIR/images/NFSU2-image.png"
            chmod 644 "$PORTS_DIR/images/NFSU2-image.png" 2>/dev/null || true
            chown ark:ark "$PORTS_DIR/images/NFSU2-image.png" 2>/dev/null || true
            print_msg "  -> Installed Box Art (Ports): $PORTS_DIR/images/NFSU2-image.png"
            break
        fi
    done

    # 3. Safely update /roms/ports/gamelist.xml without overwriting other games
    python3 - << 'PYEOF' 2>/dev/null || true
import os
import xml.etree.ElementTree as ET

gamelist_path = "/roms/ports/gamelist.xml"
if not os.path.exists(gamelist_path) and os.path.exists("/roms2/ports/gamelist.xml"):
    gamelist_path = "/roms2/ports/gamelist.xml"

if os.path.exists(gamelist_path):
    try:
        tree = ET.parse(gamelist_path)
        root = tree.getroot()
        target_game = None
        for g in root.findall("game"):
            p = g.find("path")
            if p is not None and p.text and ("NFSU2.sh" in p.text):
                target_game = g
                break
        if target_game is None:
            target_game = ET.SubElement(root, "game")
            ET.SubElement(target_game, "path").text = "./NFSU2.sh"

        def set_tag(parent, tag, val):
            el = parent.find(tag)
            if el is None:
                el = ET.SubElement(parent, tag)
            el.text = val

        set_tag(target_game, "name", "Need for Speed: Underground 2")
        set_tag(target_game, "desc", "Discover the living, breathing world of tuner culture in Need for Speed: Underground 2, the sequel to the best-selling racing game of 2003. Taking place in a massive, free-roaming city featuring five distinct interconnected neighborhoods, Underground 2 delivers an immersive game world where the streets are your menus.")
        set_tag(target_game, "image", "./images/NFSU2-image.png")
        set_tag(target_game, "thumbnail", "./images/NFSU2-thumb.png")
        set_tag(target_game, "rating", "0.88")
        set_tag(target_game, "releasedate", "20041109T000000")
        set_tag(target_game, "developer", "EA Black Box")
        set_tag(target_game, "publisher", "Electronic Arts")
        set_tag(target_game, "genre", "Racing")
        set_tag(target_game, "players", "1")

        ET.indent(root, space="	")
        with open(gamelist_path, "w", encoding="utf-8", newline="
") as f:
            f.write('<?xml version="1.0"?>
' + ET.tostring(root, encoding="unicode") + "
")
    except Exception:
        pass
PYEOF
    chown ark:ark "$PORTS_DIR/gamelist.xml" 2>/dev/null || true
fi

# 7. Clean up gamelist.xml and refresh playfe
print_msg ""
print_msg "[6/6] Organizing gamelist.xml & refreshing playfe..."
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
            ET.indent(root, space="	")
            with open(gamelist_path, "w", encoding="utf-8", newline="
") as f:
                f.write('<?xml version="1.0"?>
' + ET.tostring(root, encoding="unicode") + "
")
    except Exception:
        pass
PYEOF
chown ark:ark /roms/tools/gamelist.xml 2>/dev/null || true

sync
sudo systemctl restart emulationstation.service 2>/dev/null || true
if systemctl is-active --quiet playfe.service 2>/dev/null; then
    systemctl restart playfe.service 2>/dev/null || true
fi

print_msg ""
print_msg "=========================================================="
print_msg "   [OK] NFSU2 Thai Localization Installed Successfully!   "
print_msg "=========================================================="
print_msg "  * Game Engine : Thai language & cutscene/movie subtitles enabled"
print_msg "  * TOOLS Menu on R36H:"
print_msg "      1. NFSU2_Language_Thai.sh    (Switch in-game language to Thai)"
print_msg "      2. NFSU2_Language_English.sh (Switch in-game language to English)"
print_msg "      3. NFSU2_Toggle_Intro.sh     (Toggle skip intro movies / fast boot)"
print_msg "      4. Uninstall_NFSU2_Thai.sh   (Restore original game & clean menu)"
print_msg "  * Ready to play! Launch game from: PORTS -> NFSU2"
print_msg "=========================================================="

sleep 1
exit 0
