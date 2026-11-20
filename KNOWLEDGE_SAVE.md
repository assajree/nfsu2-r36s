# Need for Speed: Underground 2 (R36H / R36S) — องค์ความรู้สถาปัตยกรรมไฟล์เซฟ (Save Profile Structure), Controller Bindings Block และ 3-Tier CRC32 Checksum

**Document ID:** `NFSU2-R36H-KB-004`  
**Revision:** `1.0.0`  
**Last Updated:** 2026-11-18  
**Scope:** NFSU2 Save File Binary Layout, In-Game Controller Overrides Block (`0xD278..0xD6B6`), Safe Controls Reset Technique, Custom CRC32 Algorithm (`0x04C11DB7`), and 3-Tier Checksum Recalculation Order.

---

## 1. ภาพรวมสถาปัตยกรรมไฟล์เซฟ NFSU2 (Save Profile Architecture)

ในเกม **Need for Speed: Underground 2** (ทั้งเวอร์ชัน Windows PC และเวอร์ชัน Linux Recompiled บน R36H/R36S):
* โปรไฟล์ของผู้เล่นแต่ละคนจะถูกจัดเก็บเป็น **1 โฟลเดอร์ต่อ 1 โปรไฟล์** และมีไฟล์เซฟหลักที่ชื่อเดียวกับโฟลเดอร์นั้น
* **ขนาดไฟล์ตายตัวแน่นอน:** ขนาดของไฟล์เซฟที่สมบูรณ์จะต้องมีขนาดเท่ากับ **54,966 ไบต์ (`0xD6B6`)** เสมอ หากขาดหรือเกินแม้แต่ 1 ไบต์ เอนจินเกมจะปฏิเสธการโหลดทันที
* **ตำแหน่งจัดเก็บไฟล์เซฟ:**
  * **บนเครื่องพกพา Linux / PortMaster (R36H / R36S):**
    ```text
    /roms/ports/nfsu2/gamedata/AppData/Local/NFS Underground 2/<PROFILE_NAME>/<PROFILE_NAME>
    ```
  * **บนเครื่องคอมพิวเตอร์ Windows PC:**
    ```text
    %LOCALAPPDATA%\NFS Underground 2\<PROFILE_NAME>\<PROFILE_NAME>
    ```

---

## 2. แผนที่หน่วยความจำไบนารี (Binary Memory Map)

โครงสร้างภายในไฟล์เซฟขนาด 54,966 ไบต์ (`0xD6B6`) ถูกแบ่งออกเป็นส่วนหลักๆ ดังนี้:

| ช่วง Offset (Hex) | ขนาด (Bytes) | ชื่อบล็อก | หน้าที่และรายละเอียด |
| :--- | :--- | :--- | :--- |
| **`0x0000..0x0003`** | `4` | **Magic Header** | สตริง ASCII `b"20CM"` (Little-Endian ของ "MC02" / Memory Card Profile) |
| **`0x0004..0x000F`** | `12` | **Header Flags** | ข้อมูลเวอร์ชันเซฟและสถานะความสมบูรณ์ |
| **`0x0010..0x0013`** | `4` | **`CRC_A`** | 32-bit Little-Endian Checksum ของช่วง `0x001C..0x0024` |
| **`0x0014..0x0017`** | `4` | **`CRC_B`** | 32-bit Little-Endian Checksum ของช่วง `0x0024..0xD6B6` (Payload หลัก) |
| **`0x0018..0x001B`** | `4` | **`CRC_HDR`** | 32-bit Little-Endian Checksum ของช่วง `0x0000..0x0018` (รวม CRC_A และ CRC_B) |
| **`0x001C..0x0023`** | `8` | **Block A Data** | บล็อกขนาดเล็กสำหรับตรวจสอบสถานะเฮดเดอร์ |
| **`0x0024..0xD277`** | `53,844` | **Career Payload** | ความคืบหน้าโหมดเนื้อเรื่อง, รายการรถยนต์ในโรงรถ, ยอดเงินธนาคาร, ข้อความ SMS, และชิ้นส่วนแต่งรถที่ปลดล็อก |
| **`0xD278..0xD6B5`** | `1,086` (`0x43E`) | **Controller Block** | ข้อมูลการตั้งค่าปุ่มและอุปกรณ์ควบคุมภายในเกม (Controller Overrides) |

---

## 3. การ Reverse-Engineer บล็อกปุ่มควบคุม (`0xD278..0xD6B6`)

