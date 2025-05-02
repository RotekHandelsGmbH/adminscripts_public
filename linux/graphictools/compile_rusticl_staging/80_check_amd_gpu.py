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
# [Other functions omitted for brevity; unchanged]

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
# [Main and remaining functions unchanged]
