#!/bin/bash
# ==============================================================================
# Tool: NFSU2 Graphic Tuner v1.1 (R36H / playOS / ArkOS)
# Description: Standalone interactive ncurses TUI to configure:
#                1. Frame Rate Limit      (20 / 30 / 60 FPS)
#                2. Graphics Profile      (ultra_performance / performance / balanced / quality)
#                3. Performance Trade-offs (Car Reflect, Distant AI, Crowd, Particles)
# Archetype: Multi-Config Interactive TUI Tool (Flat Side-by-Side)
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
CHOICE_TMP="/tmp/nfsu2_gfx_choice.$$"
GPTK_CONF="/tmp/nfsu2_gfx_keys.gptk"

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
        [ "$TARGET_NAME" = "bash" ] || [ "$TARGET_NAME" = "sh" ] && TARGET_NAME="NFSU2_Graphics.sh"
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
for root in "$SCRIPT_DIR" /roms/ports /roms2/ports; do
    [ -d "$root" ] || continue
    for cand in "$root"/*; do
        [ -d "$cand" ] || continue
        if [ "$(basename "$cand" | tr '[:upper:]' '[:lower:]')" = "nfsu2" ]; then
            if resolve_gamedata "$cand" >/dev/null; then
                NFSU2_DIR="$(cd "$cand" && pwd)"
                break 2
            fi
        fi
    done
done

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
            dialog --backtitle "NFSU2 Graphic Tuner" --title "Game Not Found" \
                --msgbox "\n  [!] NFSU2 game folder (with gamedata/) was not found.\n\n  Checked:\n    - /roms/ports/nfsu2\n    - /roms2/ports/nfsu2\n\n  Press A or Enter to exit." \
                12 60 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
            exit 1
        fi

        dialog \
            --backtitle "NFSU2 Graphic Tuner | Folder Not Auto-Detected" \
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
        if resolve_gamedata "$PICK_DIR" >/dev/null; then
            NFSU2_DIR="$(cd "$PICK_DIR" && pwd)"
            break
        else
            dialog --backtitle "NFSU2 Graphic Tuner" --title "Invalid Folder" \
                --msgbox "\n  [!] 'gamedata/' not found inside:\n  $PICK_DIR\n\n  Press A or Enter to try again." \
                10 60 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
        fi
    done
fi

CFG_FILE="$NFSU2_DIR/nfsu2.cfg"

# ------------------------------------------------------------------------------
# 3. Config Helpers
# ------------------------------------------------------------------------------
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

set_cfg_key() {
    local key="$1"
    local val="$2"
    ensure_cfg
    if grep -q "^${key}=" "$CFG_FILE"; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$CFG_FILE"
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

read_cfg_key() {
    local key="$1"
    [ -f "$CFG_FILE" ] || return 0
    grep "^${key}=" "$CFG_FILE" 2>/dev/null | tail -n1 | cut -d= -f2 | tr -d ' "\r'
}

scan_status() {
    CURRENT_FPS="30"
    CURRENT_GFX="performance"
    CURRENT_DIST="200"
    CURRENT_SCALE="1.0"
    CURRENT_REFL="0"
    CURRENT_AI_RATE="0"
    CURRENT_AI_DIST="45"
    CURRENT_CROWD="default"
    CURRENT_PART="default"

    if [ -f "$CFG_FILE" ]; then
        local v
        v="$(read_cfg_key NFSU2_FPS)";             [ -n "$v" ] && CURRENT_FPS="$v"
        v="$(read_cfg_key NFSU2_GRAPHICS)";        [ -n "$v" ] && CURRENT_GFX="$v"
        v="$(read_cfg_key NFSU2_DRAW_DIST)";       [ -n "$v" ] && CURRENT_DIST="$v"
        v="$(read_cfg_key NFSU2_RENDER_SCALE)";    [ -n "$v" ] && CURRENT_SCALE="$v"
        v="$(read_cfg_key NFSU2_HALF_REFLECT)";    [ -n "$v" ] && CURRENT_REFL="$v"
        v="$(read_cfg_key NFSU2_DISTANT_AI_RATE)"; [ -n "$v" ] && CURRENT_AI_RATE="$v"
        v="$(read_cfg_key NFSU2_DISTANT_AI_DIST)"; [ -n "$v" ] && CURRENT_AI_DIST="$v"
        v="$(read_cfg_key NFSU2_CROWD)";           [ -n "$v" ] && CURRENT_CROWD="$v"
        v="$(read_cfg_key NFSU2_PARTICLES)";       [ -n "$v" ] && CURRENT_PART="$v"
    fi

    # Normalize aliases (1 -> 2)
    [ "$CURRENT_REFL" = "1" ] && CURRENT_REFL="2"
    [ "$CURRENT_AI_RATE" = "1" ] && CURRENT_AI_RATE="2"

    # Human-readable labels
    if [ "$CURRENT_REFL" = "0" ]; then
        REFL_LABEL="OFF"
    else
        REFL_LABEL="1/${CURRENT_REFL} Rate"
    fi

    if [ "$CURRENT_AI_RATE" = "0" ]; then
        AI_LABEL="OFF"
        CURRENT_AI_CHOICE="0"
    else
        AI_LABEL="1/${CURRENT_AI_RATE} >${CURRENT_AI_DIST}m"
        CURRENT_AI_CHOICE="${CURRENT_AI_RATE}:${CURRENT_AI_DIST}"
    fi

    case "$CURRENT_CROWD" in
        "0") CROWD_LABEL="Force OFF" ;;
        "1") CROWD_LABEL="Force ON" ;;
        *)   CURRENT_CROWD="default"; CROWD_LABEL="Preset" ;;
    esac

    case "$CURRENT_PART" in
        "0") PART_LABEL="Force OFF" ;;
        "1") PART_LABEL="Force ON" ;;
        *)   CURRENT_PART="default"; PART_LABEL="Preset" ;;
    esac

    local active_cnt=0
    [ "$CURRENT_REFL" != "0" ] && active_cnt=$((active_cnt + 1))
    [ "$CURRENT_AI_RATE" != "0" ] && active_cnt=$((active_cnt + 1))
    [ "$CURRENT_CROWD" != "default" ] && active_cnt=$((active_cnt + 1))
    [ "$CURRENT_PART" != "default" ] && active_cnt=$((active_cnt + 1))

    if [ "$active_cnt" -eq 0 ]; then
        TRADEOFF_SUMMARY="Default"
    elif [ "$active_cnt" -eq 4 ]; then
        TRADEOFF_SUMMARY="4/4 active"
    else
        TRADEOFF_SUMMARY="${active_cnt}/4 active"
    fi
}

# ------------------------------------------------------------------------------
# 4. Core Submenus
# ------------------------------------------------------------------------------
do_select_fps() {
    dialog \
        --backtitle "NFSU2 Graphic Tuner | Current: ${CURRENT_FPS} FPS" \
        --title "Select Frame Rate Limit" \
        --ok-label "Apply" \
        --cancel-label "Back" \
        --default-item "$CURRENT_FPS" \
        --menu "\nCurrent Frame Rate Limit: ${CURRENT_FPS} FPS\nChoose target frame rate cap:" \
        14 62 3 \
        "30" "30 FPS - Standard (Recommended, smooth 2:2 VSync)" \
        "20" "20 FPS - Locked 3:3 VSync (cooler, zero dips)" \
        "60" "60 FPS - Uncapped up to 60 (fluctuates in city)" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

    local rc=$?
    local new_fps
    new_fps=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"

    if [ $rc -ne 0 ] || [ -z "$new_fps" ]; then
        return
    fi

    set_cfg_key "NFSU2_FPS" "$new_fps"
    dialog --backtitle "NFSU2 Graphic Tuner" --title "Frame Rate Updated" \
        --msgbox "\n  [OK] Frame Rate Limit set to: ${new_fps} FPS\n\n  Press A or Enter to continue." \
        9 54 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

do_select_graphics() {
    dialog \
        --backtitle "NFSU2 Graphic Tuner | Current: $CURRENT_GFX" \
        --title "Select Graphics Profile" \
        --ok-label "Apply" \
        --cancel-label "Back" \
        --default-item "$CURRENT_GFX" \
        --menu "\nCurrent Profile: $CURRENT_GFX (${CURRENT_DIST}m, ${CURRENT_SCALE}x)\n(Performance Trade-offs are preserved)" \
        16 64 4 \
        "ultra_performance" "Max 30 FPS (0.75x scale, 120m, no shadows/FX)" \
        "performance"       "Fast 30 FPS (1.0x scale, 200m, low FX)" \
        "balanced"          "Balanced (1.0x scale, 200m, medium FX)" \
        "quality"           "High Quality (1.0x scale, 200m, high FX)" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

    local rc=$?
    local new_gfx
    new_gfx=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"

    if [ $rc -ne 0 ] || [ -z "$new_gfx" ]; then
        return
    fi

    local new_dist="200"
    local new_scale=""
    if [ "$new_gfx" = "ultra_performance" ]; then
        new_dist="120"
        new_scale="0.75"
    fi

    set_cfg_key "NFSU2_GRAPHICS" "$new_gfx"
    set_cfg_key "NFSU2_DRAW_DIST" "$new_dist"
    if [ -n "$new_scale" ]; then
        set_cfg_key "NFSU2_RENDER_SCALE" "$new_scale"
    else
        del_cfg_key "NFSU2_RENDER_SCALE"
    fi

    local scale_label="1.0x (640x480)"
    [ -n "$new_scale" ] && scale_label="${new_scale}x (480x360)"

    dialog --backtitle "NFSU2 Graphic Tuner" --title "Graphics Profile Updated" \
        --msgbox "\n  [OK] Graphics Profile set to: $new_gfx\n\n  * Draw Distance : ${new_dist}m\n  * Render Scale  : $scale_label\n  * Trade-offs    : Preserved (${TRADEOFF_SUMMARY})\n\n  Press A or Enter to continue." \
        12 58 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

# ------------------------------------------------------------------------------
# 5. Performance Trade-offs Submenus
# ------------------------------------------------------------------------------
do_select_half_reflect() {
    dialog \
        --backtitle "NFSU2 Graphic Tuner | Car Reflect: $REFL_LABEL" \
        --title "Car Reflection Update Rate" \
        --ok-label "Apply" \
        --cancel-label "Back" \
        --default-item "$CURRENT_REFL" \
        --menu "\nThrottle car environment reflection map updates while driving\n(Menus/Garage stay full rate; applies when Car EnvMap is ON):" \
        16 64 4 \
        "0" "OFF      - Full rate every frame (default)" \
        "2" "1/2 Rate - Recommended (15 Hz, ~8% CPU saving)" \
        "3" "1/3 Rate - Faster (10 Hz while driving)" \
        "4" "1/4 Rate - Fastest (7.5 Hz while driving)" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

    local rc=$?
    local val
    val=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"
    [ $rc -ne 0 ] || [ -z "$val" ] && return

    local lbl="OFF"
    if [ "$val" = "0" ]; then
        del_cfg_key "NFSU2_HALF_REFLECT"
    else
        set_cfg_key "NFSU2_HALF_REFLECT" "$val"
        lbl="1/${val} Rate"
    fi

    dialog --backtitle "NFSU2 Graphic Tuner" --title "Car Reflection Updated" \
        --msgbox "\n  [OK] Car Reflection Rate set to: $lbl\n\n  Press A or Enter to continue." \
        9 54 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

do_select_distant_ai() {
    dialog \
        --backtitle "NFSU2 Graphic Tuner | Distant AI: $AI_LABEL" \
        --title "Distant AI & Physics Throttle" \
        --ok-label "Apply" \
        --cancel-label "Back" \
        --default-item "$CURRENT_AI_CHOICE" \
        --menu "\nReduce AI controller & physics substep rate for distant cars\n(Player car and nearby opponents always stay at 100%):" \
        16 64 4 \
        "0"    "OFF          - Full rate for all cars (default)" \
        "2:45" "1/2 Rate 45m - Recommended (half rate >45m)" \
        "3:45" "1/3 Rate 45m - Stronger (1/3 AI, 3 substeps >45m)" \
        "2:30" "1/2 Rate 30m - Aggressive (half rate >30m)" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

    local rc=$?
    local val
    val=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"
    [ $rc -ne 0 ] || [ -z "$val" ] && return

    local lbl="OFF"
    if [ "$val" = "0" ]; then
        del_cfg_key "NFSU2_DISTANT_AI_RATE"
        del_cfg_key "NFSU2_DISTANT_AI_DIST"
    else
        local r="${val%%:*}"
        local d="${val##*:}"
        set_cfg_key "NFSU2_DISTANT_AI_RATE" "$r"
        set_cfg_key "NFSU2_DISTANT_AI_DIST" "$d"
        lbl="1/${r} Rate beyond ${d}m"
    fi

    dialog --backtitle "NFSU2 Graphic Tuner" --title "Distant AI Updated" \
        --msgbox "\n  [OK] Distant AI Throttle set to: $lbl\n\n  Press A or Enter to continue." \
        9 56 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

do_select_crowd() {
    dialog \
        --backtitle "NFSU2 Graphic Tuner | Crowd: $CROWD_LABEL" \
        --title "Roadside Crowd Override" \
        --ok-label "Apply" \
        --cancel-label "Back" \
        --default-item "$CURRENT_CROWD" \
        --menu "\nOverride roadside spectator crowds on top of Graphics Profile:" \
        14 62 3 \
        "default" "Preset Default - Follow active Graphics Profile" \
        "0"       "Force OFF      - Disable crowds (faster)" \
        "1"       "Force ON       - Always show crowds" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

    local rc=$?
    local val
    val=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"
    [ $rc -ne 0 ] || [ -z "$val" ] && return

    local lbl="Preset Default"
    if [ "$val" = "default" ]; then
        del_cfg_key "NFSU2_CROWD"
    elif [ "$val" = "0" ]; then
        set_cfg_key "NFSU2_CROWD" "0"
        lbl="Force OFF"
    else
        set_cfg_key "NFSU2_CROWD" "1"
        lbl="Force ON"
    fi

    dialog --backtitle "NFSU2 Graphic Tuner" --title "Crowd Override Updated" \
        --msgbox "\n  [OK] Crowd Override set to: $lbl\n\n  Press A or Enter to continue." \
        9 54 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

do_select_particles() {
    dialog \
        --backtitle "NFSU2 Graphic Tuner | Particles: $PART_LABEL" \
        --title "Particles Override" \
        --ok-label "Apply" \
        --cancel-label "Back" \
        --default-item "$CURRENT_PART" \
        --menu "\nOverride tire smoke & spark particles on top of Graphics Profile:" \
        14 62 3 \
        "default" "Preset Default - Follow active Graphics Profile" \
        "0"       "Force OFF      - Disable particles (faster)" \
        "1"       "Force ON       - Always enable particles" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

    local rc=$?
    local val
    val=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"
    [ $rc -ne 0 ] || [ -z "$val" ] && return

    local lbl="Preset Default"
    if [ "$val" = "default" ]; then
        del_cfg_key "NFSU2_PARTICLES"
    elif [ "$val" = "0" ]; then
        set_cfg_key "NFSU2_PARTICLES" "0"
        lbl="Force OFF"
    else
        set_cfg_key "NFSU2_PARTICLES" "1"
        lbl="Force ON"
    fi

    dialog --backtitle "NFSU2 Graphic Tuner" --title "Particles Override Updated" \
        --msgbox "\n  [OK] Particles Override set to: $lbl\n\n  Press A or Enter to continue." \
        9 54 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

do_tradeoffs_enable_all() {
    set_cfg_key "NFSU2_HALF_REFLECT" "2"
    set_cfg_key "NFSU2_DISTANT_AI_RATE" "2"
    set_cfg_key "NFSU2_DISTANT_AI_DIST" "45"
    set_cfg_key "NFSU2_CROWD" "0"
    set_cfg_key "NFSU2_PARTICLES" "0"

    dialog --backtitle "NFSU2 Graphic Tuner" --title "Trade-offs Enabled" \
        --msgbox "\n  [OK] Enabled all recommended trade-offs:\n\n  * Car Reflection : 1/2 Rate\n  * Distant AI     : 1/2 Rate (>45m)\n  * Crowd          : Force OFF\n  * Particles      : Force OFF\n\n  Press A or Enter to continue." \
        13 56 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

do_tradeoffs_reset_all() {
    del_cfg_key "NFSU2_HALF_REFLECT"
    del_cfg_key "NFSU2_DISTANT_AI_RATE"
    del_cfg_key "NFSU2_DISTANT_AI_DIST"
    del_cfg_key "NFSU2_CROWD"
    del_cfg_key "NFSU2_PARTICLES"

    dialog --backtitle "NFSU2 Graphic Tuner" --title "Trade-offs Reset" \
        --msgbox "\n  [OK] All Performance Trade-offs reset to default.\n\n  Press A or Enter to continue." \
        9 58 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

do_tradeoffs_menu() {
    while true; do
        scan_status
        dialog \
            --backtitle "NFSU2 Graphic Tuner | Trade-offs ($TRADEOFF_SUMMARY)" \
            --title "Performance Trade-offs" \
            --ok-label "Select" \
            --cancel-label "Back" \
            --menu "\nConfigure optional speed vs visual/AI trade-offs:" \
            17 64 6 \
            "1" "Car Reflection Rate (${REFL_LABEL})" \
            "2" "Distant AI Throttle (${AI_LABEL})" \
            "3" "Crowd Override      (${CROWD_LABEL})" \
            "4" "Particles Override  (${PART_LABEL})" \
            "5" "Enable All Recommended" \
            "6" "Reset All to Default" \
            2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

        local rc=$?
        local pick
        pick=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
        rm -f "$CHOICE_TMP"

        if [ $rc -ne 0 ] || [ -z "$pick" ]; then
            break
        fi

        case "$pick" in
            "1") do_select_half_reflect ;;
            "2") do_select_distant_ai ;;
            "3") do_select_crowd ;;
            "4") do_select_particles ;;
            "5") do_tradeoffs_enable_all ;;
            "6") do_tradeoffs_reset_all ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 6. Main Interactive Loop
# ------------------------------------------------------------------------------
while true; do
    scan_status

    MENU_PROMPT="\nCurrent Settings:\n  * Frame Rate Limit : ${CURRENT_FPS} FPS\n  * Graphics Profile : ${CURRENT_GFX} (${CURRENT_DIST}m, ${CURRENT_SCALE}x)\n  * Trade-offs       : Refl=${REFL_LABEL}, AI=${AI_LABEL}\n                       Crowd=${CROWD_LABEL}, Part=${PART_LABEL}\n\nChoose a setting to change, or press < Exit > to quit:"

    dialog \
        --backtitle "NFSU2 Graphic Tuner | $NFSU2_DIR" \
        --title "NFSU2 Graphic Tuner v1.1" \
        --ok-label "Select" \
        --cancel-label "Exit" \
        --menu "$MENU_PROMPT" \
        18 64 3 \
        "1" "Frame Rate Limit       (${CURRENT_FPS} FPS)" \
        "2" "Graphics Profile       (${CURRENT_GFX})" \
        "3" "Performance Trade-offs (${TRADEOFF_SUMMARY})" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

    RET=$?
    CHOICE=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"

    if [ $RET -ne 0 ] || [ -z "$CHOICE" ]; then
        break
    fi

    case "$CHOICE" in
        "1") do_select_fps ;;
        "2") do_select_graphics ;;
        "3") do_tradeoffs_menu ;;
    esac
done

exit 0
