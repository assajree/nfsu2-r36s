# แผนการแก้ไข Source Code — PR #2: Native Thai Localization & Universal Subtitles Support (v10)

**Document ID:** `NFSU2-R36H-PLAN-PR2`  
**Target Repository:** `source/nfsu2-recompiled-r36s` ([manuelpllull/nfsu2-recompiled-r36s](https://github.com/manuelpllull/nfsu2-recompiled-r36s))  
**Target Executable:** `v10` (`SPEED2.EXE` US Retail v1.0 No-CD, `4,788,224` bytes) เท่านั้น  
**Scope:** การทำให้พารามิเตอร์ `--lang=Thai` (`setGuestLanguage("Thai")`) ทำงานได้สมบูรณ์ในระดับ Runtime โดยไม่ต้องแพตช์ไฟล์ `SPEED2.EXE` บนดิสก์ พร้อมระบบเปิด/ปิดซับไตเติลคัทซีนและวิดีโอผ่าน `NFSU2_SUBTITLES` ใน `nfsu2.cfg` (อ้างอิงข้อมูลทางเทคนิคจาก [`KNOWLEDGE.md`](./KNOWLEDGE.md))  

> [!NOTE]
> แผนนี้แยกเป็นอิสระจาก [`PLAN_PR_VIDEO_PERF.md`](./PLAN_PR_VIDEO_PERF.md) เพื่อให้ง่ายต่อการส่ง Pull Request แยกกันระหว่าง **ฟีเจอร์ปรับปรุงประสิทธิภาพวิดีโอ (PR #1)** และ **ฟีเจอร์รองรับภาษาไทย + ซับไตเติล (PR #2)** โดยขอบเขตของเอกสารนี้จำกัดเฉพาะ **`v10`**

---

## 1. ปัญหาเดิมใน Source Code ปัจจุบัน

1. ใน `android/app/src/main/cpp/guest_runtime.cpp` (บรรทัด ~1407) มีรายชื่อ `"Thai"` อยู่ใน `setGuestLanguage(...)` อยู่แล้ว แต่ใน `SPEED2.EXE` (`v10`) ตาราง Language Descriptor มีเพียง 11 ช่อง (`0x00..0x0A`, `ENGLISH` ถึง `JAPANESE`) ทำให้เมื่อ `SPEED2.EXE` อ่าน `"language" = "Thai"` (ID `0x0B`) เกมจะอ้างอิงพอยน์เตอร์ `NULL` และไม่ยอมโหลด `LANGUAGES\THAILAND.BIN` รวมถึงไม่สตรีมเท็กซ์เจอร์ฟอนต์ไทยจาก `LanguageTextures.bin`
2. ฟังก์ชันตรวจสอบซับไตเติลในตัวเกม (`sub_0050CEF0` และ `sub_005535F0` ใน `v10`) อนุญาตให้แสดงซับไตเติลเฉพาะบางภาษาในยุโรป (`German`, `French`, `Spanish/Italian`, `Polish`) เท่านั้น ทำให้ภาษาไทยและภาษาอังกฤษถูกปิดซับไตเติลไว้ และยังไม่มีตัวเลือกใน `nfsu2.cfg` สำหรับเปิด/ปิดซับไตเติลได้เอง

---

## 2. รายละเอียดการแก้ไข Source Code & Config (เฉพาะ `v10`)

### 2.1 ไฟล์ `config/exe_functions.txt` (เพิ่มที่อยู่ฟังก์ชันของ `v10`)

เพิ่มรายการสำหรับ `v10` ลงใน `config/exe_functions.txt` แล้วรัน `python3 scripts/exe_variant.py header` เพื่ออัปเดต `nfs_exe_addr.h` (หาก Override ด้วย `--weaken-symbol`):

```text
0x0050CEF0  -  func  subtitle whitelist check (overrides.c)
0x005535F0  -  func  in-game movie subtitle branch (overrides.c)
```

---

### 2.2 ไฟล์ `android/app/src/main/cpp/guest_runtime.cpp` (In-Memory Runtime Patch สำหรับ `v10`)

หลังจากโหลด `SPEED2.EXE` เข้า `memory` เสร็จสิ้น (บริเวณหลังบรรทัด ~725 ใน `guest_runtime.cpp` ที่ตรวจสอบ `NFS_EXE_ID` แล้ว) ให้ตรวจสอบว่า `strcmp(NFS_EXE_ID, "v10") == 0 && guestLanguage == "Thai"` แล้วเขียนข้อมูล Language Slot 10 (แทนที่ `JAPANESE` ด้วย `THAILAND` / ID `0x0b`) ลงในหน่วยความจำจำลอง `memory` โดยตรง:

```cpp
// แนวทางเขียนลง guest memory สำหรับ v10 เมื่อ guestLanguage == "Thai" (ไม่ต้องแก้ SPEED2.EXE บนดิสก์)
if (std::strcmp(NFS_EXE_ID, "v10") == 0 && guestLanguage == "Thai") {
    // 1. เปลี่ยนชื่อไฟล์ภาษาใน Slot 10 (0x0079a6e8): "LANGUAGES\\JAPANESE.BIN" -> "LANGUAGES\\THAILAND.BIN"
    // 2. เปลี่ยนชื่อ Suffix ฟอนต์ (0x0079a700): "JAPANESE" -> "THAILAND" (เพื่อให้ sub_0051baa0 ตัดคำว่า _thailand)
    // 3. ใส่แฮชฟอนต์ไทยจาก LanguageTextures.bin (0x007f6f40, 0x007f6f48): 0x4815619d และ 0xa73823ff
    // 4. เปลี่ยน Language ID ของ Slot 10 (0x007f70c0, 0x007f7108) และ Fallback ID (0x005b7677, 0x007fca00) เป็น 0x0b (Thai)
    NFS_RUNTIME_LOG(ANDROID_LOG_INFO, "NFSU2", "Applied in-memory Thai localization table for v10");
}
```

ข้อดีของการทำใน `guest_runtime.cpp` คือ:
* ผู้ใช้สามารถใช้ไฟล์ `SPEED2.EXE` (`v10`) ต้นฉบับที่ผ่านการเช็กขนาด/แฮชเดิมได้ทันทีโดยไม่ต้องดัดแปลงไฟล์ `.EXE` บนดิสก์
* หากผู้ใช้เลือก `--lang=English` หรือภาษาอื่น ๆ โค้ดส่วนนี้จะไม่ทำงาน และเกมจะทำงานตามต้นฉบับ 100%

---

### 2.3 ไฟล์ `src/runtime/overrides.c` (เปิด/ปิดซับไตเติลผ่าน `NFSU2_SUBTITLES`)

อ่านค่าตัวแปรสภาพแวดล้อม `NFSU2_SUBTITLES` (และ `NFSU2_LANG`) เพื่อควบคุมพฤติกรรมของ `sub_0050CEF0` และ `sub_005535F0` ใน `v10`:

| ค่า `NFSU2_SUBTITLES` | พฤติกรรม |
| :--- | :--- |
| `1` | **เปิด** ซับไตเติลคัทซีนและวิดีโอสำหรับทุกภาษา (รวมถึงไทยและอังกฤษ) |
| `0` | **ปิด** ซับไตเติลทั้งหมด |
| ไม่ระบุ (`unset` / ว่าง) | เปิดอัตโนมัติเมื่อ `NFSU2_LANG=Thai`, ภาษาอื่นใช้ค่าเริ่มต้นของตัวเกม |

แนวทางโค้ดสำหรับ `sub_0050CEF0`:

```c
/* 0x0050CEF0 (v10): IsSubtitlesEnabled()
 * Controlled by NFSU2_SUBTITLES (1=on, 0=off, unset=on for Thai / game default otherwise). */
static int get_subtitle_mode(void) {
    static int mode = -2;
    if (mode == -2) {
        const char* e = getenv("NFSU2_SUBTITLES");
        if (e && e[0] == '0') mode = 0;
        else if (e && e[0] == '1') mode = 1;
        else {
            const char* lang = getenv("NFSU2_LANG");
            mode = (lang && strcmp(lang, "Thai") == 0) ? 1 : -1; /* -1 = fallback to original */
        }
    }
    return mode;
}

static void ov_is_subtitles_enabled(void) {
    int mode = get_subtitle_mode();
    if (mode >= 0) {
        g_eax = (uint32_t)mode;
        g_esp += 4;
        return;
    }
    /* หาก mode == -1: เรียกฟังก์ชันเดิม หรือคงลอจิกเช็กภาษาต้นฉบับ */
}
```

และสำหรับ `sub_005535F0` (in-game movie subtitle branch ใน `v10`):
* ใช้ `get_subtitle_mode()` ควบคุมสาขาแสดงซับไตเติลวิดีโอ (`mode == 1` บังคับแสดง, `mode == 0` บังคับซ่อน, `mode == -1` ใช้เงื่อนไขเดิมของเกม)

---

### 2.4 ไฟล์ `ports/nfsu2/nfsu2.cfg` และ `ports/NFSU2.sh` (รองรับ Config เปิด/ปิดซับไตเติล)

1. เพิ่มตัวเลือกใน `nfsu2.cfg` (และ template `ports/r36s/package/nfsu2.cfg` หากมี):
   ```ini
   # Subtitles: 1 = on (all languages), 0 = off, unset/empty = auto (on for Thai)
   NFSU2_SUBTITLES=1
   ```
2. ใน `ports/NFSU2.sh` (และ `ports/r36s/package/NFSU2.sh`) เพิ่ม `NFSU2_SUBTITLES` เข้าไปในลูป `export` (เช่น `for v in ... NFSU2_SUBTITLES; do`) เพื่อส่งต่อค่าจาก `nfsu2.cfg` เข้าสู่ runtime

---

### 2.5 ขั้นตอนการ Build และทดสอบบนเครื่อง R36H

ใช้ขั้นตอน **Fast Runtime Build (~15–20 วินาที)** แบบเดียวกับที่อธิบายไว้ใน [`PLAN_PR_VIDEO_PERF.md`](./PLAN_PR_VIDEO_PERF.md) ส่วนที่ 2 โดยเพิ่ม `--weaken-symbol=sub_0050CEF0` (และ `sub_005535F0` หาก Override ทั้งฟังก์ชัน) เฉพาะ target `v10` แล้วทดสอบรันบน R36H เพื่อตรวจสอบ:
1. `--lang=Thai` + `NFSU2_SUBTITLES=1`: ฟอนต์ไทย (`conduitmditc_tt14i_thailand`, `conduitmditc_tt21i_thailand`) แสดงผลในเมนู/HUD และซับไตเติลภาษาไทยขึ้นใน `PSA.vp6` และ `Scene01.vp6`..`Scene20.vp6`
2. `--lang=Thai` + `NFSU2_SUBTITLES=0`: เมนู/HUD ยังเป็นภาษาไทย แต่ซับไตเติลคัทซีนและวิดีโอถูกปิดตามค่า Config
3. `--lang=English` + `NFSU2_SUBTITLES=1` / `0`: สลับกลับภาษาอังกฤษได้ปกติ และเปิด/ปิดซับไตเติลภาษาอังกฤษได้ตาม Config
