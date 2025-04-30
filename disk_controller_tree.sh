#!/bin/bash
set -e

# Display Header
print_header() {
    echo -e "
╔════════════════════════════════════════════════════════════════════╗
║ 🧩  Disk-to-Controller Tree Visualizer                              ║
║ 👤  Author : bitranox                                               ║
║ 🏛️  License: MIT                                                    ║
║ 💾  Shows disks grouped by controller with model, size, interface,  ║
║     serial, and link speed                                         ║
╚════════════════════════════════════════════════════════════════════╝
"
}

# Color Setup
setup_colors() {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    BOLD_GREEN='\033[1;32m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
}

# Install missing required packages
check_dependencies() {
    REQUIRED_PKGS=(smartmontools nvme-cli jq)
    MISSING=()

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
}

# Extract storage controller info
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

# Format SMART health status
format_smart_health() {
    local status="$1"
    if [[ "$status" =~ ^(PASSED|OK|0)$ ]]; then
        echo "❤️ SMART: ✅"
    elif [[ -z "$status" ]]; then
        echo "❤️ SMART: ❓"
    else
        echo -e "${RED}❤️ SMART: ⚠️${NC}"
    fi
}

# Get drive temperature
get_drive_temperature() {
    local device="$1"
    local type="$2"
    local temp=""

    if [[ "$type" == "sata" ]]; then
        temp=$(smartctl -A "$device" 2>/dev/null | awk '/[Tt]emp/ && NF >= 10 {print $10; exit}')
    elif [[ "$type" == "nvme" ]]; then
        if command -v jq >/dev/null; then
            temp=$(nvme smart-log "$device" --json 2>/dev/null | jq -r '.temperature.sensors[0]' 2>/dev/null)
        fi
        if [[ -z "$temp" || "$temp" == "null" ]]; then
            temp=$(nvme smart-log "$device" 2>/dev/null | awk '/temperature/ && $2 ~ /^[0-9]+$/ {print $2; exit}')
        fi
        if [[ "$temp" =~ ^[0-9]+$ && "$temp" -gt 100 ]]; then
            temp=$(echo "$temp - 273.15" | bc)
            temp=${temp%.*}
        fi
    fi

    if [[ "$temp" =~ ^[0-9]+$ ]]; then
        echo "🌡️ ${temp}°C"
    else
        echo "🌡️ N/A"
    fi
}

# Color output based on link speed
color_link_speed() {
    local link="$1"
    if [[ "$link" =~ ^(12|16|32|8)\.0 ]]; then
        echo -e "${BOLD_GREEN}🧩 link=$link${NC}"
    elif [[ "$link" == "6.0 Gb/s" || "$link" =~ 6\.0 ]]; then
        echo -e "${GREEN}🧩 link=$link${NC}"
    elif [[ "$link" == "3.0 Gb/s" || "$link" =~ 3\.0 ]]; then
        echo -e "${YELLOW}🧩 link=$link${NC}"
    else
        echo "🧩 link=$link"
    fi
}

# Process SATA/SAS drives
process_sata_disks() {
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

        smart_health_raw=$(smartctl -H "$device" | grep -iE 'SMART.*(result|assessment)' | awk -F: '{print $2}' | xargs)
        smart_health=$(format_smart_health "$smart_health_raw")
        temperature=$(get_drive_temperature "$device" "sata")

        protocol=$(smartctl -i "$device" | grep -E "Transport protocol|SATA Version" | sed -n 's/.*SATA Version is:[[:space:]]*\([^ ]*\).*/\1/p')
        linkspeed=$(smartctl -i "$device" | grep -oP 'current:\s*\K[^)]+' | head -1)
        [[ -z "$linkspeed" ]] && linkspeed=$(smartctl -i "$device" | grep -oP 'SATA.*,[[:space:]]*\K[0-9.]+ Gb/s' | head -1)

        serial=${serial:-unknown}
        firmware=${firmware:-unknown}
        protocol=${protocol:-unknown}
        linkspeed=${linkspeed:-unknown}

        linkspeed_display=$(color_link_speed "$linkspeed")
        disk_info="${GREEN}💾 $device${NC}  ($vendor $model, $size, $protocol, $linkspeed_display, $smart_health, $temperature, 🔢 SN: $serial, 🔧 FW: $firmware"
        CONTROLLER_DISKS["$controller"]+="$disk_info"$'\n'
    done
}

# Process NVMe drives
process_nvme_disks() {
    for nvdev in /dev/nvme*n1; do
        [[ -b "$nvdev" ]] || continue
        sysdev="/sys/block/$(basename "$nvdev")/device"
        controller=$(get_storage_controller "$sysdev")

        idctrl=$(nvme id-ctrl -H "$nvdev" 2>/dev/null)
        [[ -z "$idctrl" ]] && echo -e "${RED}⚠️  Failed to read NVMe info from $nvdev — skipping.${NC}" && continue

        model=$(echo "$idctrl" | grep -i "mn" | head -1 | awk -F: '{print $2}' | xargs)
        vendorid=$(echo "$idctrl" | grep -i "vid" | head -1 | awk -F: '{print $2}' | xargs)
        serial=$(echo "$idctrl" | grep -i "sn" | head -1 | awk -F: '{print $2}' | xargs)
        firmware=$(echo "$idctrl" | grep -i "fr" | head -1 | awk -F: '{print $2}' | xargs)
        size=$(lsblk -dn -o SIZE "$nvdev")

        smart_health_val=$(nvme smart-log "$nvdev" | grep -i 'overall' | awk -F: '{print $2}' | xargs)
        smart_health=$(format_smart_health "$smart_health_val")
        temperature=$(get_drive_temperature "$nvdev" "nvme")

        width=$(cat "/sys/class/nvme/$(basename "$nvdev" | sed 's/n1$//')/device/current_link_width" 2>/dev/null || echo "")
        speed=$(cat "/sys/class/nvme/$(basename "$nvdev" | sed 's/n1$//')/device/current_link_speed" 2>/dev/null || echo "")

        [[ -z "$width" || -z "$speed" ]] && {
            width=$(echo "$idctrl" | grep -i "PCIe Link Width" | awk -F: '{print $2}' | xargs)
            speed=$(echo "$idctrl" | grep -i "PCIe Link Speed" | awk -F: '{print $2}' | xargs)
        }

        link="PCIe ${speed:-unknown} x${width:-unknown}"
        link_display=$(color_link_speed "$link")

        disk_info="${GREEN}💾 $nvdev${NC}  (0x$vendorid $model, $size, NVMe, $link_display, $smart_health, $temperature, 🔢 SN: ${serial:-unknown}, 🔧 FW: ${firmware:-unknown}"
        CONTROLLER_DISKS["$controller"]+="$disk_info"$'\n'
    done
}

# Print final results
print_output() {
    echo -e "${BLUE}📤 Preparing output...${NC}"
    echo -e "${CYAN}=============================="
    echo -e " Disk-to-Controller Tree (SATA/SAS/NVMe + Serial + Link Speed)"
    echo -e "==============================${NC}\n"

    for ctrl in "${!CONTROLLER_DISKS[@]}"; do
        echo -e "${CYAN}🎯 $ctrl${NC}"
        printf "${CONTROLLER_DISKS[$ctrl]}" | while read -r line; do
            [[ -n "$line" ]] && echo -e "  └── $line"
        done
        echo ""
    done
}

### Main Execution ###
declare -A CONTROLLER_DISKS

print_header
setup_colors
check_dependencies
process_sata_disks
process_nvme_disks
print_output
