#!/usr/bin/env python3
import os
import re
import shutil
import subprocess
from collections import defaultdict

# Terminal Colors
RED = '\033[0;31m'
GREEN = '\033[0;32m'
BOLD_GREEN = '\033[1;32m'
BLUE = '\033[0;34m'
CYAN = '\033[0;36m'
YELLOW = '\033[1;33m'
NC = '\033[0m'

controller_disks = defaultdict(list)

def run(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL).strip()
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

def check_dependencies():
    print(f"{BLUE}🔍 Checking dependencies...{NC}")
    for tool in ["smartctl", "lsblk", "lspci", "nvme"]:
        if not shutil.which(tool):
            print(f"{RED}❌ Missing tool: {tool}{NC}")
            exit(1)

def get_storage_controller(devpath):
    try:
        real_path = os.path.realpath(devpath)
        addresses = re.findall(r'([0-9a-f]{2}:[0-9a-f]{2}\.[0-9])', real_path)
        for addr in reversed(addresses):
            line = run(f"lspci -s {addr}")
            if re.search(r'sata|raid|sas|storage controller|non-volatile', line, re.IGNORECASE):
                return f"{addr} {line.split(':', 2)[-1].strip()}"
    except Exception:
        pass
    return "Unknown Controller"

def format_smart_health(status):
    if status in ("PASSED", "OK", "0"):
        return "❤️ SMART: ✅ ,"
    elif not status:
        return "❤️ SMART: ❓ ,"
    else:
        return f"{RED}❤️ SMART: ⚠️ ,{NC}"

def get_drive_temperature(device, dtype):
    if dtype == "sata":
        output = run(f"smartctl -A {device}")
        match = re.search(r"[Tt]emp.*?(\d+)\s*C", output)
        return f"🌡️ {match.group(1)}°C," if match else "🌡️ N/A,"
    elif dtype == "nvme":
        output = run(f"nvme smart-log {device}")
        match = re.search(r"temperature\s*:\s*(\d+)", output, re.IGNORECASE)
        return f"🌡️ {match.group(1)}°C," if match else "🌡️ N/A,"
    return "🌡️ N/A,"

def color_link_speed(link):
    if re.match(r"^(12|16|32|8)\.0", link):
        return f"{BOLD_GREEN}🧩 link={link}{NC}"
    elif "6.0" in link:
        return f"{GREEN}🧩 link={link}{NC}"
    elif "3.0" in link:
        return f"{YELLOW}🧩 link={link}{NC}"
    return f"🧩 link={link}"

def get_smart_field(device, label):
    output = run(f"smartctl -i {device}")
    match = re.search(rf"{label}:\s*(.+)", output, re.IGNORECASE)
    return match.group(1).strip() if match else "unknown"

def process_sata_disks():
    print(f"{BLUE}🧮 Scanning SATA disks...{NC}")
    for disk in sorted(os.listdir("/sys/block")):
        if not disk.startswith("sd"):
            continue
        device = f"/dev/{disk}"
        devpath = f"/sys/block/{disk}/device"
        controller = get_storage_controller(devpath)
        model = run(f"cat /sys/block/{disk}/device/model")
        vendor = run(f"cat /sys/block/{disk}/device/vendor")
        size = run(f"lsblk -dn -o SIZE {device}")
        serial = get_smart_field(device, "Serial Number")
        firmware = get_smart_field(device, "Firmware Version")
        smart_status_line = run(f"smartctl -H {device}")
        health_match = re.search(r"(PASSED|OK|FAILED)", smart_status_line, re.IGNORECASE)
        smart_health = format_smart_health(health_match.group(1).upper() if health_match else "")
        temperature = get_drive_temperature(device, "sata")
        info = run(f"smartctl -i {device}")
        protocol_match = re.search(r"SATA Version is:\s*.*?,\s*([0-9.]+ Gb/s)", info)
        protocol = protocol_match.group(1) if protocol_match else "unknown"
        link_match = re.search(r"current:\s*([0-9.]+ Gb/s)", info)
        link = link_match.group(1) if link_match else protocol
        link_display = color_link_speed(link)

        controller_disks[controller].append(
            f"{GREEN}💾 {device}{NC}  ({vendor} {model}, {size}, SATA, {link_display}, "
            f"{smart_health} {temperature} 🔢 SN: {serial}, 🔧 FW: {firmware})"
        )

def process_nvme_disks():
    print(f"{BLUE}⚡ Scanning NVMe disks...{NC}")
    for entry in os.listdir("/dev"):
        if re.match(r"nvme\d+n1$", entry):
            nvdev = f"/dev/{entry}"
            sysdev = f"/sys/block/{entry}/device"
            controller = get_storage_controller(sysdev)
            idctrl = run(f"nvme id-ctrl -H {nvdev}")
            if not idctrl:
                continue
            model = re.search(r"mn\s*:\s*(.+)", idctrl, re.IGNORECASE)
            serial = re.search(r"sn\s*:\s*(.+)", idctrl, re.IGNORECASE)
            firmware = re.search(r"fr\s*:\s*(.+)", idctrl, re.IGNORECASE)
            vendorid = re.search(r"vid\s*:\s*(.+)", idctrl, re.IGNORECASE)
            model = model.group(1).strip() if model else "unknown"
            serial = serial.group(1).strip() if serial else "unknown"
            firmware = firmware.group(1).strip() if firmware else "unknown"
            vendorid = vendorid.group(1).strip() if vendorid else "unknown"
            size = run(f"lsblk -dn -o SIZE {nvdev}")
            smart_log = run(f"nvme smart-log {nvdev}")
            crit_warn = re.search(r"critical_warning\s*:\s*(\d+)", smart_log)
            health = format_smart_health("OK" if crit_warn and crit_warn.group(1) == "0" else "FAILED")
            temperature = get_drive_temperature(nvdev, "nvme")
            base = entry[:-2]
            width = run(f"cat /sys/class/nvme/{base}/device/current_link_width")
            speed = run(f"cat /sys/class/nvme/{base}/device/current_link_speed")
            link = f"PCIe {speed} x{width}".strip()
            link_display = color_link_speed(link)

            controller_disks[controller].append(
                f"{GREEN}💾 {nvdev}{NC}  (0x{vendorid} {model}, {size}, NVMe, {link_display}, "
                f"{health} {temperature} 🔢 SN: {serial}, 🔧 FW: {firmware})"
            )

def print_output():
    print(f"{BLUE}📤 Preparing output...{NC}")
    for ctrl in sorted(controller_disks.keys()):
        print(f"{CYAN}🎯 {ctrl}{NC}")
        for line in controller_disks[ctrl]:
            print(f"  └── {line}")
        print()

def main():
    if os.geteuid() != 0:
        print(f"{RED}❌ This script must be run as root.{NC}")
        exit(1)

    print_header()
    check_dependencies()
    process_sata_disks()
    process_nvme_disks()
    print_output()

if __name__ == "__main__":
    main()
