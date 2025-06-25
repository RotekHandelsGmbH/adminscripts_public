#!/bin/bash
set -e

declare -A CONTROLLER_DISKS

main() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}❌ This script must be run as root.${NC}"; exit 1; }
    print_header
    setup_colors
    check_dependencies
    process_sata_disks
    process_nvme_disks
    print_output
}

# ── Display Functions ────────────────────────────────────────────────────────────────

print_header() {
    echo -e "
╔═══════════════════════════════════════════════════════════════════════════════════════╗
║ 🧩  Disk-to-Controller Tree Visualizer                                                 ║
║ 👤  Author : bitranox                                                                  ║
║ 🏛️  License: MIT                                                                       ║
║ 💾  Shows disks grouped by controller with model, size, interface, link speed,         ║
║     SMART status, drive temperature, serial number, and firmware revision             ║
╚═══════════════════════════════════════════════════════════════════════════════════════╝
"
}

setup_colors() {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    BOLD_GREEN='\033[1;32m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
}

print_output() {
    echo -e "${BLUE}📤 Preparing output...${NC}"
    for ctrl in "${!CONTROLLER_DISKS[@]}"; do
        echo -e "${CYAN}🎯 $ctrl${NC}"
        printf "${CONTROLLER_DISKS[$ctrl]}" | while read -r line; do
            [[ -n "$line" ]] && echo -e "  └── $line"
        done
        echo ""
    done
}

# ── Dependency Handling ───────────────────────────────────────────────────────────────

