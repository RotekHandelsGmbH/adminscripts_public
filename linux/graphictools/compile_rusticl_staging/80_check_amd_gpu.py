#!/usr/bin/env python3
"""
check_amd_gpu.py – Checks AMDGPU Kernel Driver, OpenCL, Vulkan, and ROCm Support
Copyright (c) 2025
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
def check_rocm() -> bool:
    info("Checking for ROCm support …")
    icds = list(Path("/etc/OpenCL/vendors").glob("*.icd"))
    rocm_icds = [f for f in icds if "rocm" in f.name.lower() or "amd" in f.name.lower()]
    tools = [cmd for cmd in ("rocminfo", "hipinfo") if command_exists(cmd)]

    if rocm_icds or tools:
        ok(f"ROCm environment detected. {'Tools: ' + ', '.join(tools) if tools else ''}")
        return True

    warn("ROCm not found.")
    print(f"→ {suggest('rocm-opencl-runtime')} or {suggest('rocminfo')}")
    return False

# --------------------------------------------------------------------------- #
def check_amdgpu() -> bool:
    info("Checking AMDGPU kernel driver …")
    lspci = run(["lspci", "-k"])
    if lspci is None:
        fail("lspci not available.")
        return False

    gpu_cnt = sum("Kernel driver in use: amdgpu" in line for line in lspci.splitlines())
    if gpu_cnt:
        ok(f"AMDGPU driver used by {gpu_cnt} GPU(s).")
    else:
        fail("No GPU is using AMDGPU (maybe using radeon/proprietary?).")
        return False

    lsmod_out = run(["lsmod"]) or ""
    if any(line.startswith("amdgpu") for line in lsmod_out.splitlines()):
        info("amdgpu module is loaded.")
    else:
        info("amdgpu not found in lsmod ⇒ probably built-in to kernel (OK).")
    return True

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

    platforms = set()
    for line in clinfo_out.splitlines():
        if "Platform Name" in line:
            parts = line.strip().split(":", 1)
            name = parts[1].strip() if len(parts) > 1 else parts[0].replace("Platform Name", "").strip()
            if name:
                platforms.add(name)
    info(f"Found OpenCL platform(s): {', '.join(sorted(platforms)) or 'none'}")

    gpus = count_amd_gpus_clinfo(clinfo_out)
    if gpus > 0:
        ok(f"AMD GPU(s) detected as OpenCL device(s) – Count: {gpus}")
        used_impls = [f.name.lower() for f in icd_files]
        if any("rusticl" in impl for impl in used_impls):
            warn("Rusticl OpenCL detected – limited functionality.")
            print("→ For full features (e.g., GPGPU, ML, PyOpenCL) use ROCm or AMDGPU-Pro.")
        elif any("clover" in impl for impl in used_impls):
            warn("Clover OpenCL detected – outdated backend.")
            print("→ For full features (e.g., GPGPU, ML, PyOpenCL) use ROCm or AMDGPU-Pro.")
        return True

    if any("rusticl" in p.lower() for p in platforms):
        warn("Rusticl platform detected, but no GPU available – possible limitations.")
    else:
        fail("No AMD GPU found in OpenCL device list.")

    print(f"→ {suggest('rocm-opencl-runtime')}")
    return False

# --------------------------------------------------------------------------- #
def check_vulkan() -> bool:
    info("Checking Vulkan stack …")
    if not command_exists("vulkaninfo"):
        fail("vulkaninfo is missing.")
        print(f"→ {suggest('vulkan-tools mesa-vulkan-drivers')}")
        return False

    summary = run(["vulkaninfo", "--summary"])
    if summary and "AMD" in summary:
        driver = next((line.split(":", 1)[1].strip()
                       for line in summary.splitlines()
                       if "Driver Name" in line), "unknown")
        ok(f"AMD GPU detected via Vulkan  [Driver: {driver}]")
        return True

    full_output = run(["vulkaninfo"])
    if full_output and any("deviceName" in line and "AMD" in line for line in full_output.splitlines()):
        ok("AMD GPU detected via Vulkan (Fallback through full scan).")
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
