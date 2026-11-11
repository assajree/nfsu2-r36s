#!/bin/bash
# ==============================================================================
# Tool: NFSU2 Thai Manager (All-in-One Smart TUI for R36H / playOS / ArkOS)
# Description: Interactive Linux ncurses dialog interface providing 3 smart
#              toggle controls for Need for Speed: Underground 2:
#                1. Install / Uninstall Thai Edition
#                2. Switch Language: Thai <-> English
#                3. Toggle Intro Movies: Skip (Fast Boot 1s) <-> Restore
# UI Language: 100% Pure ASCII English (Console Font Invariant)
# ==============================================================================

# 1. Root Privilege Escalation
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
BACKUP_DIR="$NFSU2_DIR/.backup_thai"
CFG_FILE="$NFSU2_DIR/nfsu2.cfg"
MOVIES_DIR="$GAMEDATA/MOVIES"

# 3. Locate fb0_mirror Binary
MIRROR_BIN=""
for cand_bin in \
    "$SCRIPT_DIR/app/fb0_mirror" \
    "$SCRIPT_DIR/fb0_mirror" \
    "/roms/tools/nfsu2_thai/app/fb0_mirror" \
    "/roms/tools/setup_ui/fb0_mirror" \
    "/roms/tools/setup_ui/app/fb0_mirror"; do
    if [ -x "$cand_bin" ]; then
        MIRROR_BIN="$cand_bin"
        break
    fi
done

# 4. Detect Environment (playOS vs ArkOS) & Prepare Display
IS_PLAYOS=0
if pgrep -x "FindManager" >/dev/null 2>&1 || pgrep -x "playfe" >/dev/null 2>&1; then
    IS_PLAYOS=1
fi

MIRROR_PID=""

cleanup_all() {
    if [ -n "$MIRROR_PID" ]; then
        kill -TERM "$MIRROR_PID" 2>/dev/null || true
        wait "$MIRROR_PID" 2>/dev/null || true
    fi
    printf "\033c" > /dev/tty1 2>/dev/null || true
    if [ "$IS_PLAYOS" -eq 1 ]; then
        killall -CONT FindManager playfe 2>/dev/null || true
    fi
}
trap cleanup_all EXIT INT TERM

# Freeze playOS frontend if present
if [ "$IS_PLAYOS" -eq 1 ]; then
    killall -STOP FindManager playfe 2>/dev/null || true
fi

# Set readable console font on /dev/tty1
setfont /usr/share/consolefonts/Lat7-TerminusBold20x10.psf.gz -C /dev/tty1 2>/dev/null || \
setfont /usr/share/consolefonts/Lat7-Terminus16.psf.gz -C /dev/tty1 2>/dev/null || true
printf "\033c\e[?25l" > /dev/tty1 2>/dev/null || true

# Start fb0_mirror for KMSDRM streaming and controller input bridge
if [ -n "$MIRROR_BIN" ]; then
    "$MIRROR_BIN" >/dev/null 2>&1 &
    MIRROR_PID=$!
    sleep 0.3
fi

export TERM=linux

# 5. Intro files list
INTRO_FILES=("ealogo.vp6" "THX_logo.vp6" "FMVOpening.vp6" "PSA.vp6")