### 3.1 ปัญหาปุ่มเพี้ยนติดในเซฟ (Stuck Corrupted Controls Trap)
เมื่อผู้เล่นเปิดเมนู Options > Settings > Controls ภายในเกม NFSU2 บนเครื่องคอนโซล แล้วเผลอไปกดเปลี่ยนปุ่มควบคุม:
* เอนจินเกมจะเขียนข้อมูลการแมปปุ่มใหม่ทับลงในบล็อก **`0xD278..0xD6B6`** (ขนาด 1,086 ไบต์)
* ข้อมูลชุดนี้คือ Controller Binding Records จำนวน 6 ชุด (Keyboard 1, Keyboard 2, Gamepad 1, Gamepad 2 ฯลฯ)
* เนื่องจากบนเครื่องพกพาไม่มีแป้นพิมพ์จริง การกดปุ่มผิดอาจทำให้ปุ่มกดยืนยัน (Enter) หรือปุ่มเลื่อนเมนูหายไป ส่งผลให้ผู้เล่น **ติดหล่มอยู่ในเมนู ไม่สามารถกดเข้าไปแก้ปุ่มคืนในเกมได้**
* แม้จะลบเกมลงใหม่หรือเปลี่ยนสคริปต์ แต่เมื่อโหลดเซฟเดิมเข้ามา บล็อกที่เซฟไว้จะกลับมาทับการควบคุมทันที

### 3.2 เทคนิคการ Reset Controls โดยไม่เสียความคืบหน้า (Surgical Zeroing)
จากการวิเคราะห์โค้ดของเอนจิน `nfsu2.aarch64` และ Windows `SPEED2.EXE`:
* เมื่อตัวเกมอ่านบล็อก `0xD278..0xD6B6` แล้วพบว่า **เป็นค่า `0x00` (Zeroed) ทั้งหมด**:
  * เอนจินจะถือว่าผู้เล่น **ไม่เคยกำหนดปุ่มเอง (No Custom Bindings)**
  * ตัวเกมจะดึงค่าปุ่มเริ่มต้น (Factory Defaults) จากพอร์ตเกมและ `SDL_GAMECONTROLLERCONFIG` มาใช้งาน 100%
* **ขั้นตอนการซ่อมแซม:**
  1. เปิดไฟล์เซฟขึ้นมาในโหมด Binary Read/Write
  2. เติมไบต์ `0x00` ลงในช่วง `0xD278..0xD6B6` จำนวน 1,086 ไบต์:
     ```python
     raw[0xD278:0xD6B6] = b"\x00" * (0xD6B6 - 0xD278)
     ```
  3. คำนวณและประทับ Checksum ทั้ง 3 ชั้นใหม่ (ดูหัวข้อที่ 4)
* **ผลลัพธ์:** ข้อมูลโหมดเนื้อเรื่อง, รถยนต์, เงิน, ข้อความ SMS และสถิติการเล่นทั้งหมดยังคงอยู่สมบูรณ์ 100% แต่ปุ่มควบคุมจะถูกคืนค่ากลับเป็นมาตรฐานทันที

---

## 4. อัลกอริทึม Custom NFSU2 CRC32 (`0x04C11DB7`)

NFSU2 มีกลไกป้องกันไฟล์เซฟเสียหายด้วยระบบ **3-Tier Checksum** หากมีการแก้ไขข้อมูลในไฟล์แล้วไม่ได้คำนวณ Checksum ใหม่ ตัวเกมจะขึ้นข้อความเตือน:
```text
"The save file is corrupt and cannot be loaded."
```

### 4.1 สูตรการคำนวณ `nfsu2_crc` (Python Reference Implementation)
อัลกอริทึมใช้ Polynomial `0x04C11DB7` (มาตรฐาน Ethernet/MPEG-2) แต่มี Seed เริ่มต้นที่คำนวณจาก 4 ไบต์แรกของบล็อกข้อมูลในรูปแบบ Big-Endian:

```python
POLY = 0x04C11DB7

# 1. สร้างตาราง Lookup Table ขนาด 256 ค่า
TABLE = []
for i in range(256):
    c = (i << 24) & 0xFFFFFFFF
    for _ in range(8):
        c = ((c << 1) ^ POLY) & 0xFFFFFFFF if (c & 0x80000000) else (c << 1) & 0xFFFFFFFF
    TABLE.append(c)

# 2. ฟังก์ชันคำนวณ Checksum
def nfsu2_crc(data: bytes, start: int = 0, end: int = None) -> int:
    if end is None:
        end = len(data)
    if end - start < 4:
        return 0
    
    # คำนวณ Initial Seed จาก 4 ไบต์แรกแบบ Big-Endian
    first = ((data[start] << 24) | 
             (data[start + 1] << 16) | 
             (data[start + 2] << 8) | 
             data[start + 3]) & 0xFFFFFFFF
    
    r = (~first) & 0xFFFFFFFF
    for i in range(start + 4, end):
        r = (((r << 8) | data[i]) ^ TABLE[(r >> 24) & 0xFF]) & 0xFFFFFFFF
        
    return (~r) & 0xFFFFFFFF
```

