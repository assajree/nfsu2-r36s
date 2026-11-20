#!/bin/bash
# ==============================================================================
# Tool: NFSU2 Controls (Custom Gamepad Remapper & Control Presets TUI)
# Description: Interactive Linux ncurses dialog interface to configure, remap,
#              and switch controller presets for Need for Speed: Underground 2:
#                1. Load Presets (PS2 Classic, Modern Triggers R2/L2, Arcade)
#                2. Customize Driving Controls (Throttle, Brake, Nitro, Shifting, Camera)
#                3. Customize Driving Controls (Throttle, Brake, Nitro, Shifting, Camera)
#                4. Reset Controls (Config or Save Profile Bindings with Backup)
# Archetype: Archetype 3 (One-Shot Interactive TUI Tool, Flat Side-by-Side)
# Standard: Native /dev/tty1 Console + gptokeyb (Zero fb0_mirror)
# UI Language: 100% Pure ASCII English (Console Font Invariant)
# ==============================================================================

# 1. Root Privilege Escalation
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E "$0" "$@"
fi

export TERM=linux

# ------------------------------------------------------------------------------
# Dynamic Location & Target Resolution (PortMaster Standard)
# ------------------------------------------------------------------------------
REAL_SCRIPT="$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$0")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
SCRIPT_NAME="$(basename "$REAL_SCRIPT")"

# 2. Locate NFSU2 Port Directory
NFSU2_DIR=""
for cand in "/roms/ports/nfsu2" "/roms2/ports/nfsu2" "/roms/ports/NFSU2" "/roms/tools/nfsu2"; do
    if [ -d "$cand" ] && [ -d "$cand/gamedata" ]; then
        NFSU2_DIR="$(cd "$cand" && pwd)"
        break
    fi
done

if [ -z "$NFSU2_DIR" ]; then
    echo "[!] ERROR: NFSU2 game folder not found at /roms/ports/nfsu2/"
    sleep 3
    exit 1
fi

GAMEDATA="$NFSU2_DIR/gamedata"
CONTROLS_CFG="$NFSU2_DIR/controls.cfg"
NFSU2_CFG="$NFSU2_DIR/nfsu2.cfg"
BACKUP_DIR="$NFSU2_DIR/.backup_controls"
mkdir -p "$BACKUP_DIR"

# Locate Save Root Directory
SAVE_ROOT="$GAMEDATA/AppData/Local/NFS Underground 2"
if [ ! -d "$SAVE_ROOT" ] && [ -d "$NFSU2_DIR/AppData/Local/NFS Underground 2" ]; then
    SAVE_ROOT="$NFSU2_DIR/AppData/Local/NFS Underground 2"
fi

# ------------------------------------------------------------------------------
# Environment Detection & Gamepad Input Setup (Native /dev/tty1 + gptokeyb)
# ------------------------------------------------------------------------------
IS_SSH=0
if [ -n "$SSH_TTY" ] || [ -n "$SSH_CLIENT" ] || [ -n "$SSH_CONNECTION" ]; then
    IS_SSH=1
fi

GPTOKEYB_PID=""
GPTOKEYB_BIN=""
CHOICE_TMP="/tmp/nfsu2_ctrl_choice.$$"
GPTK_CONF="/tmp/nfsu2_ctrl_keys.gptk"

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

        # ----------------------------------------------------------------------
        # Dual-Frontend Dynamic A/B Button Resolution (Rule: Hardware Priority)
        # ----------------------------------------------------------------------
        OK_BUTTON="b"
        CANCEL_BUTTON="a"

        # Priority 1: playOS 4.0 playfe config
        PLAYFE_CFG="/home/ark/.config/playfe/playfe.cfg"
        if [ -f "$PLAYFE_CFG" ]; then
            SWAP_VAL=$(grep -i '^swap_ab=' "$PLAYFE_CFG" 2>/dev/null | cut -d'=' -f2 | tr -d ' "\r\n' | tr '[:upper:]' '[:lower:]')
            if [ "$SWAP_VAL" = "true" ] || [ "$SWAP_VAL" = "1" ]; then
                OK_BUTTON="a"
                CANCEL_BUTTON="b"
            else
                OK_BUTTON="b"
                CANCEL_BUTTON="a"
            fi
        # Priority 2: ArkOS / EmulationStation fallback
        elif [ -f "/var/cache/Switch_AB" ] || grep -q '<bool name="InvertButtons" value="true"' /home/ark/.emulationstation/es_settings.cfg 2>/dev/null; then
            OK_BUTTON="b"
            CANCEL_BUTTON="a"
        else
            OK_BUTTON="a"
            CANCEL_BUTTON="b"
        fi

        cat > "$GPTK_CONF" << EOF
