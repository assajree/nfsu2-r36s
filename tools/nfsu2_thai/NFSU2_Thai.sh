#!/bin/bash
# ==============================================================================
# Tool: NFSU2 Thai Manager v1.1 (All-in-One Smart TUI for R36H / playOS / ArkOS)
# Description: Interactive Linux ncurses dialog interface providing 3 smart
#              toggle controls for Need for Speed: Underground 2:
#                1. Install / Uninstall Thai Edition
#                2. Switch Language: Thai <-> English
#                3. Toggle Intro Movies: Skip (Fast Boot 1s) <-> Restore
# Archetype: Archetype 3 (One-Shot Interactive TUI Tool, Flat Side-by-Side)
# Standard: Native /dev/tty1 Console + gptokeyb (Zero fb0_mirror)
# UI Language: 100% Pure ASCII English (Console Font Invariant)
# ==============================================================================

# 1. Root Privilege Escalation
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E "$0" "$@"
fi

# ------------------------------------------------------------------------------
# Dynamic Location & Target Resolution (PortMaster Standard)
# ------------------------------------------------------------------------------
REAL_SCRIPT="$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$0")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
SCRIPT_NAME="$(basename "$REAL_SCRIPT")"

# ------------------------------------------------------------------------------
# Environment Detection & Gamepad Input Setup (Native /dev/tty1 + gptokeyb)
# ------------------------------------------------------------------------------
IS_SSH=0
if [ -n "$SSH_TTY" ] || [ -n "$SSH_CLIENT" ] || [ -n "$SSH_CONNECTION" ]; then
    IS_SSH=1
fi

GPTOKEYB_PID=""
GPTOKEYB_BIN=""
CHOICE_TMP="/tmp/nfsu2_thai_choice.$$"
GPTK_CONF="/tmp/nfsu2_thai_keys.gptk"

