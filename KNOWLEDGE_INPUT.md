# Need for Speed: Underground 2 (R36H / R36S) — องค์ความรู้สถาปัตยกรรมระบบ Input, Inlining Invariants และ Joypad GPS Patch (`patch_gps.py`)

**Document ID:** `NFSU2-R36H-KB-003`  
**Revision:** `1.0.0`  
**Last Updated:** 2026-11-18  
**Scope:** Recompiled Gamepad Input Translation, Menu vs. Driving Mode Disambiguation, Compiler Inlining Invariants, World Map GPS Activation Reverse-Engineering, Live In-Memory Debugging, and Atomic Binary Deployment.

---

## 1. ภาพรวมสถาปัตยกรรมระบบ Input (DirectInput vs SDL2 GameController)

ในเกม **Need for Speed: Underground 2 (Recompiled)** บนเครื่องเล่นเกมพกพา R36H / R36S:
* ตัวเปิดเกม `NFSU2.sh` **ไม่ได้ใช้งาน `gptokeyb`** (แตกต่างจากเกมส่วนใหญ่ใน PortMaster)
* เอนจินไบนารี `nfsu2.aarch64` อ่านค่าอินพุตจาก Gamepad โดยตรงผ่านไลบรารี **SDL2 GameController API** (`GO-Super Gamepad`)
* เพื่อรองรับเอนจินเกมดั้งเดิมของ PC ที่ถูกแปลงมา ตัวแปลง Native AArch64 จะทำการแปลงค่าอินพุตจาก SDL2 เข้าสู่ตาราง **DirectInput Keyboard Scancodes (`DIK_*`)** ส่งต่อไปยังฟังก์ชันภายในเกม `setGuestKey(uint scancode, bool pressed)` (`VA 0x4ee030`)

---

## 2. การแยกโหมด Driving Mode กับ Menu Mode

เอนจินจะตรวจสอบสถานะการควบคุมของผู้เล่นผ่านฟังก์ชัน:
* **`guestDrivingControls()`** (`VA 0x4eddd0`) / ตัวแปร `_ZN12_GLOBAL__N_116inputDrivingModeE` (`VA 0x7a70840`):
  * **โหมดขับรถ (`inputDrivingMode == 1`)**:
    * ปุ่มและการควบคุมจะถูกส่งเป็นแกนและปุ่มควบคุมรถยนต์ (พวงมาลัย, คันเร่ง, เบรก, ไนตรัส, ปุ่มเปลี่ยนมุมมองกล้อง)
  * **โหมดเมนู / แผนที่ World Map (`inputDrivingMode == 0`)**:
    * สัญญาณปุ่มจะถูกแปลงเป็น Keyboard Scancodes ส่งผ่าน `setGuestKey` เพื่อนำทางเมนู เลือกตัวเลือก หรือพิมพ์ข้อความ

---

## 3. สาเหตุที่ Joypad ไม่สามารถเปิดใช้งาน GPS ในหน้า World Map

### 3.1 ข้อกำหนดของตัวเกม NFSU2 PC
* ในหน้าจอแผนที่โลก (World Map):
  * เกมเวอร์ชัน PC กำหนดให้การ **"เปิด/ปิดการนำทาง GPS" (Engage GPS)** ผูกอยู่กับคีย์ **`C`** (**`DIK_C` = `0x2E` หรือ 46**, `Menu Customise`) ซึ่งในโหมดขับรถคือปุ่มเปลี่ยนมุมมองกล้อง (`PCCOCamera`)
  * ปุ่ม **`Enter`** (**`DIK_RETURN` = `0x1C` หรือ 28**, `Menu Select`) ทำหน้าที่เลือก / ยืนยัน / เปิด-ปิดตัวกรองไอคอนบนแผนที่
  * ปุ่ม **`Escape`** (**`DIK_ESCAPE` = `0x01` หรือ 1**, `Menu Back`) ทำหน้าที่ย้อนกลับ / ปิดแผนที่
  * หมายเหตุ: ตาราง DirectInput Action Map ของโหมดเมนู (`DIACTION` 32 รายการที่ `0x7fd7e0` ใน `SPEED2.EXE`) **ไม่มี `DIK_SPACE` (`0x39`)** (`0x39` จะถูกส่งเฉพาะผ่าน `WM_KEYDOWN` `VK_SPACE` จึงไม่สร้าง DirectInput buffered event ใน World Map) ส่วนปุ่มเมนูอื่นๆ ใน `0x7fd7e0` ได้แก่ `H` (`0x23`, Help), `,` (`0x33`, Menu Button 2), `.` (`0x34`, Menu Button 3), `[` / `]` (`0x1a`/`0x1b`, L1/R1) และ `P` (`0x19`, Menu Preset)

