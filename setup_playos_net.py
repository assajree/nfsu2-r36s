#!/usr/bin/env python3
"""
setup_playos_net.py — One-Command Network, Static IP, mDNS & SSH Key Setup for playOS (R36H / R36S)

Features:
1. Auto-discovers the R36H/R36S (playOS) on the local LAN subnet (no need to look up its IP on the handheld).
2. Generates an ED25519 SSH key on the PC (if not present), installs it on the R36H (/home/ark/.ssh/authorized_keys),
   and configures ~/.ssh/config so `ssh r36h` and `scp ... r36h:...` connect passwordlessly in ~0.2s.
3. Installs and enables `avahi-daemon` on playOS so `playos.local` resolves via mDNS on every Wi-Fi network.
4. Disables Wi-Fi Power Save (`wifi.powersave = 2`) and IPv6 retry log spam (`ipv6.method = ignore`) across all
   saved Wi-Fi profiles on the device.
5. Automatically locks the device's current DHCP IP (or a user-specified `--ip x.x.x.x`) as a permanent Static IP
   for the currently connected Wi-Fi network so Wi-Fi BSSID roaming never changes the IP again.

Usage:
  python3 setup_playos_net.py                  # Auto-discover & lock current IP as Static IP
  python3 setup_playos_net.py --ip 192.168.1.47 # Auto-discover & lock specific Static IP
  python3 setup_playos_net.py --dhcp           # Keep dynamic DHCP, still configure SSH key + playos.local + power save
"""

import argparse
import concurrent.futures
import os
import pty
import re
import select
import socket
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_USER = "ark"
DEFAULT_PASS = "ark"


def run_ssh_pty(host: str, remote_cmd: str, user: str = DEFAULT_USER, password: str = DEFAULT_PASS, timeout: float = 120.0):
    """Run an SSH command using a pseudo-terminal so password prompts work without sshpass/paramiko."""
    argv = [
        "ssh",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "ConnectTimeout=4",
        "-o", "LogLevel=ERROR",
        f"{user}@{host}",
        remote_cmd,
    ]
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(argv[0], argv)

    out = b""
    sent_pw = False
    deadline = time.time() + timeout
    while time.time() < deadline:
        remaining = max(0.1, deadline - time.time())
        r, _, _ = select.select([fd], [], [], min(2.0, remaining))
        if not r:
            continue
        try:
            data = os.read(fd, 4096)
            if not data:
                break
            out += data
            if not sent_pw and b"password:" in out.lower():
                os.write(fd, (password + "\n").encode("utf-8"))
                sent_pw = True
        except OSError:
            break

    _, status = os.waitpid(pid, 0)
    os.close(fd)
    code = os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1
    text = out.decode("utf-8", errors="replace")
    # Strip password prompt line if echoed
    text = re.sub(r"^.*password:\s*\r?\n?", "", text, flags=re.IGNORECASE)
    return code, text.strip()


def get_local_subnets():
    """Detect local /24 IPv4 prefixes from `ip -4 addr`."""
    prefixes = []
    try:
        res = subprocess.run(["ip", "-4", "-o", "addr", "show"], capture_output=True, text=True, check=False)
        for line in res.stdout.splitlines():
            if " lo " in line or " docker" in line or " br-" in line:
                continue
            m = re.search(r"inet\s+(\d+\.\d+\.\d+)\.\d+/\d+", line)
            if m and m.group(1) not in prefixes:
                prefixes.append(m.group(1))
    except Exception:
        pass
    if not prefixes:
        prefixes.append("192.168.1")
    return prefixes


def probe_port_22(ip: str, timeout: float = 0.35):
    try:
        with socket.create_connection((ip, 22), timeout=timeout):
            return ip
    except Exception:
        return None


def is_playos_device(host: str, user: str, password: str) -> bool:
    code, out = run_ssh_pty(host, "echo __OK__$(uname -n)__$(id -un)__", user=user, password=password, timeout=6.0)
    if code != 0:
        return False
    return "__OK__PLAYOS__" in out.upper() or "__OK__" in out


