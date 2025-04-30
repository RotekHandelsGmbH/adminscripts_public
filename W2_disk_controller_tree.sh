#!/bin/bash

set -e

# Display program header
echo -e "
╔════════════════════════════════════════════════════════════════════╗
║ 🧩  Disk-to-Controller Tree Visualizer                              ║
║ 👤  Author : bitranox                                               ║
║ 🏛️  License: MIT                                                    ║
║ 💾  Shows disks grouped by controller with model, size, interface,  ║
║     serial, and link speed                                         ║
╚════════════════════════════════════════════════════════════════════╝
"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD_GREEN='\033[1;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

REQUIRED_PKGS=(smartmontools nvme-cli)
MISSING=()

# Check for required packages
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        MISSING+=("$pkg")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "${YELLOW}🔧 Installing missing packages: ${MISSING[*]}${NC}"
    apt-get update -qq
    apt-get install -y "${MISSING[@]}" >/dev/null
    echo -e "${GREEN}🎉 Required packages installed successfully.${NC}"
fi

declare -A CONTROLLER_DISKS



get_storage_controller() {
    local devpath="$1"
    for addr in $(realpath "$devpath" | grep -oP '([0-9a-f]{4}:)?[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' | tac); do
        ctrl=$(lspci -s "$addr")
        if echo "$ctrl" | grep -iqE 'sata|raid|sas|storage controller|non-volatile'; then
            echo "$addr ${ctrl#*:}"
            return
        fi
    done
    echo "Unknown Controller"
}


# SATA/SAS drives
for disk in /sys/block/sd*; do
    diskname=$(basename "$disk")
    devpath="$disk/device"
    device="/dev/$diskname"

    controller=$(get_storage_controller "$devpath")
    model=$(cat "$disk/device/model" 2>/dev/null)
    vendor=$(cat "$disk/device/vendor" 2>/dev/null)
    size=$(lsblk -dn -o SIZE "$device")
    serial=$(smartctl -i "$device" | grep -i 'Serial Number' | awk -F: '{print $2}' | xargs)
    firmware=$(smartctl -i "$device" | grep -i 'Firmware Version' | awk -F: '{print $2}' | xargs)
    smart_health=$(smartctl -H "$device" 2>/dev/null | grep -i 'SMART overall-health self-assessment' | awk -F: '{print $2}' | xargs)
    if [[ "$smart_health" =~ ^(PASSED|OK)$ ]]; then
        smart_health="${GREEN}✔️ $smart_health${NC}"
    elif [[ -z "$smart_health" ]]; then
        smart_health="unknown"
    else
        smart_health="${RED}⚠️ $smart_health${NC}"
    fi
    [[ -z "$smart_health" ]] && smart_health="unknown"    protocol=$(smartctl -i "$device" | grep -E "Transport protocol|SATA Version" | head -1 | sed 's/^.*SATA Version is:[[:space:]]*//' | sed 's/(current:.*)//' | sed 's/[[:space:]]*$//')
    linkspeed=$(smartctl -i "$device" | grep -oP 'current:\s*\K[^)]+' | head -1)
    [[ -z "$linkspeed" ]] && linkspeed=$(smartctl -i "$device" | grep -oP 'SATA.*,[[:space:]]*\K[0-9.]+ Gb/s' | head -1)

    [[ -z "$serial" ]] && serial="unknown"
    [[ -z "$firmware" ]] && firmware="unknown"
    [[ -z "$protocol" ]] && protocol="unknown"
    [[ -z "$linkspeed" ]] && linkspeed="unknown"

    if [[ "$linkspeed" =~ ^(12|16|32|8)\.0 ]]; then
        linkspeed_display="${BOLD_GREEN}🧩 link=$linkspeed${NC}"
    elif [[ "$linkspeed" == "6.0 Gb/s" ]]; then
        linkspeed_display="${GREEN}🧩 link=$linkspeed${NC}"
    elif [[ "$linkspeed" == "3.0 Gb/s" ]]; then
        linkspeed_display="${YELLOW}🧩 link=$linkspeed${NC}"
    else
        linkspeed_display="🧩 link=$linkspeed"
    fi

    disk_info="${GREEN}💾 $device${NC}  ($vendor $model, $size, $protocol, $linkspeed_display, 🔢 SN: $serial, 🔧 FW: $firmware, ❤️ SMART: $smart_health)"
    CONTROLLER_DISKS["$controller"]+="$disk_info"$'\n'
