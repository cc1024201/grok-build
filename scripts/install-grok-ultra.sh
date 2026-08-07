#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PREFIX=${GROK_ULTRA_PREFIX:-"$HOME/.local"}
APP_DIR="$PREFIX/lib/grok-ultra"
BIN_DIR="$PREFIX/bin"

"$ROOT_DIR/scripts/build-grok-ultra.sh"

case "$(uname -s)" in
  Linux) platform=linux ;;
  Darwin) platform=macos ;;
  *) echo "Unsupported platform: $(uname -s)" >&2; exit 2 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) arch=x86_64 ;;
  arm64|aarch64) arch=aarch64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 2 ;;
esac

package_dir="$ROOT_DIR/dist/grok-ultra-${platform}-${arch}"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR" "$BIN_DIR"
cp -R "$package_dir/bin" "$package_dir/libexec" "$package_dir/README.txt" "$APP_DIR/"
ln -sfn "$APP_DIR/bin/grok-ultra" "$BIN_DIR/grok-ultra"

cat <<EOF_DONE
Installed isolated Grok Ultra:
  command: $BIN_DIR/grok-ultra
  program: $APP_DIR
  state:   ${GROK_ULTRA_HOME:-$HOME/.grok-ultra}

The official 'grok' command and ~/.grok are untouched.
Ensure $BIN_DIR is on PATH, then run:
  grok-ultra
EOF_DONE
