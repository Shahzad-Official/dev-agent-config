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
grep -q '"name":"Codex","cli":"codex","installed":false,"version":"unavailable","vscode_extension":.*"configured":false' "$SANDBOX/missing.json"

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
grep -q '"name":"Codex","cli":"codex","installed":true,"version":"codex 1.2.3","vscode_extension":.*"configured":true' "$SANDBOX/mixed.json"
grep -q '"name":"Gemini CLI","cli":"gemini","installed":false,"version":"unavailable","vscode_extension":.*"configured":true' "$SANDBOX/mixed.json"
grep -q '"name":"OpenCode","cli":"opencode","installed":true,"version":"opencode 4.5.6","vscode_extension":.*"configured":false' "$SANDBOX/mixed.json"
grep -q '"runtime_skill_activation":"unverified"' "$SANDBOX/mixed.json"
[ ! -e "$home/version-side-effect" ]
if command -v python3 >/dev/null 2>&1; then python3 -m json.tool "$SANDBOX/mixed.json" >/dev/null; fi

# Codex CLI and VS Code extension installation are independent signals.
home="$SANDBOX/discovery-home"
mkdir -p "$home"
HOME="$home" PATH="$SYSTEM_PATH" "$ROOT/scripts/install.sh" >/dev/null

bin="$SANDBOX/cli-only-bin"
make_cli "$bin" codex 7.0.0
HOME="$home" PATH="$bin:$SYSTEM_PATH" "$ROOT/scripts/verify.sh" --json > "$SANDBOX/cli-only.json"
grep -q '"name":"Codex","cli":"codex","installed":true' "$SANDBOX/cli-only.json"
grep -q '"id":"openai.chatgpt","installation":"not-detected","listed":false,"directory_present":false' "$SANDBOX/cli-only.json"

bin="$SANDBOX/extension-only-bin"
mkdir -p "$bin"
printf '#!/bin/sh\nprintf "openai.chatgpt@1.2.3\\n"\n' > "$bin/code"
chmod +x "$bin/code"
HOME="$home" PATH="$bin:$SYSTEM_PATH" "$ROOT/scripts/verify.sh" --json > "$SANDBOX/extension-only.json"
grep -q '"name":"Codex","cli":"codex","installed":false' "$SANDBOX/extension-only.json"
grep -q '"id":"openai.chatgpt","installation":"confirmed","listed":true,"directory_present":false.*"active":"unverified"' "$SANDBOX/extension-only.json"

bin="$SANDBOX/both-bin"
make_cli "$bin" codex 7.0.0
printf '#!/bin/sh\nprintf "openai.chatgpt@1.2.3\\n"\n' > "$bin/code"
chmod +x "$bin/code"
HOME="$home" PATH="$bin:$SYSTEM_PATH" "$ROOT/scripts/verify.sh" --json > "$SANDBOX/both.json"
grep -q '"name":"Codex","cli":"codex","installed":true' "$SANDBOX/both.json"
grep -q '"id":"openai.chatgpt","installation":"confirmed","listed":true' "$SANDBOX/both.json"

HOME="$home" PATH="$SYSTEM_PATH" "$ROOT/scripts/verify.sh" --json > "$SANDBOX/neither.json"
grep -q '"name":"Codex","cli":"codex","installed":false' "$SANDBOX/neither.json"
grep -q '"id":"openai.chatgpt","installation":"not-detected","listed":false,"directory_present":false' "$SANDBOX/neither.json"

# Directory fallback is reported as presence only, never as active or CLI-listed.
mkdir -p "$home/.vscode/extensions/openai.chatgpt-9.9.9"
HOME="$home" PATH="$SYSTEM_PATH" "$ROOT/scripts/verify.sh" --json > "$SANDBOX/directory-only.json"
grep -q '"id":"openai.chatgpt","installation":"directory-only","listed":false,"directory_present":true,"directory_scope":"local-vscode".*"active":"unverified"' "$SANDBOX/directory-only.json"

# Remote SSH, WSL, and Dev Container servers use the remote VS Code Server tree.
remote_home="$SANDBOX/remote-home"
mkdir -p "$remote_home/.vscode-server/extensions/openai.chatgpt-3.0.0"
HOME="$remote_home" PATH="$SYSTEM_PATH" "$ROOT/scripts/install.sh" >/dev/null
HOME="$remote_home" PATH="$SYSTEM_PATH" "$ROOT/scripts/verify.sh" --json > "$SANDBOX/remote.json"
grep -q '"id":"openai.chatgpt","installation":"directory-only","listed":false,"directory_present":true,"directory_scope":"remote-vscode"' "$SANDBOX/remote.json"
grep -q '"directory_path":".*\.vscode-server/extensions/openai.chatgpt-3.0.0"' "$SANDBOX/remote.json"

# Explicit remote agent folders are supported, while invalid and symlinked roots are ignored.
agent_home="$SANDBOX/agent-home"
agent_folder="$SANDBOX/custom-vscode-agent"
mkdir -p "$agent_home" "$agent_folder/extensions/openai.chatgpt-4.0.0"
HOME="$agent_home" VSCODE_AGENT_FOLDER="$agent_folder" PATH="$SYSTEM_PATH" "$ROOT/scripts/install.sh" >/dev/null
HOME="$agent_home" VSCODE_AGENT_FOLDER="$agent_folder" PATH="$SYSTEM_PATH" "$ROOT/scripts/verify.sh" --json > "$SANDBOX/agent-folder.json"
grep -q '"directory_scope":"remote-agent"' "$SANDBOX/agent-folder.json"

invalid_home="$SANDBOX/invalid-home"
foreign="$SANDBOX/foreign-extensions"
mkdir -p "$invalid_home/.vscode-server" "$foreign/openai.chatgpt-5.0.0"
ln -s "$foreign" "$invalid_home/.vscode-server/extensions"
mkdir -p "$invalid_home/.vscode"
printf 'not a directory\n' > "$invalid_home/.vscode/extensions"
HOME="$invalid_home" PATH="$SYSTEM_PATH" "$ROOT/scripts/install.sh" >/dev/null
HOME="$invalid_home" PATH="$SYSTEM_PATH" "$ROOT/scripts/verify.sh" --json > "$SANDBOX/invalid.json"
grep -q '"id":"openai.chatgpt","installation":"not-detected","listed":false,"directory_present":false' "$SANDBOX/invalid.json"

echo 'PASS verify: local/remote discovery, invalid paths, mixed installs, JSON'
