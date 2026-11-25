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
    CURRENT_DIST=""
    CURRENT_BUDGET=""
    CURRENT_SCALE=""
    CURRENT_REFL="0"
    CURRENT_CAR_REFL="default"
    CURRENT_HEAD="default"
    CURRENT_CROWD="default"
    CURRENT_PART="default"

    if [ -f "$CFG_FILE" ]; then
        local v
        v="$(read_cfg_key NFSU2_FPS)";             [ -n "$v" ] && CURRENT_FPS="$v"
        v="$(read_cfg_key NFSU2_GRAPHICS)";        [ -n "$v" ] && CURRENT_GFX="$v"
        v="$(read_cfg_key NFSU2_DRAW_DIST)";       [ -n "$v" ] && CURRENT_DIST="$v"
        v="$(read_cfg_key NFSU2_DRAW_BUDGET)";     [ -n "$v" ] && CURRENT_BUDGET="$v"
        v="$(read_cfg_key NFSU2_RENDER_SCALE)";    [ -n "$v" ] && CURRENT_SCALE="$v"
        v="$(read_cfg_key NFSU2_HALF_REFLECT)";    [ -n "$v" ] && CURRENT_REFL="$v"
        v="$(read_cfg_key NFSU2_CAR_REFLECT)";     [ -n "$v" ] && CURRENT_CAR_REFL="$v"
        v="$(read_cfg_key NFSU2_HEADLIGHTS)";      [ -n "$v" ] && CURRENT_HEAD="$v"
        v="$(read_cfg_key NFSU2_CROWD)";           [ -n "$v" ] && CURRENT_CROWD="$v"
        v="$(read_cfg_key NFSU2_PARTICLES)";       [ -n "$v" ] && CURRENT_PART="$v"
    fi

    local def_dist="200" def_budget="0" def_scale="1.0"
    case "$CURRENT_GFX" in
        potato_1|potato_2|potato_3) def_dist="200"; def_budget="0"; def_scale="1.0" ;;
    esac

    local eff_dist="$CURRENT_DIST" eff_budget="$CURRENT_BUDGET"
    [ -z "$eff_dist" ] && eff_dist="$def_dist"
    [ -z "$eff_budget" ] && eff_budget="$def_budget"

    EFF_DIST="$eff_dist"
    EFF_BUDGET="$eff_budget"
    if [ -z "$CURRENT_DIST" ] && [ -z "$CURRENT_BUDGET" ]; then
        VIS_PICK="auto"
        [ "$def_budget" = "0" ] && VIS_LABEL="Auto (${def_dist}m)" || VIS_LABEL="Auto-Scale ${def_budget}"
    elif [ "$eff_budget" != "0" ]; then
        VIS_PICK="scale"
        VIS_LABEL="Auto-Scale ${eff_budget}"
    elif [ "$eff_dist" = "0" ]; then
        VIS_PICK="off"
        VIS_LABEL="OFF"
    else
        VIS_PICK="fixed"
        VIS_LABEL="Fixed ${eff_dist}m"
    fi

    if [ -z "$CURRENT_SCALE" ]; then
        SCALE_PICK="auto"
        CURRENT_SCALE="$def_scale"
        case "$def_scale" in
            0.50|0.5) SCALE_LABEL="Auto (320x240)" ;;
            0.65)     SCALE_LABEL="Auto (416x312)" ;;
            0.75)     SCALE_LABEL="Auto (480x360)" ;;
            0.85)     SCALE_LABEL="Auto (544x408)" ;;
            *)        SCALE_LABEL="Auto (640x480)" ;;
        esac
    else
        SCALE_PICK="$CURRENT_SCALE"
        case "$CURRENT_SCALE" in
            0.50|0.5) SCALE_PICK="0.50"; SCALE_LABEL="0.50x (320x240)" ;;
            0.65)     SCALE_LABEL="0.65x (416x312)" ;;
            0.75)     SCALE_LABEL="0.75x (480x360)" ;;
            0.85)     SCALE_LABEL="0.85x (544x408)" ;;
            1.0|1.00) SCALE_PICK="1.0";  SCALE_LABEL="1.0x (640x480)" ;;
            *)        SCALE_LABEL="${CURRENT_SCALE}x" ;;
        esac
    fi

    # Normalize aliases (1 -> 2)
    [ "$CURRENT_REFL" = "1" ] && CURRENT_REFL="2"

    # Human-readable labels
    if [ "$CURRENT_CAR_REFL" = "0" ]; then
        REFL_PICK="off"
        REFL_LABEL="Force OFF"
    elif [ "$CURRENT_CAR_REFL" = "1" ]; then
        if [ "$CURRENT_REFL" = "0" ]; then
            REFL_PICK="1"
            REFL_LABEL="ON Full"
        else
            REFL_PICK="$CURRENT_REFL"
            REFL_LABEL="ON 1/${CURRENT_REFL}"
        fi
    elif [ "$CURRENT_REFL" = "0" ]; then
        REFL_PICK="default"
        REFL_LABEL="Preset"
    else
        REFL_PICK="$CURRENT_REFL"
        REFL_LABEL="Preset 1/${CURRENT_REFL}"
    fi

    case "$CURRENT_HEAD" in
        "0") HEAD_LABEL="Force OFF" ;;
        "1") HEAD_LABEL="Force ON" ;;
        *)   CURRENT_HEAD="default"; HEAD_LABEL="Preset" ;;
    esac

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
    { [ "$CURRENT_REFL" != "0" ] || [ "$CURRENT_CAR_REFL" != "default" ]; } && active_cnt=$((active_cnt + 1))
    [ "$CURRENT_CROWD" != "default" ] && active_cnt=$((active_cnt + 1))
    [ "$CURRENT_PART" != "default" ] && active_cnt=$((active_cnt + 1))

    if [ "$active_cnt" -eq 0 ]; then
        TRADEOFF_SUMMARY="Default"
    elif [ "$active_cnt" -eq 3 ]; then
        TRADEOFF_SUMMARY="3/3 active"
    else
        TRADEOFF_SUMMARY="${active_cnt}/3 active"
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
        --menu "\nCurrent: ${CURRENT_FPS} FPS" \
        13 58 3 \
        "30" "30 FPS (Recommended)" \
        "20" "20 FPS" \
        "60" "60 FPS" \
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
        --menu "\nCurrent: $CURRENT_GFX" \
        16 58 6 \
        "potato_3"    "Potato" \
        "potato_2"    "PS1" \
        "potato_1"    "Lite" \
        "performance" "Fast 30 FPS" \
        "balanced"    "Balanced" \
        "quality"     "High Quality" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

    local rc=$?
    local new_gfx
    new_gfx=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"

    if [ $rc -ne 0 ] || [ -z "$new_gfx" ]; then
        return
    fi

    set_cfg_key "NFSU2_GRAPHICS" "$new_gfx"
    del_cfg_key "NFSU2_POTATO"
    scan_status

    dialog --backtitle "NFSU2 Graphic Tuner" --title "Graphics Profile Updated" \
        --msgbox "\n  [OK] Graphics Profile set to: $new_gfx\n\n  * Visibility    : ${VIS_LABEL}\n  * Render Scale  : ${SCALE_LABEL}\n  * Trade-offs    : Preserved (${TRADEOFF_SUMMARY})\n\n  Press A or Enter to continue." \
        12 58 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

