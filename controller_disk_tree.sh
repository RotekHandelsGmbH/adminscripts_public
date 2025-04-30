#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "Please run this script as root."
    exit 1
fi

echo "=============================="
echo " Disk-to-Controller Tree (Enhanced Detection)"
echo "=============================="
echo ""

declare -A CONTROLLER_DISKS

# Helper: resolve deepest real storage controller, skipping bridges
get_storage_controller() {
    local devpath="$1"
    for addr in $(realpath "$devpath" | grep -oP '([0-9a-f]{4}:)?[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' | tac); do
        ctrl=$(lspci -s "$addr")
        if echo "$ctrl" | grep -iqE 'sata|raid|sas|storage controller'; then
            echo "$ctrl"
            return
        fi
    done
    # fallback to first match
    local first=$(realpath "$devpath" | grep -oP '([0-9a-f]{4}:)?[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' | head -1)
    echo "Unknown Controller at $first"
}

for disk in /sys/block/sd*; do
    diskname=$(basename "$disk")
    devpath="$disk/device"
    device="/dev/$diskname"

    # Get controller info (deepest actual storage controller)
    controller=$(get_storage_controller "$devpath")

    # Basic info
    model=$(cat "$disk/device/model" 2>/dev/null)
    vendor=$(cat "$disk/device/vendor" 2>/dev/null)
    size=$(lsblk -dn -o SIZE "$device")

    # smartctl info
    if command -v smartctl >/dev/null; then
        smartinfo=$(smartctl -i "$device" 2>/dev/null)
        protocol=$(echo "$smartinfo" | grep -E "Transport protocol|SATA Version" | head -1 | sed 's/^[ \t]*//')
        linkspeed=$(echo "$smartinfo" | grep -oP 'current:\s*\K[^)]+' | head -1)
    else
        protocol="(no smartctl)"
        linkspeed=""
    fi

    # If smartctl failed to get link speed, try sysfs fallback
    if [[ -z "$linkspeed" || "$linkspeed" == "0.0 Gb/s" ]]; then
        # Try via /sys (only for SATA, not SAS)
        linkdir=$(readlink -f "$devpath" | grep -o '/ata[0-9]*/link[0-9]*')
        if [[ -n "$linkdir" && -e "/sys/class${linkdir}/sata_spd" ]]; then
            spd=$(cat "/sys/class${linkdir}/sata_spd" 2>/dev/null)
            [[ -n "$spd" ]] && linkspeed="$spd"
        fi
        [[ -z "$linkspeed" ]] && linkspeed="unknown"
    fi

    disk_info="$device  ($vendor $model, $size, $protocol, link=$linkspeed)"
    CONTROLLER_DISKS["$controller"]+="$disk_info"$'\n'
done

# Output grouped by controller
for ctrl in "${!CONTROLLER_DISKS[@]}"; do
    echo "$ctrl"
    printf "${CONTROLLER_DISKS[$ctrl]}" | while read -r line; do
        [[ -n "$line" ]] && echo "  └── $line"
    done
    echo ""
done
