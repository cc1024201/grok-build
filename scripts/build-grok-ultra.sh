#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

raw_target_dir=${CARGO_TARGET_DIR:-target}
case "$raw_target_dir" in
  /*) TARGET_DIR=$raw_target_dir ;;
  *) TARGET_DIR="$ROOT_DIR/$raw_target_dir" ;;
esac

raw_dist_root=${GROK_ULTRA_DIST_DIR:-dist}
case "$raw_dist_root" in
  /*) DIST_ROOT=$raw_dist_root ;;
  *) DIST_ROOT="$ROOT_DIR/$raw_dist_root" ;;
esac

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

package_name="grok-ultra-${platform}-${arch}"
package_dir="$DIST_ROOT/$package_name"
archive="$DIST_ROOT/$package_name.tar.gz"

cargo build --manifest-path "$ROOT_DIR/Cargo.toml" -p xai-grok-pager-bin --release

core="$TARGET_DIR/release/xai-grok-pager"
if [[ ! -x "$core" ]]; then
  echo "Release binary not found: $core" >&2
  exit 1
fi

rm -rf "$package_dir" "$archive" "$archive.sha256"
mkdir -p "$package_dir/bin" "$package_dir/libexec"
install -m 0755 "$core" "$package_dir/libexec/grok-ultra-core"

cat > "$package_dir/bin/grok-ultra" <<'LAUNCHER'
#!/bin/sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CORE="$SELF_DIR/../libexec/grok-ultra-core"

if [ ! -x "$CORE" ]; then
  echo "grok-ultra: core binary not found or not executable: $CORE" >&2
  exit 127
fi

case "${1-}" in
  update)
    echo "grok-ultra: self-update is disabled for the isolated self-use build." >&2
    echo "Rebuild or replace the grok-ultra package instead; the official 'grok' installation is never modified." >&2
    exit 2
    ;;
esac

ambient_grok_home=${GROK_HOME:-}
ambient_auth_path=${GROK_AUTH_PATH:-}

if [ -n "${GROK_ULTRA_HOME:-}" ]; then
  ultra_home=$GROK_ULTRA_HOME
elif [ -n "${HOME:-}" ]; then
  ultra_home=$HOME/.grok-ultra
else
  echo "grok-ultra: HOME is unset; set GROK_ULTRA_HOME to an absolute writable directory." >&2
  exit 2
fi

case "$ultra_home" in
  /*) ;;
  *) echo "grok-ultra: GROK_ULTRA_HOME must resolve to an absolute path: $ultra_home" >&2; exit 2 ;;
esac

if [ -n "${HOME:-}" ] && [ "$ultra_home" = "$HOME/.grok" ]; then
  echo "grok-ultra: refusing to use the official Grok state root: $ultra_home" >&2
  exit 2
fi
if [ -n "$ambient_grok_home" ] && [ "$ultra_home" = "$ambient_grok_home" ]; then
  echo "grok-ultra: isolated state root matches ambient GROK_HOME: $ultra_home" >&2
  echo "Unset GROK_HOME or choose a distinct GROK_ULTRA_HOME." >&2
  exit 2
fi

auth_path=${GROK_ULTRA_AUTH_PATH:-$ultra_home/auth.json}
case "$auth_path" in
  /*) ;;
  *) echo "grok-ultra: GROK_ULTRA_AUTH_PATH must resolve to an absolute path: $auth_path" >&2; exit 2 ;;
esac
if [ -n "${HOME:-}" ] && [ "$auth_path" = "$HOME/.grok/auth.json" ]; then
  echo "grok-ultra: refusing to use the official Grok credential file: $auth_path" >&2
  exit 2
fi
if [ -n "$ambient_auth_path" ] && [ "$auth_path" = "$ambient_auth_path" ]; then
  echo "grok-ultra: isolated credential path matches ambient GROK_AUTH_PATH: $auth_path" >&2
  echo "Unset GROK_AUTH_PATH or choose a distinct GROK_ULTRA_AUTH_PATH." >&2
  exit 2
fi

# Deliberately override ambient official-Grok locations. Product-specific
# GROK_ULTRA_* variables are the only supported escape hatches.
export GROK_HOME="$ultra_home"
export GROK_AUTH_PATH="$auth_path"
export GROK_AGENT="${GROK_ULTRA_AGENT:-grok-build-ultra}"
export GROK_DISABLE_AUTOUPDATER=1
export GROK_ULTRA_DISTRIBUTION=1
unset GROK_AUTO_UPDATE

if [ -n "${GROK_ULTRA_LEADER_SOCKET:-}" ]; then
  export GROK_LEADER_SOCKET="$GROK_ULTRA_LEADER_SOCKET"
else
  unset GROK_LEADER_SOCKET
fi

if [ -n "${GROK_ULTRA_SESSION_PATH:-}" ]; then
  export GROK_SESSION_PATH="$GROK_ULTRA_SESSION_PATH"
else
  unset GROK_SESSION_PATH
fi

exec "$CORE" "$@"
LAUNCHER
chmod 0755 "$package_dir/bin/grok-ultra"

cat > "$package_dir/README.txt" <<EOF_README
Grok Ultra isolated self-use build

Run:
  ./bin/grok-ultra

Default state root:
  ~/.grok-ultra

The launcher does not install or replace the official 'grok' command and
refuses the 'update' subcommand. Override the isolated state root with:
  GROK_ULTRA_HOME=/absolute/path ./bin/grok-ultra
EOF_README

tar -C "$DIST_ROOT" -czf "$archive" "$package_name"

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$archive" > "$archive.sha256"
else
  shasum -a 256 "$archive" > "$archive.sha256"
fi

printf 'Package: %s\nArchive: %s\n' "$package_dir" "$archive"