do_select_fixed_dist() {
    dialog \
        --backtitle "NFSU2 Graphic Tuner | Draw Distance: $VIS_LABEL" \
        --title "Fixed Draw Distance" \
        --ok-label "Apply" \
        --cancel-label "Back" \
        --default-item "$EFF_DIST" \
        --menu "\nCurrent: $VIS_LABEL\nHigher distance = more performance drop:" \
        19 58 8 \
        "50"  "50m" \
        "60"  "60m" \
        "70"  "70m" \
        "80"  "80m" \
        "90"  "90m" \
        "100" "100m" \
        "120" "120m" \
        "150" "150m" \
        "200" "200m (Recommended)" \
        "250" "250m" \
        "300" "300m" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

    local rc=$?
    local val
    val=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"
    [ $rc -ne 0 ] || [ -z "$val" ] && return 1

    set_cfg_key "NFSU2_DRAW_DIST" "$val"
    set_cfg_key "NFSU2_DRAW_BUDGET" "0"
    dialog --backtitle "NFSU2 Graphic Tuner" --title "Draw Distance Updated" \
        --msgbox "\n  [OK] Draw Distance set to: Fixed ${val}m\n\n  Press A or Enter to continue." \
        9 54 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
    return 0
}

do_select_autoscale() {
    dialog \
        --backtitle "NFSU2 Graphic Tuner | Draw Distance: $VIS_LABEL" \
        --title "Auto-Scale (Draw Budget)" \
        --ok-label "Apply" \
        --cancel-label "Back" \
        --default-item "$EFF_BUDGET" \
        --menu "\nMax items/frame (cap 200m)\nHigher limit = more performance drop:" \
        19 58 8 \
        "200" "200 items" \
        "240" "240 items" \
        "280" "280 items" \
        "320" "320 items" \
        "360" "360 items" \
        "400" "400 items (Recommended)" \
        "450" "450 items" \
        "500" "500 items" \
        "600" "600 items" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

    local rc=$?
    local val
    val=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"
    [ $rc -ne 0 ] || [ -z "$val" ] && return 1

    set_cfg_key "NFSU2_DRAW_DIST" "200"
    set_cfg_key "NFSU2_DRAW_BUDGET" "$val"
    dialog --backtitle "NFSU2 Graphic Tuner" --title "Draw Distance Updated" \
        --msgbox "\n  [OK] Draw Distance set to: Auto-Scale ${val}\n\n  Press A or Enter to continue." \
        9 54 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
    return 0
}

