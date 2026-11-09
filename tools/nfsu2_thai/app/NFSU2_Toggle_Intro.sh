#!/bin/bash
# ==============================================================================
# Tool: NFSU2 Toggle Intro Movies (Fast Boot) for R36H (playOS)
# Description: Toggles skipping of intro movies (EA, THX, FMVOpening, PSA)
#              for instant 1-second boot directly to Start Screen.
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
print_msg "      NFSU2 Intro Movies Toggle (Fast Boot Utility)       "
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

BLANK_SRC="$MOVIES_DIR/blank.vp6"
if [ ! -f "$BLANK_SRC" ]; then
    print_msg "[!] ERROR: blank.vp6 template not found in $MOVIES_DIR"
    wait_for_exit
    exit 1
fi

# List of intro movies to toggle
INTRO_FILES=("ealogo.vp6" "THX_logo.vp6" "FMVOpening.vp6" "PSA.vp6")

# Check if Fast Boot is currently active
# (Active if FMVOpening.vp6 is <= 2500 bytes or backup _FMVOpening.vp6 exists)
FAST_BOOT_ACTIVE=0
if [ -f "$MOVIES_DIR/_FMVOpening.vp6" ] || [ "$(stat -c%s "$MOVIES_DIR/FMVOpening.vp6" 2>/dev/null || wc -c < "$MOVIES_DIR/FMVOpening.vp6" | tr -d ' ')" -le 2500 ]; then
    FAST_BOOT_ACTIVE=1
fi

if [ "$FAST_BOOT_ACTIVE" -eq 1 ]; then
    # Mode: RESTORE ORIGINAL INTRO MOVIES
    print_msg "Current Status: Fast Boot is ENABLED (Intro skipped)"
    print_msg "Action: Restoring original intro videos..."
    print_msg ""

    for f in "${INTRO_FILES[@]}"; do
        backup_file="$MOVIES_DIR/_$f"
        target_file="$MOVIES_DIR/$f"
        if [ -f "$backup_file" ]; then
            cp -f "$backup_file" "$target_file"
            rm -f "$backup_file"
            print_msg "  -> Restored $f [OK]"
        fi
    done

    sync
    print_msg ""
    print_msg "=========================================================="
    print_msg "       [OK] Fast Boot DISABLED (Original Movies Restored) "
    print_msg "=========================================================="
    print_msg "  * EA / THX logos, Opening FMV, and PSA will play normally"
    print_msg "=========================================================="
else
    # Mode: ENABLE FAST BOOT (SKIP INTRO)
    print_msg "Current Status: Original intro movies are ACTIVE"
    print_msg "Action: Enabling Fast Boot (cutting intro movies)..."
    print_msg ""

    for f in "${INTRO_FILES[@]}"; do
        target_file="$MOVIES_DIR/$f"
        backup_file="$MOVIES_DIR/_$f"
        if [ -f "$target_file" ]; then
            # Backup original if not already backed up
            if [ ! -f "$backup_file" ]; then
                cp -f "$target_file" "$backup_file"
            fi
            # Replace with blank.vp6
            cp -f "$BLANK_SRC" "$target_file"
            print_msg "  -> Skipped $f [OK]"
        fi
    done

    sync
    print_msg ""
    print_msg "=========================================================="
    print_msg "       [OK] Fast Boot ENABLED (Instant Title Screen!)     "
    print_msg "=========================================================="
    print_msg "  * Intro movies replaced with instantaneous dummy video"
    print_msg "  * Game will launch directly to the Start Screen in ~1 sec"
    print_msg "  * Run this tool again at any time to restore videos"
    print_msg "=========================================================="
fi

wait_for_exit
exit 0
