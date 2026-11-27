# แผนการแก้ไข Source Code — PR #4: Native Fast Boot (`NFSU2_SKIP_INTRO`) & Title Screen Attract Mode Control (`NFSU2_ATTRACT_MODE`)

**Document ID:** `NFSU2-R36H-PLAN-PR4`  
**Target Repository:** `source/nfsu2-recompiled-r36s` ([manuelpllull/nfsu2-recompiled-r36s](https://github.com/manuelpllull/nfsu2-recompiled-r36s))  
**Branch:** `feat/skip-intro-attract-mode` (แตกจาก `main`)  
**Target Executables:** รองรับทั้ง **`v10`** (`0x004C53B0`) และ **`v12`** (`0x004C5580`)  
**Scope:** เพิ่มตัวเลือก Fast Boot (`NFSU2_SKIP_INTRO=1`) ข้ามวิดีโอ Intro ในระดับ runtime โดยไม่ต้องลบหรือเปลี่ยนชื่อไฟล์บนดิสก์ พร้อมระบบควบคุม Title Screen Attract Mode 30 วินาที (`NFSU2_ATTRACT_MODE=auto|0|1`) เพื่อแก้ปัญหาเพลงหน้า Title (*Riders on the Storm*) รีสตาร์ททุก 30 วินาทีเมื่อ `FMVOpening.vp6` หายหรือถูกข้าม

---

## 1. ปัญหาเดิมใน Source Code ปัจจุบัน

1. **การข้าม Intro แบบเดิมต้องเปลี่ยนชื่อหรือลบไฟล์บนดิสก์:**
   * ผู้ใช้ที่ต้องการเข้าหน้า Title เร็วขึ้น (~1 วินาที) หรือประหยัดพื้นที่ SD Card มักต้องลบหรือเปลี่ยนชื่อไฟล์ใน `gamedata/MOVIES/` (`ealogo.vp6`, `THX_logo.vp6`, `FMVOpening.vp6`, `PSA.vp6`)
2. **เพลง Title รีสตาร์ททุก 30 วินาที (Attract Mode Loop):**
   * ใน `SplashScreen::NotificationMessage` (`0x004C53B0` ใน `v10`, `0x004C5580` ใน `v12`) เมื่อได้รับข้อความ `FE_TICK` (`0xC98356BA`) เกมจะคำนวณ `(MEM32(0x008651AC) - [this + 0x50]) * 0.00025f > 30.0f` แล้วสั่งสลับไปยังหน้าจอ `"UG_LS_IntroFMV.fng"` (`FMVOpening.vp6`)
   * เมื่อไม่มี `FMVOpening.vp6` (เพราะลบไฟล์ทิ้งหรือเปิด Fast Boot) หน้าจอเล่นวิดีโอจะจบลงทันทีแล้วโหลดหน้า Title ใหม่ ส่งผลให้เพลง *Riders on the Storm* เริ่มใหม่ทุก 30 วินาที

---

## 2. การออกแบบและสถาปัตยกรรม (Zero Guest Recompile)

1. **Vtable Override แทนการแก้/ห่อ guest object:**
   * `SplashScreen::NotificationMessage` (`0x004C53B0` / `0x004C5580`) ไม่มี direct call (`E8`) ใน `SPEED2.EXE` และถูกเรียกผ่าน vtable (`RECOMP_ICALL` -> `nfs_override_lookup`) 100%
   * การลงทะเบียน `ov_splash_notify` ใน `k_overrides[]` (`src/runtime/overrides.c`) จึงใช้งานได้ทันทีกับ precompiled guest objects เดิมทั้ง **`v10` และ `v12`** โดยไม่ต้อง recompile `recomp_*.c`
   * เมื่อ `msg == 0xC98356BA` (`FE_TICK`) และ Attract Mode ถูกปิดไว้ `ov_splash_notify` จะอัปเดต `MEM32(g_ecx + 0x50u) = MEM32(0x008651ACu)` แล้วส่งต่อให้ฟังก์ชันเดิมทำงานต่อ ทำให้ timer 30 วินาทีไม่เคยถึงเกณฑ์ ในขณะที่ลอจิกอื่นของ Title Screen (`PRESS_START` ที่ใช้ `[this + 0x4C]` และการเช็กเซฟ/ปุ่มกด) ทำงานตามต้นฉบับ 100%
2. **In-Memory Intro Movie Filtering (`NFSU2_SKIP_INTRO`):**
   * ดักการเปิด/เช็กไฟล์ในเลเยอร์ไฟล์ของ runtime (`guest_files.inc` สำหรับ R36S/Android และ `win32_shims.c` สำหรับ Windows host) เฉพาะไฟล์ภายในโฟลเดอร์ `MOVIES/` ที่ชื่อตรงกับ Intro (`ealogo`, `thx_logo`, `fmvopening`, `psa` รวมถึงเวอร์ชันแยกภาษาแบบมี suffix `_xx.vp6` เช่น `THX_logo_fr.vp6`) โดยคืนค่า `ERROR_FILE_NOT_FOUND` โดยไม่แตะต้องไฟล์จริงบนดิสก์
   * ไม่กระทบคัทซีนเนื้อเรื่อง (`Scene01.vp6`..`Scene20.vp6`), วิดีโอ Tutorial หรือ `blank.vp6`
3. **เมทริกซ์พฤติกรรมของ Config:**

| `NFSU2_SKIP_INTRO` | `NFSU2_ATTRACT_MODE` | `FMVOpening.vp6` บนดิสก์ | พฤติกรรมตอน Boot | พฤติกรรมหน้า Title หลัง 30 วิ |
| :--- | :--- | :--- | :--- | :--- |
| `0` / ไม่ระบุ | `auto` / ไม่ระบุ | มีไฟล์ | เล่น Intro ปกติ | เล่น Attract Mode ปกติ (100% stock) |
| `0` / ไม่ระบุ | `auto` / ไม่ระบุ | **ไม่มีไฟล์** | ข้ามไฟล์ที่หายอัตโนมัติ | **ปิด Attract Mode อัตโนมัติ** (เพลงไม่รีสตาร์ท) |
| `0` / ไม่ระบุ | `0` | มีไฟล์ | เล่น Intro ปกติ | **ปิด Attract Mode** (เพลงเล่นต่อเนื่องเกิน 30 วิ) |
| `1` | `auto` / ไม่ระบุ | มีหรือไม่มี | **Fast Boot** ข้าม Intro เข้า Title (~1 วิ) | **ปิด Attract Mode อัตโนมัติ** (เพลงไม่รีสตาร์ท) |
| `1` | `0` | มีหรือไม่มี | **Fast Boot** ข้าม Intro เข้า Title | **ปิด Attract Mode** (เพลงเล่นต่อเนื่องเกิน 30 วิ) |
| `1` | `1` | มีไฟล์ | **Fast Boot** ข้าม Intro เข้า Title | ปลดการซ่อน `FMVOpening.vp6` หลังเข้าหน้า Title แล้วให้ Attract Mode เล่นได้ตามปกติ |

---

## 3. รายการไฟล์ที่แก้ไขใน `source/nfsu2-recompiled-r36s`

1. `config/exe_functions.txt` & `src/runtime/nfs_exe_addr.h`
   * เพิ่ม mapping `0x004C53B0` (`v10`) <-> `0x004C5580` (`v12`) สำหรับ `SplashScreen::NotificationMessage` และสร้าง header ใหม่ด้วย `python3 scripts/exe_variant.py header`
2. `src/runtime/nfs_runtime.h`
   * เพิ่ม `extern "C"` guard และประกาศ `nfs_intro_init`, `nfs_skip_intro_enabled`, `nfs_attract_mode_suppressed`, `nfs_should_skip_intro_movie`, `nfs_should_skip_intro_path`
3. `src/runtime/overrides.c`
   * เพิ่มลอจิกอ่าน env `NFSU2_SKIP_INTRO` และ `NFSU2_ATTRACT_MODE`, ตัวกรองชื่อไฟล์ Intro, `ov_splash_notify`, และลงทะเบียน `{ NFS_VA(0x004C53B0), ov_splash_notify }` ใน `k_overrides[]` (ใช้งานได้ทุกแพลตฟอร์มทั้ง R36S, Android และ Windows)
4. `android/app/src/main/cpp/guest_runtime.cpp` & `guest_files.inc`
   * ตรวจเช็กการมีอยู่จริงของ `MOVIES/FMVOpening.vp6` (case-insensitive ผ่าน `gamePath()`) แล้วส่งเข้า `nfs_intro_init(...)`
   * เพิ่ม `skipIntroMovie(path)` ใน `createFile()`, `fileAttributes()`, `longPath()`, และ `findFirstFile()`
5. `src/host/main.c` & `src/shims/win32_shims.c`
   * เรียก `nfs_intro_init(...)` และดัก `nfs_should_skip_intro_path(name)` ใน `shim_CreateFileA` เพื่อให้ฝั่ง Windows host รองรับเช่นเดียวกัน
6. `ports/r36s/package/NFSU2.sh`, `ports/r36s/package/nfsu2.cfg`, `ports/r36s/package/README.md`
   * Export `NFSU2_SKIP_INTRO` และ `NFSU2_ATTRACT_MODE` ใน `NFSU2.sh` พร้อมเอกสารและตัวอย่างการตั้งค่าใน `nfsu2.cfg` และ `README.md`

---

## 4. ขั้นตอนการ Build และทดสอบ (Verification)

1. **Compile-check ทั้ง `v10` และ `v12` ใน Docker:**
   ```bash
   COMPILE_ONLY=1 NFS_EXE_VARIANT=1 bash /src/ports/r36s/build_ci.sh
   COMPILE_ONLY=1 NFS_EXE_VARIANT=2 bash /src/ports/r36s/build_ci.sh
   ```
2. **Fast Relink (`v10`) ใน Docker (~20 วินาที):**
   * Link กับ `/work/guest-v10` ด้วย `ports/r36s/build_cross.sh` -> ได้ `nfsu2-v10-attract.aarch64`
3. **ทดสอบรันจริงบนเครื่อง R36H (`ssh r36h`):**
   * สำรอง binary เดิมบนเครื่องก่อนทดสอบ (`nfsu2.aarch64.v10.bak_before_attract`)
   * **Test Case 1 (`NFSU2_SKIP_INTRO=1`, `NFSU2_ATTRACT_MODE` unset/auto, `MOVIES/` ครบทุกไฟล์):**
     * ตรวจใน `log.txt` ว่ามี `[NFSU2 INTRO] skipped ealogo.vp6 / THX_logo.vp6 / FMVOpening.vp6 / PSA.vp6` และ `[NFSU2 ATTRACT] suppressing 30s Title Screen Attract Mode timeout`
     * รอเกิน 35–40 วินาทีบนหน้า Title Screen แล้วยืนยันว่าไม่มีการเปิด `UG_LS_IntroFMV.fng` หรือรีโหลดหน้า Title ซ้ำ (เพลงไม่รีสตาร์ท)
   * **Test Case 2 (`NFSU2_SKIP_INTRO=0`, `NFSU2_ATTRACT_MODE=0`):**
     * ยืนยันว่า Intro เล่นปกติ แต่ Attract Mode ถูกปิดไว้เมื่อถึงหน้า Title
   * คืนค่า binary และ `nfsu2.cfg` เดิมบนเครื่อง R36H หลังทดสอบเสร็จสิ้น
