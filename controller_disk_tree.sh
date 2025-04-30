#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "Please run this script as root."
    exit 1
fi

echo "=============================="
echo " Disk-to-Controller Tree with Link Speed"
echo "=============================="
echo ""

declare -A CONTROLLER_DISKS

for disk in /sys/block/sd*; do
    diskname=$(basename "$disk")
    devpath="$disk/device"

    # PCI address resolution via sysfs path
    pciaddr=$(realpath "$devpath" | grep -oP '([0-9a-f]{4}:)?[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' | head -1)
    if [[ -n "$pciaddr" ]]; then
        controller=$(lspci -s "$pciaddr")
        [[ -z "$controller" ]] && controller="Unknown Controller at $pciaddr"
    else
        controller="Unknown Controller"
    fi

    # Basic disk info
    model=$(cat "$disk/device/model" 2>/dev/null)
    vendor=$(cat "$disk/device/vendor" 2>/dev/null)
    size=$(lsblk -dn -o SIZE "/dev/$diskname")
    transport=$(lsblk -dn -o TRAN "/dev/$diskname")

    # Try link speed (SATA)
    linkdir=$(readlink -f "$disk/device" | grep -o '/ata[0-9]*/link[0-9]*')
    if [[ -n "$linkdir" && -e "/sys/class${linkdir}/sata_spd" ]]; then
        linkspeed=$(cat /sys/class${linkdir}/sata_spd 2>/dev/null)
    else
        # Try negotiated SAS link rate
        phy=$(ls -d /sys/class/sas_phy/* 2>/dev/null | grep "$diskname" | head -1)
        if [[ -n "$phy" ]]; then
            linkspeed=$(cat "$phy/negotiated_linkrate" 2>/dev/null)
        else
            linkspeed="unknown"
        fi
    fi

    disk_info="/dev/$diskname  ($vendor $model, $size, $transport, link=$linkspeed)"
    CONTROLLER_DISKS["$controller"]+="$disk_info"$'\n'
done

# Print output
for ctrl in "${!CONTROLLER_DISKS[@]}"; do
    echo "$ctrl"
    printf "${CONTROLLER_DISKS[$ctrl]}" | while read -r line; do
        [[ -n $line ]] && echo "  └── $line"
    done
    echo ""
done
