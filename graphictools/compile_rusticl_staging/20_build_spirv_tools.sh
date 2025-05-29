#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
PREFIX="/opt/mesa"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/spirv-tools-src"
BUILD_DIR="$ROOT/build-spirv-tools"
VENV="$SCRIPT_DIR/env-jinja"
PYTHON="$VENV/bin/python"
PROFILE_DIR="$SCRIPT_DIR/spirv-tools-profile-data"
SPIRV_CORPUS="$SCRIPT_DIR/spirv-tools-corpus"

# === Load Colors and Helpers ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; RESET='\033[0m'
log()    { echo -e "\n${CYAN}ℹ️  [INFO]${RESET} $1\n"; }
debug()  { echo -e "${BLUE}🔎 [DEBUG]${RESET} $1"; }
warn()   { echo -e "${YELLOW}⚠️ [WARN]${RESET} $1"; }
success(){ echo -e "${GREEN}✅ [SUCCESS]${RESET} $1"; }
error()  { echo -e "${RED}❌ [ERROR]${RESET} $1" >&2; }
fail()   { error "$1"; exit 1; }

# === Clean old build ===
log "🔧 Clean old build"
rm -rf "${ROOT}"
rm -rf "${BUILD_DIR}"
rm -rf "${PROFILE_DIR}"
rm -rf "${SPIRV_CORPUS}"


function activate_virtualenv() {
  log "🔧 Activating Python virtual environment from: $VENV"
  if [[ ! -f "$VENV/bin/activate" ]]; then
    fail "Virtualenv not found at $VENV. Please run the environment setup first."
  fi
  source "$VENV/bin/activate"
}

function download_corpus() {
  log "📚 Downloading SPIR-V test corpus..."
  mkdir -p "$SPIRV_CORPUS"
  git clone --depth=1 https://github.com/KhronosGroup/SPIRV-Cross.git "$SPIRV_CORPUS/SPIRV-Cross"
  git clone --depth=1 https://github.com/dfranx/SPIRV-VM.git "$SPIRV_CORPUS/SPIRV-VM"
  git clone --depth=1 https://github.com/KhronosGroup/SPIRV-Tools.git "$SPIRV_CORPUS/SPIRV-Tools"
}

function build_spirv_tools_pgo() {
  local mode=$1
  local extra_flags=""
  local build_suffix="$mode"

  log "🧹 Building SPIRV-Tools [$mode]..."

  if [[ "$mode" == "generate" ]]; then
    extra_flags="-fprofile-generate=$PROFILE_DIR"
  elif [[ "$mode" == "use" ]]; then
    extra_flags="-fprofile-use=$PROFILE_DIR -fprofile-correction -Wno-error=missing-profile"
  fi

  export CFLAGS="-O3 -march=native -flto -fPIC -fvisibility=hidden -fomit-frame-pointer -DNDEBUG $extra_flags"
  export CXXFLAGS="$CFLAGS"
  if [[ "$mode" == "use" ]]; then
    export CXXFLAGS="${CXXFLAGS/-Werror/} -Wno-error=missing-profile"
  fi
  export LDFLAGS="-flto -Wl,-O1 -Wl,--as-needed -Wl,--strip-all -shared $extra_flags"

  rm -rf "$BUILD_DIR-$build_suffix"
  mkdir -p "$BUILD_DIR-$build_suffix"

  cmake -S "$ROOT" -B "$BUILD_DIR-$build_suffix" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DPython3_EXECUTABLE="$PYTHON" || fail "CMake configure failed"

  cmake --build "$BUILD_DIR-$build_suffix" -- -j"$(nproc)" || fail "Build failed"
  sudo cmake --install "$BUILD_DIR-$build_suffix" || fail "Install failed"
}

function run_profiling_load() {
  log "🧪 Running profiling load with spirv-as and spirv-opt..."

  local tools_bin="$PREFIX/bin"
  local log_file="/tmp/spirv-pgo.log"
  local skipped_file="/tmp/spirv-pgo-skipped.log"
  > "$log_file"
  > "$skipped_file"

  find "$SPIRV_CORPUS" -type f -name "*.spv" | while read -r spv_file; do
    if "$tools_bin/spirv-opt" --O "$spv_file" -o /dev/null 2>>"$log_file"; then
      log "✓ spirv-opt: $spv_file"
    else
      warn "✗ spirv-opt failed: $spv_file"
    fi
  done

  find "$SPIRV_CORPUS" -type f \( -name "*.asm" -o -name "*.spvasm" \) | while read -r asm_file; do
    if "$tools_bin/spirv-as" "$asm_file" -o /dev/null 2>>"$log_file"; then
      log "✓ spirv-as: $asm_file"
    else
      warn "✗ spirv-as failed: $asm_file"
    fi
  done

  if command -v glslangValidator &>/dev/null; then
    find "$SPIRV_CORPUS" -type f \( -name "*.vert" -o -name "*.frag" -o -name "*.comp" \) \
      ! -name "*.asm.*" ! -name "*.spvasm" ! -name "*.nonuniformresource.*" \
      ! -name "*.invalid.*" ! -name "*.legacy.*" | while read -r shader; do

      log "🔍 Checking shader: $shader"

      local version_line version_number
      version_line=$(grep "^#version" "$shader" | head -n1 || true)
      version_number=$(echo "$version_line" | grep -oE '[0-9]+' || echo 0)

      if [[ "$version_number" -lt 310 ]]; then
        warn "⚠️ Skipping shader (GLSL version < 310): $shader"
        echo "Skipped shader (version too low): $shader" >> "$skipped_file"
        continue
      fi

      if grep -q "void main" "$shader"; then
        if glslangValidator -V "$shader" -o /dev/null 2>>"$log_file"; then
          log "✓ GLSL compiled: $shader"
        else
          warn "✗ GLSL compile failed: $shader"
          echo "GLSL compile failed: $shader" >> "$log_file"
        fi
      else
        warn "⚠️ Skipping invalid shader (missing main): $shader"
        echo "Skipped shader (missing main): $shader" >> "$skipped_file"
      fi

    done
  else
    warn "glslangValidator not found; skipping GLSL compilation"
  fi

  success "Profiling workload complete. Logs saved to:"
  echo "  Compile errors: $log_file"
  echo "  Skipped shaders: $skipped_file"
}

function clone_spirv_tools_repo() {
  activate_virtualenv
  if [[ ! -d "$ROOT/.git" ]]; then
    git clone https://github.com/KhronosGroup/SPIRV-Tools.git "$ROOT" || fail "Clone failed"
  fi
  cd "$ROOT"
  git reset --hard
  git clean -fd
  git fetch origin
  git checkout v2024.1 || fail "Checkout failed"
  git submodule update --init --recursive
  "$PYTHON" utils/git-sync-deps || fail "Sync deps failed"
  curl -sSL https://patch-diff.githubusercontent.com/raw/KhronosGroup/SPIRV-Tools/pull/5534.patch -o 5534.patch
  git apply 5534.patch || warn "Patch may already be applied"
}

# === MAIN ===
log "🚀 Starting Two-Pass PGO Build of SPIRV-Tools"
clone_spirv_tools_repo
download_corpus
build_spirv_tools_pgo generate
run_profiling_load
build_spirv_tools_pgo use
success "PGO-optimized build of SPIRV-Tools installed to $PREFIX"
