# Need for Speed: Underground 2 (R36H / R36S) — องค์ความรู้การแกะรอยระบบวิดีโอคัทซีนและ Binary Patch (`patch_video.py`)

**Document ID:** `NFSU2-R36H-KB-002`  
**Revision:** `1.0.0`  
**Last Updated:** 2026-11-18  
**Scope:** Cutscene / FMV Video Pipeline Reverse-Engineering, Bottleneck Analysis, ARM64 NEON Binary Patch (`patch_video.py`), and Disassembly Verification Rules  

---

## 1. ภาพรวมสถาปัตยกรรมไปป์ไลน์วิดีโอคัทซีน (FMV / `.vp6`)

ในเกม **Need for Speed: Underground 2 (Recompiled)** ไฟล์วิดีโอทั้งหมดในโฟลเดอร์ `gamedata/MOVIES/*.vp6` (เช่น `FMVOpening.vp6`, `PSA.vp6`, `Scene01.vp6`..`Scene20.vp6`, `DragTut.vp6`, `DriftTut.vp6`) ใช้ตัวถอดรหัส **On2 VP6 (`6.1.0.5`)** และเรนเดอร์ขึ้นหน้าจอผ่านเท็กซ์เจอร์ Direct3D 9 ชื่อ **`"MovieTexture"`** โดยมีขั้นตอนต่อเฟรมดังนี้:

1. **สร้างเท็กซ์เจอร์ (`sub_005CEB10` @ `VA 0x005ceb10`)**:
   * สร้างเท็กซ์เจอร์ `"MovieTexture"` ขนาด **`1024 × 512`** รูปแบบ **`D3DFMT_A8R8G8B8`** (ขนาด `2,097,152` ไบต์ หรือ **2 MB ต่อเฟรม**)
2. **ถอดรหัสเฟรมวิดีโอ (`VP6_CODEC_INTERNAL`)**:
   * ถอดรหัสบิตสตรีม `.vp6` ออกมาเป็นระนาบสี **YUV420 (`Y`, `U`, `V`)** ขนาด `640 × 480`
3. **แปลงสี `YUV420 -> ARGB8888` (`sub_006FFEAD` $\rightarrow$ `sub_006FFAA7`)**:
   * `sub_005BF680` เรียก `sub_004FE100(..., [0x00800580])` ซึ่งส่งต่อค่า `[0x00800580] = 1` ไปยัง `sub_006FFEAD`
   * ในแต่ละบรรทัดภาพ (Scanline) `sub_006FFEAD` จะเรียก `sub_006FFAA7` (ใน `v10`) หรือ `sub_006FFD4A` (ใน `v12`) เพื่อแปลงพิกเซลทีละคู่ (2 พิกเซลต่อรอบ รวม `320 × 480 = 153,600` รอบต่อเฟรม) โดยใช้ตาราง Lookup Table ที่สร้างไว้ใน `sub_00700254`:
     * `Y_tab` @ Guest VA `0x008149e0` (Host VA `0x10008149e0`, ขนาด `256 × 8` ไบต์)
     * `U_tab` @ Guest VA `0x008151e0` (Host VA `0x10008151e0`, ขนาด `256 × 8` ไบต์)
     * `V_tab` @ Guest VA `0x008159e0` (Host VA `0x10008159e0`, ขนาด `256 × 8` ไบต์)
4. **อัปโหลดขึ้น GPU (`IDirect3DTexture9::LockRect` / `UnlockRect`)**:
   * `sub_005BF680` (`VA 0x005bf69a`) เรียก `LockRect(tex, 0, &lr, NULL, 0)` ด้วย `Flags = 0` คัดลอกภาพลง `lr.pBits` แล้วเรียก `UnlockRect(tex, 0)` เพื่ออัปโหลดเข้าสู่ OpenGL ES 2.0 (`glTexSubImage2D`)

