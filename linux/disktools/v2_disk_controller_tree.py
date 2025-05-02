#!/usr/bin/env python3
import os
import re
import shutil
import subprocess
import json
from collections import defaultdict

CONTROLLER_DISKS = defaultdict(list)

# ── ANSI Colors ───────────────────────────────────────

RED = '\033[0;31m'
GREEN = '\033[0;32m'
BOLD_GREEN = '\033[1;32m'
BLUE = '\033[0;34m'
CYAN = '\033[0;36m'
YELLOW = '\033[1;33m'
NC = '\033[0m'

# ── System Utilities ─────────────────────────────────

def run(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return ""

def check_root():
    if os.geteuid() != 0:
        print(f"{RED}❌ This script must be run as root.{NC}")
        exit(1)

def check_dependencies():
    print(f"{BLUE}🔍 Checking dependencies...{NC}")
    required = ['smartctl', 'nvme', 'lspci', 'lsblk']
    for tool in required:
        if not shutil.which(tool):
            print(f"{YELLOW}Missing required tool: {tool}{NC}")
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

# ── Controller & PCI ─────────────────────────────────

def get_storage_controller(devpath):
    try:
        real_path = os.path.realpath(devpath)
        addresses = re.findall(r'([0-9a-f]{2}:[0-9a-f]{2}\.[0-9])', real_path)
        for addr in reversed(addresses):
            ctrl_line = run(f"lspci -s {addr}").strip()
            if re.search(r'sata|raid|sas|storage controller|non-volatile', ctrl_line, re.IGNORECASE):
                parts = ctrl_line.split(":", 2)
                return f"{addr} {parts[-1].strip()}"
    except Exception:
        pass
    return "Unknown Controller"

def pci_sort_key(controller_id):
    match = re.match(r'([0-9a-f]{2}):([0-9a-f]{2})\.([0-9])', controller_id)
    if match:
        return tuple(int(x, 16) for x in match.groups())
    return (999, 999, 999)

# ── Utility Functions ────────────────────────────────

def format_bytes(size_bytes):
    if size_bytes >= 1 << 40:
        return f"{size_bytes / (1 << 40):.1f}T"
    elif size_bytes >= 1 << 30:
        return f"{size_bytes / (1 << 30):.1f}G"
    elif size_bytes >= 1 << 20:
        return f"{size_bytes / (1 << 20):.1f}M"
    return f"{size_bytes}B"

def format_smart_health(passed):
    if passed is True:
        return "❤️ SMART: ✅ ,"
    elif passed is False:
        return f"{RED}❤️ SMART: ⚠️ ,{NC}"
    return "❤️ SMART: ❓ ,"

def get_temperature_from_attributes(attr_table):
    for attr in attr_table:
        if attr["id"] in [194, 190]:
            raw = attr.get("raw", {})
            if "string" in raw and raw["string"].isdigit():
                return f"🌡️ {raw['string']}°C,"
            if isinstance(raw.get("value"), int) and 0 <= raw["value"] <= 150:
                return f"🌡️ {raw['value']}°C,"
    return "🌡️ N/A,"

def get_sata_speed_label(speed_str):
    if "6.0" in speed_str:
        return "SATA6"
    elif "3.0" in speed_str:
        return "SATA3"
    elif "1.5" in speed_str:
        return "SATA1"
    return "SATA"

def color_link_speed(link):
    if "SATA6" in link:
        return f"{BOLD_GREEN}🧩 link={link}{NC}"
    elif "SATA3" in link:
        return f"{GREEN}🧩 link={link}{NC}"
    elif "SATA1" in link:
        return f"{YELLOW}🧩 link={link}{NC}"
    return f"🧩 link={link}"

def compact_model_name(vendor: str, model: str) -> str:
    """Removes duplicated vendor/model_family prefixes from model."""
    if vendor and model.startswith(vendor):
        return model
    if vendor and vendor in model:
        cleaned = model.replace(vendor, "").strip(" -")
        return cleaned if cleaned else model
    return model

# ── SATA Disk Handler (JSON-based) ──────────────────

def process_sata_disks():
    print(f"{BLUE}🧮 Scanning SATA disks...{NC}")
    lines = run("lsblk -dn -o NAME,TYPE").splitlines()
    for line in lines:
        name, dtype = line.strip().split()
        if dtype != "disk":
            continue
        device = f"/dev/{name}"
        devpath = f"/sys/block/{name}/device"
        controller = get_storage_controller(devpath)

        smart_json_raw = run(f"smartctl -j -a {device}")
        if not smart_json_raw.strip():
            continue

        try:
            data = json.loads(smart_json_raw)
        except json.JSONDecodeError:
            continue

        vendor = data.get("model_family", "").strip()
        model_raw = data.get("model_name", "unknown").strip()
        model = compact_model_name(vendor, model_raw)
        serial = data.get("serial_number", "unknown")
        firmware = data.get("firmware_version", "unknown")
        size_bytes = data.get("user_capacity", {}).get("bytes", 0)
        size = format_bytes(size_bytes)
        smart_passed = data.get("smart_status", {}).get("passed")
        smart_health = format_smart_health(smart_passed)
        attributes = data.get("ata_smart_attributes", {}).get("table", [])
        temperature = get_temperature_from_attributes(attributes)
        speed_str = data.get("interface_speed", {}).get("max", {}).get("string", "")
        protocol = get_sata_speed_label(speed_str)
        link_display = color_link_speed(protocol)

        CONTROLLER_DISKS[controller].append(
            f"{GREEN}💾 {device}{NC}  ({model}, {size}, {protocol}, "
            f"{link_display}, {smart_health} {temperature} 🔢 SN: {serial}, 🔧 FW: {firmware})"
        )

# ── Output ───────────────────────────────────────────

def print_output():
    print(f"{BLUE}📤 Preparing output...{NC}")
    sorted_keys = sorted(CONTROLLER_DISKS.keys(), key=lambda k: pci_sort_key(k.split()[0]))
    for ctrl in sorted_keys:
        print(f"{CYAN}🎯 {ctrl}{NC}")
        for dev in CONTROLLER_DISKS[ctrl]:
            print(f"  └── {dev}")
        print("")

# ── Main ─────────────────────────────────────────────

if __name__ == "__main__":
    check_root()
    print_header()
    check_dependencies()
    process_sata_disks()
    # NVMe support pending JSON integration
    print_output()