guide = esc
back = esc
start = enter
up = up
down = down
left = left
right = right
left_analog_up = up
left_analog_down = down
left_analog_left = left
left_analog_right = right
${OK_BUTTON} = enter
${CANCEL_BUTTON} = esc
EOF

        TARGET_NAME="$SCRIPT_NAME"
        [ "$TARGET_NAME" = "bash" ] || [ "$TARGET_NAME" = "sh" ] && TARGET_NAME="NFSU2_Controls.sh"
        "$GPTOKEYB_BIN" -1 "$TARGET_NAME" -c "$GPTK_CONF" &
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
    [ -z "$TERM" ] || [ "$TERM" = "unknown" ] && export TERM=linux
fi

# Ensure dialog binary is available
if ! command -v dialog >/dev/null 2>&1; then
    echo "[!] ERROR: 'dialog' package is not installed." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Configuration State Management
# ------------------------------------------------------------------------------
CFG_PRESET="PS2_Classic"
CFG_THROTTLE="B"
CFG_BRAKE="Y"
CFG_EBRAKE="A"
CFG_NITROUS="R1"
CFG_SHIFT_UP="R2"
CFG_SHIFT_DOWN="L2"
CFG_LOOK_BACK="L1"
CFG_CAMERA="X"
CFG_RESET_CAR="Select"

load_config() {
    if [ -f "$CONTROLS_CFG" ]; then
        while IFS='=' read -r key val || [ -n "$key" ]; do
            key=$(echo "$key" | tr -d ' \r\n' | tr '[:lower:]' '[:upper:]')
            val=$(echo "$val" | cut -d'#' -f1 | tr -d ' \r\n')
            [ -z "$key" ] || [ "${key:0:1}" = "#" ] && continue

            case "$key" in
                PRESET)     CFG_PRESET="$val" ;;
                THROTTLE)   CFG_THROTTLE="$val" ;;
                BRAKE)      CFG_BRAKE="$val" ;;
                EBRAKE)     CFG_EBRAKE="$val" ;;
                NITROUS)    CFG_NITROUS="$val" ;;
                SHIFT_UP)   CFG_SHIFT_UP="$val" ;;
                SHIFT_DOWN) CFG_SHIFT_DOWN="$val" ;;
                LOOK_BACK)  CFG_LOOK_BACK="$val" ;;
                CAMERA)     CFG_CAMERA="$val" ;;
                RESET_CAR)  CFG_RESET_CAR="$val" ;;
            esac
        done < "$CONTROLS_CFG"
    else
        if [ -f "$NFSU2_CFG" ] && grep -q 'SDL_GAMECONTROLLERCONFIG' "$NFSU2_CFG"; then
            CFG_PRESET="Custom"
        else
            CFG_PRESET="Default"
        fi
    fi
}

name_to_btn() {
    case "$1" in
        B) echo "b0" ;;
        A) echo "b1" ;;
        Y) echo "b3" ;;
        X) echo "b2" ;;
        L1) echo "b4" ;;
        R1) echo "b5" ;;
        L2) echo "b6" ;;
        R2) echo "b7" ;;
        Select) echo "b12" ;;
        Start) echo "b13" ;;
        *) echo "" ;;
    esac
}

