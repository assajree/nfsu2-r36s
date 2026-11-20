# NFSU2 R36H — TUI SD1/SD2 Discovery & Console Error Standard

## 1. Initialize TUI & Gamepad Bridge Before Asset Discovery
- Always configure `gptokeyb`, `DIALOG_IN`/`DIALOG_OUT` (`/dev/tty1`), and check for `dialog` **before** searching for `NFSU2_DIR` or `gamedata/`.
- Never print fatal errors only to `stdout`/`stderr` and `exit 1` when running on the handheld; surface errors via `dialog --msgbox` (or `/dev/tty1` if `dialog` is missing) so the script never flashes black and drops back to the frontend.

## 2. Strict Case-Insensitive `nfsu2` Discovery (SD1 / SD2 / Script Dir)
- Search `"$SCRIPT_DIR"`, `/roms/ports`, and `/roms2/ports` using an **exact case-insensitive basename match** (`nfsu2`, `NFSU2`) and verify both `gamedata/` and `GAMEDATA/`.
- **Never** use wildcard patterns such as `*nfsu2*` during auto-detection, as they falsely match backup directories (e.g., `/roms/ports/nfsu2_bak`).
- If auto-detection fails, open an interactive `dialog --menu` folder picker listing subdirectories in `/roms/ports` and `/roms2/ports` before aborting.

## 3. Compact 64-Column Backtitle with Active Game Path
- Display the resolved `$NFSU2_DIR` in the main menu `--backtitle` using a concise format (`<Tool Name> | $NFSU2_DIR`, e.g. `NFSU2 Controls | $NFSU2_DIR` or `NFSU2 Thai | $NFSU2_DIR`) so it fits cleanly within the R36H 64-column console width.