# 6. Status Scanner
scan_status() {
    # Check Thai Patch Status via marker flag
    THAI_INSTALLED=0
    if [ -f "$NFSU2_DIR/.nfsu2_thai" ]; then
        THAI_INSTALLED=1
    fi

    # Check Active Language
    CURRENT_LANG="English"
    if [ -f "$CFG_FILE" ]; then
        lang_val=$(grep "^NFSU2_LANG=" "$CFG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' \r\n')
        if [ "$lang_val" = "Thai" ]; then
            CURRENT_LANG="Thai"
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

# 7. Action Implementations

do_install_thai() {
    dialog --backtitle "NFSU2 Thai Manager" --title "Fast Boot Option" \
        --yesno "\nWould you like to enable Fast Boot (Skip Intro Movies)?\n\n  * Yes : Skip EA/THX/Opening logos (Direct boot to Title Screen)\n  * No  : Keep original intro movie playback\n\nSelect < Yes > or < No >, or press < ESC > to cancel." \
        12 66 < /dev/tty1 > /dev/tty1 2>/dev/null
    RC_FASTBOOT=$?

    if [ "$RC_FASTBOOT" -ne 0 ] && [ "$RC_FASTBOOT" -ne 1 ]; then
        return
    fi
    ENABLE_FASTBOOT=0
    [ "$RC_FASTBOOT" -eq 0 ] && ENABLE_FASTBOOT=1

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
        for bin_name in "nfsu2.aarch64.v10" "nfsu2.aarch64"; do
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
        # Source resolution
        for cand_bin in "$SCRIPT_DIR/gamedata/LANGUAGES/Thailand.bin" "$SCRIPT_DIR/Thailand.bin" "/roms/tools/nfsu2_thai/gamedata/LANGUAGES/Thailand.bin"; do
            if [ -f "$cand_bin" ]; then
                cp -f "$cand_bin" "$GAMEDATA/LANGUAGES/Thailand.bin"
                cp -f "$cand_bin" "$GAMEDATA/LANGUAGES/thailand.bin" 2>/dev/null || true
                break
            fi
        done
        for cand_lt in "$SCRIPT_DIR/gamedata/LANGUAGES/LanguageTextures.bin" "$SCRIPT_DIR/LanguageTextures.bin" "/roms/tools/nfsu2_thai/gamedata/LANGUAGES/LanguageTextures.bin"; do
            if [ -f "$cand_lt" ]; then
                cp -f "$cand_lt" "$GAMEDATA/LANGUAGES/LanguageTextures.bin"
                break
            fi
        done
        sleep 0.4

        echo "55" ; echo "XXX" ; echo "Patching SPEED2.EXE for Thai font streaming..." ; echo "XXX"
        PREPATCHED_EXE=""
        for cand_exe in "$SCRIPT_DIR/gamedata/SPEED2.EXE" "$SCRIPT_DIR/SPEED2.EXE" "/roms/tools/nfsu2_thai/gamedata/SPEED2.EXE"; do
            if [ -f "$cand_exe" ] && [ "$(stat -c%s "$cand_exe" 2>/dev/null || wc -c < "$cand_exe" | tr -d ' ')" -eq 4788224 ]; then
                PREPATCHED_EXE="$cand_exe"
                break
            fi
        done
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

        echo "75" ; echo "XXX" ; echo "Unlocking ARM64 cutscene and movie subtitles..." ; echo "XXX"
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

        # Apply Fast Boot if requested
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
            sleep 0.3
        fi

        touch "$NFSU2_DIR/.nfsu2_thai"
        sync
        echo "100" ; echo "XXX" ; echo "Installation completed successfully!" ; echo "XXX"
        sleep 0.6
    ) | dialog --backtitle "NFSU2 Thai Manager" --title "Installing Thai Edition" \
        --gauge "\nApplying Thai translation, HD fonts & subtitles..." 8 54 0 \
        > /dev/tty1 2>/dev/null

    if [ "$ENABLE_FASTBOOT" -eq 1 ]; then
        FASTBOOT_DESC="Intro movies skipped (Instant boot)"
    else
        FASTBOOT_DESC="Normal intro movies preserved"
    fi

    dialog --backtitle "NFSU2 Thai Manager" --title "Install Successful" \
        --msgbox "\n  [OK] Thai Localization Installed Successfully!\n\n  * Game Engine : Thai fonts and subtitles unlocked\n  * Language    : Set to Thai - Subtitles active\n  * Fast Boot   : $FASTBOOT_DESC\n  * Backup      : Saved original files in .backup_thai/" \
        12 60 < /dev/tty1 > /dev/tty1 2>/dev/null

    exit 0
}

do_uninstall_thai() {
    dialog --backtitle "NFSU2 Thai Manager" --title "Confirm Uninstallation" \
        --yesno "\nAre you sure you want to restore the original game files?\n\n* Restores original SPEED2.EXE and binaries from backup\n* Resets in-game language to English\n* Preserves player saves and .backup_thai/ safely" \
        11 60 < /dev/tty1 > /dev/tty1 2>/dev/null

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
            for bin_name in "nfsu2.aarch64.v10" "nfsu2.aarch64"; do
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
    ) | dialog --backtitle "NFSU2 Thai Manager" --title "Restoring Original Game" \
        --gauge "\nRestoring untouched files from backup..." 8 54 0 \
        > /dev/tty1 2>/dev/null

    dialog --backtitle "NFSU2 Thai Manager" --title "Restore Complete" \
        --msgbox "\n  [OK] Original Game Files Restored Successfully!\n\n  * SPEED2.EXE and binaries restored from backup\n  * In-game language reset to English\n  * Player save games are 100% safe" \
        11 58 < /dev/tty1 > /dev/tty1 2>/dev/null

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
        msg="\n  [OK] Language switched to: THAI\n\n  * Subtitles and game text will display in Thai."
    else
        msg="\n  [OK] Language switched to: ENGLISH\n\n  * Game text will display in original English."
    fi

    dialog --backtitle "NFSU2 Thai Manager" --title "Language Switched" \
        --msgbox "$msg" 9 56 < /dev/tty1 > /dev/tty1 2>/dev/null
}

