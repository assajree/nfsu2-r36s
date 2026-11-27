# NFSU2 R36H — `dialog` TUI & Graphics Tuner UX Invariants

## 1. R36H 640×480 Console Budget & `dialog` Styling (`Lat7-TerminusBold20x10`)
- Terminal `/dev/tty1` on R36H with `TerminusBold20x10` is **64 columns × 24 rows**.
- Keep `dialog --menu` width `<= 62` and height `<= 20` so boxes fit cleanly without clipping.
- **2-Column Main Menu (`NFSU2_Graphics.sh`)**: Use `<tag>` for the setting name and `<item>` for the current value (no `1..N` numbering, no `--no-tags`, and no `--colors` `\Z` escapes). Export a temporary `DIALOGRC` setting `tag_color`, `tag_selected_color`, `tag_key_color`, and `tag_key_selected_color` equal to `item_color` / `item_selected_color` so left/right columns share uniform, clean text colors.
- **1-Column Submenus**: Pass `--no-tags` to hide internal config keys (`potato_1`, `0..3`, `default`), and omit meaningless internal numeric suffixes like `(0)`, `(1)`, `(2)`, `(3)` from user-facing labels.
- **Scrollable Preset Confirmation**: Use `dialog --textbox` with `--exit-label "Confirm"` (left, default focus, rc `0`) and `--extra-button --extra-label "Back"` (right, rc `3`) so multi-line preset details scroll smoothly via D-pad Up/Down.

## 2. Graphics Tuner Menu Structure & Pure Preset Switching (`NFSU2_Graphics.sh`)
- Expose all tunable graphic options directly on the flat main menu (no separate `Performance Trade-offs` submenu) and keep the `Confirm Graphics Preset` preview 1:1 aligned in naming and order (`Resolution`, `Draw Distance`, `Texture Size`, `Texture Filter`, `World Detail`, `Car Detail`, `Car Reflection`, `Car Headlights`, `Roadside Crowd`, `Particles`, `Shadows`, `Car Lighting`, `Road Reflect`).
- Map internal `NFSU2_GRAPHICS` IDs to friendly `GFX_LABEL` names (`Potato`, `PS1`, `Lite`, `Fast 30 FPS`, `Balanced`, `High Quality`) across the main menu, backtitle, preview, and completion dialog.
- Selecting and confirming a `Graphics Profile` **must clear all graphic override keys** (`NFSU2_POTATO`, `NFSU2_DRAW_DIST`, `NFSU2_DRAW_BUDGET`, `NFSU2_RENDER_SCALE`, `NFSU2_CAR_REFLECT`, `NFSU2_HALF_REFLECT`, `NFSU2_HEADLIGHTS`, `NFSU2_CROWD`, `NFSU2_PARTICLES`, `NFSU2_DISTANT_AI_*`, plus `g_CarLodLevel`, `g_WorldLodLevel`, `g_TextureFiltering`, `g_CarShadowEnable`, `g_CarLightingEnable`, `g_RoadReflectionEnable` in `NFSU2_REGISTRY_EXTRA`), preserving only `NFSU2_FPS` and `NFSU2_LANG`.
- Never expose mutually overriding knobs (`Draw Distance` vs `Draw Call Budget`) as separate menus; combine them into `Draw Distance` where `Fixed` sets `NFSU2_DRAW_BUDGET=0`.
- Do not enable `NFSU2_DISTANT_AI_RATE` in Potato presets or expose `Distant AI Throttle` in `NFSU2_Graphics.sh` (throttling AI controllers causes corner overshoots, wall crashes, and reverse loops).

## 3. R36H Deployment & Launcher Service Policy
- On `playos.local`, `/roms/tools/NFSU2_Graphics.sh` and `/roms/00_tools/NFSU2_Graphics.sh` are symlinked to the same file; uploading to `/roms/tools/NFSU2_Graphics.sh` updates both.
- In `ports/NFSU2.sh`, do not stop or restart background services (`smbd`, `nmbd`, `filebrowser`) on launch/exit; keep only CPU/GPU/DMC `performance` governors and `vm.swappiness=10`.
