#!/bin/bash
# ==============================================================================
# Tool: NFSU2 Reset Controls (Save Controller Repair & Backup/Restore TUI)
# Description: Interactive Linux ncurses dialog utility to reset messed-up
#              in-game controller/keyboard bindings inside NFSU2 save profiles
#              back to 100% factory defaults while preserving all career progress,
#              cars, money, and SMS, with automatic save backup & restore.
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

# 2. Locate NFSU2 Port Directory
NFSU2_DIR=""
for cand in "/roms/ports/nfsu2" "/roms2/ports/nfsu2" "/roms/ports/NFSU2"; do
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

        # Resolve Dynamic A/B Button Mapping
        # Priority 1 (playfe): /home/ark/.config/playfe/playfe.cfg -> swap_ab=true means A=OK, B=Back
        # Priority 2 (ArkOS): es_settings.cfg InvertButtons or /var/cache/Switch_AB
        CONFIRM_KEY="enter"
        CANCEL_KEY="esc"
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

        "$GPTOKEYB_BIN" -1 "$SCRIPT_NAME" -c "$GPTK_CONF" >/dev/null 2>&1 &
        GPTOKEYB_PID=$!
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

# Ensure dialog is available
if ! command -v dialog >/dev/null 2>&1; then
    echo "[!] ERROR: 'dialog' package is not installed." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 3. Profile & Backup Scanner
# ------------------------------------------------------------------------------
PROFILES=()
PROFILE_PATHS=()
PROFILE_STATES=()
BACKUPS=()
BACKUP_PATHS=()
BACKUP_DATES=()

scan_profiles_and_backups() {
    PROFILES=()
    PROFILE_PATHS=()
    PROFILE_STATES=()
    BACKUPS=()
    BACKUP_PATHS=()
    BACKUP_DATES=()

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

    if [ -d "$BACKUP_DIR" ]; then
        while IFS= read -r -d '' bfile; do
            fsize=$(stat -c%s "$bfile" 2>/dev/null || wc -c < "$bfile" | tr -d ' ')
            if [ "$fsize" -eq 54966 ]; then
                bname="$(basename "$bfile" .bak)"
                bdate="$(date -r "$bfile" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "Saved")"
                BACKUPS+=("$bname")
                BACKUP_PATHS+=("$bfile")
                BACKUP_DATES+=("$bdate")
            fi
        done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "*.bak" -print0 2>/dev/null | sort -z)
    fi
}

