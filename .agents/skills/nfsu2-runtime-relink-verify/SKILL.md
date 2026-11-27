---
name: nfsu2-runtime-relink-verify
description: >-
  Fast-relink (~20s) NFSU2 ARM64 runtime changes (`src/runtime/`, `ports/r36s/`)
  against cached guest objects in Docker (`nfsu2-r36s-work`), port lifted x87
  or D3DX functions to bit-exact native C (`native_scene.c`, `native_math.c`,
  `world_cull.c`, `fx_cache.c`), and run A/B or `NFSU2_NATIVE_SCENE=2` /
  `NFSU2_NATIVE_SETUP=2` verification on physical R36H via `ssh r36h`
  (`playos.local` / `setup_playos_net.py`).
---

# NFSU2 Runtime Fast Relink, Native C Porting & R36H Verification

## 1. Fast Docker Runtime Relink (~20s on Linux Host)

Always use the pre-built Docker environment (`nfsu2-r36s-build` + `nfsu2-r36s-work`) on the Linux host rather than compiling natively on the R36H. Never use `build.py --native` on hosts with `glibc >= 2.29` (e.g. Linux Mint 22.3 / `glibc 2.39`), as it fails the `GLIBC_2.18` symbol check. Invoke `docker run` **directly** (do **not** wrap in `sg docker`, which fails with `setgroups: Operation not permitted` in sandboxed shells; `svvv` is already in group `docker`). When modifying only runtime C/C++ files (`src/runtime/*.c`, `ports/r36s/**`, `android/app/src/main/cpp/**`), link directly against the cached 113 guest `.o` files in Docker volume `nfsu2-r36s-work`:

```bash
docker run --rm -v nfsu2-r36s-work:/work -v /mnt/d/r36h/nfsu2/source/nfsu2-recompiled-r36s:/src nfsu2-r36s-build bash -c 'rm -rf /work/host-v10 && GUEST_DIR=/work/guest-v10 NFS_EXE_VARIANT_H=/work/nfsu2-v10/src/recomp/gen/nfs_exe_variant.h OUT=/work/host-v10 bash /src/ports/r36s/build_cross.sh && cp /work/host-v10/package/nfsu2.aarch64 /src/build/r36s/nfsu2-v10.aarch64 && cp /work/host-v10/package/nfsu2.aarch64.debug /src/build/r36s/nfsu2-v10.aarch64.debug && sha1sum /src/build/r36s/nfsu2-v10.aarch64 | cut -d" " -f1 > /src/build/r36s/nfsu2-v10.aarch64.sha1'
```

