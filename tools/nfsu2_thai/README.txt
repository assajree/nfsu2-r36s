==============================================================================
NFSU2 Thai Language & Tools for R36H / R36S (playOS)
==============================================================================

ชุดติดตั้งภาษาไทยสำหรับ Need for Speed: Underground 2 บนเครื่อง R36H:

1. วิธีติดตั้ง (Auto-Setup during Install):
   - คัดลอกโฟลเดอร์ asset เกม PC (CARS, GLOBAL, TRACKS, SOUND, MOVIES)
     ไปวางไว้ที่ /roms/ports/nfsu2/gamedata/ ให้เรียบร้อย
   - รันคำสั่งติดตั้งผ่าน Terminal / SSH หรือคัดลอกไฟล์ลง /roms/tools/:
     sudo bash Install_NFSU2_Thai.sh
   - ตัวสคริปต์จะทำการ:
     * สำรองไฟล์เดิมไว้ที่ .backup_thai/
     * ติดตั้ง SPEED2.EXE ภาษาไทย และ LANGUAGES/Thailand.bin
     * ปลดล็อกระบบซับไตเติลภาษาไทย (Cutscenes + Movies)
     * ตั้งค่าเริ่มต้นเป็นภาษาไทยใน nfsu2.cfg (NFSU2_LANG=Thai)
     * ติดตั้งเมนูสลับภาษาบนหน้าจอเครื่อง R36H ในหมวด TOOLS ให้อัตโนมัติ

2. เมนูบนเครื่อง R36H (หมวด TOOLS):
   - NFSU2_Language_Thai.sh:
     เมนูกดสลับภาษาเป็น "ภาษาไทย" ทันที แสดงผลออกจอ /dev/tty1
   - NFSU2_Language_English.sh:
     เมนูกดสลับภาษาเป็น "English" ทันที แสดงผลออกจอ /dev/tty1
   - Uninstall_NFSU2_Thai.sh:
     กู้คืนไฟล์เกมเดิมเป็นภาษาอังกฤษ และนำเมนูภาษาไทยออกจากหมวด TOOLS ทั้งหมด

3. ระบบ Stem-Matching Auto-Hide (ตามคู่มือ AGENTS.md):
   - โฟลเดอร์แพ็กเกจชื่อ /roms/tools/nfsu2_thai (ความยาว 9 ตัวอักษร)
   - Launcher: Uninstall_NFSU2_Thai.sh -> "uninstallnfsu2thai" (มี nfsu2thai)
   - playfe จะข้ามการสแกนโฟลเดอร์ nfsu2_thai โดยอัตโนมัติ ทำให้เมนู TOOLS สวยงามและไม่รก
==============================================================================
