# NFSU2 R36H — Cover Art, TUI Versioning & Release Notes Standard

## 1. Minimal Cover Art Standard (`tools/*/images/*-thumb.png`)
- **Canvas & Background:** `512x512` RGBA, solid dark background `#121212` (no outer border frames or circular rings around icons unless explicitly requested).
- **Minimal Typography:** Keep text to at most 2 lines — primary title (`NFSU2` bold italic racing style) and concise wide-tracked subtitle (`MOD MANAGER`, `CONTROLS MAPPER`). Do not add colored pill banners or multi-line feature descriptions.
- **R36H / Gamepad Button Color & Label Convention:**
  - Top (`X`): Blue
  - Right (`A`): Red
  - Bottom (`B`): Yellow
  - Left (`Y`): Green
  - Button labels (`X`, `A`, `B`, `Y`) use cutout background color (`#121212`).
- **Sibling Visual Alignment:** When adding or redesigning `NFSU2_*-thumb.png` icons, sample the exact `NFSU2` wordmark band, `#CCD6E3` subtitle height (`~14–15px` cap height at `y=368`), and R36H palette (`X` `#38BDF8`, `Y` `#22C55E`, `A` `#EF4444`) from `tools/nfsu2_thai/images/NFSU2_Controls-thumb.png` and inspect both side-by-side via `read_file` before presenting the preview.
- **Preview-Before-Sync Workflow:** When creating or redesigning cover art, save only to the source path (`tools/<tool>/images/`) and present it for visual review first. Do **not** sync to internal subfolders (`<toolname>/images/`), rebuild `dist/*.zip`, or deploy to R36H until the user explicitly approves.

## 2. TUI Versioning & User-Facing Patch Notes
- **TUI Titles (`*.sh`):** Display only the short version number (e.g., `v1.1`) in dialog titles and backtitles. Never clutter TUI menus with long patch note descriptions.
- **Patch Notes (`README.txt`):** Write patch notes in plain, user-friendly language. Avoid low-level technical identifiers (e.g., Unicode codepoints like `U+0E34`, chunk names like `FNTF`, or hex offsets).
