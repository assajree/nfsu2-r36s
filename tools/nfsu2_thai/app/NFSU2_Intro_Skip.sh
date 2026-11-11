#!/bin/bash
# ==============================================================================
# Tool: NFSU2 Skip Intro Movies (Fast Boot) for R36H (playOS)
# Description: Skips intro movies (EA, THX, FMVOpening, PSA) by moving them
#              to backups (_*.vp6) for instant 1-second boot with 0s flicker.
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
print_msg "        NFSU2 Skip Intro Movies (Fast Boot 1s)            "
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

# List of intro movies to skip
INTRO_FILES=("ealogo.vp6" "THX_logo.vp6" "FMVOpening.vp6" "PSA.vp6")

print_msg "Action: Bypassing intro movies for Fast Boot..."
print_msg ""

SKIPPED_COUNT=0
ALREADY_SKIPPED=0

for f in "${INTRO_FILES[@]}"; do
    target_file="$MOVIES_DIR/$f"
    backup_file="$MOVIES_DIR/_$f"

    if [ -f "$target_file" ]; then
        file_sz=$(stat -c%s "$target_file" 2>/dev/null || wc -c < "$target_file" | tr -d ' ')
        if [ "$file_sz" -le 2500 ]; then
            # Clean up old dummy file if present
            rm -f "$target_file"
            print_msg "  -> Cleared old dummy $f [OK]"
        else
            if [ ! -f "$backup_file" ]; then
                mv -f "$target_file" "$backup_file"
            else
                rm -f "$target_file"
            fi
            print_msg "  -> Bypassed $f (Moved to _$f) [OK]"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        fi
    elif [ -f "$backup_file" ]; then
        print_msg "  -> $f already skipped [OK]"
        ALREADY_SKIPPED=$((ALREADY_SKIPPED + 1))
    else
        print_msg "  -> $f not present (Skipped) [OK]"
    fi
done

sync
print_msg ""
print_msg "=========================================================="
print_msg "       [OK] Fast Boot ENABLED (Instant Title Screen!)     "
print_msg "=========================================================="
print_msg "  * Intro movies bypassed directly without video playback"
print_msg "  * Game launches directly to Start Screen with 0s flicker"
print_msg "  * Run 'NFSU2_Intro_Restore.sh' anytime to restore videos"
print_msg "=========================================================="

wait_for_exit
exit 0