done


# NVMe drives
for nvdev in /dev/nvme*n1; do

    [[ -b "$nvdev" ]] || continue
    sysdev="/sys/block/$(basename "$nvdev")/device"
    controller=$(get_storage_controller "$sysdev")
    [[ -z "$controller" ]] && controller="Unknown Controller"


    idctrl=$(nvme id-ctrl -H "$nvdev" 2>/dev/null)
    if [[ -z "$idctrl" ]]; then
        echo -e "${RED}⚠️  Failed to read NVMe info from $nvdev — skipping.${NC}"
        continue
    fi
    model=$(echo "$idctrl" | grep -i "mn" | head -1 | awk -F: '{print $2}' | xargs)
    vendorid=$(echo "$idctrl" | grep -i "vid" | head -1 | awk -F: '{print $2}' | xargs)
    vendor="0x$vendorid"
    serial=$(echo "$idctrl" | grep -i "sn" | head -1 | awk -F: '{print $2}' | xargs)
    firmware=$(echo "$idctrl" | grep -i "fr" | head -1 | awk -F: '{print $2}' | xargs)
    smart_health=$(nvme smart-log "$nvdev" 2>/dev/null | grep -i 'overall' | awk -F: '{print $2}' | xargs)
    if [[ "$smart_health" =~ ^0$ ]]; then
        smart_health="${GREEN}✔️ OK${NC}"
    elif [[ -z "$smart_health" ]]; then
        smart_health="unknown"
    else
        smart_health="${RED}⚠️ $smart_health${NC}"
    fi
    if [[ "$smart_health" =~ ^0$ ]]; then
        smart_health="${GREEN}✔️ OK${NC}"
    elif [[ -z "$smart_health" ]]; then
        smart_health="unknown"
    else
        smart_health="${RED}⚠️ $smart_health${NC}"
    fi    size=$(lsblk -dn -o SIZE "$nvdev")
    [[ -z "$serial" ]] && serial="unknown"
    [[ -z "$firmware" ]] && firmware="unknown"
    [[ -z "$size" ]] && size="unknown"

    # Try sysfs first
    width=$(cat "/sys/class/nvme/$(basename "$nvdev" | sed 's/n1$//')/device/current_link_width" 2>/dev/null || echo "")
    speed=$(cat "/sys/class/nvme/$(basename "$nvdev" | sed 's/n1$//')/device/current_link_speed" 2>/dev/null || echo "")

    # Fallback to id-ctrl
    if [[ -z "$width" || -z "$speed" ]]; then
        width=$(echo "$idctrl" | grep -i "PCIe Link Width" | awk -F: '{print $2}' | xargs)
        speed=$(echo "$idctrl" | grep -i "PCIe Link Speed" | awk -F: '{print $2}' | xargs)
    fi

    if [[ -n "$speed" && -n "$width" ]]; then
        link="PCIe $speed x$width"
    else
        link="PCIe (unknown)"
    fi

    if [[ "$link" =~ (16\.0|32\.0|8\.0|12\.0) ]]; then
        link_display="${BOLD_GREEN}🧩 link=$link${NC}"
    elif [[ "$link" =~ 6\.0 ]]; then
        link_display="${GREEN}🧩 link=$link${NC}"
    elif [[ "$link" =~ 3\.0 ]]; then
        link_display="${YELLOW}🧩 link=$link${NC}"
    else
        link_display="🧩 link=$link"
    fi

    disk_info="${GREEN}💾 $nvdev${NC}  ($vendor $model, $size, NVMe, $link_display, 🔢 SN: $serial, 🔧 FW: $firmware, ❤️ SMART: $smart_health)"
    CONTROLLER_DISKS["$controller"]+="$disk_info"$'\n'
done

echo -e "${BLUE}📤 Preparing output...${NC}"
# Output
echo -e "${CYAN}=============================="
echo -e " Disk-to-Controller Tree (SATA/SAS/NVMe + Serial + Link Speed)"
echo -e "==============================${NC}"
echo ""

for ctrl in "${!CONTROLLER_DISKS[@]}"; do
    echo -e "${CYAN}🎯 $ctrl${NC}"
    printf "${CONTROLLER_DISKS[$ctrl]}" | while read -r line; do
        [[ -n "$line" ]] && echo -e "  └── $line"
    done
    echo ""
done
