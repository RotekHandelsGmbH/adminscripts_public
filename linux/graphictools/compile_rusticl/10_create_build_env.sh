#!/usr/bin/env bash
set -euo pipefail

# === Helper Functions (Colorful, Emoji, One-liners) ===

# Color codes
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; RESET='\033[0m'

log()    { echo -e "\n${CYAN}ℹ️  [INFO]${RESET} $1\n"; }
debug()  { echo -e "${BLUE}🐞 [DEBUG]${RESET} $1"; }
warn()   { echo -e "${YELLOW}⚠️ [WARN]${RESET} $1"; }
success(){ echo -e "${GREEN}✅ [SUCCESS]${RESET} $1"; }
error()  { echo -e "${RED}❌ [ERROR]${RESET} $1" >&2; } # will continue
fail()   { error "$1"; exit 1; }


# === CONFIGURATION ===
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$ROOT/env-jinja"
LLVM_VERSION="18"
LLVM_CONFIG="llvm-config-${LLVM_VERSION}"
PYTHON_INSTALL_DIR="/opt/python-latest"
PYTHON_BIN="$PYTHON_INSTALL_DIR/bin/python"
PIP_BIN="$PYTHON_INSTALL_DIR/bin/pip"

# === HELPER FUNCTIONS ===
function check_command() {
  if ! command -v "$1" &>/dev/null; then
    fail "Required command '$1' is not installed or not in PATH."
  fi
}

# === SYSTEM DEPENDENCIES ===
function setup_system_dependencies() {
  log "🔧 Installing system dependencies via APT..."
  sudo apt update

  local pkgs=(
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
    libcurl4-openssl-dev
  )

  debug "Installing required packages..."
  sudo apt install -y "${pkgs[@]}"

  debug "Attempting Lua 5.4 development package..."
  if sudo apt install -y lua5.4-dev; then
    log "✅ lua5.4-dev installed"
  else
    warn "lua5.4-dev not available – will use compiled Lua script"
    # call fallback installer
    "$ROOT/12_install_lua_5.4_latest.sh"
  fi
}

# === LLVM TOOLCHAIN ===
function install_llvm_from_repo() {
  log "📦 Installing LLVM ${LLVM_VERSION} from apt.llvm.org..."

  sudo mkdir -p /etc/apt/keyrings
  wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | sudo tee /etc/apt/keyrings/llvm.asc >/dev/null

  local list_path="/etc/apt/sources.list.d/llvm${LLVM_VERSION}.list"
  if [[ ! -f "$list_path" ]]; then
    echo "deb [signed-by=/etc/apt/keyrings/llvm.asc] https://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-${LLVM_VERSION} main" \
      | sudo tee "$list_path" >/dev/null
  else
    debug "APT source for LLVM already present: $list_path"
  fi

  sudo apt update
  sudo apt install -y llvm-${LLVM_VERSION}-dev clang-${LLVM_VERSION}

  debug "Checking llvm-config binary..."
  check_command "$LLVM_CONFIG"
  debug "$LLVM_CONFIG version: $($LLVM_CONFIG --version)"
}

# === PYTHON INSTALL ===
function install_python_latest() {
  if [[ -d "/opt/python-latest" ]]; then
    log "🐍 Using existing Python installation at /opt/python-latest"
    return
  fi

  log "🐍 Installing latest Python version using separate script..."
  local script_path="$ROOT/../../pythontools/install_latest_python_gcc.sh"
  if [[ -x "$script_path" ]]; then
    "$script_path"
  else
    fail "Python install script not found or not executable: $script_path"
  fi
}


# === PYTHON VIRTUAL ENVIRONMENT ===
function setup_virtualenv() {
  log "🐍 Creating Python virtualenv in $VENV using $PYTHON_BIN..."

  [[ -x "$PYTHON_BIN" ]] || fail "Custom Python binary not found at $PYTHON_BIN"
  [[ -x "$PIP_BIN" ]]   || fail "Custom pip not found at $PIP_BIN"

  debug "Installing virtualenv via pip..."
  "$PIP_BIN" install --upgrade pip setuptools wheel virtualenv || fail "Failed to install virtualenv"

  rm -rf "$VENV"
  "$PYTHON_BIN" -m virtualenv --clear "$VENV" || fail "Failed to create virtualenv"

  debug "Activating virtualenv..."
  source "$VENV/bin/activate"

  debug "Upgrading pip and installing Python build tools inside virtualenv..."
  pip install --upgrade pip
  pip install meson ninja mako PyYAML

  debug "Python tools installed: $(which meson), $(which ninja)"
}

# === RUST TOOLCHAIN ===
function setup_rust() {
  log "🦀 Installing Rust toolchain if not already present..."
  if ! command -v rustc &>/dev/null; then
    curl --proto '=https' --tlsv1.2 https://sh.rustup.rs -sSf | sh -s -- -y
    source "$HOME/.cargo/env"
  fi

  debug "Rust version: $(rustc --version)"
  debug "Installing bindgen-cli (used by Mesa)..."
  cargo install --locked bindgen-cli
  cargo install --locked cbindgen
}

# === CLEAN BUILD WORKSPACE ===
function clean_build_dirs() {
  log "🧹 Cleaning old build directories under $ROOT..."
  local targets=(mesa build drm spirv-tools spirv-llvm-translator libclc-build spirv-tools-src)
  for dir in "${targets[@]}"; do
    [[ -d "$ROOT/$dir" ]] && rm -rf "$ROOT/$dir"
  done
  mkdir -p "$ROOT"
}


# === INSTALL CLANG ===
function install_clang() {
  log "🔍 Checking for existing Clang installation..."
  if command -v clang >/dev/null 2>&1; then
    success "Clang is already installed: $(clang --version | head -n1)"
    return 0
  fi

  log "⚙️ Installing Clang..."

  # Detect distro
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    distro=$ID
    distro_like=${ID_LIKE:-}
  else
    fail "Cannot detect Linux distribution (missing /etc/os-release)"
  fi

  case "$distro" in
    ubuntu|debian)
      sudo apt-get update
      sudo apt-get install -y clang
      ;;
    fedora)
      sudo dnf install -y clang
      ;;
    centos|rhel)
      sudo yum install -y epel-release   # enable EPEL if needed
      sudo yum install -y clang
      ;;
    arch)
      sudo pacman -Sy --noconfirm clang
      ;;
    *)
      # try generic families
      case "$distro_like" in
        debian)
          sudo apt-get update
          sudo apt-get install -y clang
          ;;
        rhel|fedora)
          if command -v dnf >/dev/null; then
            sudo dnf install -y clang
          else
            sudo yum install -y clang
          fi
          ;;
        arch)
          sudo pacman -Sy --noconfirm clang
          ;;
        *)
          fail "Unsupported distro: $distro. Please install clang manually."
          ;;
      esac
      ;;
  esac

  # verify
  if command -v clang >/dev/null 2>&1; then
    success "Clang installed successfully: $(clang --version | head -n1)"
  else
    fail "Clang installation failed"
  fi
}


# === MAIN ===
log "🚀 Starting environment setup for Mesa + Rusticl builds..."

setup_system_dependencies
install_clang
install_llvm_from_repo
install_python_latest
setup_virtualenv
setup_rust
clean_build_dirs

log "✅ Environment setup complete. Ready to build Mesa and dependencies."
