# check_amd_gpu.py

Author: **bitranox**  
License: **MIT**

---

## Description

`check_amd_gpu.py` is a simple Python 3 script that checks your system for:

- **AMDGPU Kernel Driver** usage
- **OpenCL** runtime availability and AMD GPU detection
- **Vulkan** stack installation and AMD GPU detection

It helps Linux users verify that their AMD GPU is properly supported and configured for both compute (OpenCL) and graphics (Vulkan) tasks.

The script also automatically suggests installation commands for missing components based on your distribution (apt, dnf, pacman).

---

## Requirements

The following system packages are needed:

- `pciutils` (for `lspci`)
- `clinfo` (for OpenCL detection)
- `mesa-opencl-icd` or `rocm-opencl-runtime` (for OpenCL drivers)
- `vulkan-tools` (for `vulkaninfo`)
- `mesa-vulkan-drivers` (for Vulkan ICD support)

You can install missing tools easily. For example, on Ubuntu/Debian:

```bash
sudo apt install pciutils clinfo vulkan-tools mesa-opencl-icd mesa-vulkan-drivers
```

---

## What the Script Detects

### 1. AMDGPU Kernel Driver
- Checks if the `amdgpu` kernel module is in use by your GPU(s).
- Verifies whether the `amdgpu` module is loaded via `lsmod`, or built directly into the kernel.

### 2. OpenCL Runtime
- Checks if `clinfo` is installed.
- Detects OpenCL Installable Client Drivers (ICDs) from `/etc/OpenCL/vendors/`.
- Confirms whether any AMD GPUs are available as OpenCL devices.
- Identifies the backend (Rusticl, Clover, ROCm, AMDGPU-Pro) in use, warning about limited functionality if necessary.

### 3. Vulkan Stack
- Checks if `vulkaninfo` is installed.
- Verifies whether any AMD GPU is available for Vulkan.
- Reports the Vulkan driver in use.

---

## Usage

Make sure the script is executable:

```bash
chmod +x check_amd_gpu.py
```

Then simply run:

```bash
./check_amd_gpu.py
```

The script will perform all checks and provide detailed, color-coded feedback.

---

## Example Output

```
[INFO]  Detecting GPU model …
✅ GPU Detected: 01:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Tahiti XT [Radeon HD 7970/8970 OEM / R9 280X] [1002:6798]

[INFO]  Checking AMDGPU kernel driver …
✅ AMDGPU driver used by 1 GPU(s).
[INFO]  amdgpu module is loaded.
[INFO]  Checking OpenCL runtime …
[INFO]  Found OpenCL ICDs: mesa.icd, rusticl.icd
[INFO]  Found OpenCL platform(s): rusticl
✅ AMD GPU(s) detected as OpenCL device(s) – Count: 1
[WARN]  Rusticl OpenCL detected – limited functionality.
→ For full features (e.g., GPGPU, ML, PyOpenCL) use ROCm or AMDGPU-Pro.
[INFO]  Checking Vulkan stack …
✅ AMD GPU detected via Vulkan  [Driver: unknown]

[INFO]  Checking for ROCm support …
[WARN]  ROCm not found.
→ sudo apt install rocm-opencl-runtime or sudo apt install rocminfo

✅ All main checks passed – system ready. 🎉

[INFO]  For detailed inspection, use:
   lspci | grep -i vga
   clinfo
   vulkaninfo
   rocminfo
```

---

## License

MIT License

(c) 2025 bitranox

