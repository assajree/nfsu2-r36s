#!/bin/bash
# ==============================================================================
# Tool: NFSU2 Restore Intro Movies for R36H (playOS)
# Description: Restores original intro movies (EA, THX, FMVOpening, PSA)
#              from backups (_*.vp6) back to active playback.
# Archetype: Archetype 3 (One-Shot Interactive Utility)
# ==============================================================================

# 1. Root Privilege Escalation
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E "$0" "$@"
fi

# 2. Output Formatting & Dual-Execution Support
print_msg() {
    echo -e "$1"
    if [ -w /dev/tty1 ]; then
        echo -e "$1" > /dev/tty1 2>/dev/null || true
    fi
}

wait_for_exit() {
    print_msg "\n  >>> Press any button or key to close <<<"
    sleep 0.6
    (
        if [ -t 0 ]; then
            read -s -n 1 -r 2>/dev/null || sleep 86400
        elif [ -c /dev/tty1 ]; then
            read -s -n 1 -r < /dev/tty1 2>/dev/null || sleep 86400
        else
            read -s -n 1 -r 2>/dev/null || sleep 86400
        fi
    ) &
    INPUT_PIDS="$!"
    for ev in /dev/input/event*; do
        if [ -r "$ev" ]; then
            ( dd if="$ev" of=/dev/null bs=16 count=1 2>/dev/null ) &
            INPUT_PIDS="$INPUT_PIDS $!"
        fi
    done
    wait -n $INPUT_PIDS 2>/dev/null || sleep 2
    disown $INPUT_PIDS 2>/dev/null || true
    kill -9 $INPUT_PIDS 2>/dev/null || true
}

clear > /dev/tty1 2>/dev/null || true
clear 2>/dev/null || true

print_msg "=========================================================="
print_msg "        NFSU2 Restore Intro Movies (Full Playback)        "
print_msg "=========================================================="
print_msg ""

# 3. Locate NFSU2 Port Directory
NFSU2_DIR=""
for cand in "/roms/ports/nfsu2" "/roms2/ports/nfsu2" "/roms/ports/NFSU2"; do
    if [ -d "$cand" ] && [ -d "$cand/gamedata" ]; then
        NFSU2_DIR="$(cd "$cand" && pwd)"
        break
    fi
done

if [ -z "$NFSU2_DIR" ]; then
    print_msg "[!] ERROR: NFSU2 game folder not found at /roms/ports/nfsu2/"
    wait_for_exit
    exit 1
fi

MOVIES_DIR="$NFSU2_DIR/gamedata/MOVIES"
if [ ! -d "$MOVIES_DIR" ]; then
    print_msg "[!] ERROR: MOVIES folder not found at $MOVIES_DIR"
    wait_for_exit
    exit 1
fi

# List of intro movies to restore
INTRO_FILES=("ealogo.vp6" "THX_logo.vp6" "FMVOpening.vp6" "PSA.vp6")

print_msg "Action: Restoring original intro videos from backups..."
print_msg ""

RESTORE_COUNT=0
ALREADY_ACTIVE=0

for f in "${INTRO_FILES[@]}"; do
    backup_file="$MOVIES_DIR/_$f"
    target_file="$MOVIES_DIR/$f"

    if [ -f "$backup_file" ]; then
        rm -f "$target_file" 2>/dev/null || true
        mv -f "$backup_file" "$target_file"
        print_msg "  -> Restored $f [OK]"
        RESTORE_COUNT=$((RESTORE_COUNT + 1))
    elif [ -f "$target_file" ]; then
        file_sz=$(stat -c%s "$target_file" 2>/dev/null || wc -c < "$target_file" | tr -d ' ')
        if [ "$file_sz" -gt 2500 ]; then
            print_msg "  -> $f already active [OK]"
            ALREADY_ACTIVE=$((ALREADY_ACTIVE + 1))
        else
            print_msg "  [!] Notice: $f is a dummy file with no backup."
        fi
    else
        print_msg "  [!] Notice: Neither $f nor backup _$f found."
    fi
done

sync
print_msg ""

if [ "$RESTORE_COUNT" -eq 0 ] && [ "$ALREADY_ACTIVE" -eq 0 ]; then
    print_msg "=========================================================="
    print_msg "       [INFO] No Video Backups Found to Restore           "
    print_msg "=========================================================="
    print_msg "  * Original intro video files were deleted from storage."
    print_msg "  * Fast Boot remains active (Instant Title Screen)."
    print_msg "  * To restore videos, copy .vp6 files back from PC into:"
    print_msg "    gamedata/MOVIES/"
    print_msg "=========================================================="
else
    print_msg "=========================================================="
    print_msg "       [OK] Intro Movies RESTORED Successfully!           "
    print_msg "=========================================================="
    print_msg "  * EA / THX logos, Opening FMV, and PSA will play normally"
    print_msg "  * Run 'NFSU2_Intro_Skip.sh' anytime to enable Fast Boot"
    print_msg "=========================================================="
fi

wait_for_exit
exit 0