do_select_draw_distance() {
    while true; do
        scan_status
        dialog \
            --backtitle "NFSU2 Graphic Tuner | Draw Distance: $VIS_LABEL" \
            --title "Draw Distance" \
            --ok-label "Select" \
            --cancel-label "Back" \
            --default-item "$VIS_PICK" \
            --menu "\nCurrent: $VIS_LABEL" \
            13 58 4 \
            "auto"  "Auto" \
            "fixed" "Fixed Distance" \
            "scale" "Auto-Scale" \
            "off"   "OFF" \
            2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

        local rc=$?
        local val
        val=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
        rm -f "$CHOICE_TMP"
        [ $rc -ne 0 ] || [ -z "$val" ] && return

        case "$val" in
            auto)
                del_cfg_key "NFSU2_DRAW_DIST"
                del_cfg_key "NFSU2_DRAW_BUDGET"
                dialog --backtitle "NFSU2 Graphic Tuner" --title "Draw Distance Updated" \
                    --msgbox "\n  [OK] Draw Distance set to: Auto\n\n  Press A or Enter to continue." \
                    9 54 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
                return
                ;;
            fixed)
                do_select_fixed_dist && return
                ;;
            scale)
                do_select_autoscale && return
                ;;
            off)
                set_cfg_key "NFSU2_DRAW_DIST" "0"
                set_cfg_key "NFSU2_DRAW_BUDGET" "0"
                dialog --backtitle "NFSU2 Graphic Tuner" --title "Draw Distance Updated" \
                    --msgbox "\n  [OK] Draw Distance set to: OFF\n\n  Press A or Enter to continue." \
                    9 54 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
                return
                ;;
        esac
    done
}

