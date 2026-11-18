#!/usr/bin/env python3
"""
Need for Speed: Underground 2 (Recompiled) - Joypad GPS Patch
Maps Joypad Button X (Top / North) to Key 'C' (DIK_C = 0x2E / 46) for GPS activation on World Map,
and maps Joypad Button Y (Left / West) to Space (DIK_SPACE = 0x39 / 57) in Menu Mode.

Architecture:
  In nfsu2.aarch64, input is processed both in the inlined main() event loop and in selectSend(bool).
  When in Menu Mode (guestDrivingControls() == false):
    1. In main() event loop:
       - 0x491e78: strb w0, [sp, #673] (DIK_SPACE) -> strb w0, [sp, #662] (DIK_C = 46)
       - 0x490f80: strb w1, [sp, #673] (DIK_SPACE) -> strb w1, [sp, #662] (DIK_C = 46)
    2. In selectSend():
       - Button X ([x2, #42]) -> [sp, #54] (DIK_C = 46)
       - Button Y ([x2, #43]) -> [sp, #65] (DIK_SPACE = 57)
"""

import os
import sys
import re

# Inlined main() event loop patches:
# strb w0, [sp, #673] -> 0x390a87e0 (Button X in menu mode) -> 0x390a5be0 (strb w0, [sp, #662] = DIK_C)
ORIG_MAIN_BTN = bytes.fromhex("e0 87 0a 39")
PATCH_MAIN_BTN = bytes.fromhex("e0 5b 0a 39")

# strb w1, [sp, #673] -> 0x390a87e1 (Button X on axis event in menu) -> 0x390a5be1 (strb w1, [sp, #662] = DIK_C)
ORIG_MAIN_AXIS = bytes.fromhex("e1 87 0a 39")
PATCH_MAIN_AXIS = bytes.fromhex("e1 5b 0a 39")

# selectSend() function patches:
# strb w2, [sp, #65] -> 0x390107e2 (Original Button X -> DIK_SPACE)
# strb w2, [sp, #54] -> 0x3900dbe2 (Patched Button X -> DIK_C = 46)
ORIG_X = bytes.fromhex("42 a8 40 39 e2 07 01 39") # ldrb w2, [x2, #42]; strb w2, [sp, #65]
PATCH_X = bytes.fromhex("42 a8 40 39 e2 db 00 39") # ldrb w2, [x2, #42]; strb w2, [sp, #54]

# strb w3, [sp, #9]  -> 0x390027e3 (Original Button Y -> DIK_ESCAPE)
# strb w3, [sp, #65] -> 0x390107e3 (Patched Button Y -> DIK_SPACE = 57)
RE_Y = re.compile(b"(\x43\xac\x40\x39.{4})\xe3\x27\x00\x39", re.DOTALL)
PATCH_Y_INSTR = bytes.fromhex("e3 07 01 39")


def patch_file(filepath: str) -> bool:
    if not os.path.isfile(filepath):
        print(f"[-] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        data = bytearray(f.read())

    orig_len = len(data)

    # 1. Check if already patched in main()
    already_main = (data.count(PATCH_MAIN_BTN) == 1 and data.count(PATCH_MAIN_AXIS) == 1)
    already_send = (data.count(PATCH_X) == 2)

    if already_main and already_send:
        print(f"[+] {os.path.basename(filepath)}: Already fully patched for Joypad GPS & Space.")
        return True

    # 2. Patch main() inlined event loop
    if data.count(ORIG_MAIN_BTN) == 1:
        data = bytearray(data.replace(ORIG_MAIN_BTN, PATCH_MAIN_BTN))
        print(f"[+] {os.path.basename(filepath)}: Patched main() button handler -> DIK_C")
    elif data.count(PATCH_MAIN_BTN) == 1:
        pass
    else:
        print(f"[-] {os.path.basename(filepath)}: Could not find unique main() button pattern")
        return False

    if data.count(ORIG_MAIN_AXIS) == 1:
        data = bytearray(data.replace(ORIG_MAIN_AXIS, PATCH_MAIN_AXIS))
        print(f"[+] {os.path.basename(filepath)}: Patched main() axis handler -> DIK_C")
    elif data.count(PATCH_MAIN_AXIS) == 1:
        pass
    else:
        print(f"[-] {os.path.basename(filepath)}: Could not find unique main() axis pattern")
        return False

    # 3. Patch selectSend() Button X
    if data.count(ORIG_X) == 2:
        data = bytearray(data.replace(ORIG_X, PATCH_X))
        print(f"[+] {os.path.basename(filepath)}: Patched selectSend() Button X -> DIK_C")
    elif data.count(PATCH_X) == 2:
        pass
    else:
        print(f"[-] {os.path.basename(filepath)}: Could not find unique selectSend() Button X pattern")
        return False

    # 4. Patch selectSend() Button Y
    matches = list(RE_Y.finditer(data))
    if len(matches) == 1:
        m = matches[0]
        data[m.end() - 4 : m.end()] = PATCH_Y_INSTR
        print(f"[+] {os.path.basename(filepath)}: Patched selectSend() Button Y -> DIK_SPACE")
    else:
        # Check if already patched
        pass

    if len(data) != orig_len:
        print(f"[-] Error: Length mismatch after patching ({len(data)} != {orig_len})")
        return False

    # Create backup before writing
    bak_path = filepath + ".orig_gps"
    if not os.path.exists(bak_path):
        with open(bak_path, "wb") as f:
            with open(filepath, "rb") as orig_f:
                f.write(orig_f.read())
        print(f"[+] Backup saved: {os.path.basename(bak_path)}")

    with open(filepath, "wb") as f:
        f.write(data)

    print(f"[+] Successfully saved {os.path.basename(filepath)}.")
    return True


def main():
    targets = sys.argv[1:]
    if not targets:
        targets = [
            "ports/nfsu2/nfsu2.aarch64",
            "ports/nfsu2/nfsu2.aarch64.v10",
            "ports/nfsu2/nfsu2.aarch64.v12",
        ]

    success = True
    for t in targets:
        if os.path.exists(t):
            if not patch_file(t):
                success = False
        else:
            print(f"[!] Skipping non-existent target: {t}")

    if success:
        print("\n[+] All targets patched successfully.")
    else:
        print("\n[-] Some targets failed.")
        sys.exit(1)


if __name__ == "__main__":
    main()
