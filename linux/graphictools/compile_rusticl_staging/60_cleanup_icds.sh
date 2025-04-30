#!/usr/bin/env bash
set -euo pipefail

ICD_DIR="/opt/mesa/etc/OpenCL/vendors"
KEEP="rusticl.icd"
TARGET="/opt/mesa/lib/libMesaOpenCL.so.1"

# === Helper Functions (Colorful, Emoji, One-liners) ===

# Color codes
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; RESET='\033[0m'

log()    { echo -e "\n${CYAN}ℹ️  [INFO]${RESET} $1\n"; }
debug()  { echo -e "${BLUE}🐞 [DEBUG]${RESET} $1"; }
warn()   { echo -e "${YELLOW}⚠️ [WARN]${RESET} $1"; }
success(){ echo -e "${GREEN}✅ [SUCCESS]${RESET} $1"; }
error()  { echo -e "${RED}❌ [ERROR]${RESET} $1" >&2; } # will continue
fail()   { error "$1"; exit 1; }

# === Main Logic ===

log "📂 Listing current ICD files in $ICD_DIR"
if ! ls -1 "$ICD_DIR"; then
  warn "(Empty or inaccessible directory)"
fi

log "🧹 Removing unnecessary ICD files (keeping only $KEEP)"
for f in "$ICD_DIR"/*.icd; do
  [[ -f "$f" ]] || continue
  if [[ "$(basename "$f")" != "$KEEP" ]]; then
    debug "Removing: $(basename "$f")"
    sudo rm -f "$f"
  else
    debug "Keeping: $(basename "$f")"
  fi
done

log "🛠️  Writing $KEEP with path to $TARGET"
echo "$TARGET" | sudo tee "$ICD_DIR/$KEEP" > /dev/null

log "🔄 Running ldconfig to refresh shared library cache"
sudo ldconfig

success "✅ ICD files deduplicated successfully."

# === OpenCL Test ===
log "🔬 Testing OpenCL installation"
if command -v clinfo &>/dev/null; then
  debug "Running clinfo..."
  if ! clinfo | grep -i "platform"; then
    warn "No OpenCL platform found."
  fi
else
  warn "clinfo not installed. Install it with: sudo apt install clinfo"
fi