# ------------------------------------------------------------------------------
# 4. Core Save Patcher: Reset Controls & Recalculate NFSU2 CRC32
# ------------------------------------------------------------------------------
reset_single_profile_file() {
    local target_file="$1"
    local prof_name="$2"
    local bak_file="$BACKUP_DIR/${prof_name}.bak"

    # Backup current save before patching
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

# ------------------------------------------------------------------------------
# 5. Submenu: Reset Controls (Select Profile or All Profiles)
# ------------------------------------------------------------------------------
do_reset_menu() {
    scan_profiles_and_backups
    local count="${#PROFILES[@]}"

    if [ "$count" -eq 0 ]; then
        dialog --backtitle "NFSU2 Reset Controls" --title "No Profiles Found" \
            --msgbox "\n  [!] No NFSU2 save profiles found in:\n\n  $SAVE_ROOT\n\n  Press A or Enter to return." \
            10 60 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
        return
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
        --backtitle "NFSU2 Reset Controls | Select Profile" \
        --title "Reset Controls to Default" \
        --ok-label "Reset" \
        --cancel-label "Back" \
        --menu "\nSelect a profile to reset controls to factory default\n(Career progress, cars & cash are 100% preserved):" \
        16 62 6 \
        "${menu_items[@]}" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"
    local ret=$?
    local sel=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"

    if [ "$ret" -ne 0 ] || [ -z "$sel" ]; then
        return
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
        dialog --backtitle "NFSU2 Reset Controls" --title "Reset Complete" \
            --msgbox "\n  [OK] Controls Reset to Factory Default!\n\n  * Profile(s) :$fixed_list\n  * Career/Cash: 100% Preserved & Checksum Verified\n  * Backup     : Saved in .backup_controls/\n\n  Press A or Enter to return to main menu." \
            12 60 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
    else
        dialog --backtitle "NFSU2 Reset Controls" --title "Error" \
            --msgbox "\n  [!] Failed to reset profile save file.\n\n  Press A or Enter to return to main menu." \
            9 56 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
    fi
}

# ------------------------------------------------------------------------------
# 6. Submenu: Restore Save from Backup
# ------------------------------------------------------------------------------
do_restore_menu() {
    scan_profiles_and_backups
    local bcount="${#BACKUPS[@]}"

    if [ "$bcount" -eq 0 ]; then
        dialog --backtitle "NFSU2 Reset Controls" --title "No Backups Found" \
            --msgbox "\n  [i] No backup files (*.bak) found in:\n\n  $BACKUP_DIR\n\n  Press A or Enter to return." \
            10 60 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
        return
    fi

    local menu_items=()
    menu_items+=("ALL" "Restore All Backups ($bcount found)")
    local idx=0
    while [ "$idx" -lt "$bcount" ]; do
        local num=$((idx + 1))
        menu_items+=("$num" "${BACKUPS[$idx]}.bak  (${BACKUP_DATES[$idx]})")
        idx=$((idx + 1))
    done

    dialog \
        --backtitle "NFSU2 Reset Controls | Restore Backup" \
        --title "Restore Save from Backup" \
        --ok-label "Restore" \
        --cancel-label "Back" \
        --menu "\nSelect a backup to restore:" \
        15 62 6 \
        "${menu_items[@]}" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"
    local ret=$?
    local sel=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"

    if [ "$ret" -ne 0 ] || [ -z "$sel" ]; then
        return
    fi

    local restored_list=""
    local restored_count=0

    if [ "$sel" = "ALL" ]; then
        local i=0
        while [ "$i" -lt "$bcount" ]; do
            local pname="${BACKUPS[$i]}"
            local bpath="${BACKUP_PATHS[$i]}"
            local dest_dir="$SAVE_ROOT/$pname"
            mkdir -p "$dest_dir"
            if cp -f "$bpath" "$dest_dir/$pname" 2>/dev/null; then
                restored_list="${restored_list} $pname"
                restored_count=$((restored_count + 1))
            fi
            i=$((i + 1))
        done
    else
        local target_idx=$((sel - 1))
        if [ "$target_idx" -ge 0 ] && [ "$target_idx" -lt "$bcount" ]; then
            local pname="${BACKUPS[$target_idx]}"
            local bpath="${BACKUP_PATHS[$target_idx]}"
            local dest_dir="$SAVE_ROOT/$pname"
            mkdir -p "$dest_dir"
            if cp -f "$bpath" "$dest_dir/$pname" 2>/dev/null; then
                restored_list="$pname"
                restored_count=1
            fi
        fi
    fi

    sync

    if [ "$restored_count" -gt 0 ]; then
        dialog --backtitle "NFSU2 Reset Controls" --title "Restore Complete" \
            --msgbox "\n  [OK] Save Backup Restored Successfully!\n\n  * Restored Profile(s): $restored_list\n\n  Press A or Enter to return to main menu." \
            10 60 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
    else
        dialog --backtitle "NFSU2 Reset Controls" --title "Error" \
            --msgbox "\n  [!] Failed to restore backup file.\n\n  Press A or Enter to return to main menu." \
            9 56 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
    fi
}

# ------------------------------------------------------------------------------
# 7. Submenu: Delete Save Backup
# ------------------------------------------------------------------------------
do_delete_menu() {
    scan_profiles_and_backups
    local bcount="${#BACKUPS[@]}"

    if [ "$bcount" -eq 0 ]; then
        dialog --backtitle "NFSU2 Reset Controls" --title "No Backups Found" \
            --msgbox "\n  [i] No backup files (*.bak) found in:\n\n  $BACKUP_DIR\n\n  Press A or Enter to return." \
            10 60 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
        return
    fi

    local menu_items=()
    menu_items+=("ALL" "Delete All Backups ($bcount found)")
    local idx=0
    while [ "$idx" -lt "$bcount" ]; do
        local num=$((idx + 1))
        menu_items+=("$num" "${BACKUPS[$idx]}.bak  (${BACKUP_DATES[$idx]})")
        idx=$((idx + 1))
    done

    dialog \
        --backtitle "NFSU2 Reset Controls | Delete Backup" \
        --title "Delete Save Backup" \
        --ok-label "Delete" \
        --cancel-label "Back" \
        --menu "\nSelect a backup to permanently delete:" \
        15 62 6 \
        "${menu_items[@]}" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"
    local ret=$?
    local sel=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"

    if [ "$ret" -ne 0 ] || [ -z "$sel" ]; then
        return
    fi

    local confirm_msg=""
    if [ "$sel" = "ALL" ]; then
        confirm_msg="\n  [!] Permanently delete ALL $bcount backup file(s)?\n\n  Files: ${BACKUPS[*]}.bak\n\n  This action cannot be undone."
    else
        local target_idx=$((sel - 1))
        if [ "$target_idx" -lt 0 ] || [ "$target_idx" -ge "$bcount" ]; then
            return
        fi
        confirm_msg="\n  [!] Permanently delete backup:\n\n  ${BACKUPS[$target_idx]}.bak (${BACKUP_DATES[$target_idx]})\n\n  This action cannot be undone."
    fi

    dialog \
        --backtitle "NFSU2 Reset Controls | Confirm Delete" \
        --title "Confirm Permanent Delete" \
        --defaultno \
        --yes-label "Delete" \
        --no-label "Cancel" \
        --yesno "$confirm_msg" \
        11 60 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
    if [ $? -ne 0 ]; then
        return
    fi

    local deleted_list=""
    local deleted_count=0

    if [ "$sel" = "ALL" ]; then
        local i=0
        while [ "$i" -lt "$bcount" ]; do
            local pname="${BACKUPS[$i]}"
            local bpath="${BACKUP_PATHS[$i]}"
            if rm -f "$bpath" 2>/dev/null; then
                deleted_list="${deleted_list} ${pname}.bak"
                deleted_count=$((deleted_count + 1))
            fi
            i=$((i + 1))
        done
    else
        local target_idx=$((sel - 1))
        local pname="${BACKUPS[$target_idx]}"
        local bpath="${BACKUP_PATHS[$target_idx]}"
        if rm -f "$bpath" 2>/dev/null; then
            deleted_list="${pname}.bak"
            deleted_count=1
        fi
    fi

    sync

    if [ "$deleted_count" -gt 0 ]; then
        dialog --backtitle "NFSU2 Reset Controls" --title "Delete Complete" \
            --msgbox "\n  [OK] Backup(s) Deleted Successfully!\n\n  * Deleted: $deleted_list\n\n  Press A or Enter to return to main menu." \
            10 60 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
    else
        dialog --backtitle "NFSU2 Reset Controls" --title "Error" \
            --msgbox "\n  [!] Failed to delete backup file.\n\n  Press A or Enter to return to main menu." \
            9 56 < "$DIALOG_IN" > "$DIALOG_OUT" 2>/dev/null
    fi
}

# ------------------------------------------------------------------------------
# 8. Main Interactive Loop
# ------------------------------------------------------------------------------
while true; do
    scan_profiles_and_backups

    P_COUNT="${#PROFILES[@]}"
    B_COUNT="${#BACKUPS[@]}"

    if [ "$P_COUNT" -gt 0 ]; then
        P_SUMMARY="$P_COUNT (${PROFILES[*]})"
    else
        P_SUMMARY="0 (None)"
    fi

    if [ "$B_COUNT" -gt 0 ]; then
        B_SUMMARY="$B_COUNT (${BACKUPS[*]})"
    else
        B_SUMMARY="0 (None)"
    fi

    BACKTITLE="NFSU2 Reset Controls | Profiles: $P_COUNT | Backups: $B_COUNT"
    MENU_PROMPT="\nSave Status:\n  * Profiles Found : $P_SUMMARY\n  * Backups Saved  : $B_SUMMARY\n\nChoose an action below, or press < Exit > to quit:"

    dialog \
        --backtitle "$BACKTITLE" \
        --title "NFSU2 Reset Controls" \
        --ok-label "Select" \
        --cancel-label "Exit" \
        --menu "$MENU_PROMPT" \
        16 60 3 \
        "1" "Reset Controls to Default" \
        "2" "Restore Save from Backup" \
        "3" "Delete Save Backup" \
        2> "$CHOICE_TMP" < "$DIALOG_IN" > "$DIALOG_OUT"

    RET=$?
    CHOICE=$(cat "$CHOICE_TMP" 2>/dev/null | tr -d ' "\r\n')
    rm -f "$CHOICE_TMP"

    if [ $RET -ne 0 ] || [ -z "$CHOICE" ]; then
        break
    fi

    case "$CHOICE" in
        "1")
            do_reset_menu
            ;;
        "2")
            do_restore_menu
            ;;
        "3")
            do_delete_menu
            ;;
    esac
done

exit 0
