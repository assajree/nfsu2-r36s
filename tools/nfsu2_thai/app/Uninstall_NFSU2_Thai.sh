#!/bin/bash
# ==============================================================================
# Tool: Uninstall NFSU2 Thai & Restore Backup (R36H / playOS)
# Description: Restores original SPEED2.EXE and configuration from backup,
#              removes Thai language tools menus from TOOLS, and preserves saves.
# Archetype: Archetype 3 (One-Shot Interactive Utility)
# Stem-Match: "uninstallnfsu2thai" contains "nfsu2thai" (Auto-hidden in playfe)
# ==============================================================================

# 1. Root Privilege Escalation
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E "$0" "$@"
fi

TOOLS_DIR="/roms/tools"

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
print_msg "   ถอนการติดตั้งภาษาไทย และกู้คืนไฟล์เดิม (NFSU2)        "
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
    print_msg "[!] ไม่พบโฟลเดอร์เกม NFSU2 ที่ /roms/ports/nfsu2/"
    wait_for_exit
    exit 1
fi

GAMEDATA="$NFSU2_DIR/gamedata"
BACKUP_DIR="$NFSU2_DIR/.backup_thai"
CFG_FILE="$NFSU2_DIR/nfsu2.cfg"

# 4. Restore from Backup
print_msg "[1/4] กำลังตรวจสอบไฟล์สำรอง (Backup)..."
if [ -d "$BACKUP_DIR" ]; then
    # 4.1 Restore SPEED2.EXE
    if [ -f "$BACKUP_DIR/SPEED2.EXE" ]; then
        cp -f "$BACKUP_DIR/SPEED2.EXE" "$GAMEDATA/SPEED2.EXE"
        cp -f "$BACKUP_DIR/SPEED2.EXE" "$GAMEDATA/speed2.exe"
        chmod 755 "$GAMEDATA/SPEED2.EXE" "$GAMEDATA/speed2.exe" 2>/dev/null || true
        chown ark:ark "$GAMEDATA/SPEED2.EXE" "$GAMEDATA/speed2.exe" 2>/dev/null || true
        print_msg "  -> กู้คืน SPEED2.EXE กลับเป็นไฟล์เดิมก่อนติดตั้ง [OK]"
    fi

    # 4.2 Restore ARM64 Binaries (nfsu2.aarch64.v10, nfsu2.aarch64)
    for bin_name in "nfsu2.aarch64.v10" "nfsu2.aarch64"; do
        if [ -f "$BACKUP_DIR/$bin_name" ]; then
            cp -f "$BACKUP_DIR/$bin_name" "$NFSU2_DIR/$bin_name"
            chmod 755 "$NFSU2_DIR/$bin_name" 2>/dev/null || true
            chown ark:ark "$NFSU2_DIR/$bin_name" 2>/dev/null || true
            print_msg "  -> กู้คืน $bin_name กลับเป็นไฟล์เดิมก่อนติดตั้ง [OK]"
        fi
    done

    # 4.3 Restore nfsu2.cfg & Force Language to English
    if [ -f "$BACKUP_DIR/nfsu2.cfg" ]; then
        cp -f "$BACKUP_DIR/nfsu2.cfg" "$CFG_FILE"
        print_msg "  -> กู้คืนการตั้งค่า nfsu2.cfg จาก Backup [OK]"
    fi
    if [ -f "$CFG_FILE" ]; then
        if grep -q "^NFSU2_LANG=" "$CFG_FILE"; then
            sed -i 's/^NFSU2_LANG=.*/NFSU2_LANG=English/' "$CFG_FILE" 2>/dev/null || true
        else
            echo "NFSU2_LANG=English" >> "$CFG_FILE"
        fi
        print_msg "  -> ปรับเปลี่ยนภาษาใน nfsu2.cfg เป็น English เรียบร้อย [OK]"
    fi

    # 4.4 Remove Thailand.bin if it was added by setup
    if [ ! -f "$BACKUP_DIR/.thailand_bin_preexisted" ] && [ -f "$GAMEDATA/LANGUAGES/Thailand.bin" ]; then
        rm -f "$GAMEDATA/LANGUAGES/Thailand.bin"
        print_msg "  -> ลบไฟล์ LANGUAGES/Thailand.bin ออกเรียบร้อย [OK]"
    fi

    # 4.5 Remove backup directory after successful restore
    rm -rf "$BACKUP_DIR"
    print_msg "  -> ล้างโฟลเดอร์สำรอง .backup_thai เรียบร้อย [OK]"