do_select_resolution() {
    dialog \
        --backtitle "NFSU2 Graphic Tuner | Resolution: $SCALE_LABEL" \
        --title "Select Render Resolution" \
        --ok-label "Apply" \
        --cancel-label "Back" \
        --default-item "$SCALE_PICK" \
        --menu "\nCurrent: $SCALE_LABEL" \
        15 58 6 \
        "auto" "Auto (Profile)" \
        "1.0"  "640x480 (1.00x)" \
        "0.85" "544x408 (0.85x)" \
        "0.75" "480x360 (0.75x)" \
        "0.65" "416x312 (0.65x)" \
        "0.50" "320x240 (0.50x)" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

    local rc=$?
    local val
    val=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"
    [ $rc -ne 0 ] || [ -z "$val" ] && return

    local lbl="Auto (Profile Default)"
    if [ "$val" = "auto" ]; then
        del_cfg_key "NFSU2_RENDER_SCALE"
    else
        set_cfg_key "NFSU2_RENDER_SCALE" "$val"
        case "$val" in
            1.0)  lbl="1.00x (640x480)" ;;
            0.85) lbl="0.85x (544x408)" ;;
            0.75) lbl="0.75x (480x360)" ;;
            0.65) lbl="0.65x (416x312)" ;;
            0.50) lbl="0.50x (320x240)" ;;
            *)    lbl="${val}x" ;;
        esac
    fi

    dialog --backtitle "NFSU2 Graphic Tuner" --title "Resolution Updated" \
        --msgbox "\n  [OK] Render Resolution set to: $lbl\n\n  Press A or Enter to continue." \
        9 54 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

# ------------------------------------------------------------------------------
# 5. Performance Trade-offs Submenus
# ------------------------------------------------------------------------------
do_select_half_reflect() {
    dialog \
        --backtitle "NFSU2 Graphic Tuner | Car Reflect: $REFL_LABEL" \
        --title "Car Reflection" \
        --ok-label "Apply" \
        --cancel-label "Back" \
        --default-item "$REFL_PICK" \
        --menu "\nCurrent: $REFL_LABEL" \
        17 58 7 \
        "default" "Preset Default" \
        "off"     "Force OFF" \
        "1"       "ON (Full Rate)" \
        "2"       "ON (1/2 Rate)" \
        "4"       "ON (1/4 Rate)" \
        "8"       "ON (1/8 Rate)" \
        "16"      "ON (1/16 Rate)" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

    local rc=$?
    local val
    val=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"
    [ $rc -ne 0 ] || [ -z "$val" ] && return

    local lbl="Preset Default"
    case "$val" in
        default)
            del_cfg_key "NFSU2_CAR_REFLECT"
            del_cfg_key "NFSU2_HALF_REFLECT"
            ;;
        off)
            set_cfg_key "NFSU2_CAR_REFLECT" "0"
            del_cfg_key "NFSU2_HALF_REFLECT"
            lbl="Force OFF"
            ;;
        1)
            set_cfg_key "NFSU2_CAR_REFLECT" "1"
            del_cfg_key "NFSU2_HALF_REFLECT"
            lbl="ON (Full Rate)"
            ;;
        2|3|4|8|16)
            set_cfg_key "NFSU2_CAR_REFLECT" "1"
            set_cfg_key "NFSU2_HALF_REFLECT" "$val"
            lbl="ON (1/${val} Rate)"
            ;;
    esac

    dialog --backtitle "NFSU2 Graphic Tuner" --title "Car Reflection Updated" \
        --msgbox "\n  [OK] Car Reflection set to: $lbl\n\n  Press A or Enter to continue." \
        9 54 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

