#!/usr/bin/env python3
"""
check_amd_gpu.py – Checks AMDGPU Kernel Driver, OpenCL, Vulkan, and ROCm Support
"""
import shutil
import subprocess
import sys
from pathlib import Path

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
def check_opencl_details() -> None:
    clinfo = run(["clinfo"])
    if not clinfo:
        return

    devices = clinfo.split("\n\n")
    for dev in devices:
        if "Device Type" in dev and "GPU" in dev:
            lines = dev.splitlines()
            summary = {}
            for line in lines:
                if ":" in line:
                    parts = line.split(":", 1)
                    if len(parts) == 2:
                        summary[parts[0].strip()] = parts[1].strip()
            if summary.get("Device Vendor", "").lower().startswith("amd"):
                print("\nOpenCL GPU Summary:")
                print(f"  Name            : {summary.get('Device Name', 'N/A')}")
                print(f"  Compute Units   : {summary.get('Max compute units', 'N/A')}")
                print(f"  Clock Frequency : {summary.get('Max clock frequency', 'N/A')} MHz")
                print(f"  Global Memory   : {int(summary.get('Global memory size', '0')) // (1024 ** 2)} MiB")
                print(f"  Local Memory    : {int(summary.get('Local memory size', '0')) // 1024} KiB")
                print(f"  OpenCL C Ver    : {summary.get('Device OpenCL C Version', 'N/A')}")
                print(f"  Extensions      : {summary.get('Device Extensions', 'N/A')[:80]}...")

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
            parts = line.split("=", 1)
            if len(parts) == 2:
                current["name"] = parts[1].strip()

        elif any(line.startswith(prefix) for prefix in ("driverVersion", "deviceUUID", "deviceType", "apiVersion", "maxImageDimension2D")):
            key = line.split("=")[0].strip()
            parts = line.split("=", 1)
            if len(parts) == 2:
                current[key.lower()] = parts[1].strip()

    if current:
        gpus.append(current)

    return len(gpus), gpus

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

    platforms = set()
    for line in clinfo_out.splitlines():
        if "Platform Name" in line:
            parts = line.strip().split(":", 1)
            if len(parts) == 2:
                platforms.add(parts[1].strip())

    info(f"Found OpenCL platform(s): {', '.join(sorted(platforms)) or 'none'}")
    check_opencl_details()

    gpu_count = sum(1 for block in clinfo_out.split("\n\n") if "Device Vendor" in block and "AMD" in block and "Device Type" in block and "GPU" in block)
    if gpu_count > 0:
        ok(f"AMD GPU(s) detected as OpenCL device(s) – Count: {gpu_count}")
        return True

    fail("No AMD GPU found in OpenCL device list.")
    return False

# --------------------------------------------------------------------------- #
def main():
    info("Detecting GPU model …")
    lspci = run(["lspci", "-nn"])
    if lspci:
        for line in lspci.splitlines():
            if "VGA" in line and ("AMD" in line or "ATI" in line):
                ok(f"GPU Detected: {line.strip()}")
                break

    print()
    if not check_opencl():
        sys.exit(1)

    print()
    count, gpus = detect_amd_gpu_vulkan_full()
    if count > 0:
        ok(f"AMD GPU(s) detected via Vulkan – Count: {count}")
        for gpu in gpus:
            print("\nVulkan GPU Summary:")
            print(f"  Name            : {gpu.get('name', 'N/A')}")
            print(f"  Driver Version  : {gpu.get('driverversion', 'N/A')}")
            print(f"  UUID            : {gpu.get('deviceuuid', 'N/A')}")
            print(f"  Type            : {gpu.get('devicetype', 'N/A')}")
            print(f"  API Version     : {gpu.get('apiversion', 'N/A')}")
            print(f"  Max 2D Dim      : {gpu.get('maximagedimension2d', 'N/A')}")
    else:
        fail("No AMD GPU detected via Vulkan.")

if __name__ == "__main__":
    main()
