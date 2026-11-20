#!/usr/bin/env bash
# Reproducible loongarch64 (Debian/Deepin loong64) build for hardinfo2.
#
# Two modes:
#   1) System mode (default): all -dev packages are installed system-wide.
#      Just run:  ./tools/build-loong64.sh
#   2) Local mode (no root): missing -dev debs are downloaded and unpacked
#      into a local prefix, and pkg-config/.pc files are rewritten to point
#      there. Run:  DSH_LOCAL_DEPS=1 ./tools/build-loong64.sh
#
# Both modes produce a dpkg-installable .deb with Architecture: loong64.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$SRC_DIR/build-loong64}"
LOCAL_DEPS="${DSH_LOCAL_DEPS:-0}"
LOCAL_ROOT="${DSH_LOCAL_DEPS_ROOT:-$SRC_DIR/.loong64-deps/root/usr}"

DEB_PACKAGES=(
  libjson-glib-dev
  libqt5opengl5-dev qtbase5-dev qtbase5-dev-tools qt5-qmake qt5-qmake-bin
  libdecor-0-dev glslang-tools
  # runtime counterparts (needed for the local-prefix link targets):
  # -dev packages ship *.so -> *.so.N symlinks but the *.so.N payloads live
  # in these runtime packages, so unpack both or the link step fails.
  libjson-glib-1.0-0 libdecor-0-0
  libqt5core5a libqt5gui5 libqt5opengl5 libqt5network5 libqt5widgets5
)

log() { printf '[build-loong64] %s\n' "$*" >&2; }

# $1 = usr root (e.g. .../root/usr), which is also the pkg-config prefix.
rewrite_pc_prefix() {
  local usr="$1" dir="$1/lib/loongarch64-linux-gnu/pkgconfig" pc
  [[ -d "$dir" ]] || return 0
  for pc in "$dir"/*.pc; do
    sed -i "s|^prefix=/usr\$|prefix=$usr|" "$pc"
  done
}

# $1 = usr root.
fix_qt5_wrappers() {
  local usr="$1" wrapper="$1/bin/loongarch64-linux-gnu-qmake"
  # qt5-qmake wrapper hardcodes /usr/lib/qt5/bin/qmake; repoint to local prefix.
  if [[ -f "$wrapper" ]]; then
    sed -i \
      -e "s|/usr/lib/qt5/bin/qmake|$usr/lib/qt5/bin/qmake|g" \
      -e "s|/usr/lib/loongarch64-linux-gnu/qt5/qt.conf|$usr/lib/loongarch64-linux-gnu/qt5/qt.conf|g" \
      "$wrapper"
  fi
}

prepare_local_deps() {
  log "local-deps mode: downloading dev packages into $LOCAL_ROOT"
  local extract_root="${LOCAL_ROOT%/usr}"
  mkdir -p "$extract_root" "$LOCAL_ROOT"
  local cache="$SRC_DIR/.loong64-deps/debs"
  mkdir -p "$cache"
  (
    cd "$cache"
    apt-get download "${DEB_PACKAGES[@]}"
    for deb in *.deb; do
      dpkg-deb -x "$deb" "$extract_root"
    done
  )
  rewrite_pc_prefix "$LOCAL_ROOT"
  fix_qt5_wrappers "$LOCAL_ROOT"
}

main() {
  [[ "$(uname -m)" == "loongarch64" ]] || { log "error: not running on loongarch64"; exit 1; }

  export PKG_CONFIG_PATH="/usr/lib/loongarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig"
  if [[ "$LOCAL_DEPS" == "1" ]]; then
    prepare_local_deps
    export PKG_CONFIG_PATH="$LOCAL_ROOT/lib/loongarch64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH"
    export PATH="$LOCAL_ROOT/lib/loongarch64-linux-gnu/qt5/bin:$LOCAL_ROOT/bin:$PATH"
  fi

  log "configuring (Qt5 + Vulkan enabled)"
  rm -rf "$BUILD_DIR"
  cmake -S "$SRC_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DHARDINFO2_VK_WAYLAND=0

  log "building"
  cmake --build "$BUILD_DIR" -j"$(nproc)"

  log "packaging .deb"
  ( cd "$BUILD_DIR" && cpack -G DEB )

  log "done:"
  ls -lh "$BUILD_DIR"/*.deb
}

main "$@"
