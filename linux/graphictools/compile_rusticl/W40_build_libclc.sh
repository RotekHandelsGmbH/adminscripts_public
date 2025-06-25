#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
PREFIX="/opt/mesa"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/libclc-build"
LLVM_VERSION="18"
LLVM_CONFIG="llvm-config-${LLVM_VERSION}"
LLVM_PROJECT_DIR="$ROOT/llvm-project"

mkdir -p "$ROOT"

# === Helper Functions (Colorful, Emoji, One-liners) ===

# Color codes
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; RESET='\033[0m'

log()    { echo -e "\n${CYAN}ℹ️  [INFO]${RESET} $1\n"; }
debug()  { echo -e "${BLUE}🐞 [DEBUG]${RESET} $1"; }
warn()   { echo -e "${YELLOW}⚠️ [WARN]${RESET} $1"; }
success(){ echo -e "${GREEN}✅ [SUCCESS]${RESET} $1"; }
error()  { echo -e "${RED}❌ [ERROR]${RESET} $1" >&2; } # will continue
fail()   { error "$1"; exit 1; }

# === Compiler Setup ===
log "🛠️ Using GCC as the compiler"
export CC=gcc
export CXX=g++


function build_libclc_only() {
  log "Building libclc for LLVM ${LLVM_VERSION} natively..."

  if [ ! -d "$LLVM_PROJECT_DIR" ]; then
    git clone --depth=1 --branch llvmorg-${LLVM_VERSION}.1.0 https://github.com/llvm/llvm-project.git "$LLVM_PROJECT_DIR" || fail "llvm-project clone failed"
  else
    log "Using existing llvm-project at $LLVM_PROJECT_DIR"
  fi

  cd "$LLVM_PROJECT_DIR/libclc"

  # === Patch CMakeLists.txt if necessary ===
  if ! grep -q "find_package(SPIRV-Tools" CMakeLists.txt; then
    log "Patching CMakeLists.txt to explicitly require SPIRV-Tools..."
    sed -i '2i\
find_package(SPIRV-Tools REQUIRED CONFIG)\nset(SPIRV-Tools_INCLUDE_DIR "'"$PREFIX"'/include")\nset(SPIRV-Tools_LIBRARY "'"$PREFIX"'/lib/libSPIRV-Tools.a")\n' CMakeLists.txt
    debug "✅ Patch inserted into CMakeLists.txt"
  fi

  # === Environment Setup ===
  export PATH="$PREFIX/bin:$PATH"
  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib/x86_64-linux-gnu/pkgconfig"
  export CMAKE_PREFIX_PATH="${PREFIX}/lib/cmake"

  debug "PATH: $PATH"
  debug "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
  debug "llvm-config version: $($LLVM_CONFIG --version)"
  debug "Checking spirv-as: $(command -v spirv-as || echo 'not found')"
  debug "Checking llvm-spirv: $(command -v llvm-spirv || echo 'not found')"
  debug "SPIRV-Tools version: $(pkg-config --modversion SPIRV-Tools || echo 'not found')"
  debug "SPIRV-ToolsConfig.cmake exists: $(ls -l $PREFIX/lib/cmake/SPIRV-Tools/SPIRV-ToolsConfig.cmake || echo '❌ missing')"
  debug "Listing CMake config files:"
  find "$PREFIX/lib/cmake" -name '*.cmake'

  # === CMake Build ===
  cmake -S . -B build -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_CONFIG="$LLVM_CONFIG" \
    -DENABLE_SPIRV=ON \
    -DCMAKE_PREFIX_PATH="$PREFIX;$PREFIX/lib;$PREFIX/lib/cmake" \
    -DCMAKE_MODULE_PATH="$PREFIX/lib/cmake/SPIRV-Tools" \
    -DSPIRV_TOOLS_INCLUDE_DIR="$PREFIX/include" \
    -DSPIRV_TOOLS_LIBRARY="$PREFIX/lib/libSPIRV-Tools.a" \
    -DSPIRV-Tools_DIR="$PREFIX/lib/cmake/SPIRV-Tools" \
    -DLLVM_SPIRV="$PREFIX/bin/llvm-spirv"

  cmake --build build -- -j"$(nproc)"
  sudo cmake --install build

  log "✅ libclc build complete and installed to $PREFIX"
}

# === MAIN ===
build_libclc_only
