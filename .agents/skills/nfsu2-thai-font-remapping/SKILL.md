---
name: nfsu2-thai-font-remapping
description: >-
  Diagnose and fix missing Thai text or clipped Thai vowels/tone marks in NFSU2
  (`Thailand.bin` FNTF chunks and `InGame*.bun` HUD packages). Use when Thai HUD
  labels disappear, show only punctuation, or lose upper/lower vowels.
---

# NFSU2 Thai Font Inspection & FNTF Remapping

## Core Principle
- Retail EA `Thailand.bin` (264,184 bytes) only includes Thai glyphs/textures for `conduitmditc_tt14i_thailand` and `conduitmditc_tt21i_thailand`.
- Large HUD fonts (`font_conduitmditctt38bi`, `font_impact36`) lack Thai glyphs in retail assets.
- **Prefer FNTF remapping over reverting HUD strings to English:** Keep Thai text intact in `STR_BLOCK` (`0x00039000`) and remap large `FNTF` (`0x00030201`) chunks to `conduitmditc_tt21i_thailand` so all modes (Race, Drag, Shift, Finish) render Thai text.

## Diagnostic Workflow
1. **Verify `STR_BLOCK` vs `FNTF`:** Check whether the missing text uses a large HUD font (`InGame*.bun`) or has a clipped glyph box in `tt14i`/`tt21i`.
2. **Check Glyph Bounding Box (`FNTF` +0x200..):** Inspect `height` and `yoff` for Thai combining marks (`U+0E31`, `U+0E34..U+0E3A`, `U+0E47..U+0E4C`). Very small heights (e.g. `h=1` for `U+0E34` in `tt14i`) cause invisible vowels on handheld screens.
3. **Remap Large `FNTF` Chunks In-Place:**
   - Preserve the font `.bin` name at chunk payload `+0x000..+0x0FF` so `FEng` resolves the font name.
   - Copy texture name (`+0x100..+0x1FF`) and `FNTF` metrics/glyphs (`+0x200..`) from `conduitmditc_tt21i_thailand`.
   - If the target `FNTF` chunk was larger (e.g., `4208` -> `3312`), write a `0x00000000` padding chunk for the remainder so total `Thailand.bin` size stays `264,184` bytes.
4. **Verify Chunk Chain:** Run `patch_thailand_bin.py --verify` and walk all chunks from `0x0` to `264,184` before packaging or deploying.
