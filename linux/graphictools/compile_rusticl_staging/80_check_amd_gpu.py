#!/usr/bin/env python3
"""
check_amd_gpu.py – Detects AMDGPU Kernel Driver, OpenCL (Rusticl/ROCm), Vulkan, and provides summaries.
"""

import subprocess
import shutil
import sys
import re
from pathlib import Path

GREEN = "\033[1;32m"
RED   = "\033[1;31m"
BLUE  = "\033[1;34m"
YELL  = "\033[1;33m"
NC    = "\033[0m"

def ok(msg):    print(f"{GREEN}✅ {msg}{NC}")
def fail(msg):  print(f"{RED}❌ {msg}{NC}")
def info(msg):  print(f"{BLUE}[INFO]{NC}  {msg}")
def warn(msg):  print(f"{YELL}[WARN]{NC}  {msg}")

def run(cmd):
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL, text=True)
    except Exception:
        return None

def command_exists(cmd):
    return shutil.which(cmd) is not None

def suggest(pkg):
    if command_exists("apt"): return f"sudo apt install {pkg}"
    if command_exists("dnf"): return f"sudo dnf install {pkg}"
    if command_exists("pacman"): return f"sudo pacman -S {pkg}"
    return f"<use your package manager>: {pkg}"

def check_amdgpu():
    info("Checking AMDGPU kernel driver …")
    lspci = run(["lspci", "-k"])
    if not lspci:
        fail("Cannot detect GPUs (lspci failed).")
        return False

    count = sum("Kernel driver in use: amdgpu" in line for line in lspci.splitlines())
    if count:
        ok(f"AMDGPU driver used by {count} GPU(s).")
    else:
        fail("No GPU is using AMDGPU.")
        return False

    lsmod = run(["lsmod"]) or ""
    if "amdgpu" in lsmod:
        info("amdgpu module is loaded.")
    else:
        info("amdgpu not listed – may be built-in to kernel.")
    return True

def parse_opencl_devices(text):
    platforms = set()
    devices = []
    current_device = {}
    in_device = False

    for line in text.splitlines():
        line = line.strip()

        if "Platform Name" in line:
            parts = line.split(":", 1) if ":" in line else line.split(None, 2)
            if len(parts) > 1:
                platforms.add(parts[-1].strip())

        if "Device Name" in line:
            if current_device:
                if "Device Vendor" in current_device and "Device Type" in current_device:
                    if "gpu" in current_device["Device Type"].lower() and re.search(r"amd|advanced micro devices", current_device["Device Vendor"], re.I):
                        devices.append(current_device)
                current_device = {}
            in_device = True

        if in_device and (":" in line or re.search(r" {2,}", line)):
            try:
                if ":" in line:
                    key, val = map(str.strip, line.split(":", 1))
                else:
                    parts = re.split(r" {2,}", line)
                    if len(parts) >= 2:
                        key, val = parts[0].strip(), parts[1].strip()
                    else:
                        continue
                current_device[key] = val
            except ValueError:
                continue

    if current_device and "Device Vendor" in current_device and "Device Type" in current_device:
        if "gpu" in current_device["Device Type"].lower() and re.search(r"amd|advanced micro devices", current_device["Device Vendor"], re.I):
            devices.append(current_device)

    return platforms, devices

def check_opencl():
    info("Checking OpenCL runtime …")
    if not command_exists("clinfo"):
        fail("clinfo is not installed.")
        print(f"→ {suggest('clinfo')}")
        return False

    clinfo_out = run(["clinfo"])
    if not clinfo_out:
        fail("Failed to run clinfo.")
        return False

    platforms, gpus = parse_opencl_devices(clinfo_out)
    info(f"Found OpenCL platform(s): {', '.join(sorted(platforms)) or 'none'}")

    if gpus:
        ok(f"AMD GPU(s) detected as OpenCL device(s) – Count: {len(gpus)}")
        for idx, d in enumerate(gpus, 1):
            print(f"\nOpenCL GPU #{idx}:")
            for key, val in d.items():
                print(f"  {key:<30}: {val}")
        return True

    if any("rusticl" in p.lower() for p in platforms):
        warn("Rusticl platform detected, but no GPU available – possible limitations.")
    else:
        fail("No AMD GPU found in OpenCL device list.")
    return False

def parse_vulkan_devices(text):
    devices = []
    device = {}
    for line in text.splitlines():
        line = line.strip()
        if "VkPhysicalDeviceProperties:" in line:
            if device:
                devices.append(device)
                device = {}
        if "=" in line:
            key, val = map(str.strip, line.split("=", 1))
            if key in ["deviceName", "driverVersion", "apiVersion", "deviceType"]:
                device[key] = val
    if device:
        devices.append(device)
    return [d for d in devices if "deviceName" in d and "amd" in d["deviceName"].lower()]

def check_vulkan():
    info("Checking Vulkan stack …")
    if not command_exists("vulkaninfo"):
        fail("vulkaninfo not found.")
        print(f"→ {suggest('vulkan-tools')}")
        return False

    vulkan_out = run(["vulkaninfo"])
    if not vulkan_out:
        fail("vulkaninfo execution failed.")
        return False

    devices = parse_vulkan_devices(vulkan_out)
    if devices:
        ok(f"AMD GPU(s) detected via Vulkan – Count: {len(devices)}")
        for idx, d in enumerate(devices, 1):
            print(f"\nVulkan GPU #{idx}:")
            for key in ["deviceName", "driverVersion", "deviceType", "apiVersion"]:
                if key in d:
                    print(f"  {key:<20}: {d[key]}")
        return True

    fail("No AMD GPU device detected through Vulkan.")
    return False

def main():
    print()
    check_amdgpu()
    print()
    opencl_ok = check_opencl()
    print()
    vulkan_ok = check_vulkan()
    print()
    if opencl_ok and vulkan_ok:
        ok("All main checks passed – system ready. 🎉")
    else:
        fail("At least one check failed – see above.")
    print()
    info("For detailed inspection, try:")
    print("   lspci | grep -i vga")
    print("   clinfo")
    print("   vulkaninfo")
    print("   rocminfo")
    sys.exit(0 if opencl_ok and vulkan_ok else 1)

if __name__ == "__main__":
    main()