check_dependencies() {
    echo -e "${BLUE}🔍 Checking dependencies...${NC}"
    local REQUIRED_PKGS=(smartmontools nvme-cli)
    local MISSING=()

    for pkg in "${REQUIRED_PKGS[@]}"; do
        dpkg -s "$pkg" >/dev/null 2>&1 || MISSING+=("$pkg")
    done

    if [[ ${#MISSING[@]} -gt 0 ]]; then
        echo -e "${YELLOW}🔧 Installing missing packages: ${MISSING[*]}${NC}"
        apt-get update -qq
        apt-get install -y "${MISSING[@]}" >/dev/null
        echo -e "${GREEN}🎉 Required packages installed successfully.${NC}"
    fi
}

# ── Utility Functions ────────────────────────────────────────────────────────────────

get_storage_controller() {
    local devpath="$1"
    for addr in $(realpath "$devpath" | grep -oP '([0-9a-f]{4}:)?[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' | tac); do
        local ctrl=$(lspci -s "$addr")
        if echo "$ctrl" | grep -iqE 'sata|raid|sas|storage controller|non-volatile'; then
            echo "$addr ${ctrl#*:}"
            return
        fi
    done
    echo "Unknown Controller"
}

format_smart_health() {
    local status="$1"
    if [[ "$status" =~ ^(PASSED|OK|0)$ ]]; then
        echo "❤️ SMART: ✅ ,"
    elif [[ -z "$status" ]]; then
        echo "❤️ SMART: ❓ ,"
    else
        echo -e "${RED}❤️ SMART: ⚠️ ,${NC}"
    fi
}

get_drive_temperature() {
    local device="$1"
    local type="$2"
    local temp=""

    if [[ "$type" == "sata" ]]; then
        temp=$(smartctl -A "$device" 2>/dev/null | awk '/[Tt]emp/ && NF >= 10 {print $10; exit}')
    elif [[ "$type" == "nvme" ]]; then
        temp=$(nvme smart-log "$device" 2>/dev/null | grep -m1 -i "^temperature" | sed -E 's/[^0-9]*([0-9]+)°C.*/\1/')
    fi

    [[ "$temp" =~ ^[0-9]+$ ]] && echo "🌡️ ${temp}°C," || echo "🌡️ N/A,"
}

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

# ── Disk Processing ───────────────────────────────────────────────────────────────────

process_sata_disks() {
    echo -e "${BLUE}🧮 Scanning SATA disks...${NC}"
    for disk in /sys/block/sd*; do
        local device="/dev/$(basename "$disk")"
        local devpath="$disk/device"
        local controller=$(get_storage_controller "$devpath")

        local model=$(cat "$disk/device/model" 2>/dev/null)
        local vendor=$(cat "$disk/device/vendor" 2>/dev/null)
        local size=$(lsblk -dn -o SIZE "$device")
        local serial=$(get_smart_field "$device" "Serial Number")
        local firmware=$(get_smart_field "$device" "Firmware Version")
        local smart_health=$(format_smart_health "$(smartctl -H "$device" | grep -iE 'SMART.*(result|assessment)' | awk -F: '{print $2}' | xargs)")
        local temperature=$(get_drive_temperature "$device" "sata")

        local protocol=$(smartctl -i "$device" | grep -E "Transport protocol|SATA Version" | sed -n 's/.*SATA Version is:[[:space:]]*\([^ ]*\).*/\1/p')
        local linkspeed=$(smartctl -i "$device" | grep -oP 'current:\s*\K[^)]+' | head -1)
        [[ -z "$linkspeed" ]] && linkspeed=$(smartctl -i "$device" | grep -oP 'SATA.*,[[:space:]]*\K[0-9.]+ Gb/s' | head -1)

        local linkspeed_display=$(color_link_speed "${linkspeed:-unknown}")

        CONTROLLER_DISKS["$controller"]+="${GREEN}💾 $device${NC}  ($vendor $model, $size, ${protocol:-unknown}, $linkspeed_display, $smart_health $temperature 🔢 SN: ${serial:-unknown}, 🔧 FW: ${firmware:-unknown}"$'\n'
    done
}

process_nvme_disks() {
    echo -e "${BLUE}⚡ Scanning NVMe disks...${NC}"
    for nvdev in /dev/nvme*n1; do
        [[ -b "$nvdev" ]] || continue
        local sysdev="/sys/block/$(basename "$nvdev")/device"
        local controller=$(get_storage_controller "$sysdev")

        local idctrl=$(nvme id-ctrl -H "$nvdev" 2>/dev/null)
        [[ -z "$idctrl" ]] && echo -e "${RED}⚠️  Failed to read NVMe info from $nvdev — skipping.${NC}" && continue

        local model=$(echo "$idctrl" | grep -i "mn" | head -1 | awk -F: '{print $2}' | xargs)
        local vendorid=$(echo "$idctrl" | grep -i "vid" | head -1 | awk -F: '{print $2}' | xargs)
        local serial=$(echo "$idctrl" | grep -i "sn" | head -1 | awk -F: '{print $2}' | xargs)
        local firmware=$(echo "$idctrl" | grep -i "fr" | head -1 | awk -F: '{print $2}' | xargs)
        local size=$(lsblk -dn -o SIZE "$nvdev")

        local critical_warning=$(nvme smart-log "$nvdev" 2>/dev/null | awk -F: '/^critical_warning/ {gsub(/[^0-9a-fx]/,"",$2); print $2}')
        local smart_health=$(format_smart_health "$critical_warning")
        local temperature=$(get_drive_temperature "$nvdev" "nvme")

        local width=$(cat "/sys/class/nvme/$(basename "$nvdev" | sed 's/n1$//')/device/current_link_width" 2>/dev/null || echo "")
        local speed=$(cat "/sys/class/nvme/$(basename "$nvdev" | sed 's/n1$//')/device/current_link_speed" 2>/dev/null || echo "")

        [[ -z "$width" || -z "$speed" ]] && {
            width=$(echo "$idctrl" | grep -i "PCIe Link Width" | awk -F: '{print $2}' | xargs)
            speed=$(echo "$idctrl" | grep -i "PCIe Link Speed" | awk -F: '{print $2}' | xargs)
        }

        local link="PCIe ${speed:-unknown} PCIe x${width:-unknown}"
        local link_display=$(color_link_speed "$link")

        CONTROLLER_DISKS["$controller"]+="${GREEN}💾 $nvdev${NC}  (0x0x$vendorid $model, $size, NVMe, $link_display, $smart_health $temperature 🔢 SN: ${serial:-unknown}, 🔧 FW: ${firmware:-unknown}"$'\n'
    done
}

get_smart_field() {
    local device="$1"
    local label="$2"
    smartctl -i "$device" | grep -i "$label" | awk -F: '{print $2}' | xargs
}

# ── Run the script ────────────────────────────────────────────────────────────────────

main
