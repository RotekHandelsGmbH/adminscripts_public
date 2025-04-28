#!/usr/bin/env python3
"""
check_amd_gpu.py – Checks AMDGPU Kernel Driver, OpenCL, and Vulkan Support
Copyright (c) 2025
"""
import re
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
# Helper Routines
def run(cmd: list[str]) -> str | None:
    """Runs a command and returns stdout as a string, or None if an error occurs."""
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
# 1)  AMDGPU Driver
def check_amdgpu() -> bool:
    info("Checking AMDGPU kernel driver …")
    lspci = run(["lspci", "-k"])
    if lspci is None:
        fail("lspci not available.")
        return False

    gpu_cnt = len(re.findall(r"Kernel driver in use:\s*amdgpu", lspci, re.I))
    if gpu_cnt:
        ok(f"AMDGPU driver used by {gpu_cnt} GPU(s).")
    else:
        fail("No GPU is using AMDGPU (maybe using radeon/proprietary?).")
        return False

    if run(["lsmod"]) and re.search(r"^\s*amdgpu", run(["lsmod"]) or "", re.M):
        info("amdgpu module is loaded.")
    else:
        info("amdgpu not found in lsmod ⇒ probably built-in to kernel (OK).")
    return True

# --------------------------------------------------------------------------- #
# 2)  OpenCL Runtime (clinfo)
def count_amd_gpus_clinfo(clinfo_out: str) -> int:
    """
    Counts device blocks in clinfo output where
      • Device Vendor = AMD/Advanced Micro Devices  and
      • Device Type   = GPU
    occur.
    """
    count = 0
    v = g = False
    for raw in clinfo_out.splitlines():
        line = raw.lstrip()
        if line.startswith("Device Name"):
            v = g = False
        elif line.startswith("Device Vendor") and \
             re.search(r"AMD|Advanced Micro Devices", line, re.I):
            v = True
        elif line.startswith("Device Type") and "GPU" in line:
            g = True
        elif line.startswith("Max compute units") and v and g:
            count += 1
            v = g = False
    return count

def check_opencl() -> bool:
    info("Checking OpenCL runtime …")
    if not command_exists("clinfo"):
        fail("clinfo is missing.")
        print(f"→ {suggest('clinfo mesa-opencl-icd')}")
        return False

    icd_files = list(Path("/etc/OpenCL/vendors").glob("*.icd"))
    if icd_files:
        info(f"Found OpenCL ICDs: {', '.join(f.name for f in icd_files)}")
    else:
        warn("No OpenCL ICD files found!")

    clinfo_out = run(["clinfo"])
    if clinfo_out is None:
        fail("Failed to execute clinfo.")
        return False

    platforms = re.findall(r"Platform Name\s+:\s+(.*)", clinfo_out)
    info(f"Found OpenCL platform(s): {', '.join(platforms) or 'none'}")

    gpus = count_amd_gpus_clinfo(clinfo_out)
    if gpus > 0:
        ok(f"AMD GPU(s) detected as OpenCL device(s) – Count: {gpus}")
        used_impls = [f.name.lower() for f in icd_files]
        if any("rusticl" in impl for impl in used_impls):
            warn("Rusticl OpenCL detected – limited functionality (software stack without full GPGPU acceleration).")
            print("→ For full features (e.g., GPGPU, ML, PyOpenCL) use ROCm or AMDGPU-Pro.")
        elif any("clover" in impl for impl in used_impls):
            warn("Clover OpenCL detected – outdated and limited usability.")
            print("→ For full features (e.g., GPGPU, ML, PyOpenCL) use ROCm or AMDGPU-Pro.")
        return True

    if "rusticl" in ''.join(platforms).lower():
        warn("Rusticl platform detected, but no GPU available – possible limitations.")
    else:
        fail("No AMD GPU found in OpenCL device list.")

    print(f"→ {suggest('rocm-opencl-runtime')}")
    return False

# --------------------------------------------------------------------------- #
# 3)  Vulkan Stack
def check_vulkan() -> bool:
    info("Checking Vulkan stack …")
    if not command_exists("vulkaninfo"):
        fail("vulkaninfo is missing.")
        print(f"→ {suggest('vulkan-tools mesa-vulkan-drivers')}")
        return False

    summary = run(["vulkaninfo", "--summary"])
    if summary and re.search(r"GPU id .* AMD", summary):
        driver = re.search(r"Driver Name\s*:\s*(.*)", summary)
        ok(f"AMD GPU detected via Vulkan  [Driver: {driver.group(1).strip() if driver else 'unknown'}]")
        return True

    # Fallback: full scan
    full_output = run(["vulkaninfo"])
    if full_output and re.search(r"deviceName.*AMD", full_output, re.I):
        ok("AMD GPU detected via Vulkan (Fallback through full scan).")
        return True

    fail("No AMD GPU device detected through Vulkan ICD.")
    print(f"→ {suggest('mesa-vulkan-drivers')}")
    return False

# --------------------------------------------------------------------------- #
def main() -> None:
    success = all((
        check_amdgpu(),
        check_opencl(),
        check_vulkan(),
    ))
    print()
    if success:
        ok("All checks passed – system ready. 🎉")
        sys.exit(0)
    fail("At least one check failed – see above.")
    sys.exit(1)

# --------------------------------------------------------------------------- #
if __name__ == "__main__":
    main()
