---
name: nfsu2-career-freeze-diagnosis
description: >-
  Diagnose NFSU2 launch failures, "No such file or directory" for nfsu2.aarch64,
  and Career mode freezes ("Guest stall: no frame for 12 s") on R36H/R36S,
  including US vs EU/Thai PC asset region mismatches (CIVIC vs CORSA).
---

# NFSU2 Launch & Career Freeze Diagnosis

Use this runbook when NFSU2 fails to launch, stalls on `Guest stall: no frame for 12 s`, or freezes when entering Career mode on R36H/R36S.

## 1. Check `log.txt` & Binary Presence

Inspect `/roms/ports/nfsu2/log.txt` and directory contents:

* **`./nfsu2.aarch64: No such file or directory`**:
  * `NFSU2_Thai.sh` is a localization/patch manager only; it does not bundle `nfsu2.aarch64*` or full `gamedata/` (`CARS/`, `TRACKS/`, `GLOBAL/`, `SOUND/`).
  * Ensure `/roms/ports/nfsu2/` comes from a complete `NFSU2-R36S.zip` release + full retail `gamedata/`, not an asset-only backup (e.g. `nfsu2_th_bak`).

## 2. Diagnose Career Mode Freeze (`Guest stall: no frame for 12 s`)

When the game launches to the menu/garage (`Crib01.BIN`) but freezes upon entering Career mode:

1. **Check wait duration vs true hang**:
   * First-time D3DX9 shader compilation (`0x670000..0x6B0000`) can pause frames for 15–45 seconds. If `log.txt` shows no `TRACKS/` file opens and remains stalled after 60+ seconds, it is a true hang.
2. **Check `gamedata/CARS/` region against the save (`SVVV`)**:
   * **US Retail**: has `gamedata/CARS/CIVIC/`, no `CORSA/`.
   * **EU / Thai PC Retail**: has `gamedata/CARS/CORSA/`, no `CIVIC/`.
   * Loading a US Career save (`SVVV`) with EU `CARS/` (or vice versa) causes `thread 1` to hang indefinitely when entering Career mode, even though `SVVV` is uncorrupted, `English` language fails identically, and a newly created profile works.
   * **Findings**: `GLOBALB.BUN` in both US and EA Thai already defines `CarTypeInfo` (`0x890` bytes) for all 4 cars (`CIVIC`, `RSX`, `CORSA`, `PEUGOT106`), and `SOUND/` is identical.
   * **Fix**: Either pair `SVVV` with the matching region's `gamedata/`, or copy `CIVIC` and `RSX` into EA Thai/EU `gamedata/CARS/` (e.g. via `dist/nfsu2_cars_us.zip`). Verified: adding `CIVIC` and `RSX` resolves Career freezes when loading US saves (`SVVV`) with US v1.0 `SPEED2.EXE`. (Loading EU saves owning `CORSA`/`PEUGOT106` under US v1.0 `SPEED2.EXE` has not been tested, and Car Lot purchase lists remain gated by `SPEED2.EXE` / `nfsu2.aarch64` region logic `sub_005706C0` and the 26-car arrays at `0x7f6da4` / `0x7f6dc0`.)
3. **Car Selection Note**:
   * Changing cars in Main Menu `Customize` / `Quick Race` does not change the Career car in `SVVV`; Career cars can only be changed at an in-game Car Lot or Garage.