### 4.2 ลำดับการคำนวณและประทับ 3-Tier Checksum (Strict Order)
การคำนวณ Checksum ทั้ง 3 ค่าต้องทำตามลำดับขั้นตอนที่แน่นอน เพราะ `CRC_HDR` ต้องครอบคลุมค่าของ `CRC_A` และ `CRC_B` ด้วย:

```python
import struct

# ขั้นที่ 1: คำนวณ CRC_A ครอบคลุมช่วง 0x1C..0x24 (8 ไบต์)
crc_a = nfsu2_crc(raw, 0x1C, 0x24)
struct.pack_into("<I", raw, 0x10, crc_a)  # เขียนลงที่ Offset 0x10 (Little-Endian)

# ขั้นที่ 2: คำนวณ CRC_B ครอบคลุมช่วง 0x24..0xD6B6 (Payload หลักทั้งหมด)
crc_b = nfsu2_crc(raw, 0x24, 0xD6B6)
struct.pack_into("<I", raw, 0x14, crc_b)  # เขียนลงที่ Offset 0x14 (Little-Endian)

# ขั้นที่ 3: คำนวณ CRC_HDR ครอบคลุมช่วง 0x00..0x18 (รวม CRC_A และ CRC_B)
crc_hdr = nfsu2_crc(raw, 0x00, 0x18)
struct.pack_into("<I", raw, 0x18, crc_hdr) # เขียนลงที่ Offset 0x18 (Little-Endian)
```

> [!CAUTION] ข้อควรระวังเรื่องลำดับการประทับ Checksum
> หากคำนวณ `CRC_HDR` ก่อนที่ `CRC_A` หรือ `CRC_B` จะถูกเขียนลงในไบต์ `0x10..0x17` ค่า Checksum ของเฮดเดอร์จะผิดทันที ทำให้เกมฟ้องว่าไฟล์เซฟเสียหาย

---

## 5. การตรวจสอบความถูกต้องของไฟล์เซฟ (Verification Script)

สคริปต์ Python สำหรับตรวจสอบความสมบูรณ์ของไฟล์เซฟ NFSU2:

```python
#!/usr/bin/env python3
import sys
import struct

def verify_save_file(file_path: str) -> bool:
    with open(file_path, "rb") as f:
        raw = f.read()

    if len(raw) != 0xD6B6:
        print(f"[!] Invalid size: {len(raw)} bytes (Expected 54,966 bytes)")
        return False

    if raw[0:4] != b"20CM":
        print(f"[!] Invalid magic header: {raw[0:4]}")
        return False

    cur_a = struct.unpack_from("<I", raw, 0x10)[0]
    cur_b = struct.unpack_from("<I", raw, 0x14)[0]
    cur_hdr = struct.unpack_from("<I", raw, 0x18)[0]

    exp_a = nfsu2_crc(raw, 0x1C, 0x24)
    exp_b = nfsu2_crc(raw, 0x24, 0xD6B6)
    exp_hdr = nfsu2_crc(raw, 0x00, 0x18)

    ok_a = (cur_a == exp_a)
    ok_b = (cur_b == exp_b)
    ok_hdr = (cur_hdr == exp_hdr)

    print(f"[*] CRC_A:   {hex(cur_a)} vs {hex(exp_a)} -> {'OK' if ok_a else 'FAIL'}")
    print(f"[*] CRC_B:   {hex(cur_b)} vs {hex(exp_b)} -> {'OK' if ok_b else 'FAIL'}")
    print(f"[*] CRC_HDR: {hex(cur_hdr)} vs {hex(exp_hdr)} -> {'OK' if ok_hdr else 'FAIL'}")

    return ok_a and ok_b and ok_hdr
```

---

## 6. เครื่องมือประจำเวิร์กสเปซ (`NFSU2_Controls.sh` เมนู `Reset -> Save`)

ในเวิร์กสเปซนี้ ได้รวมความสามารถการรีเซ็ตปุ่มในไฟล์เซฟไว้ใน **`tools/nfsu2_controls/NFSU2_Controls.sh`** (เมนู `4 Reset` -> `2 Save`) ซึ่งเป็น TUI ที่ทำงานบนเครื่อง R36H โดยตรง:
1. **Auto-Scan Profiles:** ค้นหาโปรไฟล์ทั้งหมดใน `/roms/ports/nfsu2/gamedata/AppData/Local/NFS Underground 2/`
2. **Safety Backup:** สำรองไฟล์เซฟต้นฉบับเก็บไว้ที่ `.backup_controls/<PROFILE>_<YYYYMMDD_HHMMSS>.bak` ก่อนลงมือแก้ไขทุกครั้ง (ไม่เขียนทับไฟล์เดิม)
3. **Surgical Patching:** เติม `0x00` ในบล็อก `0xD278..0xD6B6` และคำนวณ Checksum 3 ชั้นใหม่ในเสี้ยววินาที
