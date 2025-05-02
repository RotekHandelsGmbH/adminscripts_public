#!/usr/bin/env python3
"""
check_amd_gpu.py – Checks AMDGPU Kernel Driver, OpenCL, Vulkan, and ROCm Support
"""
import shutil
import subprocess
import sys
from pathlib import Path
import re

# --------------------------------------------------------------------------- #
# ANSI Colors + Emojis
GREEN = "\033[1;32m"
RED   = "\033[1;31m"
BLUE  = "\033[1;34m"
YELL  = "\033[1;33m"
NC    = "\033[0m"

def ok(msg: str):    print(f"{GREEN}✅ {msg}{NC}")
def fail(msg: str):  print(f"{RED}❌ {msg}{NC}")
def info(msg: str):  print(f"{BLUE}[INFO]{NC}  {msg}")
def warn(msg: str):  print(f"{YELL}[WARN]{NC}  {msg}")

# --------------------------------------------------------------------------- #
def run(cmd: list[str]) -> str | None:
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL, text=True)
    except (OSError, subprocess.CalledProcessError):
        return None

def command_exists(cmd: str) -> bool:
    return shutil.which(cmd) is not None

def suggest(pkg: str) -> str:
    if   command_exists("apt"):    return f"sudo apt install {pkg}"
    elif command_exists("dnf"):    return f"sudo dnf install {pkg}"
    elif command_exists("pacman"): return f"sudo pacman -S {pkg}"
    return f"<use your package manager>: {pkg}"

# --------------------------------------------------------------------------- #
def detect_gpu_model() -> None:
    info("Detecting GPU model …")
    lspci = run(["lspci", "-nn"])
    if not lspci:
        warn("Could not detect GPU model (lspci failed).")
        return

    gpu_lines = [line for line in lspci.splitlines() if "VGA" in line and ("AMD" in line or "ATI" in line)]
    if gpu_lines:
        for line in gpu_lines:
            ok(f"GPU Detected: {line.strip()}")
    else:
        warn("No AMD/ATI GPU found in lspci output.")

# --------------------------------------------------------------------------- #
def check_amdgpu() -> bool:
    info("Checking AMDGPU kernel driver …")
    lspci = run(["lspci", "-k"])
    if not lspci:
        fail("lspci not available.")
        return False

    count = sum("Kernel driver in use: amdgpu" in line for line in lspci.splitlines())
    if count:
        ok(f"AMDGPU driver used by {count} GPU(s).")
    else:
        fail("No GPU is using AMDGPU (maybe using radeon/proprietary?).")
        return False

    lsmod = run(["lsmod"]) or ""
    if any(line.startswith("amdgpu") for line in lsmod.splitlines()):
        info("amdgpu module is loaded.")
    else:
        info("amdgpu not found in lsmod ⇒ probably built-in to kernel (OK).")
    return True

# --------------------------------------------------------------------------- #
def detect_rocm() -> bool:
    info("Checking for ROCm support …")
    icds = [f.name for f in Path("/etc/OpenCL/vendors").glob("*.icd") if "rocm" in f.name.lower()]
    tools = [cmd for cmd in ("rocminfo", "hipinfo") if command_exists(cmd)]

    if icds or tools:
        ok(f"ROCm environment detected. {'Tools: ' + ', '.join(tools) if tools else ''}")
        return True

    warn("ROCm not found.")
    print(f"→ {suggest('rocm-opencl-runtime')} or {suggest('rocminfo')}")
    return False

# --------------------------------------------------------------------------- #
def check_opencl_details() -> None:
    clinfo = run(["clinfo"])
    if not clinfo:
        return

    devices = clinfo.split("\n\n")
    for dev in devices:
        if "Device Type" in dev and "GPU" in dev:
            lines = dev.splitlines()
            summary = {line.split(":", 1)[0].strip(): line.split(":", 1)[1].strip() for line in lines if ":" in line}
            if "Device Vendor" in summary and "AMD" in summary["Device Vendor"]:
                print("\nOpenCL GPU Summary:")
                print(f"  Name            : {summary.get('Device Name')}")
                print(f"  Compute Units   : {summary.get('Max compute units')}")
                print(f"  Clock Frequency : {summary.get('Max clock frequency')} MHz")
                print(f"  Global Memory   : {int(summary.get('Global memory size', '0')) // (1024 ** 2)} MiB")
                print(f"  Local Memory    : {int(summary.get('Local memory size', '0')) // 1024} KiB")
                print(f"  OpenCL C Ver    : {summary.get('Device OpenCL C Version')}")
                print(f"  Extensions      : {summary.get('Device Extensions', 'N/A')[:80]}...")

