==============================================================================
NFSU2 Reset Controls — Save Controller Repair & Backup/Restore TUI (R36H/R36S)
==============================================================================

เครื่องมือซ่อมแซมและรีเซ็ตการตั้งค่าปุ่ม (Controls) ในไฟล์เซฟของเกม
Need for Speed: Underground 2 ให้กลับมาเป็นค่าเริ่มต้นโรงงาน (Factory Default)
โดยที่ข้อมูลความคืบหน้า (เงิน, รถใน Garage, ด่าน Career, SMS) อยู่ครบ 100%

โครงสร้างเมนูใช้งาน (All-in-One TUI):
------------------------------------------------------------------------------
1. Reset Controls to Default
   - เลือกซ่อมเฉพาะโปรไฟล์ที่ต้องการ หรือเลือก All Profiles เพื่อซ่อมทั้งหมด
   - สำรองไฟล์เซฟเดิมไว้ที่ /roms/ports/nfsu2/.backup_controls/<Profile>.bak อัตโนมัติ
   - ล้างบล็อกตั้งค่าปุ่ม (0xD278 - 0xD6B6) และคำนวณ Checksum 3 ชั้นใหม่ (nfsu2Crc)
   - เมื่อเสร็จสิ้นจะกลับสู่หน้าเมนูหลัก
2. Restore Save from Backup
   - เลือกกู้คืนไฟล์เซฟจาก .bak รายโปรไฟล์ หรือกู้คืนทั้งหมด
   - เมื่อเสร็จสิ้นจะกลับสู่หน้าเมนูหลัก

มาตรฐาน PortMaster & playOS (Zero fb0_mirror, Flat Side-by-Side):
------------------------------------------------------------------------------
- รองรับทั้ง /roms/ports/ (เป้าหมายหลัก) และ /roms/tools/
- โครงสร้างโฟลเดอร์แบบ Side-by-Side ชั้นเดียว (Flat 1-Level, no app/)
- ใช้ Native /dev/tty1 Console + gptokeyb รองรับการกดปุ่มแบบ Dynamic A/B ตาม playfe
- ซ่อนโฟลเดอร์ข้อมูลอัตโนมัติด้วย Stem-Matching (nfsu2resetcontrols) เมนูไม่รก

วิธีติดตั้งใช้งานบนเครื่อง R36H / R36S:
------------------------------------------------------------------------------
[วิธีที่ 1 - แนะนำ] ติดตั้งใน Ports (/roms/ports/):
  คัดลอกไฟล์ต่อไปนี้ไปไว้ที่ /roms/ports/
    - NFSU2_Reset_Controls.sh
    - images/NFSU2_Reset_Controls-thumb.png
    - โฟลเดอร์ nfsu2resetcontrols/

[วิธีที่ 2] ติดตั้งใน Tools (/roms/tools/):
  คัดลอกทั้งโฟลเดอร์ nfsu2_reset_controls ไปไว้ที่:
    /roms/tools/nfsu2_reset_controls/
==============================================================================
