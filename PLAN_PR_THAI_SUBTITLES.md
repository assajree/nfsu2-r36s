# แผนการแก้ไข Source Code — PR #2: Native Thai Localization & Universal Subtitles Support

**Document ID:** `NFSU2-R36H-PLAN-PR2`  
**Target Repository:** `source/nfsu2-recompiled-r36s` ([manuelpllull/nfsu2-recompiled-r36s](https://github.com/manuelpllull/nfsu2-recompiled-r36s))  
**Scope:** การทำให้พารามิเตอร์ `--lang=Thai` (`setGuestLanguage("Thai")`) ทำงานได้สมบูรณ์ในระดับ Runtime โดยไม่ต้องแพตช์ไฟล์ `SPEED2.EXE` บนดิสก์ พร้อมเปิดใช้งานซับไตเติลคัทซีนและวิดีโอ (อ้างอิงข้อมูลทางเทคนิคจาก [`KNOWLEDGE.md`](./KNOWLEDGE.md))  

> [!NOTE]
> แผนนี้แยกเป็นอิสระจาก [`PLAN_PR_VIDEO_PERF.md`](./PLAN_PR_VIDEO_PERF.md) เพื่อให้ง่ายต่อการส่ง Pull Request แยกกันระหว่าง **ฟีเจอร์ปรับปรุงประสิทธิภาพวิดีโอ (PR #1)** และ **ฟีเจอร์รองรับภาษาไทย + ซับไตเติล (PR #2)**

---

## 1. ปัญหาเดิมใน Source Code ปัจจุบัน

1. ใน `android/app/src/main/cpp/guest_runtime.cpp` (บรรทัด ~1407) มีรายชื่อ `"Thai"` อยู่ใน `setGuestLanguage(...)` อยู่แล้ว แต่ใน `SPEED2.EXE` เวอร์ชัน US/EU (ทั้ง `v10` และ `v12`) ตาราง Language Descriptor มีเพียง 11 ช่อง (`0x00..0x0A`, `ENGLISH` ถึง `JAPANESE`) ทำให้เมื่อ `SPEED2.EXE` อ่าน `"language" = "Thai"` (ID `0x0B`) เกมจะอ้างอิงพอยน์เตอร์ `NULL` และไม่ยอมโหลด `LANGUAGES\THAILAND.BIN` รวมถึงไม่สตรีมเท็กซ์เจอร์ฟอนต์ไทยจาก `LanguageTextures.bin`
2. ฟังก์ชันตรวจสอบซับไตเติลในตัวเกม (`sub_0050CEF0` และ `sub_005535F0` ใน `v10` / `sub_0050D350` และ `sub_00553940` ใน `v12`) อนุญาตให้แสดงซับไตเติลเฉพาะบางภาษาในยุโรป (`German`, `French`, `Spanish/Italian`, `Polish`) เท่านั้น ทำให้ภาษาไทยและภาษาอังกฤษถูกปิดซับไตเติลไว้

---

## 2. รายละเอียดการแก้ไข Source Code C/C++

### 2.1 ไฟล์ `config/exe_functions.txt` (เพิ่มที่อยู่ฟังก์ชันและตารางข้อมูลทั้ง `v10` และ `v12`)

เพิ่มรายการสำหรับ `v10` และ `v12` ลงใน `config/exe_functions.txt` (ตรวจสอบคู่ `v12` ด้วย `scripts/exe_addr_map.py` ก่อนรัน):

```text
0x0050CEF0  0x0050D350  func  subtitle whitelist check (overrides.c)
0x005535F0  0x00553940  func  in-game movie subtitle branch (overrides.c)
```

*(หมายเหตุ: สำหรับที่อยู่ข้อมูลใน `.rdata` / `.data` ของ `v12` เช่น ตาราง Language Descriptor `0x007f7020` และสตริง `LANGUAGES\JAPANESE.BIN` `0x0079a6e8` ให้ใช้ `scripts/exe_addr_map.py` หา Offset ของ `v12` เพิ่มเป็น `data` ใน `config/exe_functions.txt` แล้วรัน `python3 scripts/exe_variant.py header`)*

---

### 2.2 ไฟล์ `android/app/src/main/cpp/guest_runtime.cpp` (In-Memory Runtime Patch เมื่อ `guestLanguage == "Thai"`)

หลังจากโหลด `SPEED2.EXE` เข้า `memory` เสร็จสิ้น (บริเวณหลังบรรทัด ~725 ใน `guest_runtime.cpp` ที่ตรวจสอบ `NFS_EXE_ID` แล้ว) หาก `guestLanguage == "Thai"` ให้เขียนข้อมูล Language Slot 10 (แทนที่ `JAPANESE` ด้วย `THAILAND` / ID `0x0b`) ลงในหน่วยความจำจำลอง `memory` โดยตรง:

```cpp
// แนวทางเขียนลง guest memory เมื่อ guestLanguage == "Thai" (ไม่ต้องแก้ SPEED2.EXE บนดิสก์)
if (guestLanguage == "Thai") {
    // 1. เปลี่ยนชื่อไฟล์ภาษาใน Slot 10 จาก "LANGUAGES\\JAPANESE.BIN" -> "LANGUAGES\\THAILAND.BIN"
    // 2. เปลี่ยนชื่อ Suffix ฟอนต์จาก "JAPANESE" -> "THAILAND" (เพื่อให้ sub_0051baa0 ตัดคำว่า _thailand)
    // 3. ใส่แฮชฟอนต์ไทยจาก LanguageTextures.bin: 0x4815619d และ 0xa73823ff
    // 4. เปลี่ยน Language ID ของ Slot 10 และ Fallback ID เป็น 0x0b (Thai)
    NFS_RUNTIME_LOG(ANDROID_LOG_INFO, "NFSU2", "Applied in-memory Thai localization table for %s", NFS_EXE_ID);
}
```

ข้อดีของการทำใน `guest_runtime.cpp` คือ:
* ผู้ใช้สามารถใช้ไฟล์ `SPEED2.EXE` ต้นฉบับ (v1.0 หรือ v1.2 ที่ผ่านการเช็กขนาด/แฮชเดิม) ได้ทันทีโดยไม่ต้องดัดแปลงไฟล์ `.EXE` บนดิสก์
* หากผู้ใช้เลือก `--lang=English` หรือภาษาอื่น ๆ โค้ดส่วนนี้จะไม่ทำงาน และเกมจะทำงานตามต้นฉบับ 100%

---

### 2.3 ไฟล์ `src/runtime/overrides.c` (ปลดล็อกซับไตเติลคัทซีนและวิดีโอ)

เพิ่ม Override (อาจควบคุมด้วยตัวแปรสภาพแวดล้อม เช่น `NFSU2_SUBTITLES=1` หรือเปิดอัตโนมัติเมื่อเลือกภาษาไทย) ดังนี้:

```c
/* 0x0050CEF0 (v12 0x0050D350): IsSubtitlesEnabled() -> always return 1 so story comic cutscenes
 * (PSA Brooke Burke, Scene01..Scene20) load subtitle streams for Thai and all languages. */
static void ov_is_subtitles_enabled(void) {
    g_eax = 1;
    g_esp += 4;
}
```

และสำหรับ `sub_005535F0` (v12: `0x00553940`):
* สามารถเลือกทำได้ 2 วิธี:
  1. ปรับ `sub_005535F0` ให้ข้ามเงื่อนไข `lang == 4 || lang == 12` (หรือเพิ่ม `|| lang == 11` สำหรับภาษาไทย) ในการแสดงซับไตเติลวิดีโอ
  2. หรือแพตช์เงื่อนไขในหน่วยความจำจำลอง (เฉพาะเมื่อ `guestLanguage == "Thai"` หรือเปิด `NFSU2_SUBTITLES=1`) เพื่อคงพฤติกรรมต้นฉบับของฟังก์ชันส่วนที่เหลือไว้ครบถ้วน

---

### 2.4 ขั้นตอนการ Build และทดสอบบนเครื่อง R36H

ใช้ขั้นตอน **Fast Runtime Build (~15 วินาที)** แบบเดียวกับที่อธิบายไว้ใน [`PLAN_PR_VIDEO_PERF.md`](./PLAN_PR_VIDEO_PERF.md) ส่วนที่ 2 โดยเพิ่ม `--weaken-symbol=sub_0050CEF0` (และ `sub_005535F0` หาก Override ทั้งฟังก์ชัน) แล้วทดสอบรันบน R36H ด้วย `--lang=Thai` เพื่อตรวจสอบ:
1. ฟอนต์ไทย (`conduitmditc_tt14i_thailand`, `conduitmditc_tt21i_thailand`) แสดงผลในเมนูและ HUD ครบถ้วน
2. ซับไตเติลภาษาไทยขึ้นในคัทซีน `PSA.vp6` และ `Scene01.vp6`..`Scene20.vp6`
3. การสลับกลับเป็น `--lang=English` ทำงานได้ปกติไม่มีผลข้างเคียง
