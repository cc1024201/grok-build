#!/usr/bin/env bash
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/package/bin" "$TMP/package/libexec" "$TMP/home"

cat > "$TMP/package/libexec/grok-ultra-core" <<'CORE'
#!/bin/sh
printf 'GROK_HOME=%s\n' "${GROK_HOME-}"
printf 'GROK_AUTH_PATH=%s\n' "${GROK_AUTH_PATH-}"
printf 'GROK_AGENT=%s\n' "${GROK_AGENT-}"
printf 'GROK_DISABLE_AUTOUPDATER=%s\n' "${GROK_DISABLE_AUTOUPDATER-}"
printf 'GROK_LEADER_SOCKET=%s\n' "${GROK_LEADER_SOCKET-}"
printf 'GROK_SESSION_PATH=%s\n' "${GROK_SESSION_PATH-}"
CORE
chmod +x "$TMP/package/libexec/grok-ultra-core"

# Extract the launcher template from the package builder without running cargo.
awk '/^cat > "\$package_dir\/bin\/grok-ultra" <<'\''LAUNCHER'\''$/{copy=1;next} /^LAUNCHER$/{copy=0} copy' \
  "$(dirname "$0")/build-grok-ultra.sh" > "$TMP/package/bin/grok-ultra"
chmod +x "$TMP/package/bin/grok-ultra"

output=$(HOME="$TMP/home" \
  GROK_HOME=/official/grok \
  GROK_AUTH_PATH=/official/auth.json \
  GROK_LEADER_SOCKET=/official/leader.sock \
  GROK_SESSION_PATH=/official/session.json \
  "$TMP/package/bin/grok-ultra")

expected_home="$TMP/home/.grok-ultra"
grep -Fx "GROK_HOME=$expected_home" <<<"$output" >/dev/null
grep -Fx "GROK_AUTH_PATH=$expected_home/auth.json" <<<"$output" >/dev/null
grep -Fx "GROK_AGENT=grok-build-ultra" <<<"$output" >/dev/null
grep -Fx 'GROK_DISABLE_AUTOUPDATER=1' <<<"$output" >/dev/null
grep -Fx 'GROK_LEADER_SOCKET=' <<<"$output" >/dev/null
grep -Fx 'GROK_SESSION_PATH=' <<<"$output" >/dev/null

set +e
HOME="$TMP/home" "$TMP/package/bin/grok-ultra" update >/dev/null 2>&1
status=$?
set -e
[[ $status -eq 2 ]]

echo "PASS: grok-ultra launcher isolates command state and blocks official updater paths."
