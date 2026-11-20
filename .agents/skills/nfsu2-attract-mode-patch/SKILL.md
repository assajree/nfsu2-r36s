---
name: nfsu2-attract-mode-patch
description: >-
  Diagnose and patch NFSU2 Title Screen Attract Mode (`sub_004C53B0` ->
  `UG_LS_IntroFMV.fng`) when Fast Boot causes Title music (Riders on the Storm)
  to restart every 30 seconds, or add conditional `FMVOpening.vp6` existence
  checks. Use when Title Screen audio loops/restarts without leaving the Title
  Screen, or when updating `patch_attract.py` / `overrides.c`.
---

# NFSU2 Title Screen Attract Mode Patch

## Root Cause
- In `SplashScreen::NotificationMessage` (`sub_004C53B0`), on `FE_TICK` (`0xc98356ba`), the game checks `(now - [esi+0x50]) * 0.00025f >= 30.0f` (`VA 0x00784478`) and switches to `"UG_LS_IntroFMV.fng"` (`FMVOpening.vp6`).
- When **Fast Boot** hides/renames `FMVOpening.vp6` (e.g. `_FMVOpening.vp6` via `NFSU2_Thai.sh`), the missing movie causes Attract Mode to finish immediately and reload the Title Screen, restarting *Riders on the Storm* every 30 seconds.

## Critical Patching Invariants
1. **Target `sub_004C53B0`, NOT `sub_004C50B0` / `sub_004C52E0`:**
   - `sub_004C50B0` (5.0s) and `sub_004C52E0` (4.0s, `THXMovieScreen`/`DemoPSAScreen`) are short logo-screen timers, not the Title Screen Attract Mode timer.
2. **Do NOT modify `30.0f` at `VA 0x00784478` in `.rdata`:**
   - Float constants in `.rdata` may be shared across unrelated functions.
3. **Do NOT early-return at the top of `sub_004C53B0`:**
   - `FE_TICK` code after `0x004c5465` still handles `PRESS_START` and first-time memory-card checks.
4. **Patch only the timeout conditional branch:**
   - Convert `b.ne +0x164` (`0x54000b21`) after the 30.0s check into unconditional `b +0x164` (`0x14000059`).
   - Verified offsets: `0x3c6e770` (`nfsu2.aarch64` / `.v10`) and `0x3d57960` (`nfsu2.aarch64.v12`).

## Conditional `FMVOpening.vp6` Check Approaches
When Attract Mode should only be suppressed if `FMVOpening.vp6` is missing:
1. **C++ Runtime Override (`source/nfsu2-recompiled-r36s/src/runtime/overrides.c`) — *For Recompiled Builds / PRs*:**
   - Override `sub_004C4EB0` (the screen-switch helper called by `sub_004C53B0` with `"UG_LS_IntroFMV.fng"`).
   - Cache `access("MOVIES/FMVOpening.vp6", F_OK) == 0` once on first call; if missing and screen name equals `"UG_LS_IntroFMV.fng"`, return immediately without switching screens. Otherwise, delegate to original `sub_004C4EB0()`.
2. **Launcher / Manager Toggle (`NFSU2.sh` or `NFSU2_Thai.sh`) — *No Recompile Needed*:**
   - Check `[ -f "$GAMEDATA/MOVIES/FMVOpening.vp6" ]` before launch or inside the Skip/Restore Intro toggle.
   - If missing, apply `patch_attract.py` (`b +0x164`); if present, run `patch_attract.py --revert` (`b.ne +0x164`).

## Workflow & Verification
1. Apply / verify locally:
   - `python patch_attract.py --all`
   - `python patch_attract.py --all --verify`
2. Verify on R36H (`playos.local`) with GNU `objdump`:
   - `objdump -d --start-address=0x406e760 --stop-address=0x406e7a0 /roms/ports/nfsu2/nfsu2.aarch64`
   - Confirm `406e770: 14000059 b 406e8d4 <sub_004C53B0+0x474>`.
