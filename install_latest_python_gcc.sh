#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
PYTHON_LATEST_DIR="/opt/python-latest"
TMP_DIR="/tmp"
PYTHON_SYMLINK_NAME="python3"
PIP_SYMLINK_NAME="pip3"

# === Helper Functions (Colorful, Emoji, One-liners) ===

# Color codes
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; RESET='\033[0m'

log()    { echo -e "\n${CYAN}ℹ️  [INFO]${RESET} $1\n"; }
debug()  { echo -e "${BLUE}🐞 [DEBUG]${RESET} $1"; }
warn()   { echo -e "${YELLOW}⚠️ [WARN]${RESET} $1"; }
success(){ echo -e "${GREEN}✅ [SUCCESS]${RESET} $1"; }
error()  { echo -e "${RED}❌ [ERROR]${RESET} $1" >&2; }
fail()   { error "$1"; exit 1; }

# === INSTALL REQUIRED TOOLS & DEV LIBS ===
MISSING_PKGS=()

for pkg in curl jq wget pkg-config; do
  command -v "$pkg" &>/dev/null || MISSING_PKGS+=("$pkg")
done

# build-toolchain
if ! command -v gcc &>/dev/null || ! command -v make &>/dev/null; then
  MISSING_PKGS+=(build-essential)
fi

# SSL and zlib headers
MISSING_PKGS+=(libssl-dev zlib1g-dev)

if [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
  log "Installing missing packages: ${MISSING_PKGS[*]}"
  apt-get update || error "apt-get update failed"
  apt-get install -y "${MISSING_PKGS[@]}" || error "Failed to install ${MISSING_PKGS[*]}"
fi

# === ENSURE GCC IS USED ===
function pick_compiler() {
  if ! command -v gcc &>/dev/null; then
    fail "GCC compiler not found!"
  fi
  export CC=gcc CXX=g++
  debug "Using compiler: $CC"
}

# === FETCH & EXTRACT CPYTHON ===
function prepare_build() {
  local TG="$1"
  local ARCHIVE="cpython-${TG}.tar.gz"
  local URL="https://github.com/python/cpython/archive/refs/tags/${TG}.tar.gz"

  cd "$TMP_DIR"
  [[ -f "$ARCHIVE" ]] || { log "Downloading $ARCHIVE…"; wget -q -O "$ARCHIVE" "$URL"; }
  rm -rf cpython-build
  mkdir -p cpython-build
  log "Extracting into build tree…"
  tar -xzf "$ARCHIVE" --strip-components=1 -C cpython-build || error "Extraction failed"
}

# === SET OPT FLAGS ===
set_opt_flags() {
    echo "🔧 This will set HIGH-PERFORMANCE compiler and linker flags:"
    echo ""
    echo "  CFLAGS    = -O3 -march=native -flto=auto -fno-semantic-interposition"
    echo "  CXXFLAGS  = (same as CFLAGS)"
    echo "  LDFLAGS   = -Wl,-O1 -Wl,--as-needed -flto=auto"
    echo ""
    read -p "❓ Do you want to apply these flags for your build? You will be able to execute python only at this machines CPU (march=native) [y/N]: " answer

    case "$answer" in
        [yY][eE][sS]|[yY])
            export CFLAGS="-O3 -march=native -flto=auto -fno-semantic-interposition"
            export CXXFLAGS="$CFLAGS"
            export LDFLAGS="-Wl,-O1 -Wl,--as-needed -flto=auto"
            echo "✅ Optimization flags set."
            ;;
        *)
            echo "❌ Optimization flags NOT set. You can still export them manually later."
            ;;
    esac
}

# === BUILD & INSTALL CPYTHON ===
function install_prefix() {
  local PREFIX="$1"
  log "Installing into $PREFIX…"
  rm -rf "$PREFIX" && mkdir -p "$PREFIX"

  pick_compiler
  cd "$TMP_DIR/cpython-build"

  log "Configuring (prefix=$PREFIX)…"
  make clean &>/dev/null || true
  make distclean &>/dev/null || true

  ./configure \
    --prefix="$PREFIX" \
    --enable-optimizations \
    --with-lto \
    --with-openssl=/usr \
    --with-system-zlib \
    || error "Configure failed for $PREFIX"

  log "Building (prefix=$PREFIX)…"
  make -j"$(nproc)" || error "Build failed for $PREFIX"

  log "Altinstalling (prefix=$PREFIX)…"
  make altinstall || error "Altinstall failed for $PREFIX"

  local PYBIN="$PREFIX/bin/python${PY_VERSION%.*}"
  local PIPBIN="$PREFIX/bin/pip${PY_VERSION%.*}"
  for name in "$PYTHON_SYMLINK_NAME" python; do
    ln -sf "$PYBIN" "$PREFIX/bin/$name"
  done
  for name in "$PIP_SYMLINK_NAME" pip; do
    ln -sf "$PIPBIN" "$PREFIX/bin/$name"
  done

  log "Installing virtualenv in $PREFIX…"
  "$PIPBIN" install --upgrade virtualenv || error "virtualenv install failed"
}

# === MAIN ===
log "Fetching latest stable CPython tag…"
TAG=$(curl -fsSL \
        -H "Accept: application/vnd.github.v3+json" \
        -H "User-Agent:install-script" \
        "https://api.github.com/repos/python/cpython/tags?per_page=100" \
      | jq -r '.[] | select(.name|test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")) | .name' \
      | head -n1) || error "Failed to fetch tags"
[[ -n "$TAG" ]] || error "No stable tag found"

PY_VERSION="${TAG#v}"
debug "Tag: $TAG → version $PY_VERSION"

set_opt_flags
prepare_build "$TAG"
install_prefix "/opt/python-${PY_VERSION}"
install_prefix "$PYTHON_LATEST_DIR"

log "Cleaning up…"
rm -rf "$TMP_DIR/cpython-build" "cpython-${TAG}.tar.gz"
debug "Removed build artifacts"

log "Done! Installed Python $PY_VERSION to:"
echo "  • Versioned:   /opt/python-$PY_VERSION"
echo "  • Latest link: $PYTHON_LATEST_DIR"
echo
echo "⚠️  Always create virtual environments from the versioned interpreter:"
echo "    /opt/python-$PY_VERSION/bin/python3 -m venv <env>"