### 3.2 ความผิดพลาดของการแมปปุ่มในพอร์ตเดิม
* ในโหมดเมนูของพอร์ตเดิม:
  * ปุ่ม **X** (`[x2, #42]` บน / North / Triangle) ถูกตั้งให้ส่ง **`DIK_SPACE`** (57)
  * ปุ่ม **Y** (`[x2, #43]` ซ้าย / West / Square) ถูกตั้งให้ส่ง **`DIK_ESCAPE`** (1) ซ้ำซ้อนกับปุ่ม B
  * **ไม่มีปุ่มใดบน Joypad เลยที่ถูกผูกไว้กับคีย์ `DIK_C` (46)**
* ผลกระทบ: ผู้เล่นจึงไม่สามารถกดปุ่มใดบนจอยเพื่อเริ่มการนำทาง GPS ได้ ต้องกดก้านขวา R3 เพื่อเรียก On-Screen Virtual Keyboard (`vkbd`) แล้วเลื่อนเคอร์เซอร์ไปกดตัวอักษร 'c' เสมอ

---

## 4. ปรากฏการณ์ Compiler Function Inlining ใน Static Binary Recompilation

บทเรียนสำคัญจากการแก้ไขบั๊กนี้คือ **การที่คอมไพเลอร์ทำการ Inline ฟังก์ชันโดยอัตโนมัติ**:
* ในซอร์สโค้ดเดิม ลอจิกการแปลงปุ่มเขียนไว้ในฟังก์ชันสถิต `selectSend(bool)` (`VA 0x5345e0`)
* แต่เมื่อคอมไพล์ด้วยการเปิด Optimization (`-O2` หรือ `-O3`):
  * คอมไพเลอร์ได้ทำการ **Inline โค้ดของ `selectSend` ทั้งบล็อกเข้าไปในฟังก์ชัน `main()`** โดยตรงถึง 2 จุด:
    1. **`0x491e78`**: ลูปตรวจจับเหตุการณ์การกดปุ่ม (`SDL_CONTROLLERBUTTONDOWN` / `UP`)
    2. **`0x490f80`**: ลูปตรวจจับเหตุการณ์การขยับแกน Analog (`SDL_CONTROLLERAXISMOTION`)
* **ผลลัพธ์**: หากทำการแพตช์เฉพาะที่ตัวฟังก์ชัน `selectSend` (`0x5347dc` / `0x5347f4`) เพียงอย่างเดียว เมื่อผู้เล่นกดปุ่มในเกมจริง ตัวเกมจะวิ่งผ่านโค้ดใน `main()` ที่ถูก Inline ไว้ ทำให้การกดปุ่มยังคงส่งค่า `Space` เหมือนเดิม

> [!IMPORTANT] กฎการทำ Binary Patching สำหรับโค้ดที่ Recompiled
> ในการวิเคราะห์และแพตช์ไบนารีที่มาจากการคอมไพล์แบบ Static Binary Recompilation **ห้ามสันนิษฐานว่าการแก้ที่ฟังก์ชันตามสัญลักษณ์ (Symbol) จะเพียงพอ** ต้องสแกนหาชุดคำสั่ง AArch64 ที่มี Pattern ตรงกันทั่วทั้งเซกเมนต์ `.text` เสมอ เพื่อครอบคลุมทั้งตัวฟังก์ชันหลักและทุกจุดที่ถูก Inline ไว้

---

## 5. รายละเอียดโครงสร้างหน่วยความจำและชุดคำสั่งที่ได้รับการแพตช์ (`patch_gps.py`)