> [!CAUTION]
> **ข้อควรระวังเรื่องตัวแปร `[0x00800580]` ใน `SPEED2.EXE`**:
> ค่าเริ่มต้นที่ `VA 0x00800580` (`1`) **ไม่ใช่** แฟล็กเลือกชุดคำสั่ง CPU (MMX vs Scalar) แต่เป็น **ตัวเลือกรูปแบบสีขาออก (Output Pixel Format Selector)** ของ `sub_006FFEAD`:
> * หาก `[0x00800580] == 1`: เลือกตัวแปลง **`YUV420 -> ARGB8888` (32-bit)** ที่ `sub_006FFAA7`
> * หาก `[0x00800580] == 0`: เลือกตัวแปลง **`YUV420 -> YUY2` (16-bit packed)** ที่ `sub_006FFA5D`
> ดังนั้น **ห้ามเปลี่ยนค่าที่ `0x00800580` เป็น `0`** เพราะจะทำให้ข้อมูลสีผิดรูปแบบ

---

## 2. สาเหตุคอขวดที่ทำให้วิดีโอคัทซีนกระตุกบน RK3326 (5 Root Causes)

จากการแกะรอยไบนารี `nfsu2.aarch64` ร่วมกับซอร์สโค้ด พบคอขวดหลัก 5 จุดที่ทำงานซ้ำในทุกเฟรมของวิดีโอ:

### 2.1 การบล็อกข้ามเธรด (`syncCall`) เพราะไม่ได้ส่ง `D3DLOCK_DISCARD`
* ที่ `VA 0x005bf69a` เกมเรียก `MovieTexture->LockRect(0, &lr, NULL, 0)` โดยส่ง `Flags = 0` (ไม่ได้ตั้งบิต `D3DLOCK_DISCARD = 0x2000`)
* ในฟังก์ชัน `rt::textureLockAsync` (`android/app/src/main/cpp/d3d9_render_thread.inc:468`, `VA 0x49b860`) มีเงื่อนไข:
  ```cpp
  if (level != 0 || (flags & D3DLOCK_READONLY) || (!fresh && !(flags & D3DLOCK_DISCARD)))
      return false;
  ```
* ส่งผลให้ตั้งแต่เฟรมที่ 2 เป็นต้นไป (`!fresh`) การ Lock ถูกปฏิเสธไม่ให้ใช้คิว Async (`OpTexUpload`) และตกไปใช้ **`syncCall` ถึง 2 ครั้งต่อเฟรม** (ตอน `LockRect` และ `UnlockRect`) ทำให้ Game Thread และ Render Thread ต้องหยุดรอคิวกันไปมาทุกเฟรม

### 2.2 การเรียก `glReadPixels` (`readBack()`) และการคัดลอกเฟรมเก่า 2 MB
* ใน `IDirect3DSurface9GLES::LockRect` (`ports/r36s/d3d9_gles/d3d9_gles_resources.h:259`) เมื่อถูกเรียกซ้ำบนเท็กซ์เจอร์ที่อัปโหลดไปแล้ว (`m_uploaded == true`) โดยไม่มี `D3DLOCK_DISCARD`:
  * ระบบเข้าใจว่าเกมต้องการอ่านพิกเซลเก่าจาก GPU จึงสั่งรัน `readBack()` ซึ่งสร้าง FBO ชั่วคราวแล้วเรียก **`glReadPixels` ขนาด `1024×512` (2 MB) ย้อนกลับจาก GPU Mali-G31 ลง CPU**!
  * แม้แต่ใน `rt::exec` (`OpTexUpload` @ `VA 0x4a3640` และ `0x4a36fc`) ตอนที่ Render Thread เรียก `tex->LockRect(level, &lr, nullptr, 0)` ก็ส่ง `Flags = 0` เช่นกัน

### 2.3 การคืนและจองหน่วยความจำ 2 MB ใหม่ทุกเฟรม (`m_upload` Thrashing)
* ใน `IDirect3DSurface9GLES::UnlockRect` (`d3d9_gles_resources.h:319`, `VA 0x4ce8d0`) เมื่อแปลงสีและอัปโหลดขึ้น `glTexSubImage2D` เสร็จ จะรันคำสั่ง:
  ```cpp
  std::vector<uint8_t>().swap(m_upload);
  ```
