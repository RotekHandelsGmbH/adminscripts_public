#!/usr/bin/env python3
import os
import re
import subprocess
import json
from collections import defaultdict

# ─────────────────────────────────────────────────────
# Constants & Globals
# ─────────────────────────────────────────────────────
CONTROLLER_DISKS = defaultdict(list)

RED = '\033[0;31m'
GREEN = '\033[0;32m'
BOLD_GREEN = '\033[1;32m'
BLUE = '\033[0;34m'
CYAN = '\033[0;36m'
YELLOW = '\033[1;33m'
NC = '\033[0m'


# ─────────────────────────────────────────────────────
# Core Utility Functions
# ─────────────────────────────────────────────────────

def run(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return ""

def get_all_block_devices():
    lines = run("lsblk -dn -o NAME").splitlines()
    return [f"/dev/{name.strip()}" for name in lines]

def get_storage_controller(devpath):
    try:
        real_path = os.path.realpath(devpath)
        addresses = re.findall(r'([0-9a-f]{2}:[0-9a-f]{2}\.[0-9])', real_path)
        for addr in reversed(addresses):
            line = run(f"lspci -s {addr}").strip()
            if re.search(r'sata|raid|sas|storage controller|non-volatile', line, re.IGNORECASE):
                return f"{addr} {line.split(':', 2)[-1].strip()}"
    except Exception:
        pass
    return "Unknown Controller"

def pci_sort_key(ctrl):
    match = re.match(r'([0-9a-f]{2}):([0-9a-f]{2})\.([0-9])', ctrl)
    if match:
        return tuple(int(x, 16) for x in match.groups())
    return (999, 999, 999)

# ─────────────────────────────────────────────────────
# SMART Parsing Logic
# ─────────────────────────────────────────────────────

def try_smartctl_json(device):
    for cmd in [f"smartctl -j -a {device}", f"smartctl -j -a -d sat {device}"]:
        raw = run(cmd)
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            continue
    return None

def try_smartctl_text(device):
    for cmd in [f"smartctl -a {device}", f"smartctl -a -d sat {device}"]:
        output = run(cmd)
        if "Model Family" in output or "SMART support is:" in output:
            return output
    return ""

def parse_sata_capabilities(text):
    match = re.search(r"SATA Version is:\s*(.*)", text)
    if match:
        capability = match.group(1).strip()
        if "6.0" in capability:
            return "SATA6"
        if "3.0" in capability:
            return "SATA3"
        if "1.5" in capability:
            return "SATA1"
    return "SATA?"

def parse_current_link_speed(text):
    match = re.search(r"current:\s*([0-9.]+ Gb/s)", text)
    if match:
        speed = match.group(1)
        if "6.0" in speed:
            return "SATA6"
        if "3.0" in speed:
            return "SATA3"
        if "1.5" in speed:
            return "SATA1"
    return "SATA?"

def parse_smart_health(text):
    match = re.search(r"SMART.*(PASSED|OK|FAILED)", text, re.IGNORECASE)
    if match:
        return match.group(1).upper()
    return None

def parse_fallback_temperature(text):
    match = re.search(r"Temperature.*?\s(\d+)\s*C", text)
    if match:
        return f"🌡️ {match.group(1)}°C,"
    return "🌡️ N/A,"

# ─────────────────────────────────────────────────────
# Formatting
# ─────────────────────────────────────────────────────

def compact_model_name(vendor, model):
    if vendor and model.startswith(vendor):
        return model
    if vendor in model:
        return model.replace(vendor, "").strip(" -")
    return model

def format_smart_health(value):
    if value in ("PASSED", "OK"):
        return "❤️ SMART: ✅ ,"
    elif value == "FAILED":
        return f"{RED}❤️ SMART: ⚠️ ,{NC}"
    return "❤️ SMART: ❓ ,"

def color_link_speed(label):
    if "SATA6" in label:
        return f"{BOLD_GREEN}🧩 link={label}{NC}"
    elif "SATA3" in label:
        return f"{GREEN}🧩 link={label}{NC}"
    elif "SATA1" in label:
        return f"{YELLOW}🧩 link={label}{NC}"
    return f"🧩 link={label}"

def format_bytes(size):
    try:
        size = int(size)
        for unit in ['B', 'K', 'M', 'G', 'T']:
            if size < 1024:
                return f"{size:.1f}{unit}"
            size /= 1024
    except:
        return "N/A"

# ─────────────────────────────────────────────────────
# Drive Handler
# ─────────────────────────────────────────────────────

def process_drive(device):
    devname = os.path.basename(device)
    sys_path = f"/sys/block/{devname}/device"
    controller = get_storage_controller(sys_path)

    data = try_smartctl_json(device)
    if data:
        model = compact_model_name(data.get("model_family", ""), data.get("model_name", "unknown"))
        serial = data.get("serial_number", "unknown")
        firmware = data.get("firmware_version", "unknown")
        size = format_bytes(data.get("user_capacity", {}).get("bytes", 0))
        health = format_smart_health(data.get("smart_status", {}).get("passed"))
        attributes = data.get("ata_smart_attributes", {}).get("table", [])
        temp = "🌡️ N/A,"
        for attr in attributes:
            if attr["id"] in [194, 190]:
                val = attr.get("raw", {}).get("value")
                if isinstance(val, int) and 0 < val < 150:
                    temp = f"🌡️ {val}°C,"
                    break
        proto = parse_sata_capabilities(data.get("interface_speed", {}).get("string", ""))
        link = color_link_speed(parse_current_link_speed(data.get("interface_speed", {}).get("string", "")))
    else:
        txt = try_smartctl_text(device)
        model = re.search(r"Device Model:\s*(.+)", txt)
        vendor = re.search(r"Model Family:\s*(.+)", txt)
        serial = re.search(r"Serial Number:\s*(.+)", txt)
        firmware = re.search(r"Firmware Version:\s*(.+)", txt)
        size = run(f"lsblk -dn -o SIZE {device}").strip()
        model = compact_model_name(
            vendor.group(1).strip() if vendor else "",
            model.group(1).strip() if model else "unknown"
        )
        serial = serial.group(1).strip() if serial else "unknown"
        firmware = firmware.group(1).strip() if firmware else "unknown"
        health = format_smart_health(parse_smart_health(txt))
        temp = parse_fallback_temperature(txt)
        proto = parse_sata_capabilities(txt)
        link = color_link_speed(parse_current_link_speed(txt))

    CONTROLLER_DISKS[controller].append(
        f"{GREEN}💾 {device}{NC}  ({model}, {size}, {proto}, {link}, "
        f"{health} {temp} 🔢 SN: {serial}, 🔧 FW: {firmware})"
    )

# ─────────────────────────────────────────────────────
# Output
# ─────────────────────────────────────────────────────

def print_output():
    print(f"{BLUE}📤 Preparing output...{NC}")
    for ctrl in sorted(CONTROLLER_DISKS.keys(), key=lambda x: pci_sort_key(x.split()[0])):
        print(f"{CYAN}🎯 {ctrl}{NC}")
        for disk in CONTROLLER_DISKS[ctrl]:
            print(f"  └── {disk}")
        print()

# ─────────────────────────────────────────────────────
# Entry Point
# ─────────────────────────────────────────────────────

def main():
    if os.geteuid() != 0:
        print(f"{RED}❌ Run as root!{NC}")
        exit(1)
    print(f"{BOLD_GREEN}")
    print("╔═══════════════════════════════════════════════════════════════════════════════════════╗")
    print("║ 🧩  Disk-to-Controller Tree Visualizer                                                 ║")
    print("║ 👤  Author : bitranox                                                                  ║")
    print("║ 🏛️  License: MIT                                                                       ║")
    print("║ 💾  Shows disks grouped by controller with model, size, interface, link speed,         ║")
    print("║     SMART status, drive temperature, serial number, and firmware revision             ║")
    print("╚═══════════════════════════════════════════════════════════════════════════════════════╝")
    print(f"{NC}")
    print(f"{BLUE}🔍 Checking dependencies...{NC}")
    for cmd in ["smartctl", "lsblk", "lspci"]:
        if not shutil.which(cmd):
            print(f"{RED}Missing: {cmd}{NC}")
            exit(1)

    print(f"{BLUE}🧮 Scanning disks...{NC}")
    for dev in get_all_block_devices():
        process_drive(dev)

    print_output()


if __name__ == "__main__":
    import shutil
    main()
