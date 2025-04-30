#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "Please run this script as root."
    exit 1
fi

echo "=============================="
echo " Disk-to-Controller Tree (via udev)"
echo "=============================="
echo ""

declare -A CONTROLLER_DISKS

for disk in /dev/sd?; do
    # Skip if not a block device
    [[ ! -b $disk ]] && continue

    # Get PCI controller path from udevadm
    pci_id=$(udevadm info --query=path --name=$disk | grep -oP 'pci-[^/]+')
    [[ -z $pci_id ]] && pci_id="unknown"

    # Map to lspci controller name if available
    if [[ $pci_id != "unknown" ]]; then
        # Convert "pci-0000:00:1f.2" → "00:1f.2"
        short_id=$(echo $pci_id | sed 's/pci-//' | cut -d: -f2-)
        controller=$(lspci -s "$short_id")
        [[ -z $controller ]] && controller="Unknown Controller ($pci_id)"
    else
        controller="Unknown Controller"
    fi

    # Disk details
    name=$(basename "$disk")
    vendor=$(cat /sys/class/block/$name/device/vendor 2>/dev/null)
    model=$(cat /sys/class/block/$name/device/model 2>/dev/null)
    size=$(lsblk -dn -o SIZE "$disk")

    disk_info="$disk  ($vendor $model, $size)"
    CONTROLLER_DISKS["$controller"]+="$disk_info"$'\n'
done

# Display results
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

