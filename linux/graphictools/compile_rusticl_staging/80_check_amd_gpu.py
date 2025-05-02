#!/usr/bin/env python3
"""
check_amd_gpu.py – Checks AMDGPU Kernel Driver, OpenCL, Vulkan, and ROCm Support
"""

import shutil
import subprocess
import sys
from pathlib import Path

# ANSI Colors
GREEN = "\033[1;32m"
RED   = "\033[1;31m"
BLUE  = "\033[1;34m"
YELL  = "\033[1;33m"
NC    = "\033[0m"

def ok(msg):   print(f"{GREEN}✅ {msg}{NC}")
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
    if not lspci:
        warn("Could not detect GPU model (lspci failed).")
        return
    for line in lspci.splitlines():
        if "VGA" in line and ("AMD" in line or "ATI" in line):
            ok(f"GPU Detected: {line.strip()}")
            pcie_info = run(["lspci", "-vv", "-s", line.split()[0]])
            if pcie_info:
                for l in pcie_info.splitlines():
                    if "LnkCap:" in l and "Speed" in l:
                        print(f"  PCIe Capability : {l.strip()}")
                    if "LnkSta:" in l and "Speed" in l:
                        print(f"  PCIe Status     : {l.strip()}")

def check_amdgpu():
    info("Checking AMDGPU kernel driver …")
    lspci = run(["lspci", "-k"])
    if not lspci:
        fail("lspci not available.")
        return False

    count = sum("Kernel driver in use: amdgpu" in line for line in lspci.splitlines())
    if count:
        ok(f"AMDGPU driver used by {count} GPU(s).")
    else:
        fail("No GPU is using AMDGPU.")
        return False

    lsmod = run(["lsmod"]) or ""
    if any(line.startswith("amdgpu") for line in lsmod.splitlines()):
        info("amdgpu module is loaded.")
    else:
        info("amdgpu not found in lsmod ⇒ probably built-in to kernel (OK).")
    return True

def check_opencl_details(clinfo):
    lines = clinfo.splitlines()
    device_blocks = []
    current_block = []

    for line in lines:
        if line.lstrip().startswith("Device Name"):
            if current_block:
                device_blocks.append("\n".join(current_block))
                current_block = []
        if line.strip():
            current_block.append(line)
    if current_block:
        device_blocks.append("\n".join(current_block))

    printed = False
    for block in device_blocks:
        summary = {}
        for line in block.splitlines():
            if ":" in line:
                key, val = map(str.strip, line.split(":", 1))
                summary[key] = val
        vendor = summary.get("Device Vendor", "").lower()
        devtype = summary.get("Device Type", "").lower()
        if any(v in vendor for v in ["amd", "ati", "advanced micro devices", "amd inc"]) and "gpu" in devtype:
            if not printed:
                print("\nOpenCL GPU Summary:")
                printed = True
            print(f"  Name            : {summary.get('Device Name', 'N/A')}")
            print(f"  Compute Units   : {summary.get('Max compute units', 'N/A')}")
            print(f"  Clock Frequency : {summary.get('Max clock frequency', 'N/A')} MHz")
            print(f"  Global Memory   : {int(summary.get('Global memory size', '0')) // (1024 ** 2)} MiB")
            print(f"  Local Memory    : {int(summary.get('Local memory size', '0')) // 1024} KiB")
            print(f"  OpenCL C Ver    : {summary.get('Device OpenCL C Version', 'N/A')}")
            print(f"  Extensions      : {summary.get('Device Extensions', 'N/A')[:80]}...")

def check_opencl():
    info("Checking OpenCL runtime …")
    if not command_exists("clinfo"):
        fail("clinfo is missing.")
        print(f"→ {suggest('clinfo mesa-opencl-icd')}")
        return False

    icds = [f.name for f in Path("/etc/OpenCL/vendors").glob("*.icd")]
    if icds:
        info(f"Found OpenCL ICDs: {', '.join(icds)}")
    else:
        warn("No OpenCL ICD files found!")

    clinfo_out = run(["clinfo"])
    if not clinfo_out:
        fail("Failed to execute clinfo.")
        return False

    platforms = []
    for line in clinfo_out.splitlines():
        line = line.strip()
        if line.startswith("Platform Name"):
            name = line.split()[-1]
            if name:
                platforms.append(name)
    info(f"Found OpenCL platform(s): {', '.join(sorted(set(platforms))) or 'none'}")

    check_opencl_details(clinfo_out)

    gpu_count = sum(1 for block in clinfo_out.split("\n\n")
                    if "Device Vendor" in block and "AMD" in block and "Device Type" in block and "GPU" in block)
    if gpu_count > 0:
        ok(f"AMD GPU(s) detected as OpenCL device(s) – Count: {gpu_count}")
        if any("rusticl" in icd.lower() for icd in icds):
            warn("Rusticl OpenCL detected – limited functionality.")
            print("→ For full features (e.g., GPGPU, ML, PyOpenCL) use ROCm or AMDGPU-Pro.")
        return True

    fail("No AMD GPU found in OpenCL device list.")
    return False

# The Vulkan and ROCm checks would follow here — omitted for brevity
# You already have this working well.

def main():
    detect_gpu_model()
    print()
    success = all([
        check_amdgpu(),
        check_opencl(),
        # check_vulkan(),  # Uncomment if Vulkan check is present
    ])
    print()
    if success:
        ok("All main checks passed – system ready. 🎉")
    else:
        fail("At least one check failed – see above.")
    print()
    info("For detailed inspection, use:")
    print("   lspci | grep -i vga")
    print("   clinfo")
    print("   vulkaninfo")
    print("   rocminfo")
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
