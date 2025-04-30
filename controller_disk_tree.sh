#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "Please run this script as root."
    exit 1
fi

echo "=============================="
echo " Disk-to-Controller Tree (with Link Speed + Protocol)"
echo "=============================="
echo ""

declare -A CONTROLLER_DISKS

for disk in /sys/block/sd*; do
    diskname=$(basename "$disk")
    devpath="$disk/device"
    device="/dev/$diskname"

    # Resolve PCI address
    pciaddr=$(realpath "$devpath" | grep -oP '([0-9a-f]{4}:)?[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' | head -1)
    if [[ -n "$pciaddr" ]]; then
        controller=$(lspci -v -s "$pciaddr" | head -1)
        [[ -z "$controller" ]] && controller="Unknown Controller at $pciaddr"
    else
        controller="Unknown Controller"
    fi

    # Get model/vendor/size
    model=$(cat "$disk/device/model" 2>/dev/null)
    vendor=$(cat "$disk/device/vendor" 2>/dev/null)
    size=$(lsblk -dn -o SIZE "$device")

    # Get protocol + link speed from smartctl
    if command -v smartctl >/dev/null; then
        smartinfo=$(smartctl -i "$device" 2>/dev/null)
        protocol=$(echo "$smartinfo" | grep -E "Transport protocol|SATA Version" | head -1 | sed 's/^[ \t]*//')
        linkspeed=$(echo "$smartinfo" | grep -oP 'current:\s*\K[^)]+' | head -1)
        [[ -z "$linkspeed" ]] && linkspeed="unknown"
    else
        protocol="(no smartctl)"
        linkspeed="unknown"
    fi

    disk_info="$device  ($vendor $model, $size, $protocol, link=$linkspeed)"
    CONTROLLER_DISKS["$controller"]+="$disk_info"$'\n'
done

# Display grouped output
for ctrl in "${!CONTROLLER_DISKS[@]}"; do
    echo "$ctrl"
    printf "${CONTROLLER_DISKS[$ctrl]}" | while read -r line; do
        [[ -n $line ]] && echo "  └── $line"
    done
    echo ""
done
