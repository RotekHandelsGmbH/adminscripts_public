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
- The script `install_latest_python_clang.sh`, located one directory up in the repository structure, is also required.
- Please clone the entire **adminscripts** repository using the following command:

  ```bash
  git clone --depth 1 https://github.com/RotekHandelsGmbH/adminscripts.git
  ```

---

## Script Descriptions and Order

1. **10_create_build_env.sh**
   - **Purpose:** Sets up the initial build environment by installing the essential development tools and dependencies required for building Mesa and related components.

2. **12_install_lua_5.4_latest.sh**
   - **Purpose:** Downloads, builds, and installs the latest Lua 5.4 version. Lua is a dependency for Mesa's build system.

3. **15_build_libdrm.sh**
   - **Purpose:** Clones and builds `libdrm` (Direct Rendering Manager library) from source. This is a crucial dependency for Mesa.

4. **20_build_spirv_tools.sh**
   - **Purpose:** Builds SPIRV-Tools, which are necessary for shader translation and handling in the Vulkan/OpenCL pipeline.

5. **30_build_spirv_llvm_translator.sh**
   - **Purpose:** Builds the SPIRV-LLVM-Translator, bridging between LLVM IR and SPIR-V representations.

6. **40_build_libclc.sh**
   - **Purpose:** Builds `libclc`, a library providing an implementation of the OpenCL C programming language library.

7. **50_build_mesa.sh**
   - **Purpose:** Configures, builds, and installs the Mesa 3D Graphics Library, including OpenGL, Vulkan drivers, and compute capabilities.

8. **60_cleanup_icds.sh**
   - **Purpose:** Cleans up unneeded Installable Client Drivers (ICDs) to maintain a minimal environment.

9. **70_write_env_profile.sh**
   - **Purpose:** Creates a shell profile script to set environment variables permanently, making the new Mesa and associated libraries available system-wide.

10. **80_check_amd_gpu.py**
    - **Purpose:** Python script to verify that the system is correctly configured.
      - Checks that the **AMDGPU kernel driver** is active.
      - Verifies **OpenCL** support (via `clinfo`) and warns if Rusticl or Clover backends are detected.
      - Checks for **Vulkan** driver and GPU detection (via `vulkaninfo`).
      - Gives hints if critical components are missing and suggests installing missing packages.

11. **90_remove_build_env.sh**
    - **Purpose:** Final cleanup. Removes the temporary build environment and unnecessary dependencies, leaving only the compiled Mesa drivers and essential libraries installed.

    **Important:** This script may remove packages such as:
    - Rust toolchain (`rustc`, `cargo`)
    - Build tools and dependencies (`cmake`, `ninja-build`, `meson`)
    - Development headers and libraries
    - Other development tools required only during build time

    If you rely on these packages for other projects or developments, **review and adapt the cleanup script before executing** to avoid accidental removal of needed software.

---

## Usage

1. Ensure you are running on a supported Linux distribution (e.g., Ubuntu, Debian).
2. Clone the entire adminscripts repository:

   ```bash
   git clone --depth 1 https://github.com/RotekHandelsGmbH/adminscripts.git
   ```

3. Make all scripts executable:

   ```bash
   chmod +x *.sh *.py
   ```

4. Execute the scripts **in order**:

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

5. Restart your shell session or source your profile to apply environment changes:

   ```bash
   source ~/.profile
   ```

---

## Notes
- These scripts assume **sudo** privileges are available.
- Ensure sufficient disk space (>10GB recommended) and a stable internet connection.
- **Clang** is used as the main compiler.
- The latest **Python** version will be installed and used inside a **virtual environment** for building Mesa and related tools.
- Review each script if you wish to customize paths or additional build flags.
- Carefully check the final cleanup script if you need development tools (Rust, Meson, CMake, etc.) for other purposes.
- The `80_check_amd_gpu.py` script provides a final verification step to ensure the AMD GPU setup, OpenCL, and Vulkan support are correctly configured.

---

Happy Building!

---