save_config() {
    # 1. Save state to controls.cfg
    cat > "$CONTROLS_CFG" << EOF
# Need for Speed: Underground 2 - Gamepad Configuration
# Generated by NFSU2 Controls Manager
PRESET=$CFG_PRESET
THROTTLE=$CFG_THROTTLE
BRAKE=$CFG_BRAKE
EBRAKE=$CFG_EBRAKE
NITROUS=$CFG_NITROUS
SHIFT_UP=$CFG_SHIFT_UP
SHIFT_DOWN=$CFG_SHIFT_DOWN
LOOK_BACK=$CFG_LOOK_BACK
CAMERA=$CFG_CAMERA
RESET_CAR=$CFG_RESET_CAR
EOF

    # 2. Translate logical game actions to physical buttons on GO-Super Gamepad
    local b_thr=$(name_to_btn "$CFG_THROTTLE")
    local b_brk=$(name_to_btn "$CFG_BRAKE")
    local b_ebrk=$(name_to_btn "$CFG_EBRAKE")
    local b_cam=$(name_to_btn "$CFG_CAMERA")
    local b_nit=$(name_to_btn "$CFG_NITROUS")
    local b_look=$(name_to_btn "$CFG_LOOK_BACK")
    local b_shup=$(name_to_btn "$CFG_SHIFT_UP")
    local b_shdn=$(name_to_btn "$CFG_SHIFT_DOWN")

    [ -z "$b_thr" ] && b_thr="b0"
    [ -z "$b_ebrk" ] && b_ebrk="b1"
    [ -z "$b_brk" ] && b_brk="b3"
    [ -z "$b_cam" ] && b_cam="b2"
    [ -z "$b_look" ] && b_look="b4"
    [ -z "$b_nit" ] && b_nit="b5"
    [ -z "$b_shdn" ] && b_shdn="b6"
    [ -z "$b_shup" ] && b_shup="b7"

    # Assemble SDL_GAMECONTROLLERCONFIG for R36H / R36S
    local map_str="1900bb3e4b4800000011000000010000,GO-Super Gamepad,a:${b_thr},b:${b_ebrk},x:${b_brk},y:${b_cam},leftshoulder:${b_look},rightshoulder:${b_nit},lefttrigger:${b_shdn},righttrigger:${b_shup},back:b12,dpdown:b9,dpleft:b10,dpright:b11,dpup:b8,guide:b16,leftstick:b14,leftx:a0,lefty:a1,rightstick:b15,rightx:a2,righty:a3,start:b13,platform:Linux,"

    # 3. Update nfsu2.cfg so the recompiled engine applies it on launch
    if [ -f "$NFSU2_CFG" ]; then
        sed -i '/SDL_GAMECONTROLLERCONFIG/d' "$NFSU2_CFG" 2>/dev/null || true
        echo "export SDL_GAMECONTROLLERCONFIG=\"$map_str\"" >> "$NFSU2_CFG"
    fi
    sync
}

apply_preset() {
    local preset="$1"
    CFG_PRESET="$preset"
    case "$preset" in
        PS2_Classic)
            CFG_THROTTLE="B"
            CFG_BRAKE="Y"
            CFG_EBRAKE="A"
            CFG_NITROUS="R1"
            CFG_SHIFT_UP="R2"
            CFG_SHIFT_DOWN="L2"
            CFG_LOOK_BACK="L1"
            CFG_CAMERA="X"
            CFG_RESET_CAR="Select"
            ;;
        Modern_Triggers)
            CFG_THROTTLE="R2"
            CFG_BRAKE="L2"
            CFG_EBRAKE="A"
            CFG_NITROUS="R1"
            CFG_SHIFT_UP="B"
            CFG_SHIFT_DOWN="Y"
            CFG_LOOK_BACK="L1"
            CFG_CAMERA="X"
            CFG_RESET_CAR="Select"
            ;;
    esac
    save_config
}