do_select_headlights() {
    dialog \
        --backtitle "NFSU2 Graphic Tuner | Headlights: $HEAD_LABEL" \
        --title "Car Headlights" \
        --ok-label "Apply" \
        --cancel-label "Back" \
        --default-item "$CURRENT_HEAD" \
        --menu "\nCurrent: $HEAD_LABEL" \
        12 58 3 \
        "default" "Preset Default" \
        "0"       "Force OFF" \
        "1"       "Force ON" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

    local rc=$?
    local val
    val=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"
    [ $rc -ne 0 ] || [ -z "$val" ] && return

    local lbl="Preset Default"
    if [ "$val" = "default" ]; then
        del_cfg_key "NFSU2_HEADLIGHTS"
    elif [ "$val" = "0" ]; then
        set_cfg_key "NFSU2_HEADLIGHTS" "0"
        lbl="Force OFF"
    else
        set_cfg_key "NFSU2_HEADLIGHTS" "1"
        lbl="Force ON"
    fi

    dialog --backtitle "NFSU2 Graphic Tuner" --title "Headlights Updated" \
        --msgbox "\n  [OK] Car Headlights set to: $lbl\n\n  Press A or Enter to continue." \
        9 54 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

do_select_crowd() {
    dialog \
        --backtitle "NFSU2 Graphic Tuner | Crowd: $CROWD_LABEL" \
        --title "Roadside Crowd Override" \
        --ok-label "Apply" \
        --cancel-label "Back" \
        --default-item "$CURRENT_CROWD" \
        --menu "\nCurrent: $CROWD_LABEL" \
        12 58 3 \
        "default" "Preset Default" \
        "0"       "Force OFF" \
        "1"       "Force ON" \
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
        --menu "\nCurrent: $PART_LABEL" \
        12 58 3 \
        "default" "Preset Default" \
        "0"       "Force OFF" \
        "1"       "Force ON" \
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
    del_cfg_key "NFSU2_DISTANT_AI_RATE"
    del_cfg_key "NFSU2_DISTANT_AI_DIST"
    set_cfg_key "NFSU2_CROWD" "0"
    set_cfg_key "NFSU2_PARTICLES" "0"

    dialog --backtitle "NFSU2 Graphic Tuner" --title "Trade-offs Enabled" \
        --msgbox "\n  [OK] Enabled all recommended trade-offs:\n\n  * Car Reflection : 1/2 Rate\n  * Crowd          : Force OFF\n  * Particles      : Force OFF\n\n  Press A or Enter to continue." \
        12 56 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
}

do_tradeoffs_reset_all() {
    del_cfg_key "NFSU2_CAR_REFLECT"
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
            --backtitle "NFSU2 Graphic Tuner | Performance Trade-offs" \
            --title "Performance Trade-offs" \
            --ok-label "Select" \
            --cancel-label "Back" \
            --menu "\nConfigure optional speed vs visual trade-offs:" \
            15 58 4 \
            "1" "Crowd Override      (${CROWD_LABEL})" \
            "2" "Particles Override  (${PART_LABEL})" \
            "3" "Enable All Recommended" \
            "4" "Reset All to Default" \
            2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

        local rc=$?
        local pick
        pick=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
        rm -f "$CHOICE_TMP"

        if [ $rc -ne 0 ] || [ -z "$pick" ]; then
            break
        fi

        case "$pick" in
            "1") do_select_crowd ;;
            "2") do_select_particles ;;
            "3") do_tradeoffs_enable_all ;;
            "4") do_tradeoffs_reset_all ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 6. Main Interactive Loop
# ------------------------------------------------------------------------------
while true; do
    scan_status

    dialog \
        --backtitle "NFSU2 Graphic Tuner | $NFSU2_DIR" \
        --title "NFSU2 Graphic Tuner v1.2" \
        --ok-label "Select" \
        --cancel-label "Exit" \
        --menu "\nChoose a setting (or Exit):" \
        17 60 7 \
        "1" "Frame Rate Limit       (${CURRENT_FPS} FPS)" \
        "2" "Graphics Profile       (${CURRENT_GFX})" \
        "3" "Draw Distance          (${VIS_LABEL})" \
        "4" "Render Resolution      (${SCALE_LABEL})" \
        "5" "Car Reflection         (${REFL_LABEL})" \
        "6" "Car Headlights         (${HEAD_LABEL})" \
        "7" "Performance Trade-offs" \
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
        "3") do_select_draw_distance ;;
        "4") do_select_resolution ;;
        "5") do_select_half_reflect ;;
        "6") do_select_headlights ;;
        "7") do_tradeoffs_menu ;;
    esac
done

exit 0
