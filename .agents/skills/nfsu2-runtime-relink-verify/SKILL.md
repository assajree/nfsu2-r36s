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

Never use `build.py --native` on hosts with `glibc >= 2.29` (e.g. Linux Mint 22.3 / `glibc 2.39`), as it fails the `GLIBC_2.18` symbol check. Invoke `docker run` **directly** (do **not** wrap in `sg docker`, which fails with `setgroups: Operation not permitted` in sandboxed shells; `svvv` is already in group `docker`). When modifying only runtime C/C++ files (`src/runtime/*.c`, `ports/r36s/**`, `android/app/src/main/cpp/**`), link directly against the cached 113 guest `.o` files in Docker volume `nfsu2-r36s-work`:

```bash
docker run --rm -v nfsu2-r36s-work:/work -v /mnt/d/r36h/nfsu2/source/nfsu2-recompiled-r36s:/src nfsu2-r36s-build bash -c 'rm -rf /work/host-v10 && GUEST_DIR=/work/guest-v10 NFS_EXE_VARIANT_H=/work/nfsu2-v10/src/recomp/gen/nfs_exe_variant.h OUT=/work/host-v10 bash /src/ports/r36s/build_cross.sh && cp /work/host-v10/package/nfsu2.aarch64 /src/build/r36s/nfsu2-v10.aarch64 && cp /work/host-v10/package/nfsu2.aarch64.debug /src/build/r36s/nfsu2-v10.aarch64.debug && sha1sum /src/build/r36s/nfsu2-v10.aarch64 | cut -d" " -f1 > /src/build/r36s/nfsu2-v10.aarch64.sha1'
```

* If adding a **newly wrapped** lifted function to `WRAP_V10` in `ports/r36s/build_guest_vm.sh`, re-run `build_guest_vm.sh` inside `nfsu2-r36s-build` first so its definition is renamed to `sub_XXXXXXXX_orig`. Functions already in `WRAP_V10` only need the fast relink above.
* When deploying a freshly relinked `nfsu2-v10.aarch64` for end-user play (outside clean upstream performance PRs), copy it to `ports/nfsu2/nfsu2.aarch64.v10` and apply all 4 downstream patchers (`patch_subtitles.py`, `patch_video.py`, `patch_gps.py`, `patch_attract.py`), then `--verify`. Instruction-sequence patchers on relinked binaries must mask PC-relative `adrp`/`add` relocation immediates (e.g., `patch_video.py` Patch 5A masks `words 15, 16, 37, 38` in `sub_006FFAA7`) because every relink shifts `.bss`/`.data` offsets.
* When adding new launch env vars (`nfsu2.cfg` / `NFSU2_REGISTRY`), keep `ports/NFSU2.sh`, `source/nfsu2-recompiled-r36s/ports/r36s/package/NFSU2.sh`, and `tools/nfsu2_thai/NFSU2_Graphics.sh` aligned so user TUI toggles remain consistent with launcher exports.
* When committing in `source/nfsu2-recompiled-r36s`, if `git commit` reports `Author identity unknown`, read the branch author via `git log -n 1 --format="%an <%ae>"` and pass `-c user.name=... -c user.email=...`.

## 2a. Frame-Rate Cap & VP6 Intro Invariant (`guest_runtime.cpp` / `widescreen.c`)

* Host frame pacing (`frameLimit` in `guest_runtime.cpp`) supports `15..240 FPS` (e.g. `20 FPS` for `3:3` VSync on the 60 Hz R36H panel).
* **Critical Invariant:** Always clamp the value passed to `nfs_widescreen_set_frame_rate()` to **`>= 30`** (`std::max(30u, frameLimit)`). Writing `1/20 s` into guest `0x007875BC` (`video mode frame time`) breaks VP6 substep timing (`0x00579DAE`) and crashes immediately at `blank.vp6` during intro boot.

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
5. **R36S Threaded `Present` Hook Invariant:**
   - With `NFSU2_RENDER_THREAD=1` on R36S, `Op::Present` executes in `android/app/src/main/cpp/d3d9_render_thread.inc` rather than `d3d9_bridge.cpp`. Any per-frame hook or divider (such as `nfs_reflect_on_present()`) must be called in both `d3d9_render_thread.inc` and `d3d9_bridge.cpp` or it will never tick on hardware.
   - For car cubemap throttling (`NFSU2_HALF_REFLECT`), only gate cubemap schedule table `0x7FEEA0`; never skip `view4 + 8` (`L_005CA805`), which jumps to `L_005CB7BB` and skips the entire main world view.

## 3. R36H Deployment & Benchmark Runbook

1. **Passwordless SSH/SCP (`ssh r36h`):**
   - The Linux host `~/.ssh/config` has `Host r36h playos playos.local 192.168.1.47` configured with ED25519 key auth (`ark`), static IP on `svvv_5g`, `avahi-daemon` (`playos.local`), and Wi-Fi Power Save disabled.
   - If playOS is freshly flashed/reinstalled or `ssh r36h` fails, run `python3 /mnt/d/r36h/nfsu2/setup_playos_net.py` once to auto-discover the device and re-apply all network/SSH settings.
2. **Deploy & Verify via `scp` / `ssh r36h`:**
   - Back up `/roms/ports/nfsu2/nfsu2.aarch64.v10` to `.bak_stock` once before overwriting both `nfsu2.aarch64.v10` and `nfsu2.aarch64`.
   - For verification runs, append `export NFSU2_NATIVE_SCENE=2` (check `[NFSU2 SCENE] verify: ... 0 bad`) or `export NFSU2_NATIVE_SETUP=2` (check `[NFSU2 SETUP] verify: ... 0 bad`) to `/roms/ports/nfsu2/nfsu2.cfg`.
   - For timing / A/B runs, append `export NFSU2_SCENE_TIMING=1` or `export NFSU2_SETUP_TIMING=1` (with `NFSU2_NATIVE_SETUP=1` vs `0`) and check `[NFSU2 SCENE] timing` / `[NFSU2 SETUP] timing`.
   - Always remove temporary `export NFSU2_*` lines from `/roms/ports/nfsu2/nfsu2.cfg` via `sed -i` immediately after pulling `log.txt`.
