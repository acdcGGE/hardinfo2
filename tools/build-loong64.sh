#!/usr/bin/env bash
# Reproducible loongarch64 (Debian/Deepin loong64) build for hardinfo2.
#
# This script checks build dependencies, prints the exact apt command for any
# that are missing, and exits. Once all dependencies are installed system-wide,
# it configures, builds and packages an installable .deb (Architecture: loong64).
#
#   ./tools/build-loong64.sh
#
# It never downloads or unpacks packages by itself — install what it reports.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$SRC_DIR/build-loong64}"

# pkg-config modules required by the full build (GTK3 + libsoup3 + Qt5 + Vulkan).
# Format: "name" or "name|minversion" (minversion checked with --atleast-version).
# Do NOT write "name>=ver": pkg-config only accepts constraints with spaces,
# and this script passes each entry as a single argument.
PC_MODULES=(
  "gtk+-3.0|3.0"
  "glib-2.0|2.24"
  "json-glib-1.0|0.14.2"
  "libsoup-3.0|3.00"
  "x11"
  "vulkan"
  "Qt5Core"
  "Qt5Gui"
  "Qt5OpenGL"
  "libdecor-0"
)

# Commands needed by the build (cmake/make are checked separately).
COMMANDS=(
  cmake make gcc g++ pkg-config msgfmt glslangValidator moc qmake
)

# Maps a missing item to the apt package that provides it.
pkg_for() {
  case "$1" in
    "cmake")            echo cmake ;;
    "make")             echo build-essential ;;
    "gcc"|"g++")        echo build-essential ;;
    "pkg-config")       echo pkg-config ;;
    "msgfmt")           echo gettext ;;
    "glslangValidator") echo glslang-tools ;;
    "moc")              echo qtbase5-dev-tools ;;
    "qmake")            echo qt5-qmake qt5-qmake-bin ;;
    "gtk+-3.0"*)        echo libgtk-3-dev ;;
    "glib-2.0"*)        echo libglib2.0-dev ;;
    "json-glib-1.0"*)   echo libjson-glib-dev ;;
    "libsoup-3.0"*)     echo libsoup-3.0-dev ;;
    "x11")              echo libx11-dev ;;
    "vulkan")           echo libvulkan-dev ;;
    "Qt5"*)             echo qtbase5-dev libqt5opengl5-dev ;;
    "libdecor-0")       echo libdecor-0-dev ;;
    *)                  echo "$1" ;;
  esac
}

log() { printf '[build-loong64] %s\n' "$*" >&2; }

check_deps() {
  local missing=() item name
  for item in "${COMMANDS[@]}"; do
    command -v "$item" >/dev/null 2>&1 || missing+=("$item")
  done
  for item in "${PC_MODULES[@]}"; do
    name="${item%%|*}"
    minver="${item#*|}"
    [[ "$minver" == "$item" ]] && minver=""
    if ! pkg-config --exists "$name" 2>/dev/null; then
      missing+=("$name")
    elif [[ -n "$minver" ]] && ! pkg-config --atleast-version="$minver" "$name" 2>/dev/null; then
      missing+=("$item")
    fi
  done

  if ((${#missing[@]})); then
    log "Missing build dependencies:"
    local -A seen=()
    local pkgs=()
    for item in "${missing[@]}"; do
      printf '  - %s\n' "$item" >&2
      for pkg in $(pkg_for "$item"); do
        if [[ -z "${seen[$pkg]:-}" ]]; then
          seen[$pkg]=1
          pkgs+=("$pkg")
        fi
      done
    done
    printf '\nInstall them with:\n\n  sudo apt install %s\n\n' "${pkgs[*]}" >&2
    return 1
  fi
  return 0
}

main() {
  [[ "$(uname -m)" == "loongarch64" ]] || { log "error: not running on loongarch64"; exit 1; }

  if ! check_deps; then
    log "dependency check failed — install the packages above and re-run."
    exit 1
  fi
  log "all build dependencies present"

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
