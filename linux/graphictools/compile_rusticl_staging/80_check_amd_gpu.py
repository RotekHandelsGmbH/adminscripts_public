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

def ok(msg): print(f"{GREEN}✅ {msg}{NC}")
def fail(msg): print(f"{RED}❌ {msg}{NC}")
def info(msg): print(f"{BLUE}[INFO]{NC}  {msg}")
def warn(msg): print(f"{YELL}[WARN]{NC}  {msg}")

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
    for line in text.splitlines():
        line = line.strip()
        if "Platform Name" in line:
            parts = line.split(":", 1) if ":" in line else line.split(None, 2)
            if len(parts) > 1:
                platforms.add(parts[-1].strip())
        if "Device Name" in line:
            if current_device:
                devices.append(current_device)
                current_device = {}
        if ":" in line:
            key, val = map(str.strip, line.split(":", 1))
        elif re.search(r" {2,}", line):
            parts = re.split(r" {2,}", line)
            if len(parts) >= 2:
                key, val = parts[0], parts[1]
            else:
                continue
        else:
            continue
        current_device[key] = val
    if current_device:
        devices.append(current_device)
    amd_devices = [d for d in devices if
                   "Device Vendor" in d and "Device Type" in d and
                   "gpu" in d["Device Type"].lower() and
                   re.search(r"amd|advanced micro devices", d["Device Vendor"], re.I)]
    return platforms, amd_devices

def summarize_opencl(d):
    print("\n📌 OpenCL Device Summary:")
    print(f"  Device Name                 : {d.get('Device Name')}")
    print(f"  Device Type                 : {d.get('Device Type')}")
    print(f"  Max Compute Units           : {d.get('Max compute units')}")
    print(f"  Max Clock Frequency         : {d.get('Max clock frequency')}")
    print(f"  Global Memory Size          : {d.get('Global memory size')} bytes")
    print(f"  Max Memory Allocation       : {d.get('Max memory allocation')} bytes")
    print(f"  Local Memory Size           : {d.get('Local memory size')} bytes")
    print(f"  Max Constant Buffer Size    : {d.get('Max constant buffer size')} bytes")
    print(f"  Max Work Group Size         : {d.get('Max work group size')}")
    print(f"  Preferred WG Size Multiple  : {d.get('Preferred work group size multiple (device)')}")
    print(f"  Max Work Item Sizes         : {d.get('Max work item sizes')}")
    print(f"  OpenCL C Version            : {d.get('Device OpenCL C Version')}")
    print(f"  IL Version                  : {d.get('IL version')}")

def check_opencl():
    info("Checking OpenCL runtime …")
    if not command_exists("clinfo"):
        fail("clinfo is not installed.")
        print(f"→ {suggest('clinfo')}")
        return False, None

    clinfo_out = run(["clinfo"])
    if not clinfo_out:
        fail("Failed to run clinfo.")
        return False, None

    platforms, gpus = parse_opencl_devices(clinfo_out)
    info(f"Found OpenCL platform(s): {', '.join(sorted(platforms)) or 'none'}")

    if gpus:
        ok(f"AMD GPU(s) detected as OpenCL device(s) – Count: {len(gpus)}")
        summarize_opencl(gpus[0])
        # Fallback memory estimate
        raw = gpus[0].get("Global memory size", "")
        if raw.isdigit():
            return True, f"{int(raw) // 1024 ** 2} MiB"
        return True, None

    if any("rusticl" in p.lower() for p in platforms):
        warn("Rusticl platform detected, but no GPU available – possible limitations.")
    else:
        fail("No AMD GPU found in OpenCL device list.")
    return False, None

def parse_vulkan_devices(text, fallback_mem=None):
    devices = []
    current_device = {}
    mem_heaps = []
    in_heap = False

    for line in text.splitlines():
        line = line.strip()
        if "VkPhysicalDeviceProperties:" in line:
            if current_device:
                devices.append(current_device)
                current_device = {}
            mem_heaps = []
        if "=" in line:
            key, val = map(str.strip, line.split("=", 1))
            if key in [
                "deviceName", "driverVersion", "apiVersion", "deviceType",
                "maxComputeWorkGroupInvocations", "maxComputeSharedMemorySize"
            ]:
                current_device[key] = val
        if "heapFlags = DEVICE_LOCAL_BIT" in line:
            in_heap = True
        elif in_heap and "size =" in line:
            match = re.search(r"size = (\d+)", line)
            if match:
                mem_heaps.append(int(match.group(1)))
            in_heap = False

    if current_device:
        if mem_heaps:
            current_device["Total Device Local Memory"] = f"{sum(mem_heaps) // 1024 ** 2} MiB"
        elif fallback_mem:
            current_device["Total Device Local Memory"] = fallback_mem
        else:
            current_device["Total Device Local Memory"] = "N/A"
        devices.append(current_device)

    return [d for d in devices if "deviceName" in d and "amd" in d["deviceName"].lower()]

def summarize_vulkan(d):
    print("\n📌 Vulkan Device Summary:")
    print(f"  Device Name                 : {d.get('deviceName')}")
    print(f"  Driver Version              : {d.get('driverVersion')}")
    print(f"  Device Type                 : {d.get('deviceType')}")
    print(f"  Vulkan API Version          : {d.get('apiVersion')}")
    print(f"  maxComputeWorkGroupInvocations : {d.get('maxComputeWorkGroupInvocations')}")
    print(f"  maxComputeSharedMemorySize     : {d.get('maxComputeSharedMemorySize')}")

def check_vulkan(fallback_mem=None):
    info("Checking Vulkan stack …")
    if not command_exists("vulkaninfo"):
        fail("vulkaninfo not found.")
        print(f"→ {suggest('vulkan-tools')}")
        return False

    vulkan_out = run(["vulkaninfo"])
    if not vulkan_out:
        fail("vulkaninfo execution failed.")
        return False

    devices = parse_vulkan_devices(vulkan_out, fallback_mem)
    if devices:
        ok(f"AMD GPU(s) detected via Vulkan – Count: {len(devices)}")
        summarize_vulkan(devices[0])
        return True

    fail("No AMD GPU device detected through Vulkan.")
    return False

def main():
    print()
    check_amdgpu()
    print()
    opencl_ok, fallback_mem = check_opencl()
    print()
    vulkan_ok = check_vulkan(fallback_mem)
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