* เนื่องจาก `m_upload` มีขนาด **2 MB (`2,097,152` ไบต์)** ซึ่งเกินเกณฑ์ `M_MMAP_THRESHOLD` ของ `glibc` (128 KB):
  * ทุกเฟรมที่ปลดล็อกเท็กซ์เจอร์ `glibc` จะเรียก `munmap()` คืนหน่วยความจำ 2 MB กลับสู่ Linux Kernel (เกิด Cross-core TLB Shootdown บน RK3326 ทั้ง 4 คอร์)
  * และในเฟรมถัดไป `m_upload.resize(2097152)` จะเรียก `mmap()` ขอหน้าหน่วยความจำใหม่ (เกิด **512 Minor Page Faults ต่อเฟรม**) พร้อมทั้งเขียนศูนย์ (`memset 0`) ทับทั้ง 2 MB ก่อนที่จะถูกเขียนทับทันทีในบรรทัดถัดไป

### 2.4 ลูปแปลงสี `BGRA -> RGBA` ทีละไบต์แบบ Scalar (`convertRowToRGBA8`)
* ใน `d3d9_gles::convertRowToRGBA8` (`VA 0x4c869c`) กรณี `D3DFMT_A8R8G8B8` (format 21) คอมไพเลอร์สร้างโค้ดโหลดและเก็บทีละไบต์ (`ldrb`/`strb` 11 คำสั่งต่อพิกเซล) สำหรับภาพขนาด `1024 × 512 = 524,288` พิกเซล คิดเป็น **~5.8 ล้านคำสั่งต่อเฟรม**

### 2.5 โค้ดจำลอง MMX บนสแตก (`V128` Union) ใน `sub_006FFAA7` และ VP6
* ตัวแปลง `YUV420 -> ARGB8888` (`sub_006FFAA7` ใน `v10` / `sub_006FFD4A` ใน `v12`) เดิมเป็นโค้ด x86 MMX (`movq`, `paddsw`, `packuswb` เพียง 21 คำสั่งต่อ 2 พิกเซล)
* เมื่อถูกแปลงเป็น C ด้วย Static Lifter คำสั่ง MMX ถูกจำลองผ่าน `V128` union บนหน่วยความจำ ทำให้ขยายตัวเป็น **236 คำสั่ง ARM64 ต่อ 2 พิกเซล** (คูณ `153,600` รอบ = **~35 ล้านคำสั่งต่อเฟรม**)
* เช่นเดียวกับตัวถอดรหัส VP6 ที่ตรวจสอบฟีเจอร์ CPU ผ่าน `sub_0070CCE8` (`v10`) / `sub_0070CF98` (`v12`) แล้วเปิดใช้งานฟังก์ชัน MMX จำลองแทนที่จะใช้ฟังก์ชัน C แบบ 32-bit Scalar ที่มีอยู่แล้วในตัวเกม

---

## 3. รายละเอียดการแพตช์ไบนารีทั้ง 7 จุดใน [`patch_video.py`](./patch_video.py)

สคริปต์ [`patch_video.py`](./patch_video.py) ใช้ตัวค้นหาสัญลักษณ์ ELF (`.symtab`) แบบไดนามิก รองรับทั้งไบนารี `v10` (`nfsu2.aarch64`, `nfsu2.aarch64.v10`) และ `v12` (`nfsu2.aarch64.v12`):