else
    print_msg "  [!] ไม่พบโฟลเดอร์ .backup_thai (อาจถูกลบไปแล้ว)"
    print_msg "  -> ปรับค่าภาษาใน nfsu2.cfg เป็น English อัตโนมัติ"
    if [ -f "$CFG_FILE" ]; then
        sed -i 's/^NFSU2_LANG=.*/NFSU2_LANG=English/' "$CFG_FILE" 2>/dev/null || true
    fi
fi

# 5. Preserve Save Games
print_msg ""
print_msg "[2/4] ตรวจสอบความปลอดภัยของ Save Game..."
SAVE_DIR="$GAMEDATA/AppData/Local/NFS Underground 2"
if [ -d "$SAVE_DIR" ]; then
    print_msg "  -> รักษา Save Game ของผู้เล่นทั้งหมดไว้คงเดิม ปลอดภัย 100% [OK]"
fi

# 6. Remove Launchers and Icons from /roms/tools/ (Preserves nfsu2_thai package)
print_msg ""
print_msg "[3/4] กำลังนำเมนูภาษาไทยออกจากหมวด TOOLS..."
rm -f "$TOOLS_DIR/NFSU2_Language_Thai.sh"
rm -f "$TOOLS_DIR/NFSU2_Language_English.sh"
rm -f "$TOOLS_DIR/Setup_NFSU2_Thai.sh"
rm -f "$TOOLS_DIR/Install_NFSU2_Tools.sh"
rm -f "$TOOLS_DIR/Uninstall_NFSU2_Tools.sh"
rm -f "$TOOLS_DIR/images/NFSU2_Language_Thai-thumb.png"
rm -f "$TOOLS_DIR/images/NFSU2_Language_English-thumb.png"
rm -f "$TOOLS_DIR/images/Setup_NFSU2_Thai-thumb.png"
rm -f "$TOOLS_DIR/images/Uninstall_NFSU2_Thai-thumb.png"
# ลบโฟลเดอร์ตกค้างรุ่นเก่า แต่คง /roms/tools/nfsu2_thai (รวม Install_NFSU2_Thai.sh) ไว้สำหรับติดตั้งใหม่
rm -rf "$TOOLS_DIR/nfsu2"

# Clean up gamelist.xml
python3 - << 'PYEOF' 2>/dev/null || true
import os
import xml.etree.ElementTree as ET

gamelist_path = "/roms/tools/gamelist.xml"
if os.path.exists(gamelist_path):
    try:
        tree = ET.parse(gamelist_path)
        root = tree.getroot()
        removed = False
        for g in list(root.findall("game")):
            p = g.find("path")
            if p is not None and p.text:
                norm_p = p.text.strip().lstrip("./")
                if "NFSU2" in norm_p or "nfsu2" in norm_p:
                    root.remove(g)
                    removed = True
        if removed:
            ET.indent(root, space="\t")
            with open(gamelist_path, "w", encoding="utf-8", newline="\n") as f:
                f.write('<?xml version="1.0"?>\n' + ET.tostring(root, encoding="unicode") + "\n")
    except Exception:
        pass
PYEOF
chown ark:ark /roms/tools/gamelist.xml 2>/dev/null || true

# 7. Final Sync & Self-Delete
print_msg ""
print_msg "[4/4] กำลังบันทึกข้อมูลและอัปเดตหน้าจอเมนู..."
sync

if systemctl is-active --quiet playfe.service 2>/dev/null; then
    systemctl restart playfe.service 2>/dev/null || true
fi

print_msg ""
print_msg "=========================================================="
print_msg "           [✓] ถอนการติดตั้งเรียบร้อยสมบูรณ์!             "
print_msg "=========================================================="
print_msg "  • ตัวเกมถูกกู้คืนกลับเป็นสถานะเดิมก่อนติดตั้งภาษาไทย"
print_msg "  • ภาษาในเกมถูกรีเซ็ตกลับเป็นภาษาอังกฤษ (English)"
print_msg "  • นำเมนูภาษาไทยออกจากหน้าจอ TOOLS ทั้งหมดเรียบร้อย"
print_msg "  • คงไฟล์แพ็กเกจติดตั้งไว้ที่ /roms/tools/nfsu2_thai/ (ติดตั้งใหม่ได้เสมอ)"
print_msg "  • ไฟล์ Save Game ของท่านยังคงอยู่ครบถ้วน ปลอดภัย 100%"
print_msg "=========================================================="

# Remove this launcher script file after message is displayed
rm -f "$TOOLS_DIR/Uninstall_NFSU2_Thai.sh" 2>/dev/null || true

wait_for_exit
exit 0
