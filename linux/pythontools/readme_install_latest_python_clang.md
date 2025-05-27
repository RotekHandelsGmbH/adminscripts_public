# Python Installer Script

This script automates the process of building and installing the latest stable version of CPython from source on Debian-based systems (e.g., Proxmox on Bookworm). It installs two copies:

1. **Versioned installation** in `/opt/python-X.Y.Z` (exact version)
2. **Latest symlinked installation** in `/opt/python-latest`

It also installs and configures `virtualenv` for each installation.

---

## Prerequisites

- Debian Bookworm or compatible (e.g., Proxmox).
- Internet access for downloading sources and packages.
- Root privileges (the script uses `apt-get` and writes to `/opt`).

## Required Packages

The script will install the following if missing:

- `build-essential` (gcc, make, etc.)
- `clang`
- `curl`, `wget`, `jq`, `pkg-config`
- `libssl-dev`, `zlib1g-dev`

## Installation

1. **Fetch the script** to your server, e.g., `/usr/local/bin/install_latest_python.sh`.
2. **Make it executable**:

   ```bash
   chmod +x install_latest_python.sh
   ```

3. **Run the script** as root or via `sudo`:

   ```bash
   ./install_latest_python.sh
   ```

The script will:

- Detect and install necessary build dependencies.
- Fetch the latest stable CPython tag from GitHub.
- Download, extract, build, and install CPython twice (versioned & latest).
- Install `virtualenv` into each Python installation.
- Clean up temporary build artifacts.

## Usage

After installation:

- **Versioned interpreter**:
  ```bash
  /opt/python-<version>/bin/python3 --version
  ```

- **Latest symlink**:
  ```bash
  /opt/python-latest/bin/python3 --version
  ```

- **Creating virtual environments** (always use versioned).  
  virtual environments might brake if You create them from `/opt/python-latest` if that gets updated 
  ```bash
  # venv
  /opt/python-<version>/bin/python3 -m venv myenv
  # virtualenv
  /opt/python-<version>/bin/python3 -m virtualenv myenv
  # check out the key differences between venv and virtualenv
  ```

## Configuration

- **`PYTHON_LATEST_DIR`**: Change the path for the "latest" symlink if desired.
- **`TMP_DIR`**: Change the temporary build directory.

## Troubleshooting

- **Missing zlib or OpenSSL** errors:
  - Ensure `zlib1g-dev` and `libssl-dev` are installable in your APT sources.

- **`mpdecimal` warnings**:
  - The script uses the bundled `libmpdecimal`; no system package is required.

- **Permissions**:
  - Run as root or with `sudo` to write to `/opt` and install packages.

- **lto terminates**:
    ```bash
    gcc: fatal error: Killed signal terminated program as
    ...
    lto-wrapper: fatal error: gcc returned 1 exit status
    ...
    /usr/bin/ld: error: lto-wrapper failed
    ```
  indicates that the GCC compilation process was killed, likely due to insufficient memory (RAM) during Link Time Optimization (LTO).
  What's happening:
  GCC is performing LTO, which is memory-intensive.
  Your system likely ran out of memory, and the OS killed the process (often with a SIGKILL).
  This leads to the lto-wrapper failed and subsequent linker errors.
---

This script streamlines Python installations on servers where package managers may lag behind upstream releases.