### 5.1 โครงสร้าง DirectInput Buffer บน Stack
* **ภายใน `main()`**: Buffer ของ Scancode เริ่มต้นที่ **`sp + 616`**:
  * `DIK_ESCAPE` (1)  $\rightarrow$ `sp + 616 + 1  = sp + 617` (`0x269`)
  * `DIK_RETURN` (28) $\rightarrow$ `sp + 616 + 28 = sp + 644` (`0x284`)
  * **`DIK_C` (46)**    $\rightarrow$ `sp + 616 + 46 = sp + 662` (`0x296`)
  * `DIK_SPACE` (57)  $\rightarrow$ `sp + 616 + 57 = sp + 673` (`0x2a1`)
  * `DIK_UP` (200)    $\rightarrow$ `sp + 616 + 200 = sp + 816` (`0x330`)
  * `DIK_LEFT` (203)  $\rightarrow$ `sp + 616 + 203 = sp + 819` (`0x333`)
  * `DIK_RIGHT` (205) $\rightarrow$ `sp + 616 + 205 = sp + 821` (`0x335`)
  * `DIK_DOWN` (208)  $\rightarrow$ `sp + 616 + 208 = sp + 824` (`0x338`)

* **ภายใน `selectSend()`**: Buffer ของ Scancode เริ่มต้นที่ **`sp + 8`**:
  * `DIK_ESCAPE` (1)  $\rightarrow$ `sp + 8 + 1  = sp + 9`
  * `DIK_RETURN` (28) $\rightarrow$ `sp + 8 + 28 = sp + 36`
  * **`DIK_C` (46)**    $\rightarrow$ `sp + 8 + 46 = sp + 54`
  * `DIK_SPACE` (57)  $\rightarrow$ `sp + 8 + 57 = sp + 65`

### 5.2 ตำแหน่งคำสั่ง AArch64 ที่ถูกแพตช์ทั้ง 4 ตำแหน่ง
| ตำแหน่ง (VA) | ฟังก์ชัน | คำสั่งเดิม | คำสั่งใหม่ | ผลลัพธ์ |
| :--- | :--- | :--- | :--- | :--- |
| **`0x491e78`** | `main()` (Button Loop) | `strb w0, [sp, #673]` (`e0 87 0a 39`) | `strb w0, [sp, #662]` (`e0 5b 0a 39`) | ปุ่ม X ส่งคีย์ `DIK_C` (46) ทันทีที่กด |
| **`0x490f80`** | `main()` (Axis Loop) | `strb w1, [sp, #673]` (`e1 87 0a 39`) | `strb w1, [sp, #662]` (`e1 5b 0a 39`) | ปุ่ม X ส่งคีย์ `DIK_C` (46) เมื่อมีการขยับแกน |
| **`0x5347e0`** | `selectSend()` (Path A) | `strb w2, [sp, #65]` (`e2 07 01 39`) | `strb w2, [sp, #54]` (`e2 db 00 39`) | ปุ่ม X ส่งคีย์ `DIK_C` (46) ใน Helper Function |
| **`0x5347f8`** | `selectSend()` (Path B) | `strb w2, [sp, #65]` (`e2 07 01 39`) | `strb w2, [sp, #54]` (`e2 db 00 39`) | ปุ่ม X ส่งคีย์ `DIK_C` (46) ใน Helper Function |
| **`0x5347f0`** | `selectSend()` (Button Y)| `strb w3, [sp, #9]` (`e3 27 00 39`) | `strb w3, [sp, #65]` (`e3 07 01 39`) | ปุ่ม Y ส่งคีย์ `DIK_SPACE` (57) แทนที่ Esc ซ้ำซ้อน |

---

## 6. เทคนิค Live In-Memory Debugging และ Atomic Binary Replacement

### 6.1 Live In-Memory Hot-Patching ผ่าน GDB
เมื่อผู้เล่นเปิดเกมค้างอยู่บนคอนโซลและพบว่าปุ่มยังไม่ทำงาน เราสามารถใช้ GDB แนบเข้ากับโปรเซสของเกมที่กำลังรันอยู่เพื่อแก้ Machine Code ใน RAM ได้ทันทีโดยไม่ต้องสั่งปิดหรือรีสตาร์ตเกม:
```bash
sudo gdb -batch \
  -ex "attach <PID>" \
  -ex "set *(int*)0x491e78 = 0x390a5be0" \
  -ex "set *(int*)0x490f80 = 0x390a5be1" \
  -ex "detach" -ex "quit"
```
วิธีนี้ช่วยยืนยันความถูกต้องของคำสั่งได้ในเสี้ยววินาที และทำให้ผู้เล่นทดสอบได้ทันที

