==============================================================================
NFSU2 Thai & Controls Manager — All-in-One Suite for R36H / R36S (playOS / ArkOS)
==============================================================================

ชุดเครื่องมือจัดการภาษาไทย ปุ่มจอย และกราฟิกสำหรับ Need for Speed: Underground 2 บนเครื่อง R36H / R36S
ประกอบด้วย 3 โปรแกรมหลัก:
  1. NFSU2_Thai.sh     — ติดตั้ง runtime + ภาษาไทย, ซับไตเติล, Skip Intro และ Attract Mode (v2.0)
  2. NFSU2_Controls.sh — ตั้งค่าปุ่มจอย (Presets / Custom) และรีเซ็ตปุ่มในเซฟ
  3. NFSU2_Graphics.sh — ปรับแต่งเฟรมเรต กราฟิก และ Performance Trade-offs (v1.1)

Patch Note v2.0 (NFSU2_Thai.sh):
------------------------------------------------------------------------------
- รวม ARM64 runtime ล่าสุดจาก branch develop (รวมฟีเจอร์ ES3 VAO/Uniforms,
  Potato Mode, VP6 NEON Video, Native Thai, Joypad GPS, Skip Intro & Attract Mode)
  ไว้ใน nfsu2thai/runtime/ ไม่ต้องแพตช์ SPEED2.EXE หรือไบนารีบนดิสก์อีกต่อไป
- เพิ่มตัวเลือกปรับแต่งผ่าน nfsu2.cfg ในเมนูหลักครบถ้วน:
  * Skip Intro / Fast Boot (NFSU2_SKIP_INTRO=0/1) ข้ามอินโทรในหน่วยความจำโดยไม่แก้ชื่อไฟล์
  * Title Attract Mode (NFSU2_ATTRACT_MODE=auto/0/1) ป้องกันเพลงหน้า Title รีเซ็ตทุก 30 วินาที
  * Subtitles (NFSU2_SUBTITLES=auto/1/0) ควบคุมการแสดงคำบรรยายซับไตเติล
- คืนชื่อไฟล์ _*.vp6 เก่าที่เคยถูก rename ให้อัตโนมัติ และคืนค่าเดิมครบ 100% เมื่อ Uninstall

คุณสมบัติหลัก (NFSU2_Thai.sh v2.0):
------------------------------------------------------------------------------
1. ติดตั้ง / ติดตั้งซ้ำ / ถอนการติดตั้ง (Install / Re-install / Uninstall):
   - คัดลอก Thailand.bin & LanguageTextures.bin พร้อมอัปเดต runtime (nfsu2.aarch64.v10 + NFSU2.sh)
   - ตั้งค่า Fast Boot (Skip Intro) และ Attract Mode ได้ทันทีตอนติดตั้ง
   - สำรองไฟล์เดิมไว้ที่ /roms/ports/nfsu2/.backup_thai/ และถอนการติดตั้งคืนสภาพเดิมได้ 100%
2. สลับภาษาได้ทันที (Switch Language: Thai <-> English):
   - สลับระหว่างภาษาไทยกับภาษาอังกฤษดั้งเดิมผ่าน NFSU2_LANG ได้ตลอดเวลา
3. ควบคุม Skip Intro / Attract Mode / Subtitles:
   - เปิด-ปิดและเลือกโหมดทั้งหมดได้อิสระผ่าน nfsu2.cfg โดยไม่แตะต้องไฟล์เกมต้นฉบับ

คุณสมบัติหลัก (NFSU2_Controls.sh):
------------------------------------------------------------------------------
1. Quick Presets:
   - PS2 Classic: ปุ่มสไตล์ PS2 สำหรับ R36H (B=เร่ง, Y=เบรก, A=เบรกมือ, X=มุมกล้อง/GPS)
   - Modern Trigger: เร่งด้วย R2, เบรกด้วย L2, เบรกมือ A, ไนตรัส R1
2. Full Custom Remapper:
   - ปรับแต่งปุ่มขับรถได้อิสระ 9 ฟังก์ชัน (Throttle, Brake, E-Brake, Nitrous,
     Shift Up/Down, Look Back, Camera, Reset Car)
3. Reset Controls (Config & Save):
   - Reset -> Config: ล้าง controls.cfg และค่า SDL_GAMECONTROLLERCONFIG ใน nfsu2.cfg
   - Reset -> Save  : รีเซ็ตการตั้งค่าปุ่มในเซฟเกมพร้อมคำนวณค่าตรวจสอบใหม่
                      โดยรักษาความคืบหน้า รถ และเงินในเซฟไว้ครบ 100%

คุณสมบัติหลัก (NFSU2_Graphics.sh v1.1):
------------------------------------------------------------------------------
1. Frame Rate Limit: เลือกจำกัดเฟรมเรต (20 / 30 / 60 FPS)
2. Graphics Profile: เลือกโปรไฟล์กราฟิก (Ultra Performance / Performance / Balanced / Quality)
   โดยยังคงค่า Performance Trade-offs ที่ตั้งไว้เดิมทั้งหมด
3. Performance Trade-offs: ปรับลดงานที่ไม่จำเป็นเพื่อช่วยให้เกมลื่นขึ้น
   - Car Reflection Rate : ลดความถี่การอัปเดตเงาสะท้อนบนตัวรถขณะขับ (OFF / 1/2 / 1/3 / 1/4 Rate)
   - Distant AI Throttle : ลดภาระการคำนวณรถ AI ที่อยู่ไกล (OFF / 1/2 >45m / 1/3 >45m / 1/2 >30m)
   - Crowd Override      : บังคับเปิดหรือปิดคนดูข้างสนามทับค่าโปรไฟล์
   - Particles Override  : บังคับเปิดหรือปิดควันยางและประกายไฟทับค่าโปรไฟล์
   - มีปุ่มลัด Enable All Recommended (เปิดชุดแนะนำครบทั้ง 4 ตัว) และ Reset All to Default

มาตรฐาน PortMaster & playOS (Zero fb0_mirror, Flat Side-by-Side):
------------------------------------------------------------------------------
- รองรับทั้ง /roms/ports/ (เป้าหมายหลัก) และ /roms/tools/
- โครงสร้างโฟลเดอร์แบบ Side-by-Side ชั้นเดียว (Flat 1-Level, no app/)
- ใช้ Native /dev/tty1 Console + gptokeyb รองรับการกดปุ่มแบบ Dynamic A/B ตาม playfe
- ซ่อนโฟลเดอร์ข้อมูลอัตโนมัติด้วย Stem-Matching (nfsu2thai) เมนูไม่รก

วิธีติดตั้งใช้งานบนเครื่อง R36H / R36S:
------------------------------------------------------------------------------
[วิธีที่ 1 - แนะนำ] ติดตั้งใน Ports (/roms/ports/):
  คัดลอกไฟล์ต่อไปนี้ไปไว้ที่ /roms/ports/ (หรือ /roms/tools/ สำหรับตัวตั้งค่าที่ต้องการ)
    - NFSU2_Thai.sh
    - NFSU2_Controls.sh
    - NFSU2_Graphics.sh
    - images/NFSU2_Thai-thumb.png
    - images/NFSU2_Controls-thumb.png
    - images/NFSU2_Graphics-thumb.png
    - โฟลเดอร์ nfsu2thai/

[วิธีที่ 2] ติดตั้งใน Tools (/roms/tools/):
  คัดลอกทั้งโฟลเดอร์ nfsu2_thai ไปไว้ที่:
    /roms/tools/nfsu2_thai/
==============================================================================