cleanup() {
    rm -f "$CHOICE_TMP" "$GPTK_CONF" 2>/dev/null || true
    if [ -n "$GPTOKEYB_PID" ]; then
        kill -9 "$GPTOKEYB_PID" 2>/dev/null || true
    fi
    pkill -9 -f "gptokeyb" 2>/dev/null || true
    killall -9 gptokeyb 2>/dev/null || true

    if [ "$IS_SSH" -eq 0 ]; then
        printf "\033c\e[?25h" > /dev/tty1 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM HUP

# Setup TTY display routing & Controller Bridge
if [ "$IS_SSH" -eq 0 ]; then
    if [ -x "/opt/inttools/gptokeyb" ]; then
        GPTOKEYB_BIN="/opt/inttools/gptokeyb"
    elif [ -x "/usr/local/bin/gptokeyb" ]; then
        GPTOKEYB_BIN="/usr/local/bin/gptokeyb"
    elif command -v gptokeyb >/dev/null 2>&1; then
        GPTOKEYB_BIN="$(command -v gptokeyb)"
    fi

    if [ -n "$GPTOKEYB_BIN" ]; then
        chmod 666 /dev/uinput 2>/dev/null || true
        export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
        pkill -9 -f "gptokeyb" 2>/dev/null || true
        killall -9 gptokeyb 2>/dev/null || true
        sleep 0.1

        # Resolve Dynamic A/B Button Mapping
        # Priority 1 (playfe): /home/ark/.config/playfe/playfe.cfg -> swap_ab=true means A=OK, B=Back
        # Priority 2 (ArkOS): es_settings.cfg InvertButtons or /var/cache/Switch_AB
        SWAP_AB=0

        if [ -f "/home/ark/.config/playfe/playfe.cfg" ]; then
            if grep -iq "^swap_ab=true" "/home/ark/.config/playfe/playfe.cfg" 2>/dev/null; then
                SWAP_AB=1
            fi
        elif [ -f "/var/cache/Switch_AB" ] || grep -iq 'InvertButtons.*value="true"' "/home/ark/.emulationstation/es_settings.cfg" 2>/dev/null; then
            SWAP_AB=1
        fi

        if [ "$SWAP_AB" -eq 1 ]; then
            A_BIND="enter"
            B_BIND="esc"
        else
            A_BIND="esc"
            B_BIND="enter"
        fi

        cat << EOF > "$GPTK_CONF"
up = up
down = down
left = left
right = right
a = $A_BIND
b = $B_BIND
x = space
y = space
select = tab
start = enter
EOF

        TARGET_NAME="$SCRIPT_NAME"
        [ "$TARGET_NAME" = "bash" ] || [ "$TARGET_NAME" = "sh" ] && TARGET_NAME="NFSU2_Thai.sh"
        "$GPTOKEYB_BIN" -1 "$TARGET_NAME" -c "$GPTK_CONF" >/dev/null 2>&1 &
        GPTOKEYB_PID=$!
        sleep 0.2
    fi

    setfont /usr/share/consolefonts/Lat7-TerminusBold20x10.psf.gz -C /dev/tty1 2>/dev/null || \
    setfont /usr/share/consolefonts/Lat7-Terminus16.psf.gz -C /dev/tty1 2>/dev/null || true
    printf "\033c\e[?25l" > /dev/tty1 2>/dev/null || true

    DIALOG_IN="/dev/tty1"
    DIALOG_OUT="/dev/tty1"
    export TERM=linux
else
    DIALOG_IN="/dev/stdin"
    DIALOG_OUT="/dev/stdout"
fi

# Ensure dialog binary is available
if ! command -v dialog >/dev/null 2>&1; then
    echo "[!] ERROR: 'dialog' package is not installed." >&2
    [ "$IS_SSH" -eq 0 ] && printf "\n[!] ERROR: 'dialog' package is not installed.\n" > /dev/tty1 2>/dev/null && sleep 4
    exit 1
fi

# ------------------------------------------------------------------------------
# 2. Locate NFSU2 Port Directory (SD1 / SD2 / Custom Mounts + Interactive Picker)
# ------------------------------------------------------------------------------
resolve_gamedata() {
    local base="$1"
    if [ -d "$base/gamedata" ]; then
        echo "$base/gamedata"
        return 0
    elif [ -d "$base/GAMEDATA" ]; then
        echo "$base/GAMEDATA"
        return 0
    fi
    return 1
}

NFSU2_DIR=""
GAMEDATA=""

# 2a. Auto-detect exact 'nfsu2' folder (case-insensitive) in Script Dir, /roms/ports, and /roms2/ports
for root in "$SCRIPT_DIR" /roms/ports /roms2/ports; do
    [ -d "$root" ] || continue
    for cand in "$root"/*; do
        [ -d "$cand" ] || continue
        if [ "$(basename "$cand" | tr '[:upper:]' '[:lower:]')" = "nfsu2" ]; then
            if GAMEDATA="$(resolve_gamedata "$cand")"; then
                NFSU2_DIR="$(cd "$cand" && pwd)"
                break 2
            fi
        fi
    done
done

# 2b. Interactive Folder Picker if auto-detection failed
if [ -z "$NFSU2_DIR" ]; then
    while true; do
        CAND_DIRS=()
        MENU_ITEMS=()
        IDX=1
        for root in /roms/ports /roms2/ports; do
            [ -d "$root" ] || continue
            for sub in "$root"/*; do
                [ -d "$sub" ] || continue
                CAND_DIRS+=("$sub")
                MENU_ITEMS+=("$IDX" "$sub")
                IDX=$((IDX + 1))
            done
        done

        if [ ${#CAND_DIRS[@]} -eq 0 ]; then
            dialog --backtitle "NFSU2 Thai Manager" --title "Game Not Found" \
                --msgbox "\n  [!] NFSU2 game folder (with gamedata/) was not found.\n\n  Checked:\n    - /roms/ports/nfsu2\n    - /roms2/ports/nfsu2 & NFSU2\n    - /mnt/*/ports & /media/*/ports\n\n  Press A or Enter to exit." \
                13 62 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
            exit 1
        fi

        dialog \
            --backtitle "NFSU2 Thai Manager | Folder Not Auto-Detected" \
            --title "Select NFSU2 Game Folder" \
            --ok-label "Select" \
            --cancel-label "Exit" \
            --menu "\nCould not auto-detect NFSU2 (gamedata/).\nSelect your NFSU2 port folder below:" \
            16 64 7 \
            "${MENU_ITEMS[@]}" \
            2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

        RET=$?
        PICK=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
        rm -f "$CHOICE_TMP"

        if [ $RET -ne 0 ] || [ -z "$PICK" ]; then
            exit 1
        fi

        PICK_DIR="${CAND_DIRS[$((PICK - 1))]}"
        if GAMEDATA="$(resolve_gamedata "$PICK_DIR")"; then
            NFSU2_DIR="$(cd "$PICK_DIR" && pwd)"
            break
        else
            dialog --backtitle "NFSU2 Thai Manager" --title "Invalid Folder" \
                --msgbox "\n  [!] 'gamedata/' not found inside:\n  $PICK_DIR\n\n  Please select the folder containing 'gamedata/'.\n\n  Press A or Enter to try again." \
                11 60 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
        fi
    done
fi

BACKUP_DIR="$NFSU2_DIR/.backup_thai"
CFG_FILE="$NFSU2_DIR/nfsu2.cfg"
MOVIES_DIR="$GAMEDATA/MOVIES"

# Locate Thai Game Assets (Search PortMaster flat directory first, SD1/SD2)
THAI_ASSETS_DIR=""
for cand_assets in \
    "$SCRIPT_DIR/nfsu2thai/gamedata" \
    "$SCRIPT_DIR/gamedata" \
    "/roms/ports/nfsu2thai/gamedata" \
    "/roms2/ports/nfsu2thai/gamedata" \
    "/roms/tools/nfsu2_thai/nfsu2thai/gamedata" \
    "/roms2/tools/nfsu2_thai/nfsu2thai/gamedata" \
    "/roms/tools/nfsu2_thai/gamedata"; do
    if [ -d "$cand_assets" ] && [ -f "$cand_assets/LANGUAGES/Thailand.bin" ]; then
        THAI_ASSETS_DIR="$cand_assets"
        break
    fi
done

# ------------------------------------------------------------------------------
# 5. Intro Movies List & Status Scanner
# ------------------------------------------------------------------------------
INTRO_FILES=("ealogo.vp6" "THX_logo.vp6" "FMVOpening.vp6" "PSA.vp6")

scan_status() {
    # Check Thai Patch Status via marker flag
    THAI_INSTALLED=0
    if [ -f "$NFSU2_DIR/.nfsu2_thai" ]; then
        THAI_INSTALLED=1
    fi

    # Check Active Language & Graphics Profile
    CURRENT_LANG="English"
    CURRENT_GRAPHICS="performance"
    if [ -f "$CFG_FILE" ]; then
        lang_val=$(grep "^NFSU2_LANG=" "$CFG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' \r\n')
        if [ "$lang_val" = "Thai" ]; then
            CURRENT_LANG="Thai"
        fi
        gfx_val=$(grep "^NFSU2_GRAPHICS=" "$CFG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' \r\n')
        if [ -n "$gfx_val" ]; then
            CURRENT_GRAPHICS="$gfx_val"
        fi
    fi

    # Check Fast Boot / Intro Status
    FAST_BOOT_ACTIVE=0
    HAS_ANY_INTRO=0
    for f in "${INTRO_FILES[@]}"; do
        if [ -f "$MOVIES_DIR/$f" ] || [ -f "$MOVIES_DIR/_$f" ]; then
            HAS_ANY_INTRO=1
            break
        fi
    done

    if [ "$HAS_ANY_INTRO" -eq 0 ]; then
        INTRO_STATUS="Deleted"
        FAST_BOOT_ACTIVE=1
    elif [ -f "$MOVIES_DIR/_FMVOpening.vp6" ] || [ ! -f "$MOVIES_DIR/FMVOpening.vp6" ]; then
        INTRO_STATUS="Skipped"
        FAST_BOOT_ACTIVE=1
    else
        INTRO_STATUS="Normal"
        FAST_BOOT_ACTIVE=0
    fi
}

# ------------------------------------------------------------------------------
# 6. Action Implementations
# ------------------------------------------------------------------------------

# Shared Yes/No menu helper using <Select> and <Exit> buttons.
# Returns: 0 = yes, 1 = no, 2 = Exit/Cancel/ESC
ask_yesno_menu() {
    local title="$1" prompt="$2" h="$3" w="$4" def="$5" yes_lbl="$6" no_lbl="$7"
    local tmp="/tmp/nfsu2_thai_yn_$$"
    local ret choice
    if [ "$def" = "no" ]; then
        dialog --backtitle "NFSU2 Thai Manager v1.1" --title "$title" \
            --ok-label "Select" --cancel-label "Exit" --default-item "no" \
            --menu "$prompt" "$h" "$w" 2 \
            "no" "$no_lbl" \
            "yes" "$yes_lbl" \
            2> "$tmp" < "$DIALOG_IN" > "$DIALOG_OUT"
    else
        dialog --backtitle "NFSU2 Thai Manager v1.1" --title "$title" \
            --ok-label "Select" --cancel-label "Exit" --default-item "yes" \
            --menu "$prompt" "$h" "$w" 2 \
            "yes" "$yes_lbl" \
            "no" "$no_lbl" \
            2> "$tmp" < "$DIALOG_IN" > "$DIALOG_OUT"
    fi
    ret=$?
    choice=$(cat "$tmp" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$tmp"
    [ $ret -ne 0 ] && return 2
    [ "$choice" = "yes" ] && return 0
    [ "$choice" = "no" ] && return 1
    return 2
}

do_install_thai() {
    IS_REINSTALL="${1:-0}"
    ENABLE_FASTBOOT=0
    ENABLE_ATTRACT_PATCH=0

    if [ "$IS_REINSTALL" -eq 1 ]; then
        ask_yesno_menu "Confirm Re-install" \
            "\nRe-install NFSU2 Thai Edition?\n\nThis will re-apply:\n  * Thailand.bin & HD Thai font textures\n  * Patched SPEED2.EXE (Thai font streaming)\n  * ARM64 Subtitles, Video NEON & Joypad GPS patches\n  * Language setting set to Thai\n\nExisting .backup_thai/ and Intro Movies state preserved." \
            19 66 "yes" \
            "Yes - Proceed with Re-install" \
            "No  - Back to menu"
        [ $? -ne 0 ] && return

        GAUGE_TITLE="Re-installing Thai Edition"
        SUCCESS_TITLE="Re-install Successful"
        SUCCESS_HEADER="[OK] Thai Localization Re-installed Successfully!"
        FASTBOOT_DESC="Preserved ($INTRO_STATUS)"
    else
        ask_yesno_menu "Fast Boot Option" \
            "\nWould you like to enable Fast Boot (Skip Intro Movies)?" \
            11 62 "yes" \
            "Yes - Direct boot to Title Screen" \
            "No  - Keep original intro movies"
        RC_FASTBOOT=$?

        if [ "$RC_FASTBOOT" -ne 0 ] && [ "$RC_FASTBOOT" -ne 1 ]; then
            return
        fi
        [ "$RC_FASTBOOT" -eq 0 ] && ENABLE_FASTBOOT=1

        if [ "$ENABLE_FASTBOOT" -eq 1 ]; then
            ask_yesno_menu "Attract Mode Option" \
                "\nAlso patch Title Attract Mode?" \
                11 62 "no" \
                "Yes - Keep Title music playing past 30s" \
                "No  - Default (Original behavior)"
            RC_ATTRACT=$?

            if [ "$RC_ATTRACT" -ne 0 ] && [ "$RC_ATTRACT" -ne 1 ]; then
                return
            fi
            [ "$RC_ATTRACT" -eq 0 ] && ENABLE_ATTRACT_PATCH=1
        fi

        GAUGE_TITLE="Installing Thai Edition"
        SUCCESS_TITLE="Install Successful"
        SUCCESS_HEADER="[OK] Thai Localization Installed Successfully!"
        if [ "$ENABLE_FASTBOOT" -eq 1 ]; then
            if [ "$ENABLE_ATTRACT_PATCH" -eq 1 ]; then
                FASTBOOT_DESC="Enabled (Attract Mode patched)"
            else
                FASTBOOT_DESC="Enabled (Attract Mode default)"
            fi
        else
            FASTBOOT_DESC="Disabled (Keep intro movies)"
        fi
    fi

    # Validate required US car models (CIVIC & RSX) before modifying any game files
    CARS_DIR=""
    for cand_cars in "$GAMEDATA/CARS" "$GAMEDATA/cars"; do
        if [ -d "$cand_cars" ]; then
            CARS_DIR="$cand_cars"
            break
        fi
    done
    HAS_CIVIC=0
    HAS_RSX=0
    if [ -n "$CARS_DIR" ]; then
        ([ -d "$CARS_DIR/CIVIC" ] || [ -d "$CARS_DIR/civic" ]) && HAS_CIVIC=1
        ([ -d "$CARS_DIR/RSX" ] || [ -d "$CARS_DIR/rsx" ]) && HAS_RSX=1
    fi
    if [ "$HAS_CIVIC" -eq 0 ] || [ "$HAS_RSX" -eq 0 ]; then
        dialog --backtitle "NFSU2 Thai Manager v1.1" --title "Unsupported Game Region" \
            --msgbox "\n  [!] Missing required car models: CARS/CIVIC and/or CARS/RSX\n\n  Thai SPEED2.EXE (US v1.0) requires CIVIC & RSX in gamedata/CARS/.\n  Please use the US PC game data or install nfsu2_cars_us.zip first.\n\n  Aborted without modifying game files.\n\n  Press A or Enter to return." \
            13 68 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
        return
    fi

    (
        echo "10" ; echo "XXX" ; echo "Backing up original game files..." ; echo "XXX"
        mkdir -p "$BACKUP_DIR"
        EXE="$GAMEDATA/SPEED2.EXE"
        [ ! -f "$EXE" ] && [ -f "$GAMEDATA/speed2.exe" ] && EXE="$GAMEDATA/speed2.exe"
        if [ -f "$EXE" ] && [ ! -f "$BACKUP_DIR/SPEED2.EXE" ]; then
            cp -f "$EXE" "$BACKUP_DIR/SPEED2.EXE"
        fi
        if [ -f "$CFG_FILE" ] && [ ! -f "$BACKUP_DIR/nfsu2.cfg" ]; then
            cp -f "$CFG_FILE" "$BACKUP_DIR/nfsu2.cfg"
        fi
        for bin_name in "nfsu2.aarch64.v10" "nfsu2.aarch64.v12" "nfsu2.aarch64"; do
            if [ -f "$NFSU2_DIR/$bin_name" ] && [ ! -f "$BACKUP_DIR/$bin_name" ]; then
                cp -f "$NFSU2_DIR/$bin_name" "$BACKUP_DIR/$bin_name"
            fi
        done
        if [ -f "$GAMEDATA/LANGUAGES/LanguageTextures.bin" ] && [ ! -f "$BACKUP_DIR/LanguageTextures.bin" ]; then
            cp -f "$GAMEDATA/LANGUAGES/LanguageTextures.bin" "$BACKUP_DIR/LanguageTextures.bin"
        fi
        sleep 0.4

        echo "30" ; echo "XXX" ; echo "Installing Thailand.bin and Thai font textures..." ; echo "XXX"
        mkdir -p "$GAMEDATA/LANGUAGES"
        if [ -n "$THAI_ASSETS_DIR" ]; then
            if [ -f "$THAI_ASSETS_DIR/LANGUAGES/Thailand.bin" ]; then
                cp -f "$THAI_ASSETS_DIR/LANGUAGES/Thailand.bin" "$GAMEDATA/LANGUAGES/Thailand.bin"
                cp -f "$THAI_ASSETS_DIR/LANGUAGES/Thailand.bin" "$GAMEDATA/LANGUAGES/thailand.bin" 2>/dev/null || true
            fi
            if [ -f "$THAI_ASSETS_DIR/LANGUAGES/LanguageTextures.bin" ]; then
                cp -f "$THAI_ASSETS_DIR/LANGUAGES/LanguageTextures.bin" "$GAMEDATA/LANGUAGES/LanguageTextures.bin"
            fi
        fi
        sleep 0.4

        echo "55" ; echo "XXX" ; echo "Patching SPEED2.EXE for Thai font streaming..." ; echo "XXX"
        PREPATCHED_EXE=""
        if [ -n "$THAI_ASSETS_DIR" ] && [ -f "$THAI_ASSETS_DIR/SPEED2.EXE" ]; then
            fsize=$(stat -c%s "$THAI_ASSETS_DIR/SPEED2.EXE" 2>/dev/null || wc -c < "$THAI_ASSETS_DIR/SPEED2.EXE" | tr -d ' ')
            if [ "$fsize" -eq 4788224 ]; then
                PREPATCHED_EXE="$THAI_ASSETS_DIR/SPEED2.EXE"
            fi
        fi

        if [ -n "$PREPATCHED_EXE" ]; then
            cp -f "$PREPATCHED_EXE" "$GAMEDATA/SPEED2.EXE"
            cp -f "$PREPATCHED_EXE" "$GAMEDATA/speed2.exe" 2>/dev/null || true
        elif [ -f "$EXE" ]; then
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
        f.seek(off); f.write(val)
' "$EXE" 2>/dev/null || true
            cp -f "$EXE" "$GAMEDATA/SPEED2.EXE"
            cp -f "$EXE" "$GAMEDATA/speed2.exe" 2>/dev/null || true
        fi
        sleep 0.4

        echo "75" ; echo "XXX" ; echo "Patching ARM64 binary (Subtitles, Video NEON & GPS)..." ; echo "XXX"
        for bin_file in "$NFSU2_DIR/nfsu2.aarch64.v10" "$NFSU2_DIR/nfsu2.aarch64.v12" "$NFSU2_DIR/nfsu2.aarch64"; do
            [ -f "$bin_file" ] || continue
            python3 - "$bin_file" << 'PYEOF' 2>/dev/null || true
import re, struct, sys

path = sys.argv[1]
with open(path, "rb") as f:
    raw = bytearray(f.read())

modified = False

# 1. Subtitle patches (v10: 87,349,296 bytes)
if len(raw) == 87349296:
    sub_patches = [
        (0x1FD660, b"\x41\xd0\x3b\xd5\x20\xa0\x40\x39\x00\x00\x00\x32\x20\xa0\x00\x39\x20\x38\x40\xb9\x00\x10\x00\x11\x20\x38\x00\xb9\xc0\x03\x5f\xd6"),
        (0x3B62EF0, b"\x58\x00\x00\x14"),
    ]
    for off, val in sub_patches:
        if raw[off : off + len(val)] != val:
            raw[off : off + len(val)] = val
            modified = True

# 2. Video Render Performance patches (NEON + Async Lock + Persistent Upload)
def p32(words):
    return struct.pack(f"<{len(words)}I", *words)

syms = {}
if len(raw) >= 64 and raw[:4] == b"\x7fELF" and raw[4] == 2:
    try:
        e_shoff = struct.unpack("<Q", raw[40:48])[0]
        e_shentsize, e_shnum, e_shstrndx = struct.unpack("<HHH", raw[58:64])
        secs = []
        for i in range(e_shnum):
            o = e_shoff + i * e_shentsize
            h = struct.unpack("<IIQQQQIIQQ", raw[o : o + 64])
            secs.append((h[0], h[1], h[4], h[5], h[6], h[9]))
        shstr = raw[secs[e_shstrndx][2] : secs[e_shstrndx][2] + secs[e_shstrndx][3]]
        sym_s = str_s = None
        for n_i, typ, off, sz, lnk, esz in secs:
            nm = shstr[n_i : shstr.find(b"\x00", n_i)].decode("ascii", "ignore")
            if typ == 2 and nm == ".symtab":
                sym_s, str_s = (off, sz, esz or 24), secs[lnk]
                break
        if sym_s and str_s:
            sdata = raw[sym_s[0] : sym_s[0] + sym_s[1]]
            tdata = raw[str_s[2] : str_s[2] + str_s[3]]
            for i in range(0, len(sdata), sym_s[2]):
                st_n, _, _, _, st_v, _ = struct.unpack("<IBBHQQ", sdata[i : i + 24])
                if st_n:
                    nm = tdata[st_n : tdata.find(b"\x00", st_n)].decode("ascii", "ignore")
                    syms[nm] = st_v
    except Exception:
        pass

def sym_off(name, delta=0, fb=None):
    va = syms[name] + delta if name in syms else fb
    if va is not None and 0x400000 <= va < len(raw) + 0x400000:
        return va - 0x400000
    return None

p5a_off = next((sym_off(s) for s in ("sub_006FFAA7", "sub_006FFD4A") if s in syms), None)
if p5a_off is None:
    if len(raw) == 87349296: p5a_off = 0x47C0440 - 0x400000
    elif len(raw) == 88589712: p5a_off = 0x48C6C40 - 0x400000

p5b_off = next((sym_off(s) for s in ("sub_0070CCE8", "sub_0070CF98") if s in syms), None)
if p5b_off is None:
    if len(raw) == 87349296: p5b_off = 0x4D16B90 - 0x400000
    elif len(raw) == 88589712: p5b_off = 0x4959D00 - 0x400000

p5a_orig_v10 = p32([
    0xA9B87BFD, 0xD53BD041, 0x910003FD, 0xA90153F3, 0x91400034, 0x9100A294, 0xA9025BF5, 0x5285478B,
    0x72A0020B, 0xA90363F7, 0xD2C00218, 0xA9046BF9, 0x52856797, 0x72A00217, 0xA90573FB, 0xF001957A,
    0x9112235A, 0xF9003FE1, 0xB9401281, 0xB9400E88, 0x51001027, 0x51002024, 0x51003022, 0x29428E85,
    0x51004029, 0xB9401E86, 0x7940928C, 0x2948368E, 0xB8274B08, 0xB8244B05, 0xB8224B03, 0x11001025,
    0x11003023, 0x11004022, 0x11002024, 0x11005021, 0xB8294B06, 0x9001959C, 0x913BE39C, 0xB8634B07,
    0xB8624B08, 0x5285279B, 0x72A0021B,
])
p5a_orig_v12 = p32([
    0xA9B87BFD, 0xD53BD041, 0x910003FD, 0xA90153F3, 0x91400034, 0x9100A294, 0xA9025BF5, 0x5285478B,
    0x72A0020B, 0xA90363F7, 0xD2C00218, 0xA9046BF9, 0x52856797, 0x72A00217, 0xA90573FB, 0x900196DA,
    0x9112635A, 0xF9003FE1, 0xB9401281, 0xB9400E88, 0x51001027, 0x51002024, 0x51003022, 0x29428E85,
    0x51004029, 0xB9401E86, 0x7940928C, 0x2948368E, 0xB8274B08, 0xB8244B05, 0xB8224B03, 0x11001025,
    0x11003023, 0x11004022, 0x11002024, 0x11005021, 0xB8294B06, 0xB00196DC, 0x913C239C, 0xB8634B07,
    0xB8624B08, 0x5285279B, 0x72A0021B,
])
p5a_prev = p32([
    0xD53BD041, 0xB9403822, 0x11001040, 0xB9003820, 0xB900283F, 0xD2C00208, 0x8B224102, 0x29409043,
    0x29419845, 0xB9401447, 0x6B0600EB, 0x540003E9, 0x53037D6B, 0x0B0B0469, 0x0B0B008A, 0x2905A829,
    0x8B234103, 0x8B244104, 0x8B254105, 0x8B264106, 0xD2893C0C, 0xF2A0102C, 0x8B0C010C, 0x9120018D,
    0x912001AE, 0x3840148F, 0x384014B0, 0xFC6F59A2, 0xFC7059C3, 0x4E630C42, 0x3940006F, 0x39400470,
    0x91000863, 0xFC6F5980, 0xFC705981, 0x4E620C00, 0x4E620C21, 0x6E081C20, 0x2E212800, 0xFC0084C0,
    0x7100056B, 0x54FFFE01, 0xD65F03C0,
])
p5a_new = p32([
    0xD53BD041, 0xB9403822, 0x11001040, 0xB9003820, 0xB900283F, 0xD2C00208, 0x8B224102, 0x29409043,
    0x29419845, 0xB9401447, 0x6B0600EB, 0x540003E9, 0x53037D6B, 0x0B0B0469, 0x0B0B008A, 0x2905A829,
    0x8B234103, 0x8B244104, 0x8B254105, 0x8B264106, 0xD2893C0C, 0xF2A0102C, 0x8B0C010C, 0x9120018D,
    0x912001AE, 0x3840148F, 0x384014B0, 0xFC6F59A2, 0xFC7059C3, 0x4E630C42, 0x3940006F, 0x39400470,
    0x91000863, 0xFC6F5980, 0xFC705981, 0x4E620C00, 0x4E620C21, 0x6E180420, 0x2E212800, 0xFC0084C0,
    0x7100056B, 0x54FFFE01, 0xD65F03C0,
])

video_sites = [
    (sym_off("_ZN2rt16textureLockAsyncEjPKjPjS2_", 0x3E0, 0x49B860), [p32([0x366FEDF9])], p32([0xD503201F])),
    (sym_off("_ZN2rt4execERKNS_3CmdE", 0x4D0, 0x4A3640), [p32([0x52800004])], p32([0x52840004])),
    (sym_off("_ZN2rt4execERKNS_3CmdE", 0x58C, 0x4A36FC), [p32([0x52800004])], p32([0x52840004])),
    (sym_off("_ZN9d3d9_gles21IDirect3DSurface9GLES10UnlockRectEv", 0x310, 0x4CE8D0),
     [p32([0xF9403260, 0xF9400AA1, 0xF900327F, 0xA900FEBF, 0xB4000060, 0xCB000021])],
     p32([0x39410E60, 0x350000C0, 0xF9403260, 0xF900327F, 0xA900FEBF, 0xB4000040])),
    (sym_off("_ZN9d3d9_gles17convertRowToRGBA8E10_D3DFORMATPKhPhj", 0x2BC, 0x4C869C),
     [p32([0x34FFEFC3, 0x8B234823, 0xD503201F, 0x39400820, 0x39000080, 0x91001021, 0x385FD020, 0x39000480,
           0x91001084, 0x385FC020, 0x381FE080, 0x385FF020, 0x381FF080, 0xEB01007F, 0x54FFFEA1, 0xD65F03C0]),
      p32([0x71004063, 0x540000E3, 0x4CDF0420, 0x4EA01C04, 0x4EA21C40, 0x4EA41C82, 0x4C9F0480, 0x17FFFFF9,
           0x31004063, 0x54FFEEA0, 0xB8404425, 0x5AC008A6, 0x138660A5, 0xB8004485, 0x71000463, 0x17FFFFFA])],
     p32([0x71004063, 0x540000E3, 0x4CDF0020, 0x4EA01C04, 0x4EA21C40, 0x4EA41C82, 0x4C9F0080, 0x17FFFFF9,
          0x31004063, 0x54FFEEA0, 0xB8404425, 0x5AC008A6, 0x138660A5, 0xB8004485, 0x71000463, 0x17FFFFFA])),
    (p5a_off, [p5a_orig_v10, p5a_orig_v12, p5a_prev], p5a_new),
    (p5b_off,
     [p32([0xA9B87BFD, 0x52BBD5A6, 0x910003FD, 0xA90153F3, 0xD53BD054, 0x91400293, 0x9100A273,
           0xA9025BF5, 0xD28000C5, 0xA90363F7, 0xD2C00217, 0xA9046BF9, 0xD2800024])],
     p32([0xD53BD041, 0xB9403822, 0x11001040, 0xB9003820, 0xB900283F, 0xD2C00208, 0x8B224102,
          0x29409043, 0xB9400C45, 0xB823491F, 0xB824491F, 0xB825491F, 0xD65F03C0])),
]

for f_off, orig_list, new_b in video_sites:
    if f_off is not None and f_off + len(new_b) <= len(raw):
        cur = bytes(raw[f_off : f_off + len(new_b)])
        if cur != new_b and any(cur == ob for ob in orig_list):
            raw[f_off : f_off + len(new_b)] = new_b
            modified = True

# 3. Joypad GPS & Space patches (Menu Mode: Button X -> DIK_C, Button Y -> DIK_SPACE)
for orig_b, patch_b, expected_cnt in [
    (bytes.fromhex("e0 87 0a 39"), bytes.fromhex("e0 5b 0a 39"), 1),
    (bytes.fromhex("e1 87 0a 39"), bytes.fromhex("e1 5b 0a 39"), 1),
    (bytes.fromhex("42 a8 40 39 e2 07 01 39"), bytes.fromhex("42 a8 40 39 e2 db 00 39"), 2),
]:
    if raw.count(orig_b) == expected_cnt:
        raw = bytearray(raw.replace(orig_b, patch_b))
        modified = True

re_y = re.compile(b"(\x43\xac\x40\x39.{4})\xe3\x27\x00\x39", re.DOTALL)
y_matches = list(re_y.finditer(raw))
if len(y_matches) == 1:
    m = y_matches[0]
    raw[m.end() - 4 : m.end()] = bytes.fromhex("e3 07 01 39")
    modified = True

if modified:
    with open(path, "wb") as f:
        f.write(raw)
PYEOF
        done

        # Configure nfsu2.cfg
        if [ -f "$CFG_FILE" ]; then
            if grep -q "^NFSU2_LANG=" "$CFG_FILE"; then
                sed -i 's/^NFSU2_LANG=.*/NFSU2_LANG=Thai/' "$CFG_FILE" 2>/dev/null || true
            else
                echo "NFSU2_LANG=Thai" >> "$CFG_FILE"
            fi
        else
            cat << 'EOF' > "$CFG_FILE"
NFSU2_GRAPHICS=performance
NFSU2_FPS=30
NFSU2_LANG=Thai
NFSU2_DRAW_DIST=200
NFSU2_REGISTRY_EXTRA=""
EOF
        fi

        # Apply Fast Boot & optional Attract Mode patch if requested
        if [ "$ENABLE_FASTBOOT" -eq 1 ]; then
            echo "90" ; echo "XXX" ; echo "Enabling Fast Boot (Skipping intro movies)..." ; echo "XXX"
            for f in "${INTRO_FILES[@]}"; do
                target_f="$MOVIES_DIR/$f"
                backup_f="$MOVIES_DIR/_$f"
                if [ -f "$target_f" ]; then
                    file_sz=$(stat -c%s "$target_f" 2>/dev/null || wc -c < "$target_f" | tr -d ' ')
                    if [ "$file_sz" -le 2500 ]; then
                        rm -f "$target_f"
                    else
                        if [ ! -f "$backup_f" ]; then
                            mv -f "$target_f" "$backup_f"
                        else
                            rm -f "$target_f"
                        fi
                    fi
                fi
            done
            if [ "$ENABLE_ATTRACT_PATCH" -eq 1 ]; then
                apply_attract_patch 1
            fi
            sleep 0.3
        fi

        touch "$NFSU2_DIR/.nfsu2_thai"
        sync
        echo "100" ; echo "XXX" ; echo "Installation completed successfully!" ; echo "XXX"
        sleep 0.5
    ) | dialog --backtitle "NFSU2 Thai Manager v1.1" --title "$GAUGE_TITLE" \
        --gauge "\nApplying Thai translation, HD fonts & subtitles..." 8 54 0 \
        > "$DIALOG_OUT" 2>/dev/null

    dialog --backtitle "NFSU2 Thai Manager v1.1" --title "$SUCCESS_TITLE" \
        --msgbox "\n  $SUCCESS_HEADER\n\n  * Engine    : Subtitles, Video NEON & GPS\n  * Language  : Thai (Subtitles active)\n  * Fast Boot : $FASTBOOT_DESC\n\n  Press A or Enter to exit." \
        12 58 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null

    exit 0
}