| จุดที่ | สัญลักษณ์เป้าหมาย (ELF Symbol) | ตำแหน่ง (VA / File Offset) | การเปลี่ยนแปลง (Original $\rightarrow$ Patched) | ผลลัพธ์ |
| :---: | :--- | :--- | :--- | :--- |
| **1** | `_ZN2rt16textureLockAsyncEjPKjPjS2_` `+0x3E0` | `VA 0x49b860`<br>(`File 0x09b860`) | `366fedf9` (`tbz w25, #13, 0x49b61c`)<br>$\rightarrow$ `d503201f` (`nop`) | ปลดล็อก Async `MovieTexture` Lock ไม่ต้องรอ `syncCall` |
| **2a** | `_ZN2rt4execERKNS_3CmdE` `+0x4D0` | `VA 0x4a3640`<br>(`File 0x0a3640`) | `52800004` (`mov w4, #0`)<br>$\rightarrow$ `52840004` (`mov w4, #0x2000`) | ส่ง `D3DLOCK_DISCARD` ตอนอัปโหลด 2D Texture ป้องกัน `readBack()` |
| **2b** | `_ZN2rt4execERKNS_3CmdE` `+0x58C` | `VA 0x4a36fc`<br>(`File 0x0a36fc`) | `52800004` (`mov w4, #0`)<br>$\rightarrow$ `52840004` (`mov w4, #0x2000`) | ส่ง `D3DLOCK_DISCARD` ตอนอัปโหลด Cube/Vol Texture |
| **3** | `_ZN9d3d9_gles21IDirect3DSurface9GLES10UnlockRectEv` `+0x310` | `VA 0x4ce8d0`<br>(`File 0x0ce8d0`, 24 B) | ตรวจ `ldrb w0, [x19, #0x43]` (`m_keepShadow`) หาก `!= 0` ให้ข้ามการคืน `m_upload` (`cbnz w0, 0x4ce8ec`) | เก็บบัฟเฟอร์ `m_upload` (2 MB) ไว้ใช้ซ้ำในเฟรมถัดไป ตัด `mmap`/`munmap` และ 512 page faults/frame |
| **4** | `_ZN9d3d9_gles17convertRowToRGBA8E10_D3DFORMATPKhPhj` `+0x2BC` | `VA 0x4c869c`<br>(`File 0x0c869c`, 64 B) | แทนที่ลูปทีละไบต์ด้วย ARM64 NEON `ld4`/`st4` (`{v0.16b-v3.16b}`) ทีละ 16 พิกเซล (64 B/รอบ) | แปลงสี `BGRA -> RGBA` เร็วขึ้น ~20 เท่า |
| **5a** | `sub_006FFAA7` (`v10`) /<br>`sub_006FFD4A` (`v12`) | `v10: VA 0x47c0440`<br>`v12: VA 0x48c6c40`<br>(172 B / 43 คำสั่ง) | แทนที่โค้ดจำลอง MMX 236 คำสั่ง ด้วย Native ARM64 NEON (`sqadd` + `mov v0.d[1], v1.d[0]` + `sqxtun`) | แปลงสี `YUV420 -> ARGB8888` เร็วขึ้น ~16 เท่า พร้อมอัปเดต `g_eax`, `g_ecx`, `g_edx`, `g_esp` ครบตาม ABI |
| **5b** | `sub_0070CCE8` (`v10`) /<br>`sub_0070CF98` (`v12`) | `v10: VA 0x4d16b90`<br>`v12: VA 0x4959d00`<br>(52 B / 13 คำสั่ง) | ตั้งค่า `*has_mmx = 0`, `*has_xmm = 0`, `*has_wmt = 0`, `g_eax = 0`, `g_esp += 4`, `ret` | บังคับให้ VP6 ใช้ฟังก์ชัน C แบบ 32-bit Scalar แทนการจำลอง MMX บนสแตก |

---

## 4. กฎการตรวจสอบรหัสเครื่อง ARM64 NEON (Disassembly Verification Rule)

> [!IMPORTANT]
> **กฎเหล็กเมื่อเขียนหรือแก้ไข Binary Patch ด้วยชุดคำสั่ง ARM64 SIMD / NEON:**
> ห้ามคำนวณบิตฟิลด์ของคำสั่ง NEON ด้วยมือเพียงอย่างเดียวโดยไม่ตรวจสอบกับ Disassembler เด็ดขาด ต้องตรวจสอบด้วย `/usr/bin/as` และ `/usr/bin/objdump -d` (มีติดตั้งพร้อมใช้งานบนเครื่อง R36H) ทุกครั้ง