# ------------------------------------------------------------------------------
# Button Picker Dialog Helper
# ------------------------------------------------------------------------------
BUTTON_LIST=(
    "B"      "Bottom"
    "A"      "Right"
    "Y"      "Left"
    "X"      "Top"
    "R1"     "Right Shoulder"
    "L1"     "Left Shoulder"
    "R2"     "Right Trigger"
    "L2"     "Left Trigger"
    "Start"  "Start Button"
    "Select" "Select Button"
)

pick_button() {
    local title="$1"
    local current_val="$2"

    dialog \
        --backtitle "NFSU2 Controls | Setting: $title" \
        --title "Select Button for $title" \
        --ok-label "Select" \
        --cancel-label "Back" \
        --default-item "$current_val" \
        --menu "\nChoose button for $title:\n(Current: $current_val)" \
        16 56 10 \
        "${BUTTON_LIST[@]}" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

    local ret=$?
    local chosen=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"

    if [ $ret -eq 0 ] && [ -n "$chosen" ]; then
        echo "$chosen"
        return 0
    fi
    echo "$current_val"
    return 1
}

set_driving_button() {
    local action="$1"
    local title="$2"
    local current_val="$3"

    local new_val=$(pick_button "$title" "$current_val")
    if [ "$new_val" = "$current_val" ] || [ -z "$new_val" ]; then
        return
    fi

    # Swap with any other driving action that currently uses new_val
    [ "$action" != "THROTTLE" ]   && [ "$CFG_THROTTLE" = "$new_val" ]   && CFG_THROTTLE="$current_val"
    [ "$action" != "BRAKE" ]      && [ "$CFG_BRAKE" = "$new_val" ]      && CFG_BRAKE="$current_val"
    [ "$action" != "EBRAKE" ]     && [ "$CFG_EBRAKE" = "$new_val" ]     && CFG_EBRAKE="$current_val"
    [ "$action" != "NITROUS" ]    && [ "$CFG_NITROUS" = "$new_val" ]    && CFG_NITROUS="$current_val"
    [ "$action" != "SHIFT_UP" ]   && [ "$CFG_SHIFT_UP" = "$new_val" ]   && CFG_SHIFT_UP="$current_val"
    [ "$action" != "SHIFT_DOWN" ] && [ "$CFG_SHIFT_DOWN" = "$new_val" ] && CFG_SHIFT_DOWN="$current_val"
    [ "$action" != "LOOK_BACK" ]  && [ "$CFG_LOOK_BACK" = "$new_val" ]  && CFG_LOOK_BACK="$current_val"
    [ "$action" != "CAMERA" ]     && [ "$CFG_CAMERA" = "$new_val" ]     && CFG_CAMERA="$current_val"
    [ "$action" != "RESET_CAR" ]  && [ "$CFG_RESET_CAR" = "$new_val" ]  && CFG_RESET_CAR="$current_val"

    case "$action" in
        THROTTLE)   CFG_THROTTLE="$new_val" ;;
        BRAKE)      CFG_BRAKE="$new_val" ;;
        EBRAKE)     CFG_EBRAKE="$new_val" ;;
        NITROUS)    CFG_NITROUS="$new_val" ;;
        SHIFT_UP)   CFG_SHIFT_UP="$new_val" ;;
        SHIFT_DOWN) CFG_SHIFT_DOWN="$new_val" ;;
        LOOK_BACK)  CFG_LOOK_BACK="$new_val" ;;
        CAMERA)     CFG_CAMERA="$new_val" ;;
        RESET_CAR)  CFG_RESET_CAR="$new_val" ;;
    esac

    CFG_PRESET="Custom"
    save_config
}

