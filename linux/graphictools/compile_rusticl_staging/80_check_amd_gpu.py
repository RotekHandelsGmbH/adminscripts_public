#!/usr/bin/env python3
"""
check_amd_gpu.py – Detects AMD GPU, OpenCL, Vulkan, and ROCm support
"""

import subprocess
import shutil
import sys
from pathlib import Path

GREEN = "\033[1;32m"
RED = "\033[1;31m"
BLUE = "\033[1;34m"
YELL = "\033[1;33m"
NC = "\033[0m"

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

def detect_gpu_model():
    info("Detecting GPU model …")
    lspci = run(["lspci", "-nn"])
    if not lspci: return
    for line in lspci.splitlines():
        if "VGA" in line and ("AMD" in line or "ATI" in line):
            ok(f"GPU Detected: {line.strip()}")
            details = run(["lspci", "-vv", "-s", line.split()[0]])
            if details:
                for l in details.splitlines():
                    if "LnkCap:" in l: print(f"  PCIe Capability : {l.strip()}")
                    if "LnkSta:" in l: print(f"  PCIe Status     : {l.strip()}")

def check_amdgpu():
    info("Checking AMDGPU kernel driver …")
    lspci = run(["lspci", "-k"]) or ""
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

def parse_clinfo(clinfo_text):
    devices = []
    current = {}
    for line in clinfo_text.splitlines():
        line = line.strip()
        if not line: continue
        if ":" in line:
            key, val = [s.strip() for s in line.split(":", 1)]
            current[key] = val
        if line.lower().startswith("max compute units"):
            if current.get("Device Type", "").lower() == "gpu" and \
               any(v in current.get("Device Vendor", "").lower() for v in ["amd", "ati", "advanced micro devices", "amd inc"]):
                devices.append(current.copy())
                current.clear()
    return devices

def check_opencl():
    info("Checking OpenCL runtime …")
    if not command_exists("clinfo"):
        fail("clinfo not found.")
        print(f"→ {suggest('clinfo mesa-opencl-icd')}")
        return False

    icds = list(Path("/etc/OpenCL/vendors").glob("*.icd"))
    if icds:
        info(f"Found OpenCL ICDs: {', '.join(f.name for f in icds)}")
    else:
        warn("No OpenCL ICD files found.")

    clinfo_out = run(["clinfo"])
    if not clinfo_out:
        fail("Failed to execute clinfo.")
        return False

    platforms = [line.split(":")[-1].strip() for line in clinfo_out.splitlines() if "Platform Name" in line]
    info(f"Found OpenCL platform(s): {', '.join(platforms) or 'none'}")

    gpus = parse_clinfo(clinfo_out)
    if gpus:
        ok(f"AMD GPU(s) detected as OpenCL device(s) – Count: {len(gpus)}")
        print("\nOpenCL GPU Summary:")
        for d in gpus:
            print(f"  Name            : {d.get('Device Name', 'N/A')}")
            print(f"  Compute Units   : {d.get('Max compute units', 'N/A')}")
            print(f"  Clock Frequency : {d.get('Max clock frequency', 'N/A')} MHz")
            print(f"  Global Memory   : {int(d.get('Global memory size', '0')) // (1024**2)} MiB")
            print(f"  Local Memory    : {int(d.get('Local memory size', '0')) // 1024} KiB")
            print(f"  OpenCL C Ver    : {d.get('Device OpenCL C Version', 'N/A')}")
        if any("rusticl" in f.name.lower() for f in icds):
            warn("Rusticl OpenCL detected – limited functionality.")
            print("→ For full features (e.g., GPGPU, ML, PyOpenCL) use ROCm or AMDGPU-Pro.")
        return True

    fail("No AMD GPU found in OpenCL device list.")
    return False

def parse_vulkan(vulkaninfo_out):
    devices = []
    device = {}
    capture = False
    for line in vulkaninfo_out.splitlines():
        line = line.strip()
        if "VkPhysicalDeviceProperties:" in line:
            if device: devices.append(device); device = {}
            capture = True
        if capture and "=" in line:
            key, val = map(str.strip, line.split("=", 1))
            if key in ["deviceName", "driverVersion", "apiVersion", "deviceType"]:
                device[key] = val
        if line.startswith("maxImageDimension2D"):
            device["max2d"] = f"{line.split('=')[-1].strip()}x{line.split('=')[-1].strip()}"
        if line.startswith("maxComputeSharedMemorySize"):
            device["shared_mem"] = line.split("=", 1)[-1].strip()
    if device: devices.append(device)
    return devices

def check_vulkan():
    info("Checking Vulkan stack …")
    if not command_exists("vulkaninfo"):
        fail("vulkaninfo not found.")
        print(f"→ {suggest('vulkan-tools mesa-vulkan-drivers')}")
        return False

    vulkan_out = run(["vulkaninfo"])
    if not vulkan_out:
        fail("vulkaninfo execution failed.")
        return False

    devices = parse_vulkan(vulkan_out)
    if not devices:
        fail("No AMD GPU device detected through Vulkan.")
        return False

    ok(f"AMD GPU(s) detected via Vulkan – Count: {len(devices)}")
    for d in devices:
        print("\nVulkan GPU Summary:")
        print(f"  Name            : {d.get('deviceName', 'N/A')}")
        print(f"  Driver Version  : {d.get('driverVersion', 'N/A')}")
        print(f"  Type            : {d.get('deviceType', 'N/A')}")
        print(f"  API Version     : {d.get('apiVersion', 'N/A')}")
        print(f"  Max 2D Dim      : {d.get('max2d', 'N/A')}")
        print(f"  Shared Mem Size : {d.get('shared_mem', 'N/A')} bytes")
    return True

def main():
    detect_gpu_model()
    print()
    results = [
        check_amdgpu(),
        check_opencl(),
        check_vulkan()
    ]
    print()
    if all(results):
        ok("All main checks passed – system ready. 🎉")
    else:
        fail("At least one check failed – see above.")
    print()
    info("For detailed inspection, use:")
    print("   lspci | grep -i vga")
    print("   clinfo")
    print("   vulkaninfo")
    print("   rocminfo")
    sys.exit(0 if all(results) else 1)

if __name__ == "__main__":
    main()
