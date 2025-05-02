#!/usr/bin/env python3
import os
import re
import subprocess
import json
from collections import defaultdict

CONTROLLER_DISKS = defaultdict(list)

# ── Colors ──────────────────────────────────────────────────────────

RED = '\033[0;31m'
GREEN = '\033[0;32m'
BOLD_GREEN = '\033[1;32m'
BLUE = '\033[0;34m'
CYAN = '\033[0;36m'
YELLOW = '\033[1;33m'
NC = '\033[0m'

# ── Helpers ─────────────────────────────────────────────────────────

def run(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return ""

def check_root():
    if os.geteuid() != 0:
        print(f"{RED}❌ This script must be run as root.{NC}")
        exit(1)

def print_header():
    print(f"""
{BOLD_GREEN}
╔═══════════════════════════════════════════════════════════════════════════════════════╗
║ 🧩  Disk-to-Controller Tree Visualizer                                                 ║
║ 👤  Author : bitranox                                                                  ║
║ 🏛️  License: MIT                                                                       ║
║ 💾  Shows disks grouped by controller with model, size, interface, link speed,         ║
║     SMART status, drive temperature, serial number, and firmware revision             ║
╚═══════════════════════════════════════════════════════════════════════════════════════╝
{NC}
""")

def check_dependencies():
    print(f"{BLUE}🔍 Checking dependencies...{NC}")
    for tool in ['lsblk', 'smartctl', 'lspci', 'udevadm']:
        if not shutil.which(tool):
            print(f"{RED}Missing tool: {tool}{NC}")
            exit(1)

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

def format_bytes(size):
    try:
        size = int(size)
        for unit in ['B', 'K', 'M', 'G', 'T']:
            if size < 1024:
                return f"{size:.1f}{unit}"
            size /= 1024
    except:
        return "N/A"

def format_temp(attrs):
    for attr in attrs:
        if attr["id"] in [190, 194]:
            raw = attr.get("raw", {})
            if "string" in raw and raw["string"].isdigit():
                return f"🌡️ {raw['string']}°C,"
            if isinstance(raw.get("value"), int) and 0 < raw["value"] < 150:
                return f"🌡️ {raw['value']}°C,"
    return "🌡️ N/A,"

def compact_model_name(vendor, model):
    if vendor and model.startswith(vendor):
        return model
    if vendor in model:
        return model.replace(vendor, "").strip(" -")
    return model

def link_label(speed):
    if "6.0" in speed:
        return "SATA6"
    if "3.0" in speed:
        return "SATA3"
    if "1.5" in speed:
        return "SATA1"
    return "SATA"

def color_link_speed(label):
    if "SATA6" in label:
        return f"{BOLD_GREEN}🧩 link={label}{NC}"
    if "SATA3" in label:
        return f"{GREEN}🧩 link={label}{NC}"
    if "SATA1" in label:
        return f"{YELLOW}🧩 link={label}{NC}"
    return f"🧩 link={label}"

def smart_health(passed):
    if passed is True:
        return "❤️ SMART: ✅ ,"
    if passed is False:
        return f"{RED}❤️ SMART: ⚠️ ,{NC}"
    return "❤️ SMART: ❓ ,"

def load_smart_data(dev):
    for cmd in [f"smartctl -j -a {dev}", f"smartctl -j -a -d sat {dev}"]:
        raw = run(cmd)
        try:
            return json.loads(raw)
        except:
            continue
    return None

# ── Main Logic ─────────────────────────────────────────────────────

def process_disks():
    print(f"{BLUE}🧮 Scanning disks...{NC}")
    lines = run("lsblk -dn -o NAME").splitlines()
    for name in lines:
        device = f"/dev/{name.strip()}"
        sys_path = f"/sys/block/{name.strip()}/device"
        controller = get_storage_controller(sys_path)

        data = load_smart_data(device)
        if data:
            model_raw = data.get("model_name", "unknown")
            vendor = data.get("model_family", "")
            model = compact_model_name(vendor, model_raw)
            serial = data.get("serial_number", "unknown")
            firmware = data.get("firmware_version", "unknown")
            size = format_bytes(data.get("user_capacity", {}).get("bytes", 0))
            health = smart_health(data.get("smart_status", {}).get("passed"))
            temp = format_temp(data.get("ata_smart_attributes", {}).get("table", []))
            speed_str = data.get("interface_speed", {}).get("max", {}).get("string", "")
            proto = link_label(speed_str)
            link = color_link_speed(proto)
        else:
            # Fallback
            model = run(f"udevadm info --query=all --name={device} | grep ID_MODEL=").strip().split('=')[-1]
            serial = run(f"udevadm info --query=all --name={device} | grep ID_SERIAL_SHORT=").strip().split('=')[-1]
            size = run(f"lsblk -dn -o SIZE {device}").strip()
            firmware = "unknown"
            temp = "🌡️ N/A,"
            health = "❤️ SMART: ❓ ,"
            proto = "SATA?"
            link = color_link_speed(proto)

        CONTROLLER_DISKS[controller].append(
            f"{GREEN}💾 {device}{NC}  ({model}, {size}, {proto}, {link}, "
            f"{health} {temp} 🔢 SN: {serial}, 🔧 FW: {firmware})"
        )

def print_output():
    print(f"{BLUE}📤 Preparing output...{NC}")
    for ctrl in sorted(CONTROLLER_DISKS.keys(), key=lambda x: pci_sort_key(x.split()[0])):
        print(f"{CYAN}🎯 {ctrl}{NC}")
        for disk in CONTROLLER_DISKS[ctrl]:
            print(f"  └── {disk}")
        print()

# ── Main ───────────────────────────────────────────────────────────

if __name__ == "__main__":
    import shutil
    check_root()
    print_header()
    check_dependencies()
    process_disks()
    print_output()