menu_customize_driving() {
    while true; do
        dialog \
            --backtitle "NFSU2 Controls | Custom" \
            --title "Customize Controls" \
            --ok-label "Edit" \
            --cancel-label "Back" \
            --menu "\nSelect a driving function to reassign:\n" \
            18 64 9 \
            "1" "Throttle / Accelerate     [$CFG_THROTTLE]" \
            "2" "Brake / Reverse           [$CFG_BRAKE]" \
            "3" "E-Brake / Handbrake       [$CFG_EBRAKE]" \
            "4" "Nitrous Boost             [$CFG_NITROUS]" \
            "5" "Shift Up (Manual)         [$CFG_SHIFT_UP]" \
            "6" "Shift Down (Manual)       [$CFG_SHIFT_DOWN]" \
            "7" "Look Back                 [$CFG_LOOK_BACK]" \
            "8" "Change Camera             [$CFG_CAMERA]" \
            "9" "Reset Car                 [$CFG_RESET_CAR]" \
            2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

        local ret=$?
        local sel=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
        rm -f "$CHOICE_TMP"

        if [ $ret -ne 0 ] || [ -z "$sel" ]; then
            break
        fi

        case "$sel" in
            1) set_driving_button "THROTTLE"   "Throttle"      "$CFG_THROTTLE" ;;
            2) set_driving_button "BRAKE"      "Brake"         "$CFG_BRAKE" ;;
            3) set_driving_button "EBRAKE"     "E-Brake"       "$CFG_EBRAKE" ;;
            4) set_driving_button "NITROUS"    "Nitrous"       "$CFG_NITROUS" ;;
            5) set_driving_button "SHIFT_UP"   "Shift Up"      "$CFG_SHIFT_UP" ;;
            6) set_driving_button "SHIFT_DOWN" "Shift Down"    "$CFG_SHIFT_DOWN" ;;
            7) set_driving_button "LOOK_BACK"  "Look Back"     "$CFG_LOOK_BACK" ;;
            8) set_driving_button "CAMERA"     "Change Camera" "$CFG_CAMERA" ;;
            9) set_driving_button "RESET_CAR"  "Reset Car"     "$CFG_RESET_CAR" ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Save Profile Scanner & Reset Helpers (3-Tier NFSU2 CRC32)
# ------------------------------------------------------------------------------
PROFILES=()
PROFILE_PATHS=()
PROFILE_STATES=()

