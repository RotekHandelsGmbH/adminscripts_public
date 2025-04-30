#!/bin/bash

set -e

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

echo -e "${CYAN}=============================="
echo -e " Disk-to-Controller Tree (SATA/SAS/NVMe + Serial + Link Speed)"
echo -e "==============================${NC}"
echo ""

declare -A CONTROLLER_DISKS

get_storage_controller() {
    local devpath="$1"
    for addr in $(realpath "$devpath" | grep -oP '([0-9a-f]{4}:)?[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' | tac); do
        ctrl=$(lspci -s "$addr")
        if echo "$ctrl" | grep -iqE 'sata|raid|sas|storage controller|non-volatile'; then
            echo "$ctrl"
            return
        fi
    done
    local first=$(realpath "$devpath" | grep -oP '([0-9a-f]{4}:)?[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' | head -1)
    echo "Unknown Controller at $first"
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
    serial="unknown"
    protocol=""
    linkspeed=""

    smartinfo=$(smartctl -i "$device" 2>/dev/null)
    protocol=$(echo "$smartinfo" | grep -E "Transport protocol|SATA Version" | head -1 | sed 's/^[ \t]*//')
    linkspeed=$(echo "$smartinfo" | grep -oP 'current:\s*\K[^)]+' | head -1)
    [[ -z "$linkspeed" ]] && linkspeed=$(echo "$smartinfo" | grep -oP 'SATA.*,\s*\K[0-9.]+ Gb/s' | head -1)
    serial=$(echo "$smartinfo" | grep -i 'Serial Number' | awk -F: '{print $2}' | xargs)

    # Sysfs fallback
    if [[ -z "$linkspeed" ]]; then
        linkdir=$(readlink -f "$devpath" | grep -o '/ata[0-9]*/link[0-9]*')
        if [[ -n "$linkdir" && -e "/sys/class${linkdir}/sata_spd" ]]; then
            spd=$(cat "/sys/class${linkdir}/sata_spd" 2>/dev/null)
            [[ -n "$spd" ]] && linkspeed="$spd"
        fi
    fi

    [[ -z "$linkspeed" ]] && linkspeed="unknown"
    [[ -z "$serial" ]] && serial="unknown"

    # Link speed color
    if [[ "$linkspeed" =~ ^(12|16|32|8)\.0 ]]; then
        linkspeed_display="${BOLD_GREEN}🧩 link=$linkspeed${NC}"
    elif [[ "$linkspeed" == "6.0 Gb/s" ]]; then
        linkspeed_display="${GREEN}🧩 link=$linkspeed${NC}"
    elif [[ "$linkspeed" == "3.0 Gb/s" ]]; then
        linkspeed_display="${YELLOW}🧩 link=$linkspeed${NC}"
    else
        linkspeed_display="🧩 link=$linkspeed"
    fi

    disk_info="${GREEN}💾 $device${NC}  ($vendor $model, $size, $protocol, $linkspeed_display, 🔢 SN: $serial)"
    CONTROLLER_DISKS["$controller"]+="$disk_info"$'\n'
done

# NVMe drives
for nvdev in /dev/nvme*n1; do
    [[ -b "$nvdev" ]] || continue
    nvbasename=$(basename "$nvdev")
    sysdev="/sys/block/$nvbasename/device"

    controller=$(get_storage_controller "$sysdev")

    model="unknown"
    vendor="unknown"
    link="unknown"
    serial="unknown"

    idctrl=$(nvme id-ctrl -H "$nvdev" 2>/dev/null)
    model=$(echo "$idctrl" | grep -i "mn" | head -1 | awk -F: '{print $2}' | xargs)
    vendor=$(echo "$idctrl" | grep -i "vid" | head -1 | awk -F: '{print $2}' | xargs)
    width=$(echo "$idctrl" | grep -i "PCIe Link Width" | awk -F: '{print $2}' | xargs)
    speed=$(echo "$idctrl" | grep -i "PCIe Link Speed" | awk -F: '{print $2}' | xargs)
    serial=$(echo "$idctrl" | grep -i "sn" | head -1 | awk -F: '{print $2}' | xargs)
    link="PCIe $speed x$width"
    size=$(lsblk -dn -o SIZE "$nvdev")

    if [[ "$link" =~ (16\.0|32\.0|8\.0|12\.0) ]]; then
        link_display="${BOLD_GREEN}🧩 link=$link${NC}"
    elif [[ "$link" =~ 6\.0 ]]; then
        link_display="${GREEN}🧩 link=$link${NC}"
    elif [[ "$link" =~ 3\.0 ]]; then
        link_display="${YELLOW}🧩 link=$link${NC}"
    else
        link_display="🧩 link=$link"
    fi

    disk_info="${GREEN}💾 $nvdev${NC}  ($vendor $model, $size, NVMe, $link_display, 🔢 SN: $serial)"
    CONTROLLER_DISKS["$controller"]+="$disk_info"$'\n'
done

# Output
for ctrl in "${!CONTROLLER_DISKS[@]}"; do
    echo -e "${CYAN}🎯 $ctrl${NC}"
    printf "${CONTROLLER_DISKS[$ctrl]}" | while read -r line; do
        [[ -n "$line" ]] && echo -e "  └── $line"
    done
    echo ""
done