do_skip_intro() {
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
    sync

    dialog --backtitle "NFSU2 Thai Manager" --title "Fast Boot Enabled" \
        --msgbox "\n  [OK] Fast Boot ENABLED - Instant Title Screen!\n\n  * Intro movies bypassed directly without video playback\n  * Game launches straight to Start Screen in ~1s - 0s flicker" \
        10 60 < /dev/tty1 > /dev/tty1 2>/dev/null
}

do_restore_intro() {
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
    sync

    if [ $rc -gt 0 ]; then
        dialog --backtitle "NFSU2 Thai Manager" --title "Intro Movies Restored" \
            --msgbox "\n  [OK] Intro Movies RESTORED Successfully!\n\n  * EA / THX logos, Opening FMV, and PSA will play normally" \
            9 58 < /dev/tty1 > /dev/tty1 2>/dev/null
    else
        dialog --backtitle "NFSU2 Thai Manager" --title "Notice" \
            --msgbox "\n  [i] No video backup files found to restore.\n\n  Fast Boot remains permanently active." \
            9 58 < /dev/tty1 > /dev/tty1 2>/dev/null
    fi
}

# 8. Main Interactive Loop
while true; do
    scan_status

    if [ "$THAI_INSTALLED" -eq 1 ]; then
        # When INSTALLED: Show full 3 options (Uninstall, Switch Language, Intro Toggle)
        TAG1="uninstall"
        LABEL1="Uninstall NFSU2 Thai"
        STATUS_PATCH="Installed"

        if [ "$CURRENT_LANG" = "Thai" ]; then
            TAG2="lang_eng"
            LABEL2="Switch Language -> English"
        else
            TAG2="lang_thai"
            LABEL2="Switch Language -> Thai"
        fi

        if [ "$INTRO_STATUS" = "Skipped" ]; then
            TAG3="intro_restore"
            LABEL3="Restore Intro Movies"
        elif [ "$INTRO_STATUS" = "Deleted" ]; then
            TAG3="intro_notice"
            LABEL3="Intro Movies Deleted"
        else
            TAG3="intro_skip"
            LABEL3="Skip Intro Movies"
        fi

        BACKTITLE="NFSU2 Thai Manager | Thai: $STATUS_PATCH | Lang: $CURRENT_LANG | Intro: $INTRO_STATUS"
        MENU_PROMPT="\nCurrent Settings:\n  * NFSU2 Thai   : $STATUS_PATCH\n  * Language     : $CURRENT_LANG\n  * Intro Movies : $INTRO_STATUS\n\nChoose an action below, or press < Exit > to quit:"

        CHOICE=$(dialog \
            --backtitle "$BACKTITLE" \
            --title "NFSU2 Thai Manager" \
            --ok-label "Select" \
            --cancel-label "Exit" \
            --menu "$MENU_PROMPT" \
            17 60 3 \
            "1" "$LABEL1" \
            "2" "$LABEL2" \
            "3" "$LABEL3" \
            --output-fd 3 3>&1 < /dev/tty1 > /dev/tty1 2>/dev/null)
    else
        # When NOT INSTALLED: Show ONLY Install option
        TAG1="install"
        LABEL1="Install NFSU2 Thai"
        STATUS_PATCH="Not Installed"

        BACKTITLE="NFSU2 Thai Manager | Thai: $STATUS_PATCH | Lang: $CURRENT_LANG | Intro: $INTRO_STATUS"
        MENU_PROMPT="\nCurrent Settings:\n  * NFSU2 Thai   : $STATUS_PATCH\n  * Language     : $CURRENT_LANG\n  * Intro Movies : $INTRO_STATUS\n\nChoose an action below, or press < Exit > to quit:"

        CHOICE=$(dialog \
            --backtitle "$BACKTITLE" \
            --title "NFSU2 Thai Manager" \
            --ok-label "Select" \
            --cancel-label "Exit" \
            --menu "$MENU_PROMPT" \
            15 60 1 \
            "1" "$LABEL1" \
            --output-fd 3 3>&1 < /dev/tty1 > /dev/tty1 2>/dev/null)
    fi

    RET=$?
    if [ $RET -ne 0 ] || [ -z "$CHOICE" ]; then
        break
    fi

    case "$CHOICE" in
        "1")
            if [ "$TAG1" = "install" ]; then
                do_install_thai
            else
                do_uninstall_thai
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
            if [ "$TAG3" = "intro_skip" ]; then
                do_skip_intro
            elif [ "$TAG3" = "intro_restore" ]; then
                do_restore_intro
            else
                dialog --backtitle "NFSU2 Thai Manager" --title "Notice" \
                    --msgbox "\n  [i] Intro videos were permanently deleted from storage.\n\n  Fast Boot remains permanently active." \
                    9 58 < /dev/tty1 > /dev/tty1 2>/dev/null
            fi
            ;;
    esac
done

exit 0