* If adding a **newly wrapped** lifted function to `WRAP_V10` in `ports/r36s/build_guest_vm.sh`, **never** rely on `objcopy --weaken-symbol` on cached `/work/guest-v10/*.o` — GCC `-O2` inlines intra-TU calls (e.g. `sub_006FFAA7` inlined 8x into `sub_006FFEAD` in `recomp_0052.o`). Instead, recompile **only** the defining `recomp_XXXX.c` into `/work/guest-v10/recomp_XXXX.wrap.c` (renaming `void sub_XXXXXXXX(void) {` to `void sub_XXXXXXXX_orig(void) {`) using the exact flags from `/work/guest-v10/.flags` (replacing `ROOT` with `/work/nfsu2-v10` and `PCRECOMP` with `/work/pcrecomp`) so the other 112 cached `.o` files are not wiped by a `$STAMP` mismatch. Verify with `aarch64-linux-gnu-nm` (`U sub_XXXXXXXX` + `T sub_XXXXXXXX_orig`). Functions already in `WRAP_V10` or invoked solely via `RECOMP_ICALL` (`k_overrides[]`) only need the ~20s fast relink above.
* **Branch-Isolated Guest Object Cache:** When linking a `main`-based PR branch while `/work/guest-v10/` holds wrapped objects from another branch (e.g. `recomp_0052.o`/`recomp_0053.o` from `perf/video-fmv`), create `/work/guest-v10-<tag>/` with symlinks to all untouched `.o` files from `/work/guest-v10/`, and compile only newly wrapped or stock-restored `.c` files into it. Never overwrite `/work/guest-v10/` with branch-diverged wraps.
* **Stock `main` Guest Cache & Dual-Variant Compile Check:** `/work/guest-v10/` currently carries `perf/video-fmv` wraps (`sub_006FFAA7`/`sub_0070CCE8`), so `main`-based PR branches that add no new wraps should link with `GUEST_DIR=/work/guest-v10-main`. To verify both `v10` and `v12` compile cleanly without owning `SPEED2.EXE` v12, run `COMPILE_ONLY=1 NFS_EXE_VARIANT=1` and `NFS_EXE_VARIANT=2` via `ports/r36s/build_ci.sh` in Docker, and cross-check `v12` disassembly/VAs against local `ports/nfsu2/nfsu2.aarch64.v12` using `aarch64-linux-gnu-objdump` inside `nfsu2-r36s-build`.
* **Integrated `develop` Guest Cache (`/work/guest-v10-develop`):** When linking `develop` (which combines `perf/video-fmv` and `feat/thai-subtitles` wraps), populate `/work/guest-v10-develop/` with symlinks from `/work/guest-v10/*.o` (`recomp_0052.o`/`recomp_0053.o` for `sub_006FFAA7`/`sub_0070CCE8`) and override `recomp_0017.o` and `recomp_0022.o` with symlinks from `/work/guest-v10-thai/` (`sub_0050CEF0_orig`/`sub_005535F0_orig`). Verify all 4 `*_orig` symbols with `aarch64-linux-gnu-nm` before linking.
* When deploying a freshly relinked `develop` `nfsu2-v10-develop.aarch64` binary, copy it directly to `ports/nfsu2/nfsu2.aarch64{.v10}` and `tools/nfsu2_thai/nfsu2thai/runtime/nfsu2.aarch64.v10` (with `NFSU2.sh` -> `tools/nfsu2_thai/nfsu2thai/runtime/NFSU2.sh.tmpl`) **without** applying the 4 downstream Python binary patchers (`patch_subtitles.py`, `patch_video.py`, `patch_gps.py`, `patch_attract.py`), since all four features are built into `develop`. Only apply those patchers (masking `adrp`/`add` immediates) when patching `main`-based binaries without the corresponding PRs merged.
* When adding new launch env vars (`nfsu2.cfg` / `NFSU2_REGISTRY`), keep `ports/NFSU2.sh`, `source/nfsu2-recompiled-r36s/ports/r36s/package/NFSU2.sh`, `tools/nfsu2_thai/nfsu2thai/runtime/NFSU2.sh.tmpl`, `tools/nfsu2_thai/NFSU2_Thai.sh`, and `tools/nfsu2_thai/NFSU2_Graphics.sh` aligned.
* When committing in `source/nfsu2-recompiled-r36s`, if `git commit` reports `Author identity unknown`, read the branch author via `git log -n 1 --format="%an <%ae>"` and pass `-c user.name=... -c user.email=...`.

## 2a. Frame-Rate Cap & VP6 Intro Invariant (`guest_runtime.cpp` / `widescreen.c`)

* Host frame pacing (`frameLimit` in `guest_runtime.cpp`) supports `15..240 FPS` (e.g. `20 FPS` for `3:3` VSync on the 60 Hz R36H panel).
* **Critical Invariant:** Always clamp the value passed to `nfs_widescreen_set_frame_rate()` to **`>= 30`** (`std::max(30u, frameLimit)`). Writing `1/20 s` into guest `0x007875BC` (`video mode frame time`) breaks VP6 substep timing (`0x00579DAE`) and crashes immediately at `blank.vp6` during intro boot.

## 2b. VP6 Cutscene & GLES Async Texture Invariants

