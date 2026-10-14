#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
home="$SANDBOX/home"
mkdir -p "$home"

"$ROOT/dev-agent-config" --help > "$SANDBOX/help"
"$ROOT/dev-agent-config" -h >/dev/null
grep -q 'graphify <action>' "$SANDBOX/help"
grep -q 'cli install|uninstall' "$SANDBOX/help"
grep -q 'codebase-memory-mcp <command>' "$SANDBOX/help"
"$ROOT/dev-agent-config" graphify --help > "$SANDBOX/graphify-help"
grep -q 'serve \[--project PATH\]' "$SANDBOX/graphify-help"
grep -q 'run \[--project PATH\]' "$SANDBOX/graphify-help"
"$ROOT/dev-agent-config" tools codebase-memory-mcp --help > "$SANDBOX/cbm-help"
grep -q 'adopt \[--dry-run\]' "$SANDBOX/cbm-help"

HOME="$home" PATH=/usr/bin:/bin "$ROOT/dev-agent-config" cli install --dry-run --bin-dir "$home/bin" > "$SANDBOX/dry"
[ ! -e "$home/bin/dev-agent-config" ]
HOME="$home" PATH=/usr/bin:/bin "$ROOT/dev-agent-config" cli install --bin-dir "$home/bin" >/dev/null
[ -L "$home/bin/dev-agent-config" ]
[ "$(readlink "$home/bin/dev-agent-config")" = "$ROOT/dev-agent-config" ]
HOME="$home" PATH=/usr/bin:/bin "$home/bin/dev-agent-config" --help >/dev/null
HOME="$home" PATH=/usr/bin:/bin "$home/bin/dev-agent-config" cli install --bin-dir "$home/bin" | grep 'UNCHANGED CLI link' >/dev/null

printf 'keep\n' > "$home/bin/unrelated"
HOME="$home" PATH=/usr/bin:/bin "$home/bin/dev-agent-config" cli uninstall --bin-dir "$home/bin" >/dev/null
[ ! -e "$home/bin/dev-agent-config" ]
[ -f "$home/bin/unrelated" ]

printf 'foreign\n' > "$home/bin/dev-agent-config"
if HOME="$home" PATH=/usr/bin:/bin "$ROOT/dev-agent-config" cli uninstall --bin-dir "$home/bin" > "$SANDBOX/conflict" 2>&1; then
  echo 'CLI uninstall removed an unowned path' >&2
  exit 1
fi
grep -qFx foreign "$home/bin/dev-agent-config"

echo 'PASS CLI: help, user-local link, idempotence, safe removal'
