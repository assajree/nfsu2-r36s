#!/bin/bash
# ==============================================================================
# Tool: NFSU2 Thai Manager v2.0 (All-in-One Smart TUI for R36H / playOS / ArkOS)
# Description: Interactive Linux ncurses dialog interface for NFSU2 runtime
#              build (develop):
#                1. Install / Re-install / Uninstall Thai Assets (Thailand.bin)
#                2. Switch Language: Thai <-> English (NFSU2_LANG)
#                3. Toggle Skip Intro / Fast Boot (NFSU2_SKIP_INTRO)
#                4. Configure Title Attract Mode (NFSU2_ATTRACT_MODE)
#                5. Configure Subtitles (NFSU2_SUBTITLES)
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
                --msgbox "\n  [!] NFSU2 game folder (with gamedata/) was not found.\n\n  Checked:\n    - /roms/ports/nfsu2\n    - /roms2/ports/nfsu2 & NFSU2\n\n  Press A or Enter to exit." \
                12 62 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
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
LAUNCHER_PATH="$(dirname "$NFSU2_DIR")/NFSU2.sh"
MOVIES_DIR="$GAMEDATA/MOVIES"
[ ! -d "$MOVIES_DIR" ] && [ -d "$GAMEDATA/movies" ] && MOVIES_DIR="$GAMEDATA/movies"

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

# Locate Bundled develop ARM64 Runtime (nfsu2.aarch64.v10 + NFSU2.sh.tmpl)
RUNTIME_DIR=""
for cand_rt in \
    "$SCRIPT_DIR/nfsu2thai/runtime" \
    "$SCRIPT_DIR/runtime" \
    "/roms/ports/nfsu2thai/runtime" \
    "/roms2/ports/nfsu2thai/runtime" \
    "/roms/tools/nfsu2_thai/nfsu2thai/runtime" \
    "/roms2/tools/nfsu2_thai/nfsu2thai/runtime" \
    "/roms/tools/nfsu2_thai/runtime"; do
    if [ -d "$cand_rt" ] && [ -f "$cand_rt/nfsu2.aarch64.v10" ]; then
        RUNTIME_DIR="$cand_rt"
        break
    fi
done

# ------------------------------------------------------------------------------
# 3. Config & Legacy File Helpers
# ------------------------------------------------------------------------------
INTRO_FILES=("ealogo.vp6" "THX_logo.vp6" "FMVOpening.vp6" "PSA.vp6")

ensure_cfg() {
    if [ ! -f "$CFG_FILE" ]; then
        cat << 'EOF' > "$CFG_FILE"
NFSU2_GRAPHICS=performance
NFSU2_FPS=30
NFSU2_LANG=English
NFSU2_DRAW_DIST=200
NFSU2_REGISTRY_EXTRA=""
EOF
    fi
}

read_cfg_key() {
    local key="$1"
    [ -f "$CFG_FILE" ] || return 0
    grep "^${key}=" "$CFG_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- | sed 's/#.*//' | tr -d ' "\r'
}

set_cfg_key() {
    local key="$1"
    local val="$2"
    ensure_cfg
    if grep -q "^${key}=" "$CFG_FILE"; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$CFG_FILE"
    elif grep -q "^# *${key}=" "$CFG_FILE"; then
        sed -i "s|^# *${key}=.*|${key}=${val}|" "$CFG_FILE"
    else
        echo "${key}=${val}" >> "$CFG_FILE"
    fi
    sync
}

del_cfg_key() {
    local key="$1"
    [ -f "$CFG_FILE" ] || return 0
    sed -i "/^${key}=/d" "$CFG_FILE"
    sync
}

# Restore any _*.vp6 intro files renamed by older tool versions so runtime
# NFSU2_SKIP_INTRO and NFSU2_ATTRACT_MODE control them cleanly in memory.
restore_renamed_intros() {
    [ -d "$MOVIES_DIR" ] || return 0
    local f target_f backup_f
    for f in "${INTRO_FILES[@]}"; do
        target_f="$MOVIES_DIR/$f"
        backup_f="$MOVIES_DIR/_$f"
        if [ -f "$backup_f" ]; then
            rm -f "$target_f" 2>/dev/null || true
            mv -f "$backup_f" "$target_f" 2>/dev/null || true
        fi
    done
}