do_uninstall_thai() {
    ask_yesno_menu "Confirm Uninstallation" \
        "\nAre you sure you want to restore original game files?\n\n* Restores original SPEED2.EXE and binaries from backup\n* Resets in-game language to English\n* Preserves player saves safely" \
        15 62 "no" \
        "Yes - Uninstall and restore original files" \
        "No  - Back to menu"

    if [ $? -ne 0 ]; then
        return
    fi

    (
        echo "15" ; echo "XXX" ; echo "Checking backup files in .backup_thai/..." ; echo "XXX" ; sleep 0.3
        EXE_RESTORED=0
        if [ -d "$BACKUP_DIR" ]; then
            if [ -f "$BACKUP_DIR/SPEED2.EXE" ]; then
                cp -f "$BACKUP_DIR/SPEED2.EXE" "$GAMEDATA/SPEED2.EXE"
                cp -f "$BACKUP_DIR/SPEED2.EXE" "$GAMEDATA/speed2.exe" 2>/dev/null || true
                EXE_RESTORED=1
            fi
            echo "40" ; echo "XXX" ; echo "Restoring original ARM64 engine binaries..." ; echo "XXX" ; sleep 0.3
            for bin_name in "nfsu2.aarch64.v10" "nfsu2.aarch64.v12" "nfsu2.aarch64"; do
                if [ -f "$BACKUP_DIR/$bin_name" ]; then
                    cp -f "$BACKUP_DIR/$bin_name" "$NFSU2_DIR/$bin_name"
                fi
            done
            if [ -f "$BACKUP_DIR/LanguageTextures.bin" ]; then
                cp -f "$BACKUP_DIR/LanguageTextures.bin" "$GAMEDATA/LANGUAGES/LanguageTextures.bin"
            fi
            if [ -f "$BACKUP_DIR/nfsu2.cfg" ]; then
                cp -f "$BACKUP_DIR/nfsu2.cfg" "$CFG_FILE"
            fi
        fi

        # If backup was missing, restore SPEED2.EXE via exact in-place unpatch
        if [ "$EXE_RESTORED" -eq 0 ]; then
            echo "50" ; echo "XXX" ; echo "Unpatching SPEED2.EXE in-place..." ; echo "XXX" ; sleep 0.3
            for exe_target in "$GAMEDATA/SPEED2.EXE" "$GAMEDATA/speed2.exe"; do
                if [ -f "$exe_target" ] && [ "$(stat -c%s "$exe_target" 2>/dev/null || wc -c < "$exe_target" | tr -d ' ')" -eq 4788224 ]; then
                    python3 -c '
import sys
target = sys.argv[1]
unpatches = [
    (0x10CEF0, b"\xe8\xcb\x37\x06\x00\x83\xf8\x05"),
    (0x153703, b"\xe8\xb8\xcf\x01\x00\x83\xf8\x04\x74\x0a\xe8\xae\xcf\x01\x00\x83\xf8\x0c\x75\x0e"),
    (0x1B7678, b"K"),
    (0x39A6F2, b"JAPANESE"),
    (0x39A700, b"JAPANESE"),
    (0x3F6F40, b"\x5f\x2f\x19\x15"),
    (0x3F6F48, b"\xc1\xf1\x3b\x74"),
    (0x3F70C0, b"\x0a\x00\x00\x00"),
    (0x3F7108, b"\x0a\x00\x00\x00"),
    (0x3FCA00, b"\xff\xff\xff\xff"),
]
with open(target, "r+b") as f:
    for off, val in unpatches:
        f.seek(off); f.write(val)
' "$exe_target" 2>/dev/null || true
                fi
            done
        fi

        echo "70" ; echo "XXX" ; echo "Removing Thailand.bin localization file..." ; echo "XXX" ; sleep 0.3
        rm -f "$GAMEDATA/LANGUAGES/Thailand.bin" "$GAMEDATA/LANGUAGES/thailand.bin" 2>/dev/null || true
        rm -f "$NFSU2_DIR/.nfsu2_thai" 2>/dev/null || true

        echo "80" ; echo "XXX" ; echo "Restoring intro movies if skipped..." ; echo "XXX"
        for f in "${INTRO_FILES[@]}"; do
            target_f="$MOVIES_DIR/$f"
            backup_f="$MOVIES_DIR/_$f"
            if [ -f "$backup_f" ]; then
                rm -f "$target_f" 2>/dev/null || true
                mv -f "$backup_f" "$target_f"
            fi
        done

        echo "90" ; echo "XXX" ; echo "Resetting language to English..." ; echo "XXX"
        if [ -f "$CFG_FILE" ]; then
            sed -i 's/^NFSU2_LANG=.*/NFSU2_LANG=English/' "$CFG_FILE" 2>/dev/null || true
        fi
        sync
        echo "100" ; echo "XXX" ; echo "Uninstallation completed!" ; echo "XXX" ; sleep 0.4
    ) | dialog --backtitle "NFSU2 Thai Manager v1.1" --title "Restoring Original Game" \
        --gauge "\nRestoring untouched files from backup..." 8 54 0 \
        > "$DIALOG_OUT" 2>/dev/null

    dialog --backtitle "NFSU2 Thai Manager v1.1" --title "Restore Complete" \
        --msgbox "\n  [OK] Original Game Files Restored Successfully!\n\n  * SPEED2.EXE and binaries restored from backup\n  * In-game language reset to English\n  * Player save games are 100% safe\n\n  Press A or Enter to exit." \
        12 58 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null

    exit 0
}

