#!/usr/bin/env python3
import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict

# Terminal colors
RED = '\033[0;31m'
BOLD_RED = '\033[1;31m'
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
    print(f"""{BOLD_GREEN}
╔═══════════════════════════════════════════════════════════════════════════════════════╗
║ 🧩  Disk-to-Controller Tree Visualizer                                                ║
║ 👤  Author : bitranox                                                                 ║
║ 🏛️  License: MIT                                                                       ║
║ 💾  Shows disks grouped by controller with model, size, interface, link speed,        ║
║     SMART status, drive temperature, serial number, and firmware revision             ║
╚═══════════════════════════════════════════════════════════════════════════════════════╝{NC}
""")

import shutil
import subprocess
import sys


def install_if_missing():
    packages = ["smartctl", "nvme"]
    package_mapping = {
        "apt": {"smartctl": "smartmontools", "nvme": "nvme-cli"},
        "dnf": {"smartctl": "smartmontools", "nvme": "nvme-cli"},
        "yum": {"smartctl": "smartmontools", "nvme": "nvme-cli"},
        "pacman": {"smartctl": "smartmontools", "nvme": "nvme-cli"},
    }

    pkg_mgr = None
    for mgr in ["apt", "dnf", "yum", "pacman"]:
        if shutil.which(mgr):
            pkg_mgr = mgr
            break

    if not pkg_mgr:
        print("⚠️ No supported package manager found (apt, dnf, yum, pacman) - continue anyway")
        return

    for cmd in packages:
        if not shutil.which(cmd):
            pkg_name = package_mapping[pkg_mgr][cmd]
            print(f"{BLUE}🔍 {cmd} not found. Installing {pkg_name} with {pkg_mgr}...")
            try:
                if pkg_mgr in ["apt", "dnf", "yum"]:
                    subprocess.check_call(["sudo", pkg_mgr, "install", "-y", pkg_name])
                elif pkg_mgr == "pacman":
                    subprocess.check_call(["sudo", "pacman", "-S", "--noconfirm", pkg_name])
            except subprocess.CalledProcessError:
                print(f"{RED}❌ Failed to install {pkg_name} using {pkg_mgr}.")
                sys.exit(1)


def check_dependencies():
    print(f"{BLUE}🔍 Checking dependencies...{NC}")
    for tool in ["smartctl", "lsblk", "lspci", "nvme"]:
        if not shutil.which(tool):
            print(f"{RED}❌ Missing tool: {tool}{NC}")
            exit(1)

def get_storage_controller(devpath):
    # devpath like : /sys/block/sda/device
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

def get_drive_temperature(device):
    output = run(f"smartctl -A {device}")
    for line in output.splitlines():
        if re.search(r"[Tt]emperature", line):
            fields = line.split()
            for val in reversed(fields):
                if val.isdigit() and 0 < int(val) < 150:
                    return f"🌡️ {val}°C,"
    return "🌡️ N/A,"

def color_link_speed(link, max_iface=None):
    speed_order = {"SATA?": 0, "SATA1": 1, "SATA3": 3, "SATA6": 6}
    link_val = speed_order.get(link, 0)
    max_val = speed_order.get(max_iface, 0)

    if max_val and link_val < max_val:
        return f"{BOLD_RED}🧩 link={link}{NC}"
    elif "SATA6" in link:
        return f"{GREEN}🧩 link={link}{NC}"
    elif "SATA3" in link:
        return f"{YELLOW}🧩 link={link}{NC}"
    return f"🧩 link={link}"

def clean_model_name(model):
    return re.sub(r"^ATA\s+", "", model).strip()

def get_smart_field(device, label):
    output = run(f"smartctl -i {device}")
    match = re.search(rf"{label}:\s*(.+)", output, re.IGNORECASE)
    return match.group(1).strip() if match else "unknown"

def get_sata_version_and_link(info_output):
    sata_cap = re.search(r"SATA Version is:\s*.*?,\s*([0-9.]+ Gb/s)", info_output)
    current_link = re.search(r"current:\s*([0-9.]+ Gb/s)", info_output)
    max_speed = sata_cap.group(1) if sata_cap else "unknown"
    link_speed = current_link.group(1) if current_link else max_speed
    iface = "SATA6" if "6.0" in max_speed else "SATA3" if "3.0" in max_speed else "SATA?"
    link = "SATA6" if "6.0" in link_speed else "SATA3" if "3.0" in link_speed else "SATA?"
    return iface, link

def process_sata_disks():
    print(f"{BLUE}🧮 Scanning SATA disks...{NC}")
    for disk in sorted(os.listdir("/sys/block")):
        if not disk.startswith("sd"):
            continue
        device = f"/dev/{disk}"
        devpath = f"/sys/block/{disk}/device"
        controller = get_storage_controller(devpath)
        model = clean_model_name(run(f"cat /sys/block/{disk}/device/model"))
        size = run(f"lsblk -dn -o SIZE {device}")
        serial = get_smart_field(device, "Serial Number")
        firmware = get_smart_field(device, "Firmware Version")
        smart_status_line = run(f"smartctl -H {device}")
        health_match = re.search(r"(PASSED|OK|FAILED)", smart_status_line, re.IGNORECASE)
        smart_health = format_smart_health(health_match.group(1).upper() if health_match else "")
        temperature = get_drive_temperature(device)
        info = run(f"smartctl -i {device}")
        iface, link = get_sata_version_and_link(info)
        link_display = color_link_speed(link, iface)

        controller_disks[controller].append(
            f"{GREEN}💾 {device}{NC}  ({model}, {size}, {iface}, {link_display}, "
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
            model = clean_model_name(model.group(1).strip()) if model else "unknown"
            serial = serial.group(1).strip() if serial else "unknown"
            firmware = firmware.group(1).strip() if firmware else "unknown"
            size = run(f"lsblk -dn -o SIZE {nvdev}")
            smart_log = run(f"nvme smart-log {nvdev}")
            crit_warn = re.search(r"critical_warning\s*:\s*(\d+)", smart_log)
            health = format_smart_health("OK" if crit_warn and crit_warn.group(1) == "0" else "FAILED")
            temperature = get_drive_temperature(nvdev)
            width = run(f"cat /sys/class/nvme/{entry[:-2]}/device/current_link_width")
            speed = run(f"cat /sys/class/nvme/{entry[:-2]}/device/current_link_speed")
            link = f"PCIe {speed} x{width}".strip()
            link_display = color_link_speed(link)

            controller_disks[controller].append(
                f"{GREEN}💾 {nvdev}{NC}  {model}, {size}, NVMe, {link_display}, "
                f"{health} {temperature} 🔢 SN: {serial}, 🔧 FW: {firmware}"
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
    install_if_missing()
    check_dependencies()
    process_sata_disks()
    process_nvme_disks()
    print_output()

if __name__ == "__main__":
    main()