def discover_playos(explicit_host: str | None, user: str, password: str) -> str:
    if explicit_host and probe_port_22(explicit_host, timeout=1.0):
        if is_playos_device(explicit_host, user, password):
            return explicit_host

    # Try mDNS playos.local first
    if probe_port_22("playos.local", timeout=0.8):
        if is_playos_device("playos.local", user, password):
            return "playos.local"

    print("[1/5] Scanning local network for playOS (R36H/R36S) on SSH port 22...")
    candidates = []
    for prefix in get_local_subnets():
        ips = [f"{prefix}.{i}" for i in range(2, 255)]
        with concurrent.futures.ThreadPoolExecutor(max_workers=64) as ex:
            for found in ex.map(probe_port_22, ips):
                if found:
                    candidates.append(found)

    for ip in candidates:
        code, out = run_ssh_pty(ip, "echo __HOST__=$(uname -n)", user=user, password=password, timeout=5.0)
        if code == 0 and "__HOST__=PLAYOS" in out.upper():
            print(f"      -> Found playOS at {ip}")
            return ip

    raise RuntimeError(
        "Could not find playOS on the local network. Make sure the R36H is turned on and connected to Wi-Fi."
    )


def ensure_local_ssh_key() -> str:
    ssh_dir = Path.home() / ".ssh"
    ssh_dir.mkdir(mode=0o700, exist_ok=True)
    os.chmod(ssh_dir, 0o700)
    key_path = ssh_dir / "id_ed25519"
    pub_path = ssh_dir / "id_ed25519.pub"
    if not key_path.exists() or not pub_path.exists():
        print("[2/5] Generating new local ED25519 SSH key (~/.ssh/id_ed25519)...")
        subprocess.run(["ssh-keygen", "-t", "ed25519", "-N", "", "-f", str(key_path)], check=True)
    return pub_path.read_text(encoding="utf-8").strip()


def update_local_ssh_config(static_ip: str, user: str):
    ssh_dir = Path.home() / ".ssh"
    cfg_path = ssh_dir / "config"
    block = (
        "# BEGIN PLAYOS R36H\n"
        f"Host r36h playos playos.local {static_ip}\n"
        f"    HostName {static_ip}\n"
        f"    User {user}\n"
        "    IdentityFile ~/.ssh/id_ed25519\n"
        "    StrictHostKeyChecking no\n"
        "    UserKnownHostsFile /dev/null\n"
        "    LogLevel ERROR\n"
        "# END PLAYOS R36H\n"
    )
    existing = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
    if "# BEGIN PLAYOS R36H" in existing and "# END PLAYOS R36H" in existing:
        updated = re.sub(
            r"# BEGIN PLAYOS R36H\n.*?# END PLAYOS R36H\n?",
            block,
            existing,
            flags=re.DOTALL,
        )
    else:
        updated = block + ("\n" + existing if existing else "")
    cfg_path.write_text(updated, encoding="utf-8")
    os.chmod(cfg_path, 0o600)


