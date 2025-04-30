#!/bin/bash

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Please run this script as root."
    exit 1
fi

echo "=============================="
echo " Disk-to-Controller Tree"
echo "=============================="
echo ""

# Read PCI devices and map to scsi_host
declare -A HOST_CONTROLLER_MAP
while IFS= read -r line; do
    # Example: 00:1f.2 SATA controller: Intel Corporation ...
    pci_id=$(echo "$line" | awk '{print $1}')
    class=$(echo "$line" | cut -d ' ' -f3-)
    for host_path in /sys/class/scsi_host/host*; do
        host=$(basename "$host_path")
        if [[ -e "$host_path/device" ]]; then
            pci_link=$(readlink -f "$host_path/device" | grep -oE '[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' || true)
            if [[ $pci_link == "$pci_id" ]]; then
                HOST_CONTROLLER_MAP["$host"]="$class"
            fi
        fi
    done
done < <(lspci | grep -i -E 'storage controller|SATA controller|RAID|SAS|NVMe|Virtio')

# Iterate through all SCSI hosts and their devices
for host in /sys/class/scsi_host/host*; do
    host_name=$(basename "$host")
    controller="${HOST_CONTROLLER_MAP[$host_name]:-(Unknown Controller)}"
    echo "$host_name [$controller]"

    # Find devices connected to this host
    devices=$(find /sys/class/scsi_device/ -name "${host_name}:*" -printf "%f\n" 2>/dev/null)

    if [[ -z "$devices" ]]; then
        echo "  └── (no disks connected)"
        continue
    fi

    for dev in $devices; do
        dev_path="/sys/class/scsi_device/$dev/device/block"
        if [[ -d $dev_path ]]; then
            disk=$(ls "$dev_path" 2>/dev/null)
            if [[ -n $disk ]]; then
                model=$(cat /sys/class/block/$disk/device/model 2>/dev/null)
                vendor=$(cat /sys/class/block/$disk/device/vendor 2>/dev/null)
                size=$(lsblk -dn -o SIZE /dev/$disk 2>/dev/null)
                echo "  └── $disk  ($vendor $model, $size)"
            fi
        fi
    done
done
