#!/usr/bin/env python3
import os
import re
import subprocess
import json
from collections import defaultdict

CONTROLLER_DISKS = defaultdict(list)

RED = '\033[0;31m'
GREEN = '\033[0;32m'
BOLD_GREEN = '\033[1;32m'
BLUE = '\033[0;34m'
CYAN = '\033[0;36m'
YELLOW = '\033[1;33m'
NC = '\033[0m'

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
        if "Device Model" in output and "SMART support is:" in output:
            return output
    return ""

def parse_sata_capability(text):
    match = re.search(r"SATA Version is:\s*.*?,\s*([0-9.]+ Gb/s)", text)
    if match:
        val = match.group(1)
        if "6.0" in val:
            return "SATA6"
        elif "3.0" in val:
            return "SATA3"
        elif "1.5" in val:
            return "SATA1"
    return "SATA?"

def parse_current_link(text):
    match = re.search(r"\(current:\s*([0-9.]+ Gb/s)\)", text)
    if match:
        val = match.group(1)
        if "6.0" in val:
            return "SATA6"
        elif "3.0" in val:
            return "SATA3"
        elif "1.5" in val:
            return "SATA1"
    return "SATA?"

def parse_smart_health(text):
    match = re.search(r"SMART.*(PASSED|OK|FAILED)", text, re.IGNORECASE)
    if match:
        return match.group(1).upper()
    return None

def parse_temperature(text):
    match = re.search(r"[Tt]emperature.*:\s+(\d+)\s*°?C", text)
    if match and 0 < int(match.group(1)) < 150:
        return f"🌡️ {match.group(1)}°C,"
    return "🌡️ N/A,"

def format_smart_health(val):
    if val in ("PASSED", "OK"):
        return "❤️ SMART: ✅ ,"
    elif val == "FAILED":
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

def compact_model_name(vendor, model):
    if vendor and model.startswith(vendor):
        return model
    if vendor in model:
        return model.replace(vendor, "").strip(" -")
    return model

def format_bytes(size):
    try:
        size = int(size)
        for unit in ['B', 'K', 'M', 'G', 'T']:
            if size < 1024:
                return f"{size:.1f}{unit}"
            size /= 1024
    except:
        return "N/A"

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
        temp = "🌡️ N/A,"
        attributes = data.get("ata_smart_attributes", {}).get("table", [])
        for attr in attributes:
            if attr["id"] in [190, 194]:
                val = attr.get("raw", {}).get("value")
                if isinstance(val, int) and 0 < val < 150:
                    temp = f"🌡️ {val}°C,"
        iface = parse_sata_capability(data.get("interface_speed", {}).get("string", ""))
        link = color_link_speed(parse_current_link(data.get("interface_speed", {}).get("string", "")))
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
        temp = parse_temperature(txt)
        iface = parse_sata_capability(txt)
        link = color_link_speed(parse_current_link(txt))

    CONTROLLER_DISKS[controller].append(
        f"{GREEN}💾 {device}{NC}  ({model}, {size}, {iface}, {link}, {health} {temp} 🔢 SN: {serial}, 🔧 FW: {firmware})"
    )

def print_output():
    print(f"{BLUE}📤 Preparing output...{NC}")
    for ctrl in sorted(CONTROLLER_DISKS.keys(), key=lambda x: pci_sort_key(x.split()[0])):
        print(f"{CYAN}🎯 {ctrl}{NC}")
        for disk in CONTROLLER_DISKS[ctrl]:
            print(f"  └── {disk}")
        print()

def main():
    if os.geteuid() != 0:
        print(f"{RED}❌ This script must be run as root.{NC}")
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
    for tool in ["smartctl", "lsblk", "lspci"]:
        if not shutil.which(tool):
            print(f"{RED}❌ Missing required tool: {tool}{NC}")
            exit(1)

    print(f"{BLUE}🧮 Scanning disks...{NC}")
    for dev in get_all_block_devices():
        process_drive(dev)

    print_output()

if __name__ == "__main__":
    import shutil
    main()