# --------------------------------------------------------------------------- #
def check_opencl() -> bool:
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
    if clinfo_out is None:
        fail("Failed to execute clinfo.")
        return False

    platforms = sorted({line.split(":", 1)[1].strip()
                        for line in clinfo_out.splitlines() if "Platform Name" in line})
    info(f"Found OpenCL platform(s): {', '.join(platforms) or 'none'}")
    check_opencl_details()

    gpu_count = sum(1 for block in clinfo_out.split("\n\n")
                    if "Device Vendor" in block and "AMD" in block and "Device Type" in block and "GPU" in block)

    if gpu_count > 0:
        ok(f"AMD GPU(s) detected as OpenCL device(s) – Count: {gpu_count}")
        if any("rusticl" in x.lower() for x in icds):
            warn("Rusticl OpenCL detected – limited functionality.")
            print("→ For full features (e.g., GPGPU, ML, PyOpenCL) use ROCm or AMDGPU-Pro.")
        return True

    fail("No AMD GPU found in OpenCL device list.")
    return False

# --------------------------------------------------------------------------- #
def detect_amd_gpu_vulkan_full() -> tuple[int, list[dict]]:
    output = run(["vulkaninfo"])
    if not output:
        return 0, []

    gpus = []
    current = {}
    for line in output.splitlines():
        line = line.strip()

        if line.startswith("deviceName") and "AMD" in line:
            if current:
                gpus.append(current)
                current = {}
            current["name"] = line.split("=", 1)[1].strip()

        elif line.startswith("driverVersion"):
            current["driver"] = line.split("=", 1)[1].strip()
        elif line.startswith("deviceUUID"):
            current["uuid"] = line.split("=", 1)[1].strip()
        elif line.startswith("deviceType"):
            current["type"] = line.split("=", 1)[1].strip()
        elif line.startswith("apiVersion"):
            current["api"] = line.split("=", 1)[1].strip()
        elif line.startswith("maxImageDimension2D"):
            current["max2d"] = line.split("=", 1)[1].strip()

    if current:
        gpus.append(current)

    return len(gpus), gpus

# --------------------------------------------------------------------------- #
def check_vulkan() -> bool:
    info("Checking Vulkan stack …")
    if not command_exists("vulkaninfo"):
        fail("vulkaninfo is missing.")
        print(f"→ {suggest('vulkan-tools mesa-vulkan-drivers')}")
        return False

    summary = run(["vulkaninfo", "--summary"])
    driver = "unknown"
    if summary:
        for line in summary.splitlines():
            if "Driver Name" in line:
                driver = line.split(":", 1)[1].strip()
                break

    gpu_count, devices = detect_amd_gpu_vulkan_full()
    if gpu_count > 0:
        ok(f"AMD GPU(s) detected via Vulkan – Count: {gpu_count}")
        for dev in devices:
            print("\nVulkan GPU Summary:")
            print(f"  Name            : {dev.get('name')}")
            print(f"  Driver Version  : {dev.get('driver')}")
            print(f"  UUID            : {dev.get('uuid')}")
            print(f"  Type            : {dev.get('type')}")
            print(f"  API Version     : {dev.get('api')}")
            print(f"  Max 2D Dim      : {dev.get('max2d')}")
        if driver != "unknown":
            info(f"Driver (from summary): {driver}")
        return True

    fail("No AMD GPU device detected through Vulkan ICD.")
    print(f"→ {suggest('mesa-vulkan-drivers')}")
    return False

# --------------------------------------------------------------------------- #
def main() -> None:
    detect_gpu_model()
    print()
    success = all((
        check_amdgpu(),
        check_opencl(),
        check_vulkan(),
    ))
    print()
    detect_rocm()
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

# --------------------------------------------------------------------------- #
if __name__ == "__main__":
    main()
