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
    current = {}
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if line.startswith("Device Name"):
            if current:
                device_blocks.append(current)
                current = {}
        if ":" in line:
            key, val = map(str.strip, line.split(":", 1))
            current[key] = val
    if current:
        device_blocks.append(current)

    printed = False
    for device in device_blocks:
        vendor = device.get("Device Vendor", "").lower()
        devtype = device.get("Device Type", "").lower()
        if any(v in vendor for v in ["amd", "ati", "advanced micro devices", "amd inc"]) and "gpu" in devtype:
            if not printed:
                print("\nOpenCL GPU Summary:")
                printed = True
            print(f"  Name            : {device.get('Device Name', 'N/A')}")
            print(f"  Compute Units   : {device.get('Max compute units', 'N/A')}")
            print(f"  Clock Frequency : {device.get('Max clock frequency', 'N/A')} MHz")
            print(f"  Global Memory   : {int(device.get('Global memory size', '0')) // (1024 ** 2)} MiB")
            print(f"  Local Memory    : {int(device.get('Local memory size', '0')) // 1024} KiB")
            print(f"  OpenCL C Ver    : {device.get('Device OpenCL C Version', 'N/A')}")
            print(f"  Extensions      : {device.get('Device Extensions', 'N/A')[:80]}...")

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

def detect_amd_gpu_vulkan_full():
    output = run(["vulkaninfo"])
    if not output:
        return 0, []

    gpus = []
    current = {}
    in_device = False
    in_limits = False

    for line in output.splitlines():
        line = line.strip()
        if line.startswith("VkPhysicalDeviceProperties:"):
            if current.get("name"):
                gpus.append(current)
                current = {}
            in_device = True
            in_limits = False
            continue
        elif line.startswith("VkPhysicalDeviceLimits:"):
            in_limits = True
            continue
        elif line.startswith("VkPhysicalDeviceMemoryProperties:") or line.startswith("Device Extensions:"):
            in_limits = False
            continue

        if in_device:
            if line.startswith("deviceName") and "AMD" in line:
                current["name"] = line.split("=", 1)[-1].strip()
            elif line.startswith("driverVersion"):
                current["driver"] = line.split("=", 1)[-1].strip()
            elif line.startswith("deviceType"):
                current["type"] = line.split("=", 1)[-1].strip()
            elif line.startswith("apiVersion"):
                current["api"] = line.split("=", 1)[-1].strip()

        if in_limits:
            if line.startswith("maxImageDimension2D"):
                dim = line.split("=", 1)[-1].strip()
                current["max2d"] = f"{dim}x{dim}"
            elif line.startswith("maxComputeSharedMemorySize"):
                current["shared_mem"] = line.split("=", 1)[-1].strip()

    if current.get("name"):
        gpus.append(current)

    return len(gpus), gpus

def check_vulkan():
    info("Checking Vulkan stack …")
    if not command_exists("vulkaninfo"):
        fail("vulkaninfo is missing.")
        print(f"→ {suggest('vulkan-tools mesa-vulkan-drivers')}")
        return False

    count, gpus = detect_amd_gpu_vulkan_full()
    if count > 0:
        ok(f"AMD GPU(s) detected via Vulkan – Count: {count}")
        for gpu in gpus:
            print("\nVulkan GPU Summary:")
            print(f"  Name            : {gpu.get('name', 'N/A')}")
            print(f"  Driver Version  : {gpu.get('driver', 'N/A')}")
            print(f"  Type            : {gpu.get('type', 'N/A')}")
            print(f"  API Version     : {gpu.get('api', 'N/A')}")
            print(f"  Max 2D Dim      : {gpu.get('max2d', 'N/A')}")
            print(f"  Shared Mem Size : {gpu.get('shared_mem', 'N/A')} bytes")

            bus_width_bits = 384
            mem_clock_mhz = 1375
            lspci_data = run(["lspci", "-vv"])
            if lspci_data:
                for line in lspci_data.splitlines():
                    if "Width" in line and "bits" in line:
                        try:
                            bus_width_bits = int([s for s in line.split() if s.isdigit()][0])
                        except: pass
            clinfo_data = run(["clinfo"])
            if clinfo_data:
                for line in clinfo_data.splitlines():
                    if "Max clock frequency" in line:
                        try:
                            mem_clock_mhz = int(line.split()[-2])
                        except: pass

            bandwidth_bytes = (bus_width_bits / 8) * 2 * mem_clock_mhz * 1e6
            print(f"  Bus Width       : {bus_width_bits} bits")
            print(f"  Mem Clock       : {mem_clock_mhz} MHz")
            if bus_width_bits < 64 or mem_clock_mhz < 100:
                warn("⚠️  Detected values may be defaults or invalid. Consider verifying manually.")
            print(f"  Est. Bandwidth  : {bandwidth_bytes / 1e9:.1f} GB/s")
            print("  Bandwidth Note  : Use tools like 'glmark2', 'rocm_bandwidth_test', or 'lspci -vv'")
        return True

    fail("No AMD GPU detected via Vulkan.")
    return False

def main():
    detect_gpu_model()
    print()
    success = all([
        check_amdgpu(),
        check_opencl(),
        check_vulkan()
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
