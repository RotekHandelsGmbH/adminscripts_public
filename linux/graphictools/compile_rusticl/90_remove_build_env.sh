#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$ROOT/env-jinja"
LLVM_VERSION="18"

# === Helper Functions (Colorful, Emoji, One-liners) ===

# Color codes
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; RESET='\033[0m'

log()    { echo -e "\n${CYAN}ℹ️  [INFO]${RESET} $1\n"; }
info()   { echo -e "\n${CYAN}ℹ️  [INFO]${RESET} $1\n"; }
debug()  { echo -e "${BLUE}🐞 [DEBUG]${RESET} $1"; }
warn()   { echo -e "${YELLOW}⚠️ [WARN]${RESET} $1"; }
success(){ echo -e "${GREEN}✅ [SUCCESS]${RESET} $1"; }
error()  { echo -e "${RED}❌ [ERROR]${RESET} $1" >&2; }
fail()   { error "$1"; exit 1; }

# === 1. REMOVE BUILD FILES ===

function remove_build_dirs() {
  log "🧹 Removing local build folders and source codes..."
  rm -rf "$ROOT"/{mesa,build,drm,spirv-tools,spirv-llvm-translator,libclc-build,spirv-llvm-translator-build,spirv-tools-src}
}

# === 2. REMOVE VIRTUALENV ===
function remove_virtualenv() {
  log "🧹 Removing Python virtual environment..."
  rm -rf "$VENV"
}

# === 3. REMOVE SYSTEM BUILD PACKAGES ===

function remove_system_packages() {
  log "🧼 Removing build packages installed via apt..."

  sudo apt remove --purge -y \
    bison build-essential clang-${LLVM_VERSION} cmake flex git
    glslang-dev glslang-tools libclang-cpp${LLVM_VERSION}-dev libdrm-dev libelf-dev
    libexpat1-dev libglvnd-dev libpolly-${LLVM_VERSION}-dev libudev-dev
    libunwind-dev libva-dev libwayland-dev libegl1-mesa-dev
    libwayland-egl-backend-dev libx11-dev libx11-xcb-dev libxdamage-dev
    libxext-dev libxinerama-dev libxrandr-dev libxcb-dri2-0-dev libxcb-dri3-dev
    libxcb-glx0-dev libxcb-present-dev libxcb-randr0-dev libxcb-shm0-dev
    libxcb-sync-dev libxcb1-dev libxshmfence-dev libxxf86vm-dev
    meson ninja-build pkg-config python3-pip python3-setuptools
    valgrind wayland-protocols zlib1g-dev libzstd-dev curl
    libcurl4-openssl-dev || true
}

function autoremove_packages() {
  log "🧽 Running apt autoremove..."
  sudo apt autoremove -y
}

# === 4. REMOVE RUST TOOLCHAIN ===

function remove_rust() {
  if command -v rustup &>/dev/null; then
    log "🦀 Removing Rust toolchain (via rustup)..."
    rustup self uninstall -y
  else
    log "ℹ️  Rustup is not installed – skipping."
  fi
}

# === MAIN ===

log "🧨 Starting clean removal of the Mesa build environment..."
log "⚠️  The Mesa installation and profile script will be retained."

remove_build_dirs
remove_virtualenv
remove_system_packages
autoremove_packages
remove_rust

log "✅ Cleanup complete. System is clean – Mesa remains intact."