### กรณีศึกษาข้อผิดพลาดระดับบิตที่ต้องระวัง:
1. **บิต `size[11:10]` ของคำสั่ง `ld4` / `st4`**:
   * `0x4cdf0020` / `0x4c9f0080` (`size = 00`): `ld4/st4 {v0.16b-v3.16b}, [x1], #64` — แยกช่องสีระดับ **8-bit byte** (`B`, `G`, `R`, `A`) ถูกต้อง
   * `0x4cdf0420` / `0x4c9f0480` (`size = 01`): `ld4/st4 {v0.8h-v3.8h}, [x1], #64` — แยกข้อมูลระดับ **16-bit halfword** (`BG`, `RA`) ทำให้ช่องสี `B` กับ `R` ไม่ถูกสลับ (ภาพเพี้ยนเป็นสีฟ้า) และสลับพิกเซลคู่กับพิกเซลคี่แทน
2. **บิต `imm5` และ `imm4` ของคำสั่ง `ins` / `mov` เวกเตอร์ (`mov v0.d[1], v1.d[0]`)**:
   * `0x6e180420` (`imm5 = 11000`, `imm4 = 0000`): `mov v0.d[1], v1.d[0]` — คัดลอกพิกเซลที่ 2 เข้าครึ่งบน (`d[1]`) ของเรจิสเตอร์ `v0` ถูกต้อง
   * `0x6e081c20` (`imm5 = 01000`): กลายเป็น `mov v0.d[0], v1.d[0]` ซึ่งเขียนทับพิกเซลแรกใน `d[0]` และปล่อยให้ `d[1]` เป็น `0` (ทำให้เกิดเส้นดำแนวตั้งคั่นทุกพิกเซลคี่)

### คำสั่งตรวจสอบ Disassembly บนเครื่อง R36H ผ่าน SSH:
```bash
# ตรวจสอบ Patch 4 (convertRowToRGBA8 @ 0x4c869c)
objdump -d --start-address=0x4c869c --stop-address=0x4c86dc /roms/ports/nfsu2/nfsu2.aarch64

# ตรวจสอบ Patch 5a (sub_006FFAA7 @ 0x47c0440)
objdump -d --start-address=0x47c0440 --stop-address=0x47c04ec /roms/ports/nfsu2/nfsu2.aarch64
```

---

## 5. การใช้งานสคริปต์ [`patch_video.py`](./patch_video.py) และค่า MD5 มาตรฐาน

```bash
# 1. แพตช์ไบนารีทั้งหมดในโปรเจกต์ (nfsu2.aarch64, v10, v12)
python patch_video.py

# 2. ตรวจสอบสถานะการแพตช์โดยไม่แก้ไขไฟล์
python patch_video.py --verify

# 3. ย้อนกลับเป็นไบนารีต้นฉบับก่อนแพตช์วิดีโอ
python patch_video.py --revert
```

### ตารางค่า MD5 ของไบนารี ARM64 (`v1.1.0`)
| ไบนารี | ขนาด (Bytes) | MD5 (ปลดล็อกเฉพาะซับไตเติล) | MD5 (ปลดล็อกซับไตเติล + แพตช์วิดีโอลื่นไหล) |
| :--- | :--- | :--- | :--- |
| `nfsu2.aarch64` / `nfsu2.aarch64.v10` | `87,349,296` | `e4e82fa19410a0f6131df8ecb75606d4` | `ceb3ba53a8bc29583e72a42765922ce3` |
| `nfsu2.aarch64.v12` | `88,589,712` | `541ac31df753868eb8cc8675cc37c697` | `56f06a62233dbe68dc23d6fd0ca7cd87` |