* **GLES `GetDesc()` Pool/Usage Preservation (`d3d9_gles_resources.h` / `d3d9_gles.cpp`):** `GLTextureObject` must store the actual `usage` and `pool` passed to `CreateTexture()` and return them from `IDirect3DSurface9GLES::GetDesc()`. Hardcoding `Pool = D3DPOOL_DEFAULT` / `Usage = 0` causes `rt::textureLockAsync()` to reject every uncompressed texture (including `MovieTexture`), falling back to synchronous `kind3/m19` & `m20` (`sync ~6.6 ms/frame`).
* **On2 VP6 6.1.0.5 Indirect Kernels (`overrides.c`):** All core VP6 block kernels (`0x8B9C54..0x8B9EAC`: `IDctSlow/10/1`, `ReconIntra`, `ReconInter`, `ReconInterHalfPixel2`, `ReconBlock`, `FilterBlock2d`, `FilterBlock2dBilid`, `ClearSysState`) are called through `RECOMP_ICALL` (no guest `.o` rebuild needed when added to `k_overrides[]`) and sit at exact `+0x2B0` offset in `v12` (verify against `ports/nfsu2/nfsu2.aarch64.v12`).
* **VP6 Bit-Exact Quirks:** `IDctSlow` (`0x0071D757`) truncates each 1D row pass output to `(int16_t)` before the column pass (`+ 8 >> 4`). `ReconInterHalfPixel2` (`0x0071D216`) uses truncating average `(ref1 + ref2) >> 1` (`vhadd_u8`, **not** `vrhadd_u8`).
* **VP6 Native Frame Rate:** Retail NFSU2 `.vp6` cutscenes (`FMVOpening.vp6`, `Scene01.vp6`, `PSA.vp6`, `ealogo.vp6`) are `512x512` at `25.00 FPS` (`819175/32767`). Verify via `ffprobe` on R36H when interpreting `[NFSU2 HITCH]` periodicity (every 6 frames under 30 FPS cap = `25/30` sync cadence).

## 2c. v10 Localization, Subtitle & Cross-Target Wrap Invariants (`guest_runtime.cpp` / `overrides.c`)

* **Language ID vs. Region/SKU ID (`0x007FCA00` vs. `0x00864F24`):** On US retail v1.0 `SPEED2.EXE`, guest `0x007FCA00` holds the active **Language ID** (`0x0B` = Thai, set at `0x005B76BD`), whereas `0x00864F24` (read by `sub_005706C0`) holds the **Region/SKU ID** (always `0` on US v1.0). Auto-detecting active language (e.g. `NFSU2_SUBTITLES` auto-thai mode) must read `MEM32(0x007FCA00u)`, while checking whether `sub_005535F0_orig()` runs its native subtitle branch must match `MEM32(0x00864F24u)`.
* **R36S v10-Only Wraps in Shared Files (`overrides.c`):** `src/runtime/overrides.c` is compiled by both R36S (`build_cross.sh`) and Android (`android/app/src/main/cpp/CMakeLists.txt`), for both `v10` and `v12`. Guard any R36S v10-only wrapped `sub_XXXXXXXX` definitions with `#if defined(NFS_R36S) && (NFS_EXE_VARIANT == NFS_EXE_V10)` and append them to `WRAP` in `ports/r36s/build_guest_vm.sh` only when `exe_variant.py current` is `v10` so `v12` and Android builds never fail.

## 2. Bit-Exact Native C Porting from Lifted Code (`native_scene.c` / `native_math.c` / `world_cull.c` / `fx_cache.c`)

1. **Extract Lifted C Source from Docker Volume:**
   Inspect the exact lifted C code in `/work/guest-v10/recomp_*.wrap.c` (or `/work/nfsu2-v10/src/recomp/gen/recomp_*.c`) rather than guessing from x86 assembly alone. Always quote globs inside `bash -c '...'` and use `grep -nE` + `awk` (~3–5s; avoid Python regex scans over all `recomp_*.c`, which time out):
   ```bash
   docker run --rm -v nfsu2-r36s-work:/work nfsu2-r36s-build bash -c 'grep -nE "^void sub_005BC940\(" /work/nfsu2-v10/src/recomp/gen/recomp_*.c'
   docker run --rm -v nfsu2-r36s-work:/work nfsu2-r36s-build bash -c 'awk "/^void sub_005BC940\(void\)/,/^}/" /work/nfsu2-v10/src/recomp/gen/recomp_0030.c'
   ```
