#!/bin/bash

# -------------------------------------------------------------------
# 🛠️ Mesa/Rusticl Environment Setup Script
# This script writes environment variables to /etc/profile.d/mesa.sh
# -------------------------------------------------------------------

# === Helper Functions (Colorful, Emoji, One-liners) ===

# Color codes
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; RESET='\033[0m'

log()    { echo -e "\n${CYAN}ℹ️  [INFO]${RESET} $1\n"; }
info()    { echo -e "\n${CYAN}ℹ️  [INFO]${RESET} $1\n"; }
debug()  { echo -e "${BLUE}🐞 [DEBUG]${RESET} $1"; }
warn()   { echo -e "${YELLOW}⚠️ [WARN]${RESET} $1"; }
success(){ echo -e "${GREEN}✅ [SUCCESS]${RESET} $1"; }
error()  { echo -e "${RED}❌ [ERROR]${RESET} $1" >&2; }
fail()   { error "$1"; exit 1; }

function write_env_script() {
  log "🛠️  Setting up Mesa/Rusticl environment variables..."

  # Hardcode PREFIX
  local PREFIX="/opt/mesa"
  local PROFILE_SCRIPT="/etc/profile.d/mesa.sh"

  debug "📂 Using PREFIX=$PREFIX"

  # Check for sudo permissions
  if [[ $EUID -ne 0 ]]; then
    warn "🔒 This operation needs sudo privileges. Trying with sudo..."
  fi

  log "✍️  Writing environment setup to $PROFILE_SCRIPT..."

  sudo tee "$PROFILE_SCRIPT" > /dev/null <<EOF
# Mesa/Rusticl environment
export LD_LIBRARY_PATH=$PREFIX/lib:\$LD_LIBRARY_PATH
export LIBGL_DRIVERS_PATH=$PREFIX/lib/dri
export VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/radeon_icd.x86_64.json
export OCL_ICD_VENDORS=$PREFIX/etc/OpenCL/vendors
export RUSTICL_ENABLE=radeonsi
EOF

  # shellcheck disable=SC2181
  if [[ $? -ne 0 ]]; then
    fail "❌ Failed to write the environment script. Exiting."
  fi

  log "🔒 Setting executable permissions on $PROFILE_SCRIPT..."
  sudo chmod +x "$PROFILE_SCRIPT"

  # shellcheck disable=SC2181
  if [[ $? -ne 0 ]]; then
    fail "❌ Failed to set permissions. Exiting."
  fi

  log "🔄 Loading environment variables..."
  if [[ -f "$PROFILE_SCRIPT" ]]; then
    # shellcheck disable=SC1090
    source "$PROFILE_SCRIPT"
    success "✅ Environment successfully loaded!"
  else
    fail "⚠️  Environment script not found after writing. Please check manually."
  fi

  success "🎉 Mesa/Rusticl environment setup is complete!"
}

# --- Start ---
log "🚀 Starting Mesa/Rusticl environment setup script..."
write_env_script
