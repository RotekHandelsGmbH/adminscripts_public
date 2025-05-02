#!/usr/bin/env python3
import os
import re
import subprocess
from collections import defaultdict

# ── Setup ─────────────────────────────────────────────────────────────────────────────

CONTROLLER_DISKS = defaultdict(list)

# ── Colors ─────────────────────────────────────────────────────────────────────────────

RED = '\033[0;31m'
GREEN = '\033[0;32m'
BOLD_GREEN = '\033[1;32m'
BLUE = '\033[0;34m'
CYAN = '\033[0;36m'
YELLOW = '\033[1;33m'
NC = '\033[0m'

# ── Utility Functions ─────────────────────────────────────────────────────────────────

def run(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True).strip()
    except subprocess.CalledProcessError:
        return ""

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

def check_root():
    if os.geteuid() != 0:
        print(f"{RED}❌ This script must be run as root.{NC}")
        exit(1)

def check_dependencies():
    print(f"{BLUE}🔍 Checking dependencies...{NC}")
    required = ['smartctl', 'nvme']
    for tool in required:
        if not shutil.which(tool):
            print(f"{YELLOW}Missing required tool: {tool}{NC}")
            exit(1)

def get_storage_controller(devpath):
    try:
        real_path = run(f"realpath {devpath}")
        addresses = re.findall(r'([0-9a-f]{4}:)?[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]', real_path)
        for addr in reversed(addresses):
            ctrl = run(f"lspci -s {addr}")
            if re.search(r'sata|raid|sas|storage controller|non-volatile', ctrl, re.IGNORECASE):
                return f"{addr} {ctrl.split(':', 1)[-1]}"
    except Exception:
        pass
    return "Unknown Controller"

def format_smart_health(status):
    if status.upper() in ('PASSED', 'OK', '0'):
        return "❤️ SMART: ✅ ,"
    elif not status:
        return "❤️ SMART: ❓ ,"
    else:
        return f"{RED}❤️ SMART: ⚠️ ,{NC}"

def get_drive_temperature(device, dtype):
    if dtype == "sata":
        output = run(f"smartctl -A {device}")
        match = re.search(r'(?i)(Temp|Temperature).*?([0-9]+)', output)
        return f"🌡️ {match.group(2)}°C," if match else "🌡️ N/A,"
    elif dtype == "nvme":
        output = run(f"nvme smart-log {device}")
        match = re.search(r'Temperature\s*:\s*([0-9]+)', output, re.IGNORECASE)
        return f"🌡️ {match.group(1)}°C," if match else "🌡️ N/A,"
    return "🌡️ N/A,"

def color_link_speed(link):
    if re.match(r'(12|16|32|8)\.0', link):
        return f"{BOLD_GREEN}🧩 link={link}{NC}"
    elif "6.0" in link:
        return f"{GREEN}🧩 link={link}{NC}"
    elif "3.0" in link:
        return f"{YELLOW}🧩 link={link}{NC}"
    return f"🧩 link={link}"

def get_smart_field(device, label):
    output = run(f"smartctl -i {device}")
    match = re.search(f"{label}:\\s*(.+)", output, re.IGNORECASE)
    return match.group(1).strip() if match else "unknown"

# ── Disk Processing ───────────────────────────────────────────────────────────────────

def process_sata_disks():
    print(f"{BLUE}🧮 Scanning SATA disks...{NC}")
    for dev in os.listdir("/sys/block"):
        if not dev.startswith("sd"):
            continue
        device = f"/dev/{dev}"
        devpath = f"/sys/block/{dev}/device"
        controller = get_storage_controller(devpath)

        model = run(f"cat {devpath}/model")
        vendor = run(f"cat {devpath}/vendor")
        size = run(f"lsblk -dn -o SIZE {device}")
        serial = get_smart_field(device, "Serial Number")
        firmware = get_smart_field(device, "Firmware Version")
        smart_health = format_smart_health(run(f"smartctl -H {device} | grep -iE 'SMART.*(result|assessment)' | awk -F: '{{print $2}}'"))
        temperature = get_drive_temperature(device, "sata")
        protocol = run(f"smartctl -i {device} | grep -E 'Transport protocol|SATA Version' | sed -n 's/.*SATA Version is:[[:space:]]*\\([^ ]*\\).*/\\1/p'")
        linkspeed = run(f"smartctl -i {device} | grep -oP 'current:\\s*\\K[^)]+' | head -1") or \
                    run(f"smartctl -i {device} | grep -oP 'SATA.*,[[:space:]]*\\K[0-9.]+ Gb/s' | head -1")
        link_display = color_link_speed(linkspeed or "unknown")

        CONTROLLER_DISKS[controller].append(f"{GREEN}💾 {device}{NC}  ({vendor} {model}, {size}, {protocol or 'unknown'}, {link_display}, {smart_health} {temperature} 🔢 SN: {serial}, 🔧 FW: {firmware})")

def process_nvme_disks():
    print(f"{BLUE}⚡ Scanning NVMe disks...{NC}")
    for entry in os.listdir("/dev"):
        if not re.match(r'nvme\d+n1$', entry):
            continue
        nvdev = f"/dev/{entry}"
        sysdev = f"/sys/block/{entry}/device"
        controller = get_storage_controller(sysdev)

        idctrl = run(f"nvme id-ctrl -H {nvdev}")
        if not idctrl:
            print(f"{RED}⚠️  Failed to read NVMe info from {nvdev} — skipping.{NC}")
            continue

        model = re.search(r'MN\s*:\s*(.*)', idctrl)
        vendorid = re.search(r'VID\s*:\s*(.*)', idctrl)
        serial = re.search(r'SN\s*:\s*(.*)', idctrl)
        firmware = re.search(r'FR\s*:\s*(.*)', idctrl)
        size = run(f"lsblk -dn -o SIZE {nvdev}")
        crit_warn = run(f"nvme smart-log {nvdev} | awk -F: '/^critical_warning/ {{print $2}}'")
        smart_health = format_smart_health(crit_warn)
        temperature = get_drive_temperature(nvdev, "nvme")

        base = entry[:-2]  # Strip 'n1'
        width = run(f"cat /sys/class/nvme/{base}/device/current_link_width")
        speed = run(f"cat /sys/class/nvme/{base}/device/current_link_speed")
        link = f"PCIe {speed or 'unknown'} PCIe x{width or 'unknown'}"
        link_display = color_link_speed(link)

        CONTROLLER_DISKS[controller].append(f"{GREEN}💾 {nvdev}{NC}  (0x{vendorid.group(1) if vendorid else '??'} {model.group(1) if model else '??'}, {size}, NVMe, {link_display}, {smart_health} {temperature} 🔢 SN: {serial.group(1) if serial else '??'}, 🔧 FW: {firmware.group(1) if firmware else '??'})")

# ── Output ────────────────────────────────────────────────────────────────────────────

def print_output():
    print(f"{BLUE}📤 Preparing output...{NC}")
    for ctrl, devices in CONTROLLER_DISKS.items():
        print(f"{CYAN}🎯 {ctrl}{NC}")
        for dev in devices:
            print(f"  └── {dev}")
        print("")

# ── Main ──────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import shutil
    check_root()
    print_header()
    check_dependencies()
    process_sata_disks()
    process_nvme_disks()
    print_output()
