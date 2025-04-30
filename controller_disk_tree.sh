#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "Please run this script as root."
    exit 1
fi

echo "=============================="
echo " Disk-to-Controller Tree (with Link Speed + Serial Numbers)"
echo "=============================="
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

# SATA/SAS drives (sdX)
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

    if command -v smartctl >/dev/null; then
        smartinfo=$(smartctl -i "$device" 2>/dev/null)
        protocol=$(echo "$smartinfo" | grep -E "Transport protocol|SATA Version" | head -1 | sed 's/^[ \t]*//')
        linkspeed=$(echo "$smartinfo" | grep -oP 'current:\s*\K[^)]+' | head -1)
        [[ -z "$linkspeed" ]] && linkspeed=$(echo "$smartinfo" | grep -oP 'SATA.*,\s*\K[0-9.]+ Gb/s' | head -1)
        serial=$(echo "$smartinfo" | grep -i 'Serial Number' | awk -F: '{print $2}' | xargs)
    fi

    if [[ -z "$linkspeed" ]]; then
        linkdir=$(readlink -f "$devpath" | grep -o '/ata[0-9]*/link[0-9]*')
        if [[ -n "$linkdir" && -e "/sys/class${linkdir}/sata_spd" ]]; then
            spd=$(cat "/sys/class${linkdir}/sata_spd" 2>/dev/null)
            [[ -n "$spd" ]] && linkspeed="$spd"
        fi
    fi

    [[ -z "$linkspeed" ]] && linkspeed="unknown"
    [[ -z "$serial" ]] && serial="unknown"

    disk_info="$device  ($vendor $model, $size, $protocol, link=$linkspeed, SN: $serial)"
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

    if command -v nvme >/dev/null; then
        idctrl=$(nvme id-ctrl -H "$nvdev" 2>/dev/null)
        model=$(echo "$idctrl" | grep -i "mn" | head -1 | awk -F: '{print $2}' | xargs)
        vendor=$(echo "$idctrl" | grep -i "vid" | head -1 | awk -F: '{print $2}' | xargs)
        width=$(echo "$idctrl" | grep -i "PCIe Link Width" | awk -F: '{print $2}' | xargs)
        speed=$(echo "$idctrl" | grep -i "PCIe Link Speed" | awk -F: '{print $2}' | xargs)
        serial=$(echo "$idctrl" | grep -i "sn" | head -1 | awk -F: '{print $2}' | xargs)
        link="PCIe $speed x$width"
    fi

    size=$(lsblk -dn -o SIZE "$nvdev")
    disk_info="$nvdev  ($vendor $model, $size, NVMe, link=$link, SN: $serial)"
    CONTROLLER_DISKS["$controller"]+="$disk_info"$'\n'
done

# Print result
for ctrl in "${!CONTROLLER_DISKS[@]}"; do
    echo "$ctrl"
    printf "${CONTROLLER_DISKS[$ctrl]}" | while read -r line; do
        [[ -n "$line" ]] && echo "  └── $line"
    done
    echo ""
done
