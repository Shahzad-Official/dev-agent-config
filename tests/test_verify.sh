#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
SYSTEM_PATH='/usr/bin:/bin'

make_cli() {
  local bin="$1" name="$2" version="$3"
  mkdir -p "$bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s %s"\n' "$name" "$version" > "$bin/$name"
  chmod +x "$bin/$name"
}

# Missing CLIs are not confused with absent configurations.
home="$SANDBOX/missing"
mkdir -p "$home"
HOME="$home" PATH="$SYSTEM_PATH" "$ROOT/scripts/install.sh" >/dev/null
HOME="$home" PATH="$SYSTEM_PATH" "$ROOT/scripts/verify.sh" --json > "$SANDBOX/missing.json"
grep -q '"name":"Codex","cli":"codex","installed":false,"version":"unavailable","configured":false' "$SANDBOX/missing.json"

# A healthy existing configuration remains configured even without its CLI.
home="$SANDBOX/configured"
mkdir -p "$home/.codex"
HOME="$home" PATH="$SYSTEM_PATH" "$ROOT/scripts/install.sh" >/dev/null
HOME="$home" PATH="$SYSTEM_PATH" "$ROOT/scripts/verify.sh" > "$SANDBOX/configured.txt"
grep -q 'installed: false' "$SANDBOX/configured.txt"
grep -q 'configuration health: healthy' "$SANDBOX/configured.txt"

# Broken managed skill links are reported and make verification fail.
home="$SANDBOX/broken"
mkdir -p "$home"
HOME="$home" PATH="$SYSTEM_PATH" "$ROOT/scripts/install.sh" >/dev/null
rm "$home/.agents/skills/ponytail"
ln -s "$SANDBOX/does-not-exist" "$home/.agents/skills/ponytail"
if HOME="$home" PATH="$SYSTEM_PATH" "$ROOT/scripts/verify.sh" --json > "$SANDBOX/broken.json"; then
  echo 'Broken skill link passed verification' >&2
  exit 1
fi
grep -q '"status":"broken-link"' "$SANDBOX/broken.json"
grep -q '"healthy":false' "$SANDBOX/broken.json"

# Mixed CLI/config installations and versions are detected independently.
home="$SANDBOX/mixed"
bin="$SANDBOX/bin"
mkdir -p "$home/.codex" "$home/.gemini"
make_cli "$bin" codex 1.2.3
make_cli "$bin" opencode 4.5.6
# Simulate a CLI that writes during --version; verification must contain the write.
printf '#!/bin/sh\nmkdir -p "$HOME/version-side-effect"\nprintf "opencode 4.5.6\\n"\n' > "$bin/opencode"
chmod +x "$bin/opencode"
HOME="$home" PATH="$bin:$SYSTEM_PATH" "$ROOT/scripts/install.sh" >/dev/null
HOME="$home" PATH="$bin:$SYSTEM_PATH" "$ROOT/scripts/verify.sh" --json > "$SANDBOX/mixed.json"
grep -q '"name":"Codex","cli":"codex","installed":true,"version":"codex 1.2.3","configured":true' "$SANDBOX/mixed.json"
grep -q '"name":"Gemini CLI","cli":"gemini","installed":false,"version":"unavailable","configured":true' "$SANDBOX/mixed.json"
grep -q '"name":"OpenCode","cli":"opencode","installed":true,"version":"opencode 4.5.6","configured":false' "$SANDBOX/mixed.json"
grep -q '"runtime_skill_activation":"unverified"' "$SANDBOX/mixed.json"
[ ! -e "$home/version-side-effect" ]
if command -v python3 >/dev/null 2>&1; then python3 -m json.tool "$SANDBOX/mixed.json" >/dev/null; fi

echo 'PASS verify: missing CLIs, existing configs, broken links, mixed installations, JSON'