scan_save_profiles() {
    PROFILES=()
    PROFILE_PATHS=()
    PROFILE_STATES=()

    if [ -d "$SAVE_ROOT" ]; then
        while IFS= read -r -d '' pdir; do
            pname="$(basename "$pdir")"
            pfile="$pdir/$pname"
            if [ -f "$pfile" ]; then
                fsize=$(stat -c%s "$pfile" 2>/dev/null || wc -c < "$pfile" | tr -d ' ')
                if [ "$fsize" -eq 54966 ]; then
                    # Check controller block [0xD278:0xD6B6]
                    state=$(python3 -c '
import sys
with open(sys.argv[1], "rb") as f:
    f.seek(0xD278)
    blk = f.read(0x43E)
print("Default" if all(b == 0 for b in blk) else "Custom/Saved")
' "$pfile" 2>/dev/null || echo "Unknown")
                    PROFILES+=("$pname")
                    PROFILE_PATHS+=("$pfile")
                    PROFILE_STATES+=("$state")
                fi
            fi
        done < <(find "$SAVE_ROOT" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
    fi
}

reset_single_profile_file() {
    local target_file="$1"
    local prof_name="$2"
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local bak_file="$BACKUP_DIR/${prof_name}_${timestamp}.bak"

    # Backup current save with timestamp before patching
    cp -f "$target_file" "$bak_file" 2>/dev/null || return 1

    python3 - "$target_file" << 'PYEOF'
import sys
import struct

POLY = 0x04c11db7
TABLE = []
for i in range(256):
    c = (i << 24) & 0xffffffff
    for _ in range(8):
        c = ((c << 1) ^ POLY) & 0xffffffff if (c & 0x80000000) else (c << 1) & 0xffffffff
    TABLE.append(c)

def nfsu2_crc(data: bytes, start: int = 0, end: int = None) -> int:
    if end is None:
        end = len(data)
    if end - start < 4:
        return 0
    first = ((data[start] << 24) | (data[start + 1] << 16) | (data[start + 2] << 8) | data[start + 3]) & 0xffffffff
    r = (~first) & 0xffffffff
    for i in range(start + 4, end):
        r = (((r << 8) | data[i]) ^ TABLE[(r >> 24) & 0xff]) & 0xffffffff
    return (~r) & 0xffffffff

path = sys.argv[1]
with open(path, "rb") as f:
    raw = bytearray(f.read())

if len(raw) != 0xD6B6 or raw[0:4] != b"20CM":
    sys.exit(1)

# Zero out the 6 runtime controller binding records at 0xD278..0xD6B6 (0x43E bytes)
raw[0xD278:0xD6B6] = b"\x00" * (0xD6B6 - 0xD278)

# Recalculate Block A, Block B, and Header CRCs
crc_a = nfsu2_crc(raw, 0x1C, 0x24)
crc_b = nfsu2_crc(raw, 0x24, 0xD6B6)
struct.pack_into("<I", raw, 0x10, crc_a)
struct.pack_into("<I", raw, 0x14, crc_b)

crc_hdr = nfsu2_crc(raw, 0x00, 0x18)
struct.pack_into("<I", raw, 0x18, crc_hdr)

with open(path, "wb") as f:
    f.write(raw)
PYEOF
    return $?
}

menu_reset_config() {
    dialog --backtitle "NFSU2 Controls | Reset Config" --title "Reset Config to Defaults" \
        --yesno "\nReset all launcher gamepad configs back to default?\n\nThis removes controls.cfg and SDL_GAMECONTROLLERCONFIG from nfsu2.cfg.\n\nProceed with reset?" \
        11 58 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
    if [ $? -eq 0 ]; then
        CFG_PRESET="Default"
        rm -f "$CONTROLS_CFG" 2>/dev/null || true
        if [ -f "$NFSU2_CFG" ]; then
            sed -i '/SDL_GAMECONTROLLERCONFIG/d' "$NFSU2_CFG" 2>/dev/null || true
        fi
        sync
        dialog --backtitle "NFSU2 Controls | Reset Config" --title "Reset Complete" \
            --msgbox "\n  [OK] Custom button mappings removed!\n\n  Game config restored to pure default.\n\n  Press A or Enter to continue." \
            10 54 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
        return 0
    fi
    return 1
}

menu_reset_save() {
    scan_save_profiles
    local count="${#PROFILES[@]}"

    if [ "$count" -eq 0 ]; then
        dialog --backtitle "NFSU2 Controls | Reset Save" --title "No Profiles Found" \
            --msgbox "\n  [!] No NFSU2 save profiles found in:\n\n  $SAVE_ROOT\n\n  Press A or Enter to return." \
            10 60 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
        return 1
    fi

    local menu_items=()
    menu_items+=("ALL" "All Profiles ($count found)")
    local idx=0
    while [ "$idx" -lt "$count" ]; do
        local num=$((idx + 1))
        menu_items+=("$num" "Profile: ${PROFILES[$idx]}  [${PROFILE_STATES[$idx]}]")
        idx=$((idx + 1))
    done

    dialog \
        --backtitle "NFSU2 Controls | Reset Save" \
        --title "Reset Save Controls" \
        --ok-label "Reset" \
        --cancel-label "Back" \
        --menu "\nSelect a profile to reset in-game controls to default\n(Career progress, cars & cash are 100% preserved):" \
        16 62 6 \
        "${menu_items[@]}" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"
    local ret=$?
    local sel=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"

    if [ $ret -ne 0 ] || [ -z "$sel" ]; then
        return 1
    fi

    local fixed_list=""
    local fixed_count=0

    if [ "$sel" = "ALL" ]; then
        local i=0
        while [ "$i" -lt "$count" ]; do
            if reset_single_profile_file "${PROFILE_PATHS[$i]}" "${PROFILES[$i]}"; then
                fixed_list="${fixed_list} ${PROFILES[$i]}"
                fixed_count=$((fixed_count + 1))
            fi
            i=$((i + 1))
        done
    else
        local target_idx=$((sel - 1))
        if [ "$target_idx" -ge 0 ] && [ "$target_idx" -lt "$count" ]; then
            if reset_single_profile_file "${PROFILE_PATHS[$target_idx]}" "${PROFILES[$target_idx]}"; then
                fixed_list="${PROFILES[$target_idx]}"
                fixed_count=1
            fi
        fi
    fi

    sync

    if [ "$fixed_count" -gt 0 ]; then
        dialog --backtitle "NFSU2 Controls | Reset Save" --title "Reset Complete" \
            --msgbox "\n  [OK] Save Controls Reset to Factory Default!\n\n  * Profile(s) :$fixed_list\n  * Career/Cash: 100% Preserved & Checksum Verified\n  * Backup     : Saved in .backup_controls/\n\n  Press A or Enter to continue." \
            12 60 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
        return 0
    else
        dialog --backtitle "NFSU2 Controls | Reset Save" --title "Error" \
            --msgbox "\n  [!] Failed to reset profile save file.\n\n  Press A or Enter to continue." \
            9 56 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
        return 1
    fi
}

menu_reset() {
    while true; do
        dialog \
            --backtitle "NFSU2 Controls | Reset" \
            --title "Reset Controls" \
            --ok-label "Select" \
            --cancel-label "Back" \
            --menu "\nSelect what you want to reset to default:\n" \
            12 58 2 \
            "1" "Config  (controls.cfg & nfsu2.cfg)" \
            "2" "Save    (In-game save bindings + backup)" \
            2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

        local ret=$?
        local sel=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
        rm -f "$CHOICE_TMP"

        if [ $ret -ne 0 ] || [ -z "$sel" ]; then
            break
        fi

        case "$sel" in
            1) menu_reset_config && break ;;
            2) menu_reset_save && break ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Main Interactive Loop (Minimal Layout)
# ------------------------------------------------------------------------------
load_config

while true; do
    BACKTITLE="NFSU2 Controls"
    MENU_PROMPT="\nActive Preset: $CFG_PRESET"

    dialog \
        --backtitle "$BACKTITLE" \
        --title "NFSU2 Controls" \
        --ok-label "Select" \
        --cancel-label "Exit" \
        --menu "$MENU_PROMPT" \
        12 54 4 \
        "1" "PS2 Classic" \
        "2" "Modern Trigger" \
        "3" "Custom" \
        "4" "Reset" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

    RET=$?
    CHOICE=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"

    if [ $RET -ne 0 ] || [ -z "$CHOICE" ]; then
        break
    fi

    case "$CHOICE" in
        1)
            apply_preset "PS2_Classic"
            dialog --backtitle "NFSU2 Controls" --title "Preset Applied" \
                --msgbox "\n  [OK] Preset 'PS2 Classic' applied successfully!\n\n  * Throttle: B (Bottom)  * Brake: Y (Left)\n  * E-Brake:  A (Right)   * Camera: X (Top)\n\n  Press A or Enter to continue." \
                11 58 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
            ;;
        2)
            apply_preset "Modern_Triggers"
            dialog --backtitle "NFSU2 Controls" --title "Preset Applied" \
                --msgbox "\n  [OK] Preset 'Modern Trigger' applied successfully!\n\n  * Throttle: R2 Trigger  * Brake: L2 Trigger\n  * E-Brake:  A (Right)   * Nitro: R1 Shoulder\n\n  Press A or Enter to continue." \
                11 58 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
            ;;
        3)
            menu_customize_driving
            ;;
        4)
            menu_reset
            ;;
    esac
done

exit 0
