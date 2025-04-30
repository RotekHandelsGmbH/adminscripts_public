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

  # === First pass: generate profiling data ===
  log "🔁 First pass: compiling with -fprofile-generate"
  export CFLAGS="-O3 -march=native -mtune=native -flto -fprofile-generate -fomit-frame-pointer -fPIC"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="-Wl,-O3 -flto -fprofile-generate"

  rm -rf "$ROOT/drm/build"
  meson setup "$ROOT/drm/build" "$ROOT/drm" \
    -Dprefix="$PREFIX" \
    -Damdgpu=enabled \
    -Dbuildtype=release \
    --reconfigure \
    || fail "Meson setup (generate phase) failed"

  ninja -v -C "$ROOT/drm/build" || fail "libdrm build (generate) failed"
  sudo ninja -C "$ROOT/drm/build" install || fail "libdrm install (generate) failed"

  # === Simulate a workload that uses libdrm (example test app) ===
  log "⚙️ Running dummy workload to generate PGO data..."
  cat > "$ROOT/test_pgo.c" <<EOF
#include <stdio.h>
#include <xf86drm.h>
int main() {
    int version = drmGetVersion(0) != NULL;
    printf("drmGetVersion call result: %d\\n", version);
    return 0;
}
EOF

  gcc "$ROOT/test_pgo.c" -o "$ROOT/test_pgo" -I"$PREFIX/include" -L"$PREFIX/lib" -ldrm || fail "Failed to build test workload"
  DRM_DIR=/dev/dri
  if [[ -e "$DRM_DIR/card0" ]]; then
    "$ROOT/test_pgo" || warn "Test workload failed to run"
  else
    warn "No /dev/dri/card0 found. Skipping real PGO run"
  fi

  # === Second pass: use collected profile data ===
  log "🔁 Second pass: compiling with -fprofile-use"
  export CFLAGS="-O3 -march=native -mtune=native -flto -fprofile-use -fomit-frame-pointer -fPIC"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="-Wl,-O3 -flto -fprofile-use"

  rm -rf "$ROOT/drm/build"
  meson setup "$ROOT/drm/build" "$ROOT/drm" \
    -Dprefix="$PREFIX" \
    -Damdgpu=enabled \
    -Dbuildtype=release \
    --reconfigure \
    || fail "Meson setup (use phase) failed"

  ninja -v -C "$ROOT/drm/build" || fail "libdrm build (use) failed"
  sudo ninja -C "$ROOT/drm/build" install || fail "libdrm install (use) failed"

  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
  debug "libdrm_amdgpu version: $(pkg-config --modversion libdrm_amdgpu || echo 'Not found')"
}
