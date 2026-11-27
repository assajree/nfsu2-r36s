# แผนการแก้ไข Source Code และการ Build บนเครื่อง R36H — PR #1: Cutscene / FMV Video Performance Optimization

**Document ID:** `NFSU2-R36H-PLAN-PR1`  
**Target Repository:** `source/nfsu2-recompiled-r36s` ([manuelpllull/nfsu2-recompiled-r36s](https://github.com/manuelpllull/nfsu2-recompiled-r36s))  
**Scope:** การนำการปรับปรุงประสิทธิภาพวิดีโอคัทซีน (FMV / `.vp6`) ทั้งหมดจาก `patch_video.py` เข้าสู่ซอร์สโค้ด C/C++ โดยตรง พร้อมขั้นตอนการคอมไพล์ (Build) ผ่าน Docker (`nfsu2-r36s-build`) ที่เตรียมไว้บนเครื่อง Linux Host  

> [!NOTE]
> แผนนี้แยกเฉพาะส่วน **การเพิ่มประสิทธิภาพวิดีโอสากล (Universal Video Performance)** สำหรับทำ Pull Request ที่ 1 โดยไม่มีส่วนของภาษาไทยปะปน (ส่วนภาษาไทยและซับไตเติลแยกไว้ใน [`PLAN_PR_THAI_SUBTITLES.md`](./PLAN_PR_THAI_SUBTITLES.md))

---

## ส่วนที่ 1: รายละเอียดการแก้ไขไฟล์ Source Code C/C++

### 1.1 ไฟล์ `android/app/src/main/cpp/d3d9_render_thread.inc`

#### (ก) ปลดล็อก Async `MovieTexture` Lock ใน `rt::textureLockAsync` (บรรทัดที่ ~468)
เมื่อเกมล็อกเท็กซ์เจอร์เต็มแผ่น (`!hasRect && level == 0`) แบบเขียนทับ (`!(flags & D3DLOCK_READONLY)`) ให้สามารถส่งผ่านคิว `OpTexUpload` แบบ Asynchronous ได้ทุกเฟรม แม้ว่าตัวเกม (`sub_005BF680`) จะส่ง `Flags = 0` มาโดยไม่ได้ระบุ `D3DLOCK_DISCARD`:

```cpp
// เดิม (บรรทัด ~468):
if (level != 0 || (flags & D3DLOCK_READONLY) || (!fresh && !(flags & D3DLOCK_DISCARD)))
    return false;

// แก้ไขเป็น:
if (level != 0 || (flags & D3DLOCK_READONLY))
    return false;
```

#### (ข) ส่งแฟล็ก `D3DLOCK_DISCARD` (`0x2000`) ใน `rt::exec` (`OpTexUpload`, บรรทัดที่ ~708 และ ~723)
เนื่องจาก `OpTexUpload` เขียนทับพิกเซลของ Mip Level นั้นทั้งแผ่นเสมอ จึงต้องส่ง `D3DLOCK_DISCARD` (`0x2000u`) ให้ `LockRect` เพื่อป้องกันไม่ให้ GLES Backend เรียก `readBack()` (`glReadPixels` ย้อนกลับจาก GPU):

```cpp
// เดิม (บรรทัด ~708 สำหรับ 2D Texture และ ~723 สำหรับ Cube/Vol Texture):
if (SUCCEEDED(tex->LockRect(c.u[1], &lr, nullptr, 0)) && lr.pBits) {

// แก้ไขเป็น (ทั้ง 2 จุด):
if (SUCCEEDED(tex->LockRect(c.u[1], &lr, nullptr, D3DLOCK_DISCARD)) && lr.pBits) {
```

---

### 1.2 ไฟล์ `ports/r36s/d3d9_gles/d3d9_gles_resources.h`

#### (ก) เพิ่มลูป ARM64 NEON ทีละ 16 พิกเซลใน `convertRowToRGBA8` (บรรทัดที่ ~40)
เพิ่ม `#if defined(__aarch64__)` สำหรับ `D3DFMT_A8R8G8B8` และ `D3DFMT_X8R8G8B8` เพื่อใช้ชุดคำสั่ง `vld4q_u8` / `vst4q_u8` แปลงสีทีละ 16 พิกเซล (64 ไบต์ต่อรอบ):

```cpp
#if defined(__aarch64__)
#include <arm_neon.h>
#endif
```

และภายใน `convertRowToRGBA8`:
```cpp
    case D3DFMT_A8R8G8B8:
        // B,G,R,A -> R,G,B,A
#if defined(__aarch64__)
        for (; width >= 16; width -= 16, src += 64, dst += 64) {
            uint8x16x4_t px = vld4q_u8(src);
            uint8x16_t tmp = px.val[0];
            px.val[0] = px.val[2];
            px.val[2] = tmp;
            vst4q_u8(dst, px);
        }
#endif
        for (UINT x = 0; x < width; ++x, src += 4, dst += 4) {
            dst[0] = src[2];
            dst[1] = src[1];
            dst[2] = src[0];
            dst[3] = src[3];
        }
        break;
```

#### (ข) เก็บบัฟเฟอร์ `m_upload` (2 MB) ไว้ใช้ซ้ำสำหรับ Dynamic Surface ใน `IDirect3DSurface9GLES::UnlockRect` (บรรทัดที่ ~319)
สำหรับเท็กซ์เจอร์ที่มีการอัปเดตซ้ำทุกเฟรม (`m_keepShadow == true` เช่น `MovieTexture`) ไม่ต้องทำลายเวกเตอร์ `m_upload` ทุกเฟรม เพื่อตัด `mmap`/`munmap` syscalls, Cross-core TLB shootdowns และ 512 Minor Page Faults ต่อเฟรม:

```cpp
// เดิม (บรรทัด ~319):
if (!m_keepShadow && m_uploaded) { std::vector<uint8_t>().swap(m_cpuBuffer); g_texShadowBytes -= m_shadowAccounted; m_shadowAccounted = 0; }
std::vector<uint8_t>().swap(m_upload);

// แก้ไขเป็น:
if (!m_keepShadow && m_uploaded) { std::vector<uint8_t>().swap(m_cpuBuffer); g_texShadowBytes -= m_shadowAccounted; m_shadowAccounted = 0; }
if (!m_keepShadow) { std::vector<uint8_t>().swap(m_upload); }
```

---

### 1.3 ไฟล์ `config/exe_functions.txt` และ `src/runtime/overrides.c`

#### (ก) เพิ่มรายการฟังก์ชันใน `config/exe_functions.txt`
เพิ่มที่อยู่ฟังก์ชันของทั้ง `v10` และ `v12` ลงท้ายไฟล์ `config/exe_functions.txt`:

```text
0x006FFAA7  0x006FFD4A  func  VP6 YUV420 to ARGB8888 scanline converter, MMX (overrides.c)
0x0070CCE8  0x0070CF98  func  VP6 CPU feature detection: MMX/XMM/WMT (overrides.c)
```

จากนั้นรันคำสั่งอัปเดต Header:
```bash
python3 scripts/exe_variant.py header
```

#### (ข) เพิ่มฟังก์ชัน Native Override ใน `src/runtime/overrides.c`
เพิ่มฟังก์ชันแปลงสี `YUV420 -> ARGB8888` ด้วย ARM64 NEON (`ov_vp6_yuv420_to_argb`) และฟังก์ชันปิดโหมดจำลอง MMX ของ VP6 (`ov_vp6_cpu_features`) ลงใน `src/runtime/overrides.c` และลงทะเบียนในตาราง `k_overrides[]`:

```c
#if defined(__aarch64__)
#include <arm_neon.h>
#endif

/* 0x0070CCE8 (v12 0x0070CF98): VP6 CPU feature detection (cdecl: int *has_mmx, int *has_xmm, int *has_wmt).
 * The lifted MMX/SSE2 paths emulate 64/128-bit SIMD through stack V128 unions (~10x slower than VP6's
 * built-in 32-bit scalar C routines on ARM64). Report 0 for all three so VP6_InitFunctionPointers selects
 * native 32-bit scalar C functions. */
static void ov_vp6_cpu_features(void) {
    const uint32_t esp = g_esp;
    const uint32_t p_mmx = *(const uint32_t*)ADDR(esp + 4);
    const uint32_t p_xmm = *(const uint32_t*)ADDR(esp + 8);
    const uint32_t p_wmt = *(const uint32_t*)ADDR(esp + 12);
    if (p_mmx) *(uint32_t*)ADDR(p_mmx) = 0;
    if (p_xmm) *(uint32_t*)ADDR(p_xmm) = 0;
    if (p_wmt) *(uint32_t*)ADDR(p_wmt) = 0;
    g_eax = 0;
    g_esp = esp + 4;
}

/* 0x006FFAA7 (v12 0x006FFD4A): YUV420 -> ARGB8888 scanline converter (2 pixels per iteration).
 * Uses precomputed 16-bit signed lookup tables initialized by sub_00700254 at:
 *   Y_tab = 0x008149E0, U_tab = 0x008151E0, V_tab = 0x008159E0 (identical in v10 and v12). */
static void ov_vp6_yuv420_to_argb(void) {
    const uint32_t esp = g_esp;
    uint32_t y_va       = *(const uint32_t*)ADDR(esp + 4);
    uint32_t u_va       = *(const uint32_t*)ADDR(esp + 8);
    uint32_t v_va       = *(const uint32_t*)ADDR(esp + 12);
    uint32_t dst_va     = *(const uint32_t*)ADDR(esp + 16);
    uint32_t dst_end_va = *(const uint32_t*)ADDR(esp + 20);

    if (dst_end_va > dst_va) {
        const uint32_t count = (dst_end_va - dst_va) >> 3;
        const uint8_t* y_ptr = (const uint8_t*)ADDR(y_va);
        const uint8_t* u_ptr = (const uint8_t*)ADDR(u_va);
        const uint8_t* v_ptr = (const uint8_t*)ADDR(v_va);
        uint8_t* dst_ptr     = (uint8_t*)ADDR(dst_va);

        const int16_t* y_tab = (const int16_t*)ADDR(0x008149E0u);
        const int16_t* u_tab = (const int16_t*)ADDR(0x008151E0u);
        const int16_t* v_tab = (const int16_t*)ADDR(0x008159E0u);

        for (uint32_t i = 0; i < count; ++i) {
            const uint8_t u = *u_ptr++;
            const uint8_t v = *v_ptr++;
            const uint8_t y0 = y_ptr[0];
            const uint8_t y1 = y_ptr[1];
            y_ptr += 2;
#if defined(__aarch64__)
            int16x4_t vu  = vld1_s16(&u_tab[(uint32_t)u * 4]);
            int16x4_t vv  = vld1_s16(&v_tab[(uint32_t)v * 4]);
            int16x4_t vuv = vqadd_s16(vu, vv);
            int16x4_t vy0 = vld1_s16(&y_tab[(uint32_t)y0 * 4]);
            int16x4_t vy1 = vld1_s16(&y_tab[(uint32_t)y1 * 4]);
            int16x8_t vp  = vcombine_s16(vqadd_s16(vy0, vuv), vqadd_s16(vy1, vuv));
            uint8x8_t out = vqmovun_s16(vp);
            vst1_u8(dst_ptr, out);
#else
            for (int c = 0; c < 4; ++c) {
                int uv = (int)u_tab[u * 4 + c] + (int)v_tab[v * 4 + c];
                int p0 = (int)y_tab[y0 * 4 + c] + uv;
                int p1 = (int)y_tab[y1 * 4 + c] + uv;
                dst_ptr[c]     = (uint8_t)(p0 < 0 ? 0 : (p0 > 255 ? 255 : p0));
                dst_ptr[4 + c] = (uint8_t)(p1 < 0 ? 0 : (p1 > 255 ? 255 : p1));
            }
#endif
            dst_ptr += 8;
        }
        g_ecx = y_va + count * 2;
        g_edx = u_va + count;
    }
    g_eax = 0;
    g_esp = esp + 4;
}
```

และในตาราง `k_overrides[]` (ท้ายไฟล์ `src/runtime/overrides.c`):
```c
static const OverrideEntry k_overrides[] = {
    {NFS_VA(0x006F5D25), ov_is_cyrix},
    {NFS_VA(0x0075ADE0), ov_crt_memmove},
    {NFS_VA(0x006FFAA7), ov_vp6_yuv420_to_argb},
    {NFS_VA(0x0070CCE8), ov_vp6_cpu_features},
};
```

> [!TIP]
> เพื่อให้ทั้ง Direct Call (`bl sub_006FFAA7`) และ Indirect Dispatch Call วิ่งเข้าฟังก์ชันใหม่เหมือนกันทั้งหมด สามารถประกาศ `void sub_006FFAA7(void) { ov_vp6_yuv420_to_argb(); }` และ `void sub_0070CCE8(void) { ov_vp6_cpu_features(); }` พร้อมเพิ่มชื่อ `sub_006FFAA7 sub_0070CCE8` ในตัวแปร `WRAP_V10` ของ `ports/r36s/build_guest_vm.sh` (หรือใช้ `objcopy --weaken-symbol` ในวิธีที่ 1 ด้านล่าง)

---

## ส่วนที่ 2: คู่มือการ Build ผ่าน Docker (`nfsu2-r36s-build`)

ใช้ Docker image `nfsu2-r36s-build` และ volume `nfsu2-r36s-work` ที่เตรียมไว้แล้วบนเครื่อง Linux Host (รัน `docker run` โดยตรง ไม่ต้องครอบด้วย `sg docker` และไม่ใช้ `build.py --native` บน host ที่มี `glibc >= 2.29`):

### วิธีที่ 1: Fast Runtime Relink (~20 วินาที) — เมื่อแก้ไขเฉพาะ Runtime / Overrides

ใช้เมื่อ `sub_006FFAA7` และ `sub_0070CCE8` ถูก wrap ไว้ใน `guest-v10` แล้ว โดย link โค้ด runtime ใหม่เข้ากับ Guest `.o` ทั้ง 113 ไฟล์ที่ cache อยู่ใน Docker volume `nfsu2-r36s-work`:

```bash
docker run --rm \
  -v nfsu2-r36s-work:/work \
  -v /mnt/d/r36h/nfsu2/source/nfsu2-recompiled-r36s:/src \
  nfsu2-r36s-build bash -c '
    rm -rf /work/host-v10 &&
    GUEST_DIR=/work/guest-v10 \
    NFS_EXE_VARIANT_H=/work/nfsu2-v10/src/recomp/gen/nfs_exe_variant.h \
    OUT=/work/host-v10 \
    bash /src/ports/r36s/build_cross.sh &&
    cp /work/host-v10/package/nfsu2.aarch64 /src/build/r36s/nfsu2-v10.aarch64 &&
    cp /work/host-v10/package/nfsu2.aarch64.debug /src/build/r36s/nfsu2-v10.aarch64.debug &&
    sha1sum /src/build/r36s/nfsu2-v10.aarch64 | cut -d" " -f1 > /src/build/r36s/nfsu2-v10.aarch64.sha1
  '
```

### วิธีที่ 2: อัปเดต Guest Objects เมื่อเพิ่มฟังก์ชันใหม่ใน `WRAP_V10`

หาก `sub_006FFAA7` หรือ `sub_0070CCE8` ยังไม่เคยอยู่ใน `WRAP_V10` ของ `ports/r36s/build_guest_vm.sh`:
1. เพิ่ม `sub_006FFAA7` และ `sub_0070CCE8` ลงใน `WRAP_V10` (หรือทำ `objcopy --weaken-symbol=sub_006FFAA7 --weaken-symbol=sub_0070CCE8` บน `/work/guest-v10/*.o`) เพื่อเปลี่ยนสัญลักษณ์เดิมให้เป็น `_orig` / weak symbol ก่อน
2. รัน `build_guest_vm.sh` ภายใน container `nfsu2-r36s-build` (หรือ weaken symbol ใน `/work/guest-v10/*.o`) แล้วจึงรันคำสั่ง Fast Runtime Relink ด้านบน

### การนำไฟล์ไปทดสอบบนเครื่อง R36H (`ssh r36h`)

หลัง Build เสร็จจะได้ไฟล์ `/mnt/d/r36h/nfsu2/source/nfsu2-recompiled-r36s/build/r36s/nfsu2-v10.aarch64` จากนั้นอัปโหลดไปที่ `/roms/ports/nfsu2/` บนเครื่อง R36H:

```bash
scp /mnt/d/r36h/nfsu2/source/nfsu2-recompiled-r36s/build/r36s/nfsu2-v10.aarch64 r36h:/roms/ports/nfsu2/nfsu2.aarch64.v10.new
ssh r36h 'chmod 755 /roms/ports/nfsu2/nfsu2.aarch64.v10.new && mv -f /roms/ports/nfsu2/nfsu2.aarch64.v10.new /roms/ports/nfsu2/nfsu2.aarch64.v10 && cp -f /roms/ports/nfsu2/nfsu2.aarch64.v10 /roms/ports/nfsu2/nfsu2.aarch64 && sync'
```