# ------------------------------------------------------------------------------
# 4. Status Scanner
# ------------------------------------------------------------------------------
scan_status() {
    THAI_INSTALLED=0
    if [ -f "$NFSU2_DIR/.nfsu2_thai" ]; then
        THAI_INSTALLED=1
    fi

    CURRENT_LANG="English"
    CURRENT_SKIP_INTRO="0"
    CURRENT_ATTRACT="auto"
    CURRENT_SUBTITLES="auto"

    if [ -f "$CFG_FILE" ]; then
        local v
        v="$(read_cfg_key NFSU2_LANG)"
        [ "$v" = "Thai" ] && CURRENT_LANG="Thai"

        v="$(read_cfg_key NFSU2_SKIP_INTRO)"
        case "$v" in
            1|y|Y|t|T|yes|true) CURRENT_SKIP_INTRO="1" ;;
            *)                  CURRENT_SKIP_INTRO="0" ;;
        esac

        v="$(read_cfg_key NFSU2_ATTRACT_MODE)"
        case "$v" in
            0|f|F|off|OFF|false) CURRENT_ATTRACT="0" ;;
            1|t|T|on|ON|true)    CURRENT_ATTRACT="1" ;;
            *)                   CURRENT_ATTRACT="auto" ;;
        esac

        v="$(read_cfg_key NFSU2_SUBTITLES)"
        case "$v" in
            1) CURRENT_SUBTITLES="1" ;;
            0) CURRENT_SUBTITLES="0" ;;
            *) CURRENT_SUBTITLES="auto" ;;
        esac
    fi

    if [ "$CURRENT_SKIP_INTRO" = "1" ]; then
        SKIP_LABEL="ON (1)"
    else
        SKIP_LABEL="OFF (0)"
    fi

    case "$CURRENT_ATTRACT" in
        0) ATTRACT_LABEL="Off (0)" ;;
        1) ATTRACT_LABEL="On (1)" ;;
        *) ATTRACT_LABEL="Auto" ;;
    esac

    case "$CURRENT_SUBTITLES" in
        1) SUB_LABEL="Force ON (1)" ;;
        0) SUB_LABEL="Force OFF (0)" ;;
        *) SUB_LABEL="Auto (Thai ON)" ;;
    esac
}

# ------------------------------------------------------------------------------
# 5. Action Implementations
# ------------------------------------------------------------------------------