do_toggle_language() {
    target_l="$1"
    if [ -f "$CFG_FILE" ]; then
        if grep -q "^NFSU2_LANG=" "$CFG_FILE"; then
            sed -i "s/^NFSU2_LANG=.*/NFSU2_LANG=$target_l/" "$CFG_FILE" 2>/dev/null || true
        else
            echo "NFSU2_LANG=$target_l" >> "$CFG_FILE"
        fi
    else
        cat << EOF > "$CFG_FILE"
NFSU2_GRAPHICS=performance
NFSU2_FPS=30
NFSU2_LANG=$target_l
NFSU2_DRAW_DIST=200
NFSU2_REGISTRY_EXTRA=""
EOF
    fi
    sync

    if [ "$target_l" = "Thai" ]; then
        msg="\n  [OK] Language switched to: THAI\n\n  * Subtitles and game text will display in Thai.\n\n  Press A or Enter to continue."
    else
        msg="\n  [OK] Language switched to: ENGLISH\n\n  * Game text will display in original English.\n\n  Press A or Enter to continue."
    fi

    dialog --backtitle "NFSU2 Thai Manager v1.1" --title "Language Switched" \
        --msgbox "$msg" 10 56 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

do_select_graphics() {
    local GFX_TMP="/tmp/nfsu2_gfx_choice.$$"
    dialog \
        --backtitle "NFSU2 Thai Manager v1.1 | Graphics: $CURRENT_GRAPHICS" \
        --title "Select Graphics Profile" \
        --ok-label "Apply" \
        --cancel-label "Back" \
        --default-item "$CURRENT_GRAPHICS" \
        --menu "\nCurrent Profile: $CURRENT_GRAPHICS\nChoose target performance vs visual quality:" \
        16 64 4 \
        "ultra_performance" "Max 30 FPS (0.75x scale, 120m, no shadows/FX)" \
        "performance"       "Fast 30 FPS (1.0x scale, 200m, low FX)" \
        "balanced"          "Balanced (1.0x scale, 200m, medium FX)" \
        "quality"           "High Quality (1.0x scale, 200m, high FX)" \
        2> "$GFX_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"
    local rc=$?
    local new_gfx
    new_gfx=$(cat "$GFX_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$GFX_TMP"

    if [ $rc -ne 0 ] || [ -z "$new_gfx" ]; then
        return
    fi

    local new_dist="200"
    local new_scale=""
    if [ "$new_gfx" = "ultra_performance" ]; then
        new_dist="120"
        new_scale="0.75"
    fi

    if [ -f "$CFG_FILE" ]; then
        if grep -q "^NFSU2_GRAPHICS=" "$CFG_FILE"; then
            sed -i "s|^NFSU2_GRAPHICS=.*|NFSU2_GRAPHICS=$new_gfx|" "$CFG_FILE"
        else
            echo "NFSU2_GRAPHICS=$new_gfx" >> "$CFG_FILE"
        fi
        if grep -q "^NFSU2_DRAW_DIST=" "$CFG_FILE"; then
            sed -i "s|^NFSU2_DRAW_DIST=.*|NFSU2_DRAW_DIST=$new_dist|" "$CFG_FILE"
        else
            echo "NFSU2_DRAW_DIST=$new_dist" >> "$CFG_FILE"
        fi
        if [ -n "$new_scale" ]; then
            if grep -q "^NFSU2_RENDER_SCALE=" "$CFG_FILE"; then
                sed -i "s|^NFSU2_RENDER_SCALE=.*|NFSU2_RENDER_SCALE=$new_scale|" "$CFG_FILE"
            else
                echo "NFSU2_RENDER_SCALE=$new_scale" >> "$CFG_FILE"
            fi
        else
            sed -i "/^NFSU2_RENDER_SCALE=/d" "$CFG_FILE"
        fi
    else
        cat << EOF > "$CFG_FILE"
NFSU2_GRAPHICS=$new_gfx
NFSU2_FPS=30
NFSU2_LANG=$CURRENT_LANG
NFSU2_DRAW_DIST=$new_dist
NFSU2_REGISTRY_EXTRA=""
EOF
        [ -n "$new_scale" ] && echo "NFSU2_RENDER_SCALE=$new_scale" >> "$CFG_FILE"
    fi
    sync

    local scale_label="1.0x (640x480)"
    [ -n "$new_scale" ] && scale_label="${new_scale}x (480x360)"
    dialog --backtitle "NFSU2 Thai Manager v1.1" --title "Graphics Profile Updated" \
        --msgbox "\n  [OK] Graphics Profile set to: $new_gfx\n\n  * Draw Distance : ${new_dist}m\n  * Render Scale  : $scale_label\n\n  Press A or Enter to continue." \
        11 58 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

# Return 0 if Title Attract Mode is currently patched in nfsu2.aarch64*, else 1
is_attract_patched() {
    python3 - "$NFSU2_DIR" << 'PYEOF' 2>/dev/null
import os, struct, sys

nfsu2_dir = sys.argv[1]
prefix = bytes.fromhex("a51c0853bf000a6a")
suffix = bytes.fromhex("0a200051c31000110102c0d20430005100400051234863b87402409194a20091904e9d52100fa07230482ab8")
patch_pat = prefix + struct.pack("<I", 0x14000059) + suffix
known_offs = (0x3C6E768, 0x3D57958)

for name in ("nfsu2.aarch64", "nfsu2.aarch64.v10", "nfsu2.aarch64.v12"):
    p = os.path.join(nfsu2_dir, name)
    if not os.path.isfile(p):
        continue
    with open(p, "rb") as f:
        for off in known_offs:
            f.seek(off)
            if f.read(len(patch_pat)) == patch_pat:
                sys.exit(0)
        f.seek(0)
        if patch_pat in f.read():
            sys.exit(0)
sys.exit(1)
PYEOF
}

# Patch (1) or revert (0) Title Screen Attract Mode branch in nfsu2.aarch64* (<0.1s via seek)
apply_attract_patch() {
    local enable="$1"
    python3 - "$NFSU2_DIR" "$enable" << 'PYEOF' 2>/dev/null || true
import os, struct, sys

nfsu2_dir, enable = sys.argv[1], sys.argv[2] == "1"
prefix = bytes.fromhex("a51c0853bf000a6a")
suffix = bytes.fromhex("0a200051c31000110102c0d20430005100400051234863b87402409194a20091904e9d52100fa07230482ab8")
orig_b = struct.pack("<I", 0x54000B21)   # b.ne +0x164
patch_b = struct.pack("<I", 0x14000059)  # b    +0x164
orig_pat = prefix + orig_b + suffix
patch_pat = prefix + patch_b + suffix
want_b = patch_b if enable else orig_b
known_offs = (0x3C6E768, 0x3D57958)

for name in ("nfsu2.aarch64", "nfsu2.aarch64.v10", "nfsu2.aarch64.v12"):
    p = os.path.join(nfsu2_dir, name)
    if not os.path.isfile(p):
        continue
    with open(p, "r+b") as f:
        branch_off = -1
        for off in known_offs:
            f.seek(off)
            chunk = f.read(len(orig_pat))
            if chunk in (orig_pat, patch_pat):
                branch_off = off + len(prefix)
                break
        if branch_off < 0:
            f.seek(0)
            data = f.read()
            idx = data.find(orig_pat)
            if idx < 0:
                idx = data.find(patch_pat)
            if idx >= 0:
                branch_off = idx + len(prefix)
        if branch_off >= 0:
            f.seek(branch_off)
            if f.read(4) != want_b:
                f.seek(branch_off)
                f.write(want_b)
PYEOF
}

do_skip_intro() {
    PATCH_ATTRACT=0
    ask_yesno_menu "Attract Mode Option" \
        "\nAlso patch Title Attract Mode when skipping intro?" \
        11 62 "no" \
        "Yes - Keep Title music playing past 30s" \
        "No  - Default (Original behavior)"
    RC_ATTRACT=$?

    if [ "$RC_ATTRACT" -ne 0 ] && [ "$RC_ATTRACT" -ne 1 ]; then
        return
    fi
    [ "$RC_ATTRACT" -eq 0 ] && PATCH_ATTRACT=1

    for f in "${INTRO_FILES[@]}"; do
        target_f="$MOVIES_DIR/$f"
        backup_f="$MOVIES_DIR/_$f"
        if [ -f "$target_f" ]; then
            file_sz=$(stat -c%s "$target_f" 2>/dev/null || wc -c < "$target_f" | tr -d ' ')
            if [ "$file_sz" -le 2500 ]; then
                rm -f "$target_f"
            else
                if [ ! -f "$backup_f" ]; then
                    mv -f "$target_f" "$backup_f"
                else
                    rm -f "$target_f"
                fi
            fi
        fi
    done
    if [ "$PATCH_ATTRACT" -eq 1 ]; then
        apply_attract_patch 1
        ATTRACT_MSG="Title Attract Mode disabled (music plays without reset)"
    else
        ATTRACT_MSG="Title Attract Mode left unchanged (default)"
    fi
    sync

    dialog --backtitle "NFSU2 Thai Manager v1.1" --title "Fast Boot Enabled" \
        --msgbox "\n  [OK] Fast Boot ENABLED - Instant Title Screen!\n\n  * Intro movies bypassed directly without video playback\n  * $ATTRACT_MSG\n  * Game launches straight to Start Screen in ~1s\n\n  Press A or Enter to continue." \
        12 66 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

do_restore_intro() {
    REVERT_ATTRACT=0
    if is_attract_patched; then
        ask_yesno_menu "Attract Mode Option" \
            "\nTitle Attract Mode patch is currently active.\nRevert Attract Mode back to original behavior?" \
            12 62 "no" \
            "Yes - Revert Attract Mode to original" \
            "No  - Default (Keep current binary)"
        RC_ATTRACT=$?

        if [ "$RC_ATTRACT" -ne 0 ] && [ "$RC_ATTRACT" -ne 1 ]; then
            return
        fi
        [ "$RC_ATTRACT" -eq 0 ] && REVERT_ATTRACT=1
    fi

    rc=0
    for f in "${INTRO_FILES[@]}"; do
        target_f="$MOVIES_DIR/$f"
        backup_f="$MOVIES_DIR/_$f"
        if [ -f "$backup_f" ]; then
            rm -f "$target_f" 2>/dev/null || true
            mv -f "$backup_f" "$target_f"
            rc=$((rc + 1))
        fi
    done
    if [ $rc -gt 0 ] && [ "$REVERT_ATTRACT" -eq 1 ]; then
        apply_attract_patch 0
        ATTRACT_MSG="Title Attract Mode reverted to original behavior"
    elif [ $rc -gt 0 ]; then
        ATTRACT_MSG="Title Attract Mode left unchanged"
    fi
    sync

    if [ $rc -gt 0 ]; then
        dialog --backtitle "NFSU2 Thai Manager v1.1" --title "Intro Movies Restored" \
            --msgbox "\n  [OK] Intro Movies RESTORED Successfully!\n\n  * EA/THX logos, Opening FMV, and PSA will play normally\n  * $ATTRACT_MSG\n\n  Press A or Enter to continue." \
            11 66 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
    else
        dialog --backtitle "NFSU2 Thai Manager v1.1" --title "Notice" \
            --msgbox "\n  [i] No video backup files found to restore.\n\n  Fast Boot remains permanently active.\n\n  Press A or Enter to continue." \
            10 60 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
    fi
}

# ------------------------------------------------------------------------------
# 7. Main Interactive Loop
# ------------------------------------------------------------------------------
while true; do
    scan_status

    if [ "$THAI_INSTALLED" -eq 1 ]; then
        # When INSTALLED: Intro, Switch Language, Re-install, Uninstall
        STATUS_PATCH="Installed"

        if [ "$INTRO_STATUS" = "Skipped" ]; then
            TAG1="intro_restore"
            LABEL1="Restore Intro Movies"
        elif [ "$INTRO_STATUS" = "Deleted" ]; then
            TAG1="intro_notice"
            LABEL1="Intro Movies Deleted"
        else
            TAG1="intro_skip"
            LABEL1="Skip Intro Movies"
        fi

        if [ "$CURRENT_LANG" = "Thai" ]; then
            TAG2="lang_eng"
            LABEL2="Switch Language -> English"
        else
            TAG2="lang_thai"
            LABEL2="Switch Language -> Thai"
        fi

        TAG3="reinstall"
        LABEL3="Re-install NFSU2 Thai"
        TAG4="uninstall"
        LABEL4="Uninstall NFSU2 Thai"

        BACKTITLE="NFSU2 Thai | $NFSU2_DIR"
        MENU_PROMPT="\nCurrent Settings:\n  * NFSU2 Thai   : $STATUS_PATCH\n  * Language     : $CURRENT_LANG\n  * Intro Movies : $INTRO_STATUS\n\nChoose an action below, or press < Exit > to quit:"

        dialog \
            --backtitle "$BACKTITLE" \
            --title "NFSU2 Thai Manager v1.1" \
            --ok-label "Select" \
            --cancel-label "Exit" \
            --menu "$MENU_PROMPT" \
            18 62 4 \
            "1" "$LABEL1" \
            "2" "$LABEL2" \
            "3" "$LABEL3" \
            "4" "$LABEL4" \
            2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"
    else
        # When NOT INSTALLED: Show ONLY Install option
        TAG1="install"
        LABEL1="Install NFSU2 Thai"
        STATUS_PATCH="Not Installed"

        BACKTITLE="NFSU2 Thai | $NFSU2_DIR"
        MENU_PROMPT="\nCurrent Settings:\n  * NFSU2 Thai   : $STATUS_PATCH\n  * Language     : $CURRENT_LANG\n  * Intro Movies : $INTRO_STATUS\n\nChoose an action below, or press < Exit > to quit:"

        dialog \
            --backtitle "$BACKTITLE" \
            --title "NFSU2 Thai Manager v1.1" \
            --ok-label "Select" \
            --cancel-label "Exit" \
            --menu "$MENU_PROMPT" \
            15 60 1 \
            "1" "$LABEL1" \
            2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"
    fi

    RET=$?
    CHOICE=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"

    if [ $RET -ne 0 ] || [ -z "$CHOICE" ]; then
        break
    fi

    case "$CHOICE" in
        "1")
            if [ "$TAG1" = "install" ]; then
                do_install_thai 0
            elif [ "$TAG1" = "intro_skip" ]; then
                do_skip_intro
            elif [ "$TAG1" = "intro_restore" ]; then
                do_restore_intro
            else
                dialog --backtitle "NFSU2 Thai Manager v1.1" --title "Notice" \
                    --msgbox "\n  [i] Intro videos were permanently deleted from storage.\n\n  Fast Boot remains permanently active.\n\n  Press A or Enter to continue." \
                    10 62 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
            fi
            ;;
        "2")
            if [ "$TAG2" = "lang_thai" ]; then
                do_toggle_language "Thai"
            else
                do_toggle_language "English"
            fi
            ;;
        "3")
            do_install_thai 1
            ;;
        "4")
            do_uninstall_thai
            ;;
    esac
done

exit 0