def main():
    parser = argparse.ArgumentParser(description="Configure playOS (R36H/R36S) Static IP, mDNS (playos.local), Wi-Fi Power Save & SSH Key.")
    parser.add_argument("--host", help="Initial IP or hostname of R36H (auto-discovered if omitted)")
    parser.add_argument("--ip", help="Specific Static IP to lock (defaults to locking the device's current DHCP IP)")
    parser.add_argument("--dhcp", action="store_true", help="Keep dynamic DHCP instead of locking a Static IP")
    parser.add_argument("--user", default=DEFAULT_USER, help="SSH username (default: ark)")
    parser.add_argument("--password", default=DEFAULT_PASS, help="SSH password (default: ark)")
    args = parser.parse_args()

    host = discover_playos(args.host, args.user, args.password)
    pubkey = ensure_local_ssh_key()

    print(f"[2/5] Installing SSH key and inspecting active Wi-Fi profile on {host}...")
    probe_script = (
        f"mkdir -p ~/.ssh && chmod 700 ~/.ssh && "
        f"(grep -qF '{pubkey}' ~/.ssh/authorized_keys 2>/dev/null || echo '{pubkey}' >> ~/.ssh/authorized_keys) && "
        f"chmod 600 ~/.ssh/authorized_keys && "
        "ACTIVE_CONN=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: '$2==\"wlan0\"{print $1; exit}') && "
        "CURR_CIDR=$(ip -4 -o addr show dev wlan0 | awk '{print $4; exit}') && "
        "CURR_GW=$(ip -4 route show default dev wlan0 | awk '{print $3; exit}') && "
        "echo \"__INFO__|${ACTIVE_CONN}|${CURR_CIDR}|${CURR_GW}\""
    )
    code, out = run_ssh_pty(host, probe_script, user=args.user, password=args.password)
    if code != 0 or "__INFO__|" not in out:
        raise RuntimeError(f"Failed to query Wi-Fi state from {host}:\n{out}")

    info_line = [ln for ln in out.splitlines() if "__INFO__|" in ln][-1]
    _, active_conn, curr_cidr, curr_gw = info_line.split("|", 3)
    active_conn = active_conn.strip()
    curr_cidr = curr_cidr.strip()
    curr_gw = curr_gw.strip()

    if not active_conn or not curr_cidr:
        raise RuntimeError(f"Could not detect active wlan0 connection (got conn='{active_conn}', cidr='{curr_cidr}')")

    curr_ip, prefix_len = curr_cidr.split("/") if "/" in curr_cidr else (curr_cidr, "24")
    target_ip = args.ip.split("/")[0] if args.ip else curr_ip
    target_cidr = f"{target_ip}/{prefix_len}"
    if not curr_gw:
        parts = target_ip.split(".")
        curr_gw = f"{parts[0]}.{parts[1]}.{parts[2]}.1"

    print(f"      -> Active Wi-Fi: '{active_conn}' | Current IP: {curr_cidr} | Gateway: {curr_gw}")

    print("[3/5] Installing avahi-daemon (playos.local mDNS) & disabling Wi-Fi Power Save / IPv6 spam...")
    setup_cmd = (
        f"echo {args.password} | sudo -S bash -c '"
        "set -e; "
        "mkdir -p /etc/NetworkManager/conf.d; "
        "printf \"[connection]\\nwifi.powersave = 2\\n\" > /etc/NetworkManager/conf.d/99-wifi-powersave-off.conf; "
        "nmcli -t -f NAME,TYPE connection show | awk -F: \"$2==\\\"802-11-wireless\\\"{print \\$1}\" | while IFS= read -r c; do "
        "  [ -n \"$c\" ] && nmcli connection modify \"$c\" 802-11-wireless.powersave 2 ipv6.method ignore 2>/dev/null || true; "
        "done; "
        "if ! command -v avahi-daemon >/dev/null 2>&1; then "
        "  DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq avahi-daemon libnss-mdns; "
        "fi; "
        "systemctl enable --now avahi-daemon; "
    )
    if args.dhcp:
        setup_cmd += (
            f"nmcli connection modify \"{active_conn}\" ipv4.method auto ipv4.addresses \"\" ipv4.gateway \"\" ipv4.dns \"\"; "
        )
    else:
        setup_cmd += (
            f"nmcli connection modify \"{active_conn}\" ipv4.addresses \"{target_cidr}\" ipv4.gateway \"{curr_gw}\" ipv4.dns \"{curr_gw} 8.8.8.8 1.1.1.1\" ipv4.method manual; "
        )
    setup_cmd += (
        f"systemd-run --unit=playos-net-reapply-{int(time.time())} nmcli connection up \"{active_conn}\" >/dev/null 2>&1 || true"
        "'"
    )
    code, out = run_ssh_pty(host, setup_cmd, user=args.user, password=args.password, timeout=180.0)
    if code != 0:
        raise RuntimeError(f"Remote configuration failed (exit {code}):\n{out}")

    print(f"[4/5] Waiting for wlan0 to apply {'DHCP' if args.dhcp else f'Static IP {target_cidr}'}...")
    time.sleep(4.0)

    verify_host = "playos.local" if args.dhcp else target_ip
    update_local_ssh_config(verify_host, args.user)

    print("[5/5] Verifying passwordless `ssh r36h` and `playos.local` mDNS...")
    res = subprocess.run(
        ["ssh", "r36h", "echo \"Host: $(uname -n) | IP: $(hostname -I) | Avahi: $(systemctl is-active avahi-daemon)\" && ip -4 addr show dev wlan0 | grep inet"],
        capture_output=True,
        text=True,
        timeout=10.0,
    )
    if res.returncode != 0:
        raise RuntimeError(f"Verification via `ssh r36h` failed:\n{res.stderr}")

    print("\n======================================================================")
    print(" playOS Network & SSH Setup Complete!")
    for line in res.stdout.strip().splitlines():
        print("  ", line.strip())
    print(" You can now connect anytime using:")
    print(f"   ssh r36h          (pinned to {verify_host})")
    print("   ssh ark@playos.local")
    print("======================================================================")


if __name__ == "__main__":
    main()