2. **Match x87 Double-Precision Order & FPU Status Flags:**
   - Lifted x87 arithmetic operates in `double` precision and rounds to `float` only on `fstp dword ptr`. Preserve exact operand grouping (e.g., `(dx * dx + dz * dz) + dy * dy`).
   - Translate `FPU_CMP(a, b)` + `fnstsw ax` patterns accurately:
     - `test ah, 0x41; jne` (`C3 | C0`): branches when `!(a > b)` (`a <= b` or NaN).
     - `test ah, 0x01; jne` (`C0`): branches when `!(a >= b)` (`a < b` or NaN).
     - `test ah, 0x05; jp` (`C2 | C0` even parity): branches when `a >= b` or NaN; falls through only when `a < b`.
3. **Write-Log Verification Invariant (`NFSU2_NATIVE_SCENE=2`):**
   - Record all heap/global writes via `W32(addr, val)`.
   - Before calling `sub_XXXXXXXX_orig()`, save `const int nl = nlog; undoLog(); nlog = -1;` so nested calls inside `*_orig()` do not touch `wlog`, then call `checkLog(k, nl)`.
   - Compare output cursors (e.g. `M32(view + 0x4C)`, `M32(0x82DA5C)`) after `*_orig()` to catch false-cull early exits where native code wrote 0 entries (`nl == 0`) while `*_orig()` wrote an entry.
4. **D3DX Effect Setup & `CommitChanges` Invariants (`fx_cache.c` / `world_cull.c` / `NFSU2_NATIVE_SETUP=2`):**
   - **Disable Secondary Fast-Paths During Verify (`mode == 2`):** Gate `ov_fx_method()` native `Set*` shortcuts (`overrides.c`) and lazy `CommitChanges` (`hud_half.c`) on `nfs_fx_setup_mode() == 1` so `=2` verifies against authentic lifted D3DX execution.
   - **Post-Loop `_controlfp` Restore in `CommitChanges`:** `guestApply` (preshader VM `sub_00664743`) can set bit `0` of `[fx + 0x118]` *during* the dirty loop. Always check `M8(fx + 0x118) & 1` after the loop (and when `n == 0`), restore `g_fpu_cw` matching CRT `_controlfp([fx + 0x114], 0x30000)` (`g_fpu_cw = (g_fpu_cw & 0x1C3Fu) | pcBits`), and clear `M32(fx + 0x118) &= ~1u`. Save/restore/compare `g_fpu_cw` in the verify harness.
   - **Device-Call Capture Comparison (`naOf`):** When comparing captured D3D9 device calls between native and lifted runs, only compare arguments `1 .. naOf(method) - 1` (e.g., `SetTexture` method `65` and `SetRenderState` method `57` have 3 args `a[0..2]`; comparing `a[3]` reads stale guest stack words from lifted `RECOMP_ICALL`).
5. **R36S Threaded `Present` Hook & Potato Mode Invariants:**
   - With `NFSU2_RENDER_THREAD=1` on R36S, `Op::Present` executes in `android/app/src/main/cpp/d3d9_render_thread.inc` rather than `d3d9_bridge.cpp`. Any per-frame hook or divider (such as `nfs_reflect_on_present()`) must be called in both `d3d9_render_thread.inc` and `d3d9_bridge.cpp` or it will never tick on hardware.
   - For car cubemap throttling (`NFSU2_HALF_REFLECT`), only gate cubemap schedule table `0x7FEEA0`; never skip `view4 + 8` (`L_005CA805`), which jumps to `L_005CB7BB` and skips the entire main world view.
   - In `d3d9_gles.cpp` (`prepareDraw`), classify 2D/UI draws as `is2DUI = hasPositionT || (upData != nullptr) || !m_rs[D3DRS_ZENABLE]` before clamping `GL_TEXTURE_BASE_LEVEL` (`NFSU2_POTATO >= 2`); checking `hasPositionT` alone breaks the rotating minimap, World Map roads, and loading backgrounds.
   - In `native_scene.c`, gate the `potato_3` `vflags & 0x1800u` skip on `M32(0x00870CB8u) == 0u` so `Car Reflection` (`NFSU2_CAR_REFLECT=1`) can still render cubemaps when enabled.

