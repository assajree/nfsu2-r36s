# NFSU2 R36H — Gamepad Mapping & World Map Input Invariants

## 1. PlayOS / PortMaster `GO-Super Gamepad` X/Y Inversion (`x:b2,y:b3` vs `y:b2,x:b3`)
- On R36H (`playOS`), `/opt/system/Tools/PortMaster/gamecontrollerdb.txt` (line 1110) and SDL2's built-in mapping bind `GO-Super Gamepad` by printed Nintendo-style face label (`x:b2,y:b3`: top `b2` = `X`, left `b3` = `Y`), whereas `ports/r36s/sdl_gamepad.h` and `kR36SPadMapping` in `ports/r36s/main.cpp` expect PS2/Xbox positional order (`y:b2,x:b3`: top `b2` = `Y`/Triangle, left `b3` = `X`/Square).
- `preparePadMapping()` in `ports/r36s/main.cpp` only installs `kR36SPadMapping` when `!hasSticks || getenv("NFSU2_FORCE_PAD_MAPPING")`. Because PortMaster's `x:b2,y:b3` mapping already includes `leftstick:` and `rightstick:`, `kR36SPadMapping` is **not** applied automatically.
- **Invariant**:
  - Do **not** swap `buttons_[X]` and `buttons_[Y]` inside `ports/r36s/sdl_gamepad.h` for upstream PRs (that breaks ArkOS and other devices using positional `x:b3,y:b2`).
  - Keep `export SDL_GAMECONTROLLERCONFIG="...x:b3,y:b2..."` in `/roms/ports/nfsu2/nfsu2.cfg` (via `NFSU2_Controls.sh` `PS2_Classic`) or set `NFSU2_FORCE_PAD_MAPPING=1` when testing on R36H playOS so physical **X (top, `b2`)** maps to `buttons_[Y]` (Triangle / GPS `DIK_C`).
  - When debugging button swaps on R36H, always verify `[NFSU2 PAD] active mapping:` and `[NFSU2 PAD] <btn> / raw button <idx>` in `/roms/ports/nfsu2/log.txt`.

## 2. NFSU2 Menu `DIACTION` Table (`0x7fd7e0`) vs `DIK_SPACE` (`0x39`)
- In `SPEED2.EXE`, the 32-action Menu/Frontend DirectInput action table (`0x7fd7e0`) includes:
  - `user=31`: `0x1c` (`DIK_RETURN`, Menu Select)
  - `user=33`: `0x23` (`DIK_H`, Help)
  - `user=34`: `0x01` (`DIK_ESCAPE`, Menu Back)
  - `user=35`: `0x2e` (`DIK_C`, Menu Customise — triggers **Engage GPS** on World Map)
  - `user=36`: `0x33` (`DIK_COMMA`, Menu Button 2), `user=37`: `0x34` (`DIK_PERIOD`, Menu Button 3)
  - `user=38`/`39`: `0x1a`/`0x1b` (`[`/`]`, Menu L1/R1), `user=46`: `0x19` (`DIK_P`, Menu Preset)
- `DIK_SPACE` (`0x39`) is **not** in the Menu `DIACTION` table; `guest_input.inc` delivers zero DirectInput buffered events for `0x39` in menus (only `WM_KEYDOWN` `VK_SPACE`).
- Never document or comment that `DIK_SPACE` (`buttons_[X]`) filters World Map icons; toggling items on the World Map uses `Menu Select` (`0x1c`, bottom `B`).
