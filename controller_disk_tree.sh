#!/bin/bash

# Requires: root, lsblk, lspci, readlink

if [[ $EUID -ne 0 ]]; then
    echo "Please run this script as root."
    exit 1
fi

echo "=============================="
echo " Disk-to-Controller Tree (Accurate)"
echo "=============================="
echo ""

declare -A CONTROLLER_DISKS
declare -A CONTROLLER_INFO

# Iterate over all scsi devices (e.g., 2:0:0:0)
for scsi in /sys/class/scsi_device/*; do
    # Block device path
    blockdev_path="$scsi/device/block"
    [[ ! -d $blockdev_path ]] && continue

    # Extract disk name (e.g., sda)
    disk=$(ls "$blockdev_path" 2>/dev/null)
    [[ -z $disk ]] && continue

    # Resolve PCI parent of the disk
    pci_path=$(readlink -f "$scsi/device" | grep -oP '/pci[^/]+' | tail -1)
    pci_path_full=$(basename "$pci_path")

    # Lookup controller info from lspci
    controller_line=$(lspci -s "$pci_path_full")
    [[ -z $controller_line ]] && controller_line="Unknown Controller at $pci_path_full"

    # Collect disk info
    model=$(cat /sys/class/block/$disk/device/model 2>/dev/null)
    vendor=$(cat /sys/class/block/$disk/device/vendor 2>/dev/null)
    size=$(lsblk -dn -o SIZE "/dev/$disk" 2>/dev/null)
    disk_info="/dev/$disk  ($vendor $model, $size)"

    # Append to controller group
    CONTROLLER_DISKS["$controller_line"]+="$disk_info"$'\n'
    CONTROLLER_INFO["$controller_line"]=1
done

# Output the results
if [[ ${#CONTROLLER_DISKS[@]} -eq 0 ]]; then
    echo "No disks found."
    exit 0
fi

for ctrl in "${!CONTROLLER_DISKS[@]}"; do
    echo "$ctrl"
    while read -r diskline; do
        [[ -n $diskline ]] && echo "  └── $diskline"
    done <<< "${CONTROLLER_DISKS[$ctrl]}"
    echo ""
done
