# Admin Scripts

## Install
To clone the adminscripts repo (master branch) to your local machine, open a terminal and run:

```bash
git clone https://github.com/RotekHandelsGmbH/adminscripts.git
```

This will create a folder called adminscripts with everything from the master branch. If you only want the latest snapshot (a “shallow” clone), you can do:

```bash
git clone --depth 1 https://github.com/RotekHandelsGmbH/adminscripts.git
```

## scripts

- [install latest python from source on linux with clang compiler](./readme_install_latest_python_clang.md)
- [FilteredTreeSync - Selectively copies files matching a specific pattern, preserving the full directory tree structure](./readme_FilteredTreeSync.md)
- [check AMD GPU driver, opencl and vulkan settings](./readme_check_amd_gpu.md)
- [compile opencl rusticl and Mesa Vulkan. Tested with AMD HD7900 Series (R9 200, HD 7970, Tahiti) and X11 on Debian bookworm](compile_rusticl/readme_compile_rusticl.md)
