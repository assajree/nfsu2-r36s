# NFSU2 R36H — `dialog` TUI & Graphics Tuner UX Invariants

## 1. R36H 640×480 Console Budget (`Lat7-TerminusBold20x10`)
- Terminal `/dev/tty1` on R36H with `TerminusBold20x10` is **64 columns × 24 rows**.
- Keep `dialog --menu` width `<= 60` with concise item labels (no verbose parenthetical descriptions that wrap or overflow).
- When the main menu has 6–7 items, keep the prompt header to 1 line (`\nChoose a setting (or Exit):`) and dialog height `<= 22` so every item is visible without scrolling.

## 2. Coupled Knobs & Profile Switching (`NFSU2_Graphics.sh`)
- Never expose mutually overriding knobs (`Draw Distance` vs `Draw Call Budget`) as separate menus; combine them into a single `Visibility / Culling` menu where `Fixed` presets explicitly set `NFSU2_DRAW_BUDGET=0`.
- Selecting a `Graphics Profile` must preserve user overrides (`NFSU2_DRAW_DIST`, `NFSU2_DRAW_BUDGET`, `NFSU2_RENDER_SCALE`) rather than deleting them back to `Auto`.
- Do not enable `NFSU2_DISTANT_AI_RATE` in Potato presets or expose `Distant AI Throttle` in `NFSU2_Graphics.sh` (throttling AI controllers causes corner overshoots, wall crashes, and reverse loops).
