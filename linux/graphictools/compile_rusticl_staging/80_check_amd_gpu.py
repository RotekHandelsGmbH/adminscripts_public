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
def get_amdgpu_gpu_count(lspci_out: str) -> int:
    return sum("Kernel driver in use: amdgpu" in line for line in lspci_out.splitlines())

def is_amdgpu_module_loaded() -> bool:
    lsmod_out = run(["lsmod"]) or ""
    return any(line.startswith("amdgpu") for line in lsmod_out.splitlines())

def check_amdgpu() -> bool:
    info("Checking AMDGPU kernel driver …")
    lspci = run(["lspci", "-k"])
    if not lspci:
        fail("lspci not available.")
        return False

    count = get_amdgpu_gpu_count(lspci)
    if count:
        ok(f"AMDGPU driver used by {count} GPU(s).")
    else:
        fail("No GPU is using AMDGPU (maybe using radeon/proprietary?).")
        return False

    if is_amdgpu_module_loaded():
        info("amdgpu module is loaded.")
    else:
        info("amdgpu not found in lsmod ⇒ probably built-in to kernel (OK).")
    return True

# --------------------------------------------------------------------------- #
def detect_rocm_icds() -> list[str]:
    return [f.name for f in Path("/etc/OpenCL/vendors").glob("*.icd") if "rocm" in f.name.lower() or "amd" in f.name.lower()]

def detect_rocm_tools() -> list[str]:
    return [cmd for cmd in ("rocminfo", "hipinfo") if command_exists(cmd)]

def check_rocm() -> bool:
    info("Checking for ROCm support …")
    icds = detect_rocm_icds()
    tools = detect_rocm_tools()

    if icds or tools:
        ok(f"ROCm environment detected. {'Tools: ' + ', '.join(tools) if tools else ''}")
        return True

    warn("ROCm not found.")
    print(f"→ {suggest('rocm-opencl-runtime')} or {suggest('rocminfo')}")
    return False

# --------------------------------------------------------------------------- #
def count_amd_gpus_clinfo(clinfo_out: str) -> int:
    count = 0
    v = g = False
    for raw in clinfo_out.splitlines():
        line = raw.lstrip()
        if line.startswith("Device Name"):
            v = g = False
        elif line.startswith("Device Vendor") and ("AMD" in line or "Advanced Micro Devices" in line):
            v = True
        elif line.startswith("Device Type") and "GPU" in line:
            g = True
        elif line.startswith("Max compute units") and v and g:
            count += 1
            v = g = False
    return count

def parse_opencl_platforms(clinfo_out: str) -> list[str]:
    platforms = set()
    for line in clinfo_out.splitlines():
        if "Platform Name" in line:
            parts = line.strip().split(":", 1)
            name = parts[1].strip() if len(parts) > 1 else parts[0].replace("Platform Name", "").strip()
            if name:
                platforms.add(name)
    return sorted(platforms)

def detect_icd_files() -> list[str]:
    return [f.name for f in Path("/etc/OpenCL/vendors").glob("*.icd")]

def warn_about_icd(icd_list: list[str]):
    lower = [i.lower() for i in icd_list]
    if any("rusticl" in i for i in lower):
        warn("Rusticl OpenCL detected – limited functionality.")
        print("→ For full features (e.g., GPGPU, ML, PyOpenCL) use ROCm or AMDGPU-Pro.")
    elif any("clover" in i for i in lower):
        warn("Clover OpenCL detected – outdated backend.")
        print("→ Use ROCm or AMDGPU-Pro.")

def check_opencl() -> bool:
    info("Checking OpenCL runtime …")
    if not command_exists("clinfo"):
        fail("clinfo is missing.")
        print(f"→ {suggest('clinfo mesa-opencl-icd')}")
        return False

    icds = detect_icd_files()
    if icds:
        info(f"Found OpenCL ICDs: {', '.join(icds)}")
    else:
        warn("No OpenCL ICD files found!")

    clinfo_out = run(["clinfo"])
    if clinfo_out is None:
        fail("Failed to execute clinfo.")
        return False

    platforms = parse_opencl_platforms(clinfo_out)
    info(f"Found OpenCL platform(s): {', '.join(platforms) or 'none'}")

    devices = clinfo_out.split("\n\n")
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
                print(f"  OpenCL C Ver    : {summary.get('Device OpenCL C Version')}")

    gpu_count = count_amd_gpus_clinfo(clinfo_out)
    if gpu_count > 0:
        ok(f"AMD GPU(s) detected as OpenCL device(s) – Count: {gpu_count}")
        warn_about_icd(icds)
        return True

    if any("rusticl" in p.lower() for p in platforms):
        warn("Rusticl platform detected, but no GPU available – possible limitations.")
    else:
        fail("No AMD GPU found in OpenCL device list.")

    print(f"→ {suggest('rocm-opencl-runtime')}")
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
            current["name"] = line.split("=", 1)[1].strip()
        elif line.startswith("driverVersion") and current:
            current["driver"] = line.split("=", 1)[1].strip()
        elif line.startswith("deviceUUID") and current:
            current["uuid"] = line.split("=", 1)[1].strip()
        elif line.startswith("deviceType") and current:
            current["type"] = line.split("=", 1)[1].strip()
        elif line.startswith("apiVersion") and current:
            current["api"] = line.split("=", 1)[1].strip()
        elif line.startswith("maxImageDimension2D") and current:
            current["max2d"] = line.split("=", 1)[1].strip()
            gpus.append(current)
            current = {}
    return len(gpus), gpus

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
    check_rocm()
    print()

    if success:
        ok("All main checks passed – system ready. \U0001f389")
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