### 6.2 การแก้ไขปัญหา Linux `ETXTBSY` ด้วย Atomic Replacement
เมื่อพยายามอัปโหลดไฟล์ไบนารีทับไฟล์ที่กำลังรันอยู่บน Linux Kernel จะส่งข้อผิดพลาด:
```text
OSError: Failure (ETXTBSY: Text file busy)
```
**แนวทางแก้ไขที่ถูกต้อง**:
1. อัปโหลดไฟล์เวอร์ชันใหม่ขึ้นเป็นไฟล์ชั่วคราว เช่น `nfsu2.aarch64.v10.new`
2. กำหนดสิทธิ์ Execute: `chmod 755 *.new`
3. สั่งสลับชื่อด้วยคำสั่ง Atomic Move:
   ```bash
   mv -f /roms/ports/nfsu2/nfsu2.aarch64.v10.new /roms/ports/nfsu2/nfsu2.aarch64.v10
   ```
ระบบไฟล์ Linux จะทำ Unlink Inode ตัวเดิมออกจากไดเรกทอรี (แต่โปรเซสที่รันอยู่ยังคงถือ File Descriptor เดิมและทำงานต่อไปได้ตามปกติ) ขณะที่การเรียกเกมครั้งถัดไปจะโหลดไฟล์ไบนารีตัวใหม่ทันที

---

## 7. กลไกการ Remap ปุ่มผ่าน `SDL_GAMECONTROLLERCONFIG` (Dynamic Remapping Bridge)

### 7.1 สาเหตุที่การเขียน `controls.cfg` เพียงอย่างเดียวไม่ส่งผลในเกม
จากการ Reverse-Engineer ไบนารี `nfsu2.aarch64` ในส่วนลูปอินพุต `main()` (ที่ VA `0x491084..0x491138`):
* เอนจินเกมแปลงค่า Logical Button จาก SDL2 เข้าสู่ DirectInput Scancode โดยตรงแบบ **Hardcoded**:
  * Logical `a`             $\rightarrow$ `sp + 816` (`DIK_UP`, Throttle/Gas)
  * Logical `x`             $\rightarrow$ `sp + 824` (`DIK_DOWN`, Brake/Reverse)
  * Logical `b`             $\rightarrow$ `sp + 673` (`DIK_SPACE`, Handbrake/E-Brake)
  * Logical `y`             $\rightarrow$ `sp + 662` (`DIK_C`, Change Camera)
  * Logical `rightshoulder` $\rightarrow$ `sp + 672` (`DIK_RSHIFT`, Nitrous Boost)
  * Logical `leftshoulder`  $\rightarrow$ `sp + 664` (`DIK_D`, Look Back)
  * Logical `righttrigger`  $\rightarrow$ Shift Up
  * Logical `lefttrigger`   $\rightarrow$ Shift Down
* ตัวเกมไม่ได้มีโค้ดอ่านไฟล์ `controls.cfg` แบบ Text Config เลย การเขียนไฟล์ `controls.cfg` เพียงอย่างเดียวจึงไม่เปลี่ยนการควบคุมใดๆ ในเกม

