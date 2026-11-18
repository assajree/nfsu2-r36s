# แผนการแก้ไข Source Code และการ Build บนเครื่อง R36H — PR #3: Joypad GPS Activation on World Map & DirectInput Space Restoration

**Document ID:** `NFSU2-R36H-PLAN-PR3`  
**Target Repository:** `source/nfsu2-recompiled-r36s` ([manuelpllull/nfsu2-recompiled-r36s](https://github.com/manuelpllull/nfsu2-recompiled-r36s))  
**Scope:** การเปิดใช้งานฟังก์ชัน GPS บนหน้าจอแผนที่โลก (World Map) ด้วยปุ่ม Joypad (ปุ่ม X / Triangle) และการคืนค่าฟังก์ชันปุ่ม Space สำหรับการฟิลเตอร์ไอคอนบนแผนที่และเมนูโรงรถ โดยแก้ไขระดับ C++ Source Code ใน `ports/r36s/sdl_gamepad.h` พร้อมขั้นตอนการคอมไพล์บน R36H  

---

## 1. ที่มาและปัญหา (Problem Statement)

ในเกม **Need for Speed: Underground 2 (Recompiled)** พอร์ตสำหรับเครื่อง R36S/R36H:
1. **ไม่สามารถเปิดใช้งานระบบนำทาง GPS ผ่านหน้าต่าง World Map ด้วย Joypad ได้**:
   * ในเวอร์ชัน PC ตัวเกมกำหนดให้การเปิด/ปิด GPS บนแผนที่ผูกอยู่กับคีย์บอร์ด **`C`** (**`DIK_C` = `0x2E` หรือ 46**)
   * ในคลาส `SdlGamepad` (`ports/r36s/sdl_gamepad.h`) เมื่ออยู่ในโหมดเมนู (`driving == false`) ตัวแปลงปุ่มไม่ได้แมปคีย์ `0x2E` ให้กับปุ่มใดเลย
   * ผู้เล่นต้องกดก้านขวา (R3) เพื่อเรียก On-screen Virtual Keyboard (`vkbd`) แล้วเลื่อนไปพิมพ์ตัว `c` เสมอ
2. **การแมปปุ่มซ้ำซ้อนในโหมดเมนู**:
   * ผู้พัฒนาเดิมตั้งค่าให้ทั้งปุ่ม Circle (ปุ่ม B) และปุ่ม Triangle (ปุ่มบน / X บน R36S / `buttons_[Y]`) ส่งคีย์ **`DIK_ESCAPE`** (`0x01`) เหมือนกันทั้งคู่
   * ทำให้ปุ่ม Triangle เสียประโยชน์ และไม่มีปุ่มสำหรับส่งคีย์ `DIK_C`

---

## 2. การแก้ไข Source Code C++

### ไฟล์เป้าหมาย: `ports/r36s/sdl_gamepad.h`

ที่ฟังก์ชัน `SdlGamepad::apply(bool driving, SetKey& setKey)` (บรรทัดที่ ~106-112):

```cpp
// ==========================================
// โค้ดเดิม (บรรทัด ~106-112):
// ==========================================
        } else {
            want[0xcb] = buttons_[Left] || past(-stickX_, 0xcb); want[0xcd] = buttons_[Right] || past(stickX_, 0xcd);
            want[0xc8] = buttons_[Up] || past(-stickY_, 0xc8); want[0xd0] = buttons_[Down] || past(stickY_, 0xd0);
            want[0x1c] = buttons_[A] || buttons_[Start];
            want[0x01] = buttons_[B] || buttons_[Y];
            want[0x39] = buttons_[X];
        }

// ==========================================
// แก้ไขเป็น:
// ==========================================
        } else {
            want[0xcb] = buttons_[Left] || past(-stickX_, 0xcb); want[0xcd] = buttons_[Right] || past(stickX_, 0xcd);
            want[0xc8] = buttons_[Up] || past(-stickY_, 0xc8); want[0xd0] = buttons_[Down] || past(stickY_, 0xd0);
            want[0x1c] = buttons_[A] || buttons_[Start]; // Cross / Start = Accept (Enter)
            want[0x01] = buttons_[B];                    // Circle = Back / Cancel (Escape)
            want[0x2e] = buttons_[Y];                    // Triangle = Engage GPS on World Map (DIK_C = 46)
            want[0x39] = buttons_[X];                    // Square = Filter map icons / Garage options (DIK_SPACE = 57)
        }
```

และแก้ไขคำอธิบายที่ส่วนหัวของไฟล์ `sdl_gamepad.h` (บรรทัดที่ ~17):
```cpp
// เดิม:
// Menus: d-pad / left stick move, Cross or Start accept, Circle or Triangle back, Square = Space.

// แก้ไขเป็น:
// Menus: d-pad / left stick move, Cross or Start accept, Circle back, Triangle = Engage GPS (C), Square = Space.
```

---

## 3. ความสัมพันธ์กับ Binary Patcher (`patch_gps.py`)

เนื่องจากคอมไพเลอร์ทำการ **Inline** คลาส `SdlGamepad` เข้าไปใน `main()` ของ `ports/r36s/main.cpp` สำหรับผู้ที่ใช้งานไบนารีสำเร็จรูปที่คอมไพล์ไปแล้ว ให้ใช้ `patch_gps.py` ซึ่งจะแพตช์ไบนารี AArch64 ครอบคลุมทั้ง 4 ตำแหน่ง:
1. `0x491e78`: ใน `main()` (Button Loop Event Handler)
2. `0x490f80`: ใน `main()` (Axis Loop Event Handler)
3. `0x5347e0`: ใน `selectSend()` (Path A)
4. `0x5347f8`: ใน `selectSend()` (Path B)
5. `0x5347f0`: ใน `selectSend()` (Button Y $\rightarrow$ `DIK_SPACE`)

---

## 4. ขั้นตอนการคอมไพล์ (Native Build บน R36H)

### 4.1 Quick Incremental Build (~15 วินาที)
```bash
cd /home/ark/source/nfsu2-recompiled-r36s
ninja -C build nfsu2.aarch64
```

### 4.2 ตรวจสอบผลลัพธ์
```bash
# ตรวจสอบว่ามีคำสั่ง strb w?, [sp, #662] ใน main() หรือไม่
objdump -d build/nfsu2.aarch64 | grep "sp, #662"
```

---

## 5. รายละเอียดสำหรับการส่ง Pull Request

* **PR Title**: `fix(input): map Triangle/North button to key C in menus to engage GPS on World Map`
* **Commit Message**:
  ```text
  fix(input): map Triangle button to DIK_C in menus for World Map GPS

  On PC NFSU2, engaging GPS on the World Map screen requires DirectInput key
  'C' (0x2E). Previously in SdlGamepad (ports/r36s/sdl_gamepad.h), buttons_[Y]
  (Triangle / North) was redundantly mapped to DIK_ESCAPE alongside buttons_[B]
  (Circle), leaving no gamepad button capable of triggering GPS without opening
  the on-screen virtual keyboard.

  This commit:
  - Maps buttons_[Y] (Triangle / North, physical X on R36S) to DIK_C (0x2E) in menu mode.
  - Leaves buttons_[B] (Circle, physical A on R36S) as the sole Back/Cancel button (DIK_ESCAPE).
  - Preserves buttons_[X] (Square, physical Y on R36S) as DIK_SPACE (0x39) for filtering map icons.
  - Restores authentic PS2 console layout where Triangle engages GPS on the World Map.
  ```
