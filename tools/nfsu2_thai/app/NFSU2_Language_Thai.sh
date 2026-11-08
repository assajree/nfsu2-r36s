#!/bin/bash
# ==============================================================================
# Tool: NFSU2 Language Switcher -> Thai (ภาษาไทย) for R36H (playOS)
# Description: Switches Need for Speed: Underground 2 language to Thai
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
    print_msg "\n  >>> กดปุ่มใดก็ได้บนเครื่อง หรือ คีย์บอร์ด เพื่อปิดหน้านี้ <<<"
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
    kill -9 $INPUT_PIDS 2>/dev/null || true
}

clear > /dev/tty1 2>/dev/null || true
clear 2>/dev/null || true

print_msg "=========================================================="
print_msg "      เปลี่ยนภาษา NFSU2 เป็น: ภาษาไทย (THAI)             "
print_msg "=========================================================="
print_msg ""

# 3. Locate NFSU2 Port Directory
NFSU2_DIR=""
for cand in "/roms/ports/nfsu2" "/roms2/ports/nfsu2" "/roms/ports/NFSU2"; do
    if [ -d "$cand" ]; then
        NFSU2_DIR="$(cd "$cand" && pwd)"
        break
    fi
done

if [ -z "$NFSU2_DIR" ]; then
    print_msg "[!] ไม่พบโฟลเดอร์เกม NFSU2 ที่ /roms/ports/nfsu2/"
    wait_for_exit
    exit 1
fi

CFG_FILE="$NFSU2_DIR/nfsu2.cfg"
EXE="$NFSU2_DIR/gamedata/SPEED2.EXE"
if [ ! -f "$EXE" ] && [ -f "$NFSU2_DIR/gamedata/speed2.exe" ]; then
    EXE="$NFSU2_DIR/gamedata/speed2.exe"
fi

# 4. Check SPEED2.EXE Thai patch status
if [ -f "$EXE" ]; then
    python3 -c '
import sys
patches = [
    (0x39A6E8, b"LANGUAGES\\THAILAND.BIN"),
    (0x39A700, b"THAILAND"),
    (0x3F6F40, b"\x9d\x61\x15\x48"),
    (0x3F6F48, b"\xff\x23\x38\xa7"),
    (0x3F70C0, b"\x0b\x00\x00\x00"),
    (0x3F7108, b"\x0b\x00\x00\x00"),
]
data = open("'"$EXE"'", "rb").read()
if len(data) == 4788224 and not all(data[off:off+len(val)] == val for off, val in patches):
    with open("'"$EXE"'", "r+b") as f:
        for off, val in patches:
            f.seek(off); f.write(val)
' 2>/dev/null || true
fi

# 5. Update nfsu2.cfg
if [ ! -f "$CFG_FILE" ]; then
    cat << 'EOF' > "$CFG_FILE"
NFSU2_GRAPHICS=performance
NFSU2_FPS=30
NFSU2_LANG=Thai
NFSU2_DRAW_DIST=200
NFSU2_REGISTRY_EXTRA=""
EOF
else
    if grep -q "^NFSU2_LANG=" "$CFG_FILE"; then
        sed -i 's/^NFSU2_LANG=.*/NFSU2_LANG=Thai/' "$CFG_FILE"
    else
        echo "NFSU2_LANG=Thai" >> "$CFG_FILE"
    fi
fi

sync
print_msg "  [✓] ทำการตั้งค่าภาษาไทยเรียบร้อยแล้ว!"
print_msg "  -> NFSU2_LANG=Thai ใน $CFG_FILE"
print_msg ""
print_msg "=========================================================="
print_msg "     เมื่อเข้าเกมครั้งต่อไป ตัวเกมจะแสดงผลเป็นภาษาไทย      "
print_msg "=========================================================="

wait_for_exit
exit 0