### 7.2 ทางออกที่ถูกต้อง: การเชื่อมต่อผ่าน `SDL_GAMECONTROLLERCONFIG` ใน `nfsu2.cfg`
* ตัวเปิดเกม `NFSU2.sh` จะทำคำสั่ง `. "$GAMEDIR/nfsu2.cfg"` (source config) ก่อนการเรียกเปิดเอนจินเกม `./$BIN` เสมอ
* ไลบรารี SDL2 รองรับการ Override การแมปปุ่มของอุปกรณ์จอยแพดผ่านตัวแปร Environment **`SDL_GAMECONTROLLERCONFIG`**
* ดังนั้น สคริปต์ `NFSU2_Controls.sh` จึงได้รับการปรับปรุงให้คำนวณชุดรหัสปุ่ม Hardware (`b0..b15`) ของ `GO-Super Gamepad` ตามตัวเลือกที่ผู้ใช้ตั้งค่า แล้วนำไปเขียนลงใน `nfsu2.cfg` ในรูป:
  ```bash
  export SDL_GAMECONTROLLERCONFIG="1900bb3e4b4800000011000000010000,GO-Super Gamepad,a:${b_thr},b:${b_ebrk},x:${b_brk},y:${b_cam},leftshoulder:${b_look},rightshoulder:${b_nit},lefttrigger:${b_shdn},righttrigger:${b_shup},back:b12,dpdown:b9,dpleft:b10,dpright:b11,dpup:b8,guide:b16,leftstick:b14,leftx:a0,lefty:a1,rightstick:b15,rightx:a2,righty:a3,start:b13,platform:Linux,"
  ```
* เมื่อรันเกม SDL2 จะทำการสลับสัญญาณปุ่มตั้งแต่ระดับฮาร์ดแวร์ก่อนส่งเข้าเอนจิน ทำให้การตั้งค่าปุ่มและ Preset ทุกแบบ (PS2 Classic, Modern Triggers, Arcade, Custom Remap) มีผลจริงในเกม 100% โดยไม่ต้องแก้โค้ด C++ ในเอนจิน

### 7.3 ตารางรหัสปุ่มฮาร์ดแวร์จริงของ R36H (`GO-Super Gamepad` / Linux Evdev)
จากการวิเคราะห์ Kernel Evdev และ log การกดปุ่มจริงใน `log.txt`:
* **`b0`** = ปุ่ม **`B`** (ล่าง / Bottom) — `BTN_SOUTH` (304)
* **`b1`** = ปุ่ม **`A`** (ขวา / Right) — `BTN_EAST` (305)
* **`b2`** = ปุ่ม **`X`** (บน / Top) — `BTN_NORTH` (307)
* **`b3`** = ปุ่ม **`Y`** (ซ้าย / Left) — `BTN_WEST` (308)
* **`b4`** = ปุ่ม **`L1`** (ไหล่ซ้าย)
* **`b5`** = ปุ่ม **`R1`** (ไหล่ขวา)
* **`b6`** = ปุ่ม **`L2`** (Trigger ซ้าย)
* **`b7`** = ปุ่ม **`R2`** (Trigger ขวา)

> [!IMPORTANT] ข้อควรระวังการสลับคู่ X/Y ระหว่าง Linux Kernel กับ SDL
> บนเคอร์เนล Linux ค่า `BTN_NORTH` (307) จะได้อินเด็กซ์ `b2` (ปุ่ม X บน) และ `BTN_WEST` (308) จะได้อินเด็กซ์ `b3` (ปุ่ม Y ซ้าย) ดังนั้นเมื่อต้องการให้กด **Y ซ้ายเพื่อเบรก** ต้องผูกเข้ากับ `x:b3` และเมื่อต้องการให้กด **X บนเพื่อเปลี่ยนมุมกล้อง/เปิด GPS** ต้องผูกเข้ากับ `y:b2` ห้ามสลับเป็น `x:b2, y:b3` โดยเด็ดขาด
>
> **หมายเหตุด้าน PortMaster บน playOS:** ไฟล์ `/opt/system/Tools/PortMaster/gamecontrollerdb.txt` (บรรทัด 1110) และค่า built-in ใน SDL2 กำหนด `GO-Super Gamepad` เป็น `x:b2,y:b3` (ตามตัวอักษรบนปุ่ม) ซึ่งมี `leftstick:`/`rightstick:` ครบอยู่แล้ว ทำให้ `preparePadMapping()` ใน `ports/r36s/main.cpp` ไม่เขียนทับด้วย `kR36SPadMapping` (`y:b2,x:b3`) ดังนั้นบน playOS หากไม่ได้กำหนด `SDL_GAMECONTROLLERCONFIG` ที่มี `x:b3,y:b2` ใน `nfsu2.cfg` (หรือไม่ได้ตั้ง `NFSU2_FORCE_PAD_MAPPING=1`) ปุ่มเปิด GPS จะไปอยู่ที่ปุ่ม **Y ซ้าย (`b3`)** แทน **X บน (`b2`)**
