# Build Environment Setup and Mesa Driver Compilation Scripts

Author: **bitranox**  
License: **MIT**

---

## Overview

This repository contains a series of shell scripts designed to **set up a Linux build environment**, **compile necessary libraries**, **build Mesa drivers**, and finally **clean up the build environment**.

The main goal is to **prepare the system to compile [llama.cpp](https://github.com/ggerganov/llama.cpp) with Vulkan support**, enabling the use of **old AMD GPUs (such as the R9 200 and HD7970 series)** for running LLMs like LLaMA efficiently via Vulkan compute.

The scripts **must be executed in order** as numbered to ensure successful compilation and installation.

Tested with **AMD R9 200** and **AMD HD7970** on **Debian Bookworm**.

**Important:**
- The script `install_latest_python_gcc.sh`, located in another directory up in the repository structure, is also required.
- Please clone the entire **adminscripts** repository using the following command:

  ```bash
  sudo git clone --depth 1 https://github.com/RotekHandelsGmbH/adminscripts.git
  ```

---

## Optimization Notes

These scripts use **`gcc`** as the main compiler, configured with **aggressive optimization flags**:

- `-O3`
- `-march=native`
- **Profile-guided optimizations** (2-pass compilation using `-fprofile-generate` and `-fprofile-use`)

This setup aims to **squeeze (hopefully) maximum performance** out of older AMD GPUs by tuning the binaries specifically for the host system's architecture and 
usage patterns.

---

## Script Descriptions and Order

1. **10_create_build_env.sh**  
   Sets up the initial build environment by installing essential development tools and dependencies.

2. **12_install_lua_5.4_latest.sh**  
   Builds and installs Lua 5.4, required by Mesa.

3. **15_build_libdrm.sh**  
   Builds the Direct Rendering Manager (libdrm), a core dependency.

4. **20_build_spirv_tools.sh**  
   Builds SPIR-V tools for shader processing.

5. **30_build_spirv_llvm_translator.sh**  
   Builds the SPIRV-LLVM-Translator for SPIR-V/LLVM IR conversion.

6. **40_build_libclc.sh**  
   Builds libclc, the OpenCL C language library.

7. **50_build_mesa.sh**  
   Compiles the Mesa 3D Graphics Library with Vulkan/OpenCL support using the above optimizations.

8. **60_cleanup_icds.sh**  
   Removes unneeded Installable Client Drivers (ICDs).

9. **70_write_env_profile.sh**  
   Adds Mesa-related environment variables to the shell profile.

10. **80_check_amd_gpu.py**  
    Verifies driver setup and reports Vulkan/OpenCL readiness.

11. **90_remove_build_env.sh**  
    Cleans up all temporary build tools and environments.

    ⚠️ **Warning:** May remove essential development tools (Rust, CMake, etc.)—review before running.

---

## Usage

1. Ensure you're running on a supported Linux distribution (e.g., Ubuntu, Debian).
2. Clone the repository:

   ```bash
   git clone --depth 1 https://github.com/RotekHandelsGmbH/adminscripts.git
   ```

3. Make all scripts executable:

   ```bash
   chmod +x *.sh *.py
   ```

4. Execute the scripts in order:

   ```bash
   ./10_create_build_env.sh
   ./12_install_lua_5.4_latest.sh
   ./15_build_libdrm.sh
   ./20_build_spirv_tools.sh
   ./30_build_spirv_llvm_translator.sh
   ./40_build_libclc.sh
   ./50_build_mesa.sh
   ./60_cleanup_icds.sh
   ./70_write_env_profile.sh
   python3 80_check_amd_gpu.py
   ./90_remove_build_env.sh
   ```

5. Restart your shell or source the profile:

   ```bash
   source ~/.profile
   ```

---

## Notes

- Requires `sudo` privileges.
- Recommend ≥10GB free disk space and stable internet connection.
- Uses `gcc` with `-O3`, `-march=native`, and **profile-guided optimizations** to boost runtime performance.
- Installs and uses the latest Python in a **virtual environment**.
- Review each script to customize options as needed.
- Final cleanup removes many build tools—review `90_remove_build_env.sh` carefully.

---

Happy Building!

---