# Shared Yes/No menu helper using <Select> and <Exit> buttons.
# Returns: 0 = yes, 1 = no, 2 = Exit/Cancel/ESC
ask_yesno_menu() {
    local title="$1" prompt="$2" h="$3" w="$4" def="$5" yes_lbl="$6" no_lbl="$7"
    local tmp="/tmp/nfsu2_thai_yn_$$"
    local ret choice
    if [ "$def" = "no" ]; then
        dialog --backtitle "NFSU2 Thai Manager v2.0" --title "$title" \
            --ok-label "Select" --cancel-label "Back" --default-item "no" \
            --menu "$prompt" "$h" "$w" 2 \
            "no" "$no_lbl" \
            "yes" "$yes_lbl" \
            2> "$tmp" < "$DIALOG_IN" > "$DIALOG_OUT"
    else
        dialog --backtitle "NFSU2 Thai Manager v2.0" --title "$title" \
            --ok-label "Select" --cancel-label "Back" --default-item "yes" \
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

select_attract_mode_value() {
    local current_val="$1"
    local tmp="/tmp/nfsu2_attract_$$"
    local rc choice
    dialog \
        --backtitle "NFSU2 Thai Manager v2.0 | Attract Mode: $current_val" \
        --title "Title Screen Attract Mode" \
        --ok-label "Select" \
        --cancel-label "Back" \
        --default-item "$current_val" \
        --menu "\nControl the 30s idle Attract Mode on the Title Screen:\n(Sets NFSU2_ATTRACT_MODE in nfsu2.cfg)" \
        14 66 3 \
        "auto" "Auto (Disable if FMVOpening missing/skipped)" \
        "0"    "Always Off (Keep Title music past 30s)" \
        "1"    "Original On (Play FMVOpening after 30s idle)" \
        2> "$tmp" < "$DIALOG_IN" > "$DIALOG_OUT"
    rc=$?
    choice=$(cat "$tmp" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$tmp"
    [ $rc -ne 0 ] || [ -z "$choice" ] && return 1
    SELECTED_ATTRACT="$choice"
    return 0
}

do_install_thai() {
    local is_reinstall="${1:-0}"
    local enable_skip="$CURRENT_SKIP_INTRO"
    local attract_val="$CURRENT_ATTRACT"
    local gauge_title success_title success_header skip_desc

    if [ -z "$THAI_ASSETS_DIR" ]; then
        dialog --backtitle "NFSU2 Thai Manager v2.0" --title "Missing Thai Assets" \
            --msgbox "\n  [!] Thai localization assets (Thailand.bin) were not found.\n\n  Expected under:\n    $SCRIPT_DIR/nfsu2thai/gamedata/LANGUAGES/\n\n  Press A or Enter to return." \
            12 66 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
        return
    fi

    if [ "$is_reinstall" -eq 1 ]; then
        ask_yesno_menu "Confirm Re-install" \
            "\nRe-install NFSU2 Thai assets & runtime?\n\nThis will re-copy:\n  * Thailand.bin & HD Thai font textures\n  * ARM64 runtime (nfsu2.aarch64.v10) & NFSU2.sh launcher\n  * Restore any legacy _*.vp6 renamed intro videos\n  * Set NFSU2_LANG=Thai in nfsu2.cfg\n\nExisting Skip Intro, Attract Mode, and Subtitles preserved." \
            17 66 "yes" \
            "Yes - Proceed with Re-install" \
            "No  - Back to menu"
        [ $? -ne 0 ] && return

        gauge_title="Re-installing Thai Edition"
        success_title="Re-install Successful"
        success_header="[OK] Thai Assets & Runtime Re-installed!"
        [ "$enable_skip" = "1" ] && skip_desc="ON (Attract: $attract_val)" || skip_desc="OFF (Attract: $attract_val)"
    else
        ask_yesno_menu "Fast Boot (Skip Intro)" \
            "\nEnable Fast Boot (NFSU2_SKIP_INTRO=1)?\n\nSkips EA/THX/Opening/PSA intro movies in memory\nwithout renaming or deleting files." \
            13 64 "yes" \
            "Yes - Direct boot to Title Screen (NFSU2_SKIP_INTRO=1)" \
            "No  - Play original intro movies (NFSU2_SKIP_INTRO=0)"
        local rc_fast=$?
        if [ "$rc_fast" -eq 0 ]; then
            enable_skip="1"
        elif [ "$rc_fast" -eq 1 ]; then
            enable_skip="0"
        else
            return
        fi

        if ! select_attract_mode_value "auto"; then
            return
        fi
        attract_val="$SELECTED_ATTRACT"

        gauge_title="Installing Thai Assets"
        success_title="Install Successful"
        success_header="[OK] Thai Localization Installed Successfully!"
        [ "$enable_skip" = "1" ] && skip_desc="ON (Attract: $attract_val)" || skip_desc="OFF (Attract: $attract_val)"
    fi

    # Validate required US car models (CIVIC & RSX) before modifying game files
    local cars_dir="" cand_cars
    for cand_cars in "$GAMEDATA/CARS" "$GAMEDATA/cars"; do
        if [ -d "$cand_cars" ]; then
            cars_dir="$cand_cars"
            break
        fi
    done
    local has_civic=0 has_rsx=0
    if [ -n "$cars_dir" ]; then
        ([ -d "$cars_dir/CIVIC" ] || [ -d "$cars_dir/civic" ]) && has_civic=1
        ([ -d "$cars_dir/RSX" ] || [ -d "$cars_dir/rsx" ]) && has_rsx=1
    fi
    if [ "$has_civic" -eq 0 ] || [ "$has_rsx" -eq 0 ]; then
        dialog --backtitle "NFSU2 Thai Manager v2.0" --title "Unsupported Game Region" \
            --msgbox "\n  [!] Missing required car models: CARS/CIVIC and/or CARS/RSX\n\n  Thai runtime localization (US v1.0) requires CIVIC & RSX.\n  Please use US PC game data or install nfsu2_cars_us.zip first.\n\n  Aborted without modifying game files.\n\n  Press A or Enter to return." \
            13 68 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
        return
    fi

    (
        echo "15" ; echo "XXX" ; echo "Backing up original runtime, launcher & config..." ; echo "XXX"
        mkdir -p "$BACKUP_DIR"
        if [ -f "$CFG_FILE" ] && [ ! -f "$BACKUP_DIR/nfsu2.cfg" ]; then
            cp -f "$CFG_FILE" "$BACKUP_DIR/nfsu2.cfg"
        fi
        if [ -f "$LAUNCHER_PATH" ] && [ ! -f "$BACKUP_DIR/NFSU2.sh" ]; then
            cp -f "$LAUNCHER_PATH" "$BACKUP_DIR/NFSU2.sh"
        fi
        for bin_name in "nfsu2.aarch64.v10" "nfsu2.aarch64"; do
            if [ -f "$NFSU2_DIR/$bin_name" ] && [ ! -f "$BACKUP_DIR/$bin_name" ]; then
                cp -f "$NFSU2_DIR/$bin_name" "$BACKUP_DIR/$bin_name"
            fi
        done
        if [ -f "$GAMEDATA/LANGUAGES/LanguageTextures.bin" ] && [ ! -f "$BACKUP_DIR/LanguageTextures.bin" ]; then
            cp -f "$GAMEDATA/LANGUAGES/LanguageTextures.bin" "$BACKUP_DIR/LanguageTextures.bin"
        fi
        sleep 0.2

        echo "45" ; echo "XXX" ; echo "Installing Thailand.bin and Thai font textures..." ; echo "XXX"
        mkdir -p "$GAMEDATA/LANGUAGES"
        if [ -f "$THAI_ASSETS_DIR/LANGUAGES/Thailand.bin" ]; then
            cp -f "$THAI_ASSETS_DIR/LANGUAGES/Thailand.bin" "$GAMEDATA/LANGUAGES/Thailand.bin"
            cp -f "$THAI_ASSETS_DIR/LANGUAGES/Thailand.bin" "$GAMEDATA/LANGUAGES/thailand.bin" 2>/dev/null || true
        fi
        if [ -f "$THAI_ASSETS_DIR/LANGUAGES/LanguageTextures.bin" ]; then
            cp -f "$THAI_ASSETS_DIR/LANGUAGES/LanguageTextures.bin" "$GAMEDATA/LANGUAGES/LanguageTextures.bin"
        fi
        sleep 0.2

        if [ -n "$RUNTIME_DIR" ]; then
            echo "70" ; echo "XXX" ; echo "Updating ARM64 runtime (nfsu2.aarch64.v10) & NFSU2.sh..." ; echo "XXX"
            if [ -f "$RUNTIME_DIR/nfsu2.aarch64.v10" ]; then
                cp -f "$RUNTIME_DIR/nfsu2.aarch64.v10" "$NFSU2_DIR/nfsu2.aarch64.v10"
                cp -f "$RUNTIME_DIR/nfsu2.aarch64.v10" "$NFSU2_DIR/nfsu2.aarch64"
                chmod 755 "$NFSU2_DIR/nfsu2.aarch64.v10" "$NFSU2_DIR/nfsu2.aarch64" 2>/dev/null || true
            fi
            if [ -f "$RUNTIME_DIR/NFSU2.sh.tmpl" ]; then
                cp -f "$RUNTIME_DIR/NFSU2.sh.tmpl" "$LAUNCHER_PATH"
                chmod 755 "$LAUNCHER_PATH" 2>/dev/null || true
            fi
        fi

        echo "85" ; echo "XXX" ; echo "Cleaning legacy _*.vp6 renames & updating nfsu2.cfg..." ; echo "XXX"
        restore_renamed_intros
        set_cfg_key "NFSU2_LANG" "Thai"
        if [ "$is_reinstall" -eq 0 ]; then
            set_cfg_key "NFSU2_SKIP_INTRO" "$enable_skip"
            set_cfg_key "NFSU2_ATTRACT_MODE" "$attract_val"
        fi

        touch "$NFSU2_DIR/.nfsu2_thai"
        sync
        echo "100" ; echo "XXX" ; echo "Installation completed successfully!" ; echo "XXX"
        sleep 0.3
    ) | dialog --backtitle "NFSU2 Thai Manager v2.0" --title "$gauge_title" \
        --gauge "\nInstalling Thai assets, runtime & configuration..." 8 60 0 \
        > "$DIALOG_OUT" 2>/dev/null

    local rt_desc="Not bundled (using existing runtime)"
    [ -n "$RUNTIME_DIR" ] && rt_desc="Updated (develop v10 + NFSU2.sh)"

    dialog --backtitle "NFSU2 Thai Manager v2.0" --title "$success_title" \
        --msgbox "\n  $success_header\n\n  * Assets    : Thailand.bin & LanguageTextures.bin\n  * Runtime   : $rt_desc\n  * Language  : Thai (in-memory runtime)\n  * Fast Boot : $skip_desc\n\n  Press A or Enter to exit." \
        13 62 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null

    exit 0
}

do_uninstall_thai() {
    ask_yesno_menu "Confirm Uninstallation" \
        "\nAre you sure you want to uninstall NFSU2 Thai?\n\n* Removes Thailand.bin localization data\n* Restores original nfsu2.aarch64*, NFSU2.sh, and nfsu2.cfg\n* Restores LanguageTextures.bin (and SPEED2.EXE if backed up)\n* Preserves player save games safely" \
        15 64 "no" \
        "Yes - Uninstall and restore original files" \
        "No  - Back to menu"

    if [ $? -ne 0 ]; then
        return
    fi

    (
        echo "20" ; echo "XXX" ; echo "Restoring backed-up runtime, launcher & assets..." ; echo "XXX" ; sleep 0.2
        if [ -d "$BACKUP_DIR" ]; then
            # Restore legacy SPEED2.EXE backup if an older version created it
            if [ -f "$BACKUP_DIR/SPEED2.EXE" ]; then
                cp -f "$BACKUP_DIR/SPEED2.EXE" "$GAMEDATA/SPEED2.EXE"
                cp -f "$BACKUP_DIR/SPEED2.EXE" "$GAMEDATA/speed2.exe" 2>/dev/null || true
            fi
            for bin_name in "nfsu2.aarch64.v10" "nfsu2.aarch64.v12" "nfsu2.aarch64"; do
                if [ -f "$BACKUP_DIR/$bin_name" ]; then
                    cp -f "$BACKUP_DIR/$bin_name" "$NFSU2_DIR/$bin_name"
                    chmod 755 "$NFSU2_DIR/$bin_name" 2>/dev/null || true
                fi
            done
            if [ -f "$BACKUP_DIR/NFSU2.sh" ]; then
                cp -f "$BACKUP_DIR/NFSU2.sh" "$LAUNCHER_PATH"
                chmod 755 "$LAUNCHER_PATH" 2>/dev/null || true
            fi
            if [ -f "$BACKUP_DIR/LanguageTextures.bin" ]; then
                cp -f "$BACKUP_DIR/LanguageTextures.bin" "$GAMEDATA/LANGUAGES/LanguageTextures.bin"
            fi
            if [ -f "$BACKUP_DIR/nfsu2.cfg" ]; then
                cp -f "$BACKUP_DIR/nfsu2.cfg" "$CFG_FILE"
            fi
        fi

        echo "60" ; echo "XXX" ; echo "Removing Thailand.bin & restoring intro filenames..." ; echo "XXX" ; sleep 0.2
        rm -f "$GAMEDATA/LANGUAGES/Thailand.bin" "$GAMEDATA/LANGUAGES/thailand.bin" 2>/dev/null || true
        rm -f "$NFSU2_DIR/.nfsu2_thai" 2>/dev/null || true
        restore_renamed_intros

        echo "85" ; echo "XXX" ; echo "Finalizing configuration..." ; echo "XXX" ; sleep 0.2
        if [ ! -f "$BACKUP_DIR/nfsu2.cfg" ] && [ -f "$CFG_FILE" ]; then
            set_cfg_key "NFSU2_LANG" "English"
            del_cfg_key "NFSU2_SUBTITLES"
        elif [ -f "$CFG_FILE" ] && [ "$(read_cfg_key NFSU2_LANG)" = "Thai" ]; then
            set_cfg_key "NFSU2_LANG" "English"
        fi
        sync
        echo "100" ; echo "XXX" ; echo "Uninstallation completed!" ; echo "XXX" ; sleep 0.3
    ) | dialog --backtitle "NFSU2 Thai Manager v2.0" --title "Restoring Original Game" \
        --gauge "\nRestoring original configuration and removing Thai assets..." 8 60 0 \
        > "$DIALOG_OUT" 2>/dev/null

    dialog --backtitle "NFSU2 Thai Manager v2.0" --title "Uninstall Complete" \
        --msgbox "\n  [OK] NFSU2 Thai Uninstalled Successfully!\n\n  * Thailand.bin removed and backups restored\n  * Language reset to English\n  * Player save games are 100% safe\n\n  Press A or Enter to exit." \
        12 58 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null

    exit 0
}

do_toggle_language() {
    local target_l="$1"
    local msg
    set_cfg_key "NFSU2_LANG" "$target_l"

    if [ "$target_l" = "Thai" ]; then
        msg="\n  [OK] Language switched to: THAI\n\n  * Game text and menus will display in Thai.\n\n  Press A or Enter to continue."
    else
        msg="\n  [OK] Language switched to: ENGLISH\n\n  * Game text will display in original English.\n\n  Press A or Enter to continue."
    fi

    dialog --backtitle "NFSU2 Thai Manager v2.0" --title "Language Switched" \
        --msgbox "$msg" 10 56 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

do_configure_skip_intro() {
    local tmp="/tmp/nfsu2_skip_$$"
    local rc choice
    dialog \
        --backtitle "NFSU2 Thai Manager v2.0 | Skip Intro: $SKIP_LABEL" \
        --title "Skip Intro / Fast Boot" \
        --ok-label "Apply" \
        --cancel-label "Back" \
        --default-item "$CURRENT_SKIP_INTRO" \
        --menu "\nCurrent: $SKIP_LABEL\nSkip EA/THX/Opening/PSA intro movies in memory\n(Sets NFSU2_SKIP_INTRO in nfsu2.cfg):" \
        13 62 2 \
        "1" "ON  - Fast Boot directly to Title Screen" \
        "0" "OFF - Play original intro movies" \
        2> "$tmp" < "$DIALOG_IN" > "$DIALOG_OUT"
    rc=$?
    choice=$(cat "$tmp" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$tmp"

    [ $rc -ne 0 ] || [ -z "$choice" ] && return

    restore_renamed_intros
    set_cfg_key "NFSU2_SKIP_INTRO" "$choice"

    local label
    [ "$choice" = "1" ] && label="ON (Fast Boot enabled)" || label="OFF (Normal intro playback)"
    dialog --backtitle "NFSU2 Thai Manager v2.0" --title "Skip Intro Updated" \
        --msgbox "\n  [OK] NFSU2_SKIP_INTRO set to: $choice\n\n  * Status: $label\n\n  Press A or Enter to continue." \
        10 56 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

do_configure_attract_mode() {
    if ! select_attract_mode_value "$CURRENT_ATTRACT"; then
        return
    fi
    local choice="$SELECTED_ATTRACT"
    set_cfg_key "NFSU2_ATTRACT_MODE" "$choice"

    local desc
    case "$choice" in
        0) desc="Always Off (Title music loops without 30s reset)" ;;
        1) desc="Original On (Plays FMVOpening after 30s idle)" ;;
        *) desc="Auto (Disabled when FMVOpening missing/skipped)" ;;
    esac
    dialog --backtitle "NFSU2 Thai Manager v2.0" --title "Attract Mode Updated" \
        --msgbox "\n  [OK] NFSU2_ATTRACT_MODE set to: $choice\n\n  * $desc\n\n  Press A or Enter to continue." \
        10 62 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

do_configure_subtitles() {
    local tmp="/tmp/nfsu2_sub_$$"
    local rc choice
    dialog \
        --backtitle "NFSU2 Thai Manager v2.0 | Subtitles: $SUB_LABEL" \
        --title "Subtitles Setting (v1.0)" \
        --ok-label "Apply" \
        --cancel-label "Back" \
        --default-item "$CURRENT_SUBTITLES" \
        --menu "\nCurrent: $SUB_LABEL\nControl cutscene and in-game movie subtitles\n(Sets NFSU2_SUBTITLES in nfsu2.cfg):" \
        14 64 3 \
        "auto" "Auto  - ON for Thai, original for other languages" \
        "1"    "Force ON  - Show subtitles in all languages" \
        "0"    "Force OFF - Hide subtitles in all languages" \
        2> "$tmp" < "$DIALOG_IN" > "$DIALOG_OUT"
    rc=$?
    choice=$(cat "$tmp" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$tmp"

    [ $rc -ne 0 ] || [ -z "$choice" ] && return

    if [ "$choice" = "auto" ]; then
        del_cfg_key "NFSU2_SUBTITLES"
    else
        set_cfg_key "NFSU2_SUBTITLES" "$choice"
    fi

    local desc
    case "$choice" in
        1) desc="Force ON (Subtitles enabled for all languages)" ;;
        0) desc="Force OFF (Subtitles disabled)" ;;
        *) desc="Auto (ON automatically when Language is Thai)" ;;
    esac
    dialog --backtitle "NFSU2 Thai Manager v2.0" --title "Subtitles Updated" \
        --msgbox "\n  [OK] NFSU2_SUBTITLES set to: $choice\n\n  * $desc\n\n  Press A or Enter to continue." \
        10 62 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

# ------------------------------------------------------------------------------
# 6. Main Interactive Loop
# ------------------------------------------------------------------------------
while true; do
    scan_status

    if [ "$THAI_INSTALLED" -eq 1 ]; then
        STATUS_PATCH="Installed"
        if [ "$CURRENT_LANG" = "Thai" ]; then
            TAG1="lang_eng"
            LABEL1="Switch Language   [Thai -> English]"
        else
            TAG1="lang_thai"
            LABEL1="Switch Language   [English -> Thai]"
        fi

        BACKTITLE="NFSU2 Thai | $NFSU2_DIR"
        MENU_PROMPT="\nCurrent Settings:\n  * Thai Assets  : $STATUS_PATCH\n  * Language     : $CURRENT_LANG\n  * Skip Intro   : $SKIP_LABEL\n  * Attract Mode : $ATTRACT_LABEL\n  * Subtitles    : $SUB_LABEL\n\nChoose an action below, or press < Exit > to quit:"

        dialog \
            --backtitle "$BACKTITLE" \
            --title "NFSU2 Thai Manager v2.0" \
            --ok-label "Select" \
            --cancel-label "Exit" \
            --menu "$MENU_PROMPT" \
            20 64 6 \
            "1" "$LABEL1" \
            "2" "Skip Intro / Fast Boot  [$SKIP_LABEL]" \
            "3" "Title Attract Mode      [$ATTRACT_LABEL]" \
            "4" "Subtitles               [$SUB_LABEL]" \
            "5" "Re-install Thai Assets" \
            "6" "Uninstall NFSU2 Thai" \
            2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"
    else
        STATUS_PATCH="Not Installed"
        BACKTITLE="NFSU2 Thai | $NFSU2_DIR"
        MENU_PROMPT="\nCurrent Settings:\n  * Thai Assets  : $STATUS_PATCH\n  * Language     : $CURRENT_LANG\n  * Skip Intro   : $SKIP_LABEL\n  * Attract Mode : $ATTRACT_LABEL\n  * Subtitles    : $SUB_LABEL\n\nChoose an action below, or press < Exit > to quit:"

        dialog \
            --backtitle "$BACKTITLE" \
            --title "NFSU2 Thai Manager v2.0" \
            --ok-label "Select" \
            --cancel-label "Exit" \
            --menu "$MENU_PROMPT" \
            16 62 1 \
            "1" "Install NFSU2 Thai" \
            2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"
    fi

    RET=$?
    CHOICE=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"

    if [ $RET -ne 0 ] || [ -z "$CHOICE" ]; then
        break
    fi

    if [ "$THAI_INSTALLED" -eq 1 ]; then
        case "$CHOICE" in
            "1")
                if [ "$TAG1" = "lang_thai" ]; then
                    do_toggle_language "Thai"
                else
                    do_toggle_language "English"
                fi
                ;;
            "2") do_configure_skip_intro ;;
            "3") do_configure_attract_mode ;;
            "4") do_configure_subtitles ;;
            "5") do_install_thai 1 ;;
            "6") do_uninstall_thai ;;
        esac
    else
        case "$CHOICE" in
            "1") do_install_thai 0 ;;
        esac
    fi
done

exit 0
