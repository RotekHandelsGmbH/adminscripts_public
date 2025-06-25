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


log "🛠️ Cleaning up old build directory"
rm -rf "${ROOT}"

# === Force GCC ===
log "🛠️ Forcing GCC as the compiler and setup compiler flags"
# export CFLAGS="-O3 -march=native -flto -fPIC -fvisibility=hidden -fomit-frame-pointer -DNDEBUG -fprofile-generate"
export CFLAGS="-O3 -march=native -flto -fPIC -fvisibility=hidden -fomit-frame-pointer -DNDEBUG"
export CXXFLAGS="$CFLAGS"
# -O3                   # Enable highest level of optimization (aggressive inlining, loop unrolling, vectorization)
# -march=native         # Optimize code for the local CPU architecture (may break portability)
# -flto                 # Enable Link Time Optimization (LTO) for better cross-module optimization
# -fPIC                 # Generate position-independent code (required for shared libraries)
# -fvisibility=hidden   # Hide all symbols by default; only explicitly exported ones are visible (improves load time and security)
# -fomit-frame-pointer  # Omit the frame pointer to free a register (slightly faster, but makes debugging stack traces harder)
# -DNDEBUG              # Disable debug `assert()` and other debug-only code (used in production builds)
# -fprofile-generate    # Instrument the program to collect profiling data at runtime (for use with PGO - Profile Guided Optimization)

# export LDFLAGS="-flto -Wl,-O1 -Wl,--as-needed -Wl,--strip-all -shared  -fprofile-generate"
export LDFLAGS="-flto -Wl,-O1 -Wl,--as-needed -Wl,--strip-all"
# -flto                  # Enable Link Time Optimization (LTO) during linking for cross-module inlining and better optimization
# -Wl,-O1                # Pass optimization level 1 to the linker (balance between speed and link-time complexity)
# -Wl,--as-needed        # Only link shared libraries that are actually used (reduces dependencies and load time)
# -Wl,--strip-all        # Strip all symbol information from the final binary (smaller size, but no debugging symbols)
# -shared                # Produce a shared object (.so) instead of an executable
# -fprofile-generate    # Instrument the program to collect profiling data at runtime (for use with PGO - Profile Guided Optimization)

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
    -DCMAKE_PREFIX_PATH="$PREFIX;$PREFIX/lib;$PREFIX/lib/cmake" \
    -DCMAKE_MODULE_PATH="$PREFIX/lib/cmake/SPIRV-Tools" \
    -DSPIRV-Tools_DIR="$PREFIX/lib/cmake/SPIRV-Tools" \
    -DLLVM_SPIRV="$PREFIX/bin/llvm-spirv"

  cmake --build build -- -j"$(nproc)"
  sudo cmake --install build

  log "✅ libclc build complete and installed to $PREFIX"
}

# === MAIN ===
build_libclc_only
