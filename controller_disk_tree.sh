#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "Please run this script as root."
    exit 1
fi

echo "=============================="
echo " Disk-to-Controller Tree (via sysfs)"
echo "=============================="
echo ""

declare -A CONTROLLER_DISKS

for disk in /sys/block/sd*; do
    diskname=$(basename "$disk")
    devpath="$disk/device"

    # Follow parent chain to find PCI address
    pciaddr=$(realpath "$devpath" | grep -oP '([0-9a-f]{4}:)?[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' | head -1)

    if [[ -n "$pciaddr" ]]; then
        controller=$(lspci -s "$pciaddr")
        [[ -z "$controller" ]] && controller="Unknown Controller at $pciaddr"
    else
        controller="Unknown Controller"
    fi

    # Disk info
    model=$(cat "$disk/device/model" 2>/dev/null)
    vendor=$(cat "$disk/device/vendor" 2>/dev/null)
    size=$(lsblk -dn -o SIZE "/dev/$diskname" 2>/dev/null)

    CONTROLLER_DISKS["$controller"]+="/dev/$diskname  ($vendor $model, $size)\n"
done

# Display results
if [[ ${#CONTROLLER_DISKS[@]} -eq 0 ]]; then
    echo "No disks found."
    exit 0
fi

for ctrl in "${!CONTROLLER_DISKS[@]}"; do
    echo "$ctrl"
    printf "${CONTROLLER_DISKS[$ctrl]}" | while read -r line; do
        [[ -n "$line" ]] && echo "  └── $line"
    done
    echo ""
done