## 3. R36H Deployment & Benchmark Runbook

1. **Passwordless SSH/SCP (`ssh r36h`):**
   - The Linux host `~/.ssh/config` has `Host r36h playos playos.local 192.168.1.47` configured with ED25519 key auth (`ark`), static IP on `svvv_5g`, `avahi-daemon` (`playos.local`), and Wi-Fi Power Save disabled.
   - If playOS is freshly flashed/reinstalled or `ssh r36h` fails, run `python3 /mnt/d/r36h/nfsu2/setup_playos_net.py` once to auto-discover the device and re-apply all network/SSH settings.
2. **Deploy & Verify via `scp` / `ssh r36h`:**
   - Back up `/roms/ports/nfsu2/nfsu2.aarch64.v10` to `.bak_stock` once before overwriting both `nfsu2.aarch64.v10` and `nfsu2.aarch64`.
   - When testing an unpatched upstream PR branch (`main`-based) on an already-patched/modded R36H, also back up to `.bak_before_<tag>` first so the modded binary can be restored cleanly afterwards; for `ports/r36s/sdl_gamepad.h` changes, pre-verify with a host `g++ -std=c++17 -Iports/r36s/sdk/include/SDL2` test, inspect `aarch64-linux-gnu-objdump -d` on the relinked binary (e.g. `grep "sp, #662"` for `DIK_C`), and confirm `[NFSU2 PAD] active mapping:` in `/roms/ports/nfsu2/log.txt`.
   - When verifying an in-memory `SPEED2.EXE` runtime patch (such as native Thai localization) on an already-modded R36H, also back up `/roms/ports/nfsu2/gamedata/SPEED2.EXE` to `.bak_before_<tag>` and temporarily deploy the untouched stock US v1.0 `SPEED2.EXE` (`MD5 95b4dc3e9a6c72b06a8bd62b0c56ea63`) so on-disk patches cannot mask runtime bugs; restore both binary and exe after verification.
   - If the game may be running (`ETXTBSY`), upload via `nfsu2.aarch64.v10.new`, `chmod 755`, then atomically `mv -f` to `nfsu2.aarch64.v10` and `cp -f` to `nfsu2.aarch64`.
   - For verification runs, append `export NFSU2_NATIVE_SCENE=2` (check `[NFSU2 SCENE] verify: ... 0 bad`) or `export NFSU2_NATIVE_SETUP=2` (check `[NFSU2 SETUP] verify: ... 0 bad`) to `/roms/ports/nfsu2/nfsu2.cfg`.
     *(Note: `[NFSU2 SCENE]` and `[NFSU2 SETUP]` verify lines only emit during active 3D world/driving frames; a headless `NFSU2_BOOT_TIMEOUT` run that stays on the Title Screen validates boot/Thai/Subtitles/Skip-Intro/Attract/PAD/HUD/Present, not 3D scene/setup.)*
   - For timing / A/B runs, append `export NFSU2_SCENE_TIMING=1` or `export NFSU2_SETUP_TIMING=1` (with `NFSU2_NATIVE_SETUP=1` vs `0`) and check `[NFSU2 SCENE] timing` / `[NFSU2 SETUP] timing`.
   - Always remove temporary `export NFSU2_*` lines from `/roms/ports/nfsu2/nfsu2.cfg` via `sed -i` immediately after pulling `log.txt`.
   - **Unattended SSH Timed Verification (`NFSU2_BOOT_TIMEOUT`):** From an SSH session (never from a menu-launched script), stop `playfe.service` to release KMSDRM master, launch with `NFSU2_BOOT_TIMEOUT=45 timeout -k 5 55 ./nfsu2.aarch64.v10 /roms/ports/nfsu2/gamedata --cap30 --lang=English` (use `-k 5` so SIGKILL cleans up if SIGTERM is ignored), inspect logs, then restore backed-up binaries/`nfsu2.cfg`/`MOVIES/` and run `sudo systemctl start playfe.service`.
