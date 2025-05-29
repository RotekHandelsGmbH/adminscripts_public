#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
LLVM_VERSION="18"
LLVM_CONFIG="llvm-config-${LLVM_VERSION}"
PREFIX="/opt/mesa"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/spirv-llvm-translator-build"

# === Helper Functions (Colorful, Emoji, One-liners) ===

# Color codes
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; RESET='\033[0m'

log()    { echo -e "\n${CYAN}ℹ️  [INFO]${RESET} $1\n"; }
debug()  { echo -e "${BLUE}🐞 [DEBUG]${RESET} $1"; }
warn()   { echo -e "${YELLOW}⚠️ [WARN]${RESET} $1"; }
success(){ echo -e "${GREEN}✅ [SUCCESS]${RESET} $1"; }
error()  { echo -e "${RED}❌ [ERROR]${RESET} $1" >&2; } # will continue
fail()   { error "$1"; exit 1; }

# === Force Clang ===
#log "🛠️ Forcing Clang as the compiler"
#export CC=clang
#export CXX=clang++

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

# === BUILD ===
function build_spirv_llvm_translator() {
  log "Building SPIRV-LLVM-Translator (LLVM $LLVM_VERSION)..."

  mkdir -p "$ROOT"
  cd "$ROOT"

  if [[ ! -d "$ROOT/spirv-llvm-translator" ]]; then
    git clone --depth=1 --branch llvm_release_180 https://github.com/KhronosGroup/SPIRV-LLVM-Translator.git spirv-llvm-translator || fail "Clone failed"
  else
    log "Using existing spirv-llvm-translator source directory"
  fi

  LLVM_PREFIX="$($LLVM_CONFIG --prefix)"
  debug "LLVM_PREFIX: $LLVM_PREFIX"
  [[ -f "$LLVM_PREFIX/lib/cmake/llvm/LLVMConfig.cmake" ]] || fail "LLVMConfig.cmake missing"

  cmake -S spirv-llvm-translator -B spirv-llvm-translator/build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DLLVM_CONFIG="$LLVM_CONFIG" \
    -DCMAKE_PREFIX_PATH="$LLVM_PREFIX;$PREFIX" \
    -DLLVM_DIR="$LLVM_PREFIX/lib/cmake/llvm"

  cmake --build spirv-llvm-translator/build --target llvm-spirv -- -j$(nproc)
  sudo cmake --install spirv-llvm-translator/build

  if [[ ! -f "$PREFIX/bin/llvm-spirv" ]]; then
    fail "llvm-spirv not found after install!"
  fi

  debug "✅ llvm-spirv installed to: $PREFIX/bin/llvm-spirv"
}

build_spirv_llvm_translator
