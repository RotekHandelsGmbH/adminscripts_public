function build_libdrm() {
  log "Building libdrm >= 2.4.121 with PGO and LTO..."

  # Clone if not already cloned
  if [[ ! -d "$ROOT/drm" ]]; then
    git clone --depth=1 --branch libdrm-2.4.121 \
      https://gitlab.freedesktop.org/mesa/drm.git "$ROOT/drm" \
      || fail "Failed to clone libdrm repository"
  fi

  export CC=gcc
  export CXX=g++

  # === First build: Profile-generate ===
  log "🔁 First pass: compiling with -fprofile-generate"
  export CFLAGS="-O3 -march=native -mtune=native -flto -fprofile-generate -fomit-frame-pointer -fPIC"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="-Wl,-O3 -flto -fprofile-generate"

  rm -rf "$ROOT/drm/build"
  meson setup "$ROOT/drm/build" "$ROOT/drm" \
    -Dprefix="$PREFIX" \
    -Damdgpu=enabled \
    -Dbuildtype=release \
    || fail "Meson setup (generate phase) failed"

  ninja -C "$ROOT/drm/build" || fail "libdrm build (generate) failed"
  sudo ninja -C "$ROOT/drm/build" install || fail "libdrm install (generate) failed"

  # === Simulate workload (replace with actual test app) ===
  log "⚙️ Running simulated workload for PGO data collection..."
  # Add your real test/workload here, or replace with an actual executable using libdrm
  sleep 2  # Placeholder

  # === Second build: Profile-use ===
  log "🔁 Second pass: compiling with -fprofile-use"
  export CFLAGS="-O3 -march=native -mtune=native -flto -fprofile-use -fomit-frame-pointer -fPIC"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="-Wl,-O3 -flto -fprofile-use"

  rm -rf "$ROOT/drm/build"
  meson setup "$ROOT/drm/build" "$ROOT/drm" \
    -Dprefix="$PREFIX" \
    -Damdgpu=enabled \
    -Dbuildtype=release \
    || fail "Meson setup (use phase) failed"

  ninja -C "$ROOT/drm/build" || fail "libdrm build (use) failed"
  sudo ninja -C "$ROOT/drm/build" install || fail "libdrm install (use) failed"

  # Final confirmation
  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
  debug "libdrm_amdgpu version: $(pkg-config --modversion libdrm_amdgpu || echo 'Not found')"
}
