#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
JSON=0
[ "${1:-}" = --json ] && JSON=1
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != --json ]; }; then
  echo "Usage: $0 [--json]" >&2
  exit 2
fi

FAILED=0
FIRST_AGENT=1
FIRST_UNSUPPORTED=1
OS="$(uname -s 2>/dev/null || printf unknown)"
VERIFY_TMP="$(mktemp -d)"
trap 'rm -rf "$VERIFY_TMP"' EXIT

bool() { [ "$1" -eq 1 ] && printf true || printf false; }
json_string() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g; s//\\r/g'
}

instruction_status() {
  local path="$1"
  if [ -L "$path" ]; then printf symlink
  elif [ ! -e "$path" ]; then printf missing
  elif [ ! -f "$path" ]; then printf invalid-type
  elif grep -qF '# >>> dev-agent-config managed >>>' "$path" && grep -qF 'Preserve established architecture' "$path"; then printf healthy
  else printf unmanaged
  fi
}

skill_status() {
  local path="$1"
  if [ -L "$path" ]; then
    if [ ! -e "$path" ]; then printf broken-link
    elif [ "$(readlink "$path")" = "$ROOT/skills/ponytail" ] && [ -f "$path/SKILL.md" ]; then printf healthy
    else printf conflicting-link
    fi
  elif [ ! -e "$path" ]; then printf missing
  else printf unmanaged
  fi
}

skill_link_target() {
  if [ -L "$1" ]; then readlink "$1"; else printf ''; fi
}

code_intelligence_status() {
  local path="$1"
  if [ -L "$path" ]; then
    if [ "$(readlink "$path")" = "$ROOT/instructions/code-intelligence.md" ] && [ -f "$path" ]; then printf healthy
    elif [ ! -e "$path" ]; then printf broken-link
    else printf conflicting-link
    fi
  elif [ ! -e "$path" ]; then printf missing
  else printf unmanaged
  fi
}

safe_version() {
  local executable="$1" sandbox out err pid count line
  sandbox="$(mktemp -d)"
  out="$sandbox/stdout"
  err="$sandbox/stderr"
  # Some CLIs initialize caches even for --version, so isolate all writable homes.
  ( cd "$sandbox" && HOME="$sandbox" XDG_CONFIG_HOME="$sandbox/config" XDG_DATA_HOME="$sandbox/data" XDG_CACHE_HOME="$sandbox/cache" CI=1 "$executable" --version </dev/null >"$out" 2>"$err" ) &
  pid=$!
  count=0
  while kill -0 "$pid" 2>/dev/null && [ "$count" -lt 20 ]; do
    sleep 0.1
    count=$((count + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    rm -rf "$sandbox"
    printf timeout
    return
  fi
  wait "$pid" 2>/dev/null || true
  line="$(sed -n '1p' "$out")"
  [ -n "$line" ] || line="$(sed -n '1p' "$err")"
  rm -rf "$sandbox"
  [ -n "$line" ] && printf '%s' "$line" || printf unavailable
}

register_extension_directories() {
  EXTENSION_DIRS="$VERIFY_TMP/extension-directories"
  : > "$EXTENSION_DIRS"
  printf '%s\t%s\n' local-vscode "$HOME/.vscode/extensions" >> "$EXTENSION_DIRS"
  printf '%s\t%s\n' local-insiders "$HOME/.vscode-insiders/extensions" >> "$EXTENSION_DIRS"
  printf '%s\t%s\n' local-vscodium "$HOME/.vscode-oss/extensions" >> "$EXTENSION_DIRS"
  printf '%s\t%s\n' remote-vscode "$HOME/.vscode-server/extensions" >> "$EXTENSION_DIRS"
  printf '%s\t%s\n' remote-insiders "$HOME/.vscode-server-insiders/extensions" >> "$EXTENSION_DIRS"
  printf '%s\t%s\n' flatpak-vscode "$HOME/.var/app/com.visualstudio.code/data/vscode/extensions" >> "$EXTENSION_DIRS"
  if [ -n "${XDG_DATA_HOME:-}" ]; then printf '%s\t%s\n' xdg-vscode "$XDG_DATA_HOME/vscode/extensions" >> "$EXTENSION_DIRS"; fi
  if [ -n "${VSCODE_AGENT_FOLDER:-}" ]; then printf '%s\t%s\n' remote-agent "$VSCODE_AGENT_FOLDER/extensions" >> "$EXTENSION_DIRS"; fi
}

extension_directory_evidence() {
  local extension_id="$1" scope directory entry
  [ -n "$extension_id" ] || return
  while IFS="$(printf '\t')" read -r scope directory; do
    [ -d "$directory" ] && [ ! -L "$directory" ] && [ -r "$directory" ] || continue
    for entry in "$directory/$extension_id" "$directory/$extension_id"-*; do
      if [ -d "$entry" ] && [ ! -L "$entry" ] && [ -r "$entry" ]; then
        printf '%s\t%s' "$scope" "$entry"
        return
      fi
    done
  done < "$EXTENSION_DIRS"
}

discover_vscode_extensions() {
  local candidate scope directory output error pid count attempted=0
  VSCODE_CLI=''
  VSCODE_LIST_STATUS=unavailable
  VSCODE_LIST="$VERIFY_TMP/vscode-extensions"
  : > "$VSCODE_LIST"
  for candidate in code code-insiders codium; do
    VSCODE_CLI="$(command -v "$candidate" 2>/dev/null || true)"
    [ -z "$VSCODE_CLI" ] || break
  done
  [ -n "$VSCODE_CLI" ] || return

  output="$VERIFY_TMP/vscode-stdout"
  error="$VERIFY_TMP/vscode-stderr"
  : > "$output"
  while IFS="$(printf '\t')" read -r scope directory; do
    [ -d "$directory" ] && [ ! -L "$directory" ] && [ -r "$directory" ] || continue
    attempted=1
    part="$VERIFY_TMP/vscode-$scope"
    (
      cd "$VERIFY_TMP" || exit 1
      HOME="$VERIFY_TMP" XDG_CONFIG_HOME="$VERIFY_TMP/config" XDG_DATA_HOME="$VERIFY_TMP/data" XDG_CACHE_HOME="$VERIFY_TMP/cache" \
        "$VSCODE_CLI" --list-extensions --show-versions --extensions-dir "$directory" </dev/null >"$part" 2>"$error"
    ) &
    pid=$!
    count=0
    while kill -0 "$pid" 2>/dev/null && [ "$count" -lt 20 ]; do sleep 0.1; count=$((count + 1)); done
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      VSCODE_LIST_STATUS=timeout
      return
    fi
    if wait "$pid" 2>/dev/null; then cat "$part" >> "$output"; else VSCODE_LIST_STATUS=error; return; fi
  done < "$EXTENSION_DIRS"

  if [ "$attempted" -eq 0 ]; then
    (
      cd "$VERIFY_TMP" || exit 1
      HOME="$VERIFY_TMP" XDG_CONFIG_HOME="$VERIFY_TMP/config" XDG_DATA_HOME="$VERIFY_TMP/data" XDG_CACHE_HOME="$VERIFY_TMP/cache" \
        "$VSCODE_CLI" --list-extensions --show-versions </dev/null >"$output" 2>"$error"
    ) &
    pid=$!
    count=0
    while kill -0 "$pid" 2>/dev/null && [ "$count" -lt 20 ]; do sleep 0.1; count=$((count + 1)); done
    if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; VSCODE_LIST_STATUS=timeout; return; fi
    if ! wait "$pid" 2>/dev/null; then VSCODE_LIST_STATUS=error; return; fi
  fi
  tr '[:upper:]' '[:lower:]' < "$output" | sed 's/@.*$//' > "$VSCODE_LIST"
  VSCODE_LIST_STATUS=available
}

extension_listed() {
  [ "$VSCODE_LIST_STATUS" = available ] && grep -qFx "$1" "$VSCODE_LIST"
}

emit_agent() {
  local name="$1" command_name="$2" config_dir="$3" instruction="$4" skill="$5" extension_id="$6"
  local executable='' installed=0 configured=0 version=unavailable instructions skills skill_target health extension_listed_value=false extension_directory=false extension_installation=not-detected extension_evidence='' extension_scope='' extension_path=''
  executable="$(command -v "$command_name" 2>/dev/null || true)"
  if [ -n "$executable" ]; then installed=1; version="$(safe_version "$executable")"; fi
  if [ -d "$config_dir" ] || [ -e "$instruction" ] || [ -L "$instruction" ]; then configured=1; fi
  instructions="$(instruction_status "$instruction")"
  skills="$(skill_status "$skill")"
  skill_target="$(skill_link_target "$skill")"
  if [ -n "$extension_id" ]; then
    if extension_listed "$extension_id"; then extension_listed_value=true; fi
    extension_evidence="$(extension_directory_evidence "$extension_id")"
    if [ -n "$extension_evidence" ]; then
      extension_directory=true
      extension_scope="${extension_evidence%%$(printf '\t')*}"
      extension_path="${extension_evidence#*$(printf '\t')}"
    fi
    if [ "$extension_listed_value" = true ]; then extension_installation=confirmed
    elif [ "$extension_directory" = true ]; then extension_installation=directory-only
    fi
  fi
  if [ "$configured" -eq 0 ]; then
    health=not-configured
  elif [ "$instructions" = healthy ] && [ "$skills" = healthy ]; then
    health=healthy
  else
    health=incomplete
    FAILED=1
  fi

  if [ "$JSON" -eq 1 ]; then
    [ "$FIRST_AGENT" -eq 1 ] || printf ','
    FIRST_AGENT=0
    printf '\n    {"name":"%s","cli":"%s","installed":%s,"version":"%s","vscode_extension":{"id":"%s","installation":"%s","listed":%s,"directory_present":%s,"directory_scope":"%s","directory_path":"%s","active":"unverified"},"configured":%s,"configuration_health":"%s","instruction":{"path":"%s","status":"%s"},"skill":{"path":"%s","status":"%s","link_target":"%s"},"runtime_skill_activation":"unverified"}' \
      "$(json_string "$name")" "$(json_string "$command_name")" "$(bool "$installed")" "$(json_string "$version")" \
      "$(json_string "$extension_id")" "$extension_installation" "$extension_listed_value" "$extension_directory" "$(json_string "$extension_scope")" "$(json_string "$extension_path")" "$(bool "$configured")" "$health" \
      "$(json_string "$instruction")" "$instructions" "$(json_string "$skill")" "$skills" "$(json_string "$skill_target")"
  else
    printf '\n%s\n' "$name"
    printf '  installed: %s' "$(bool "$installed")"
    if [ "$installed" -eq 1 ]; then printf ' (%s; %s)' "$executable" "$version"; fi
    printf '\n  configured: %s\n' "$(bool "$configured")"
    if [ -n "$extension_id" ]; then
      printf '  VS Code extension: %s installation=%s listed=%s directory_present=%s' "$extension_id" "$extension_installation" "$extension_listed_value" "$extension_directory"
      [ -z "$extension_scope" ] || printf ' scope=%s path=%s' "$extension_scope" "$extension_path"
      printf ' active=unverified\n'
    else
      printf '  VS Code extension: not mapped\n'
    fi
    printf '  configuration health: %s\n' "$health"
    printf '  instructions: %s [%s]\n' "$instruction" "$instructions"
    printf '  skill: %s' "$skill"
    [ -z "$skill_target" ] || printf ' -> %s' "$skill_target"
    printf ' [%s]\n' "$skills"
    printf '  runtime skill activation: unverified\n'
  fi
}

emit_unsupported() {
  local name="$1" command_name="$2" config1="$3" config2="${4:-}" executable='' installed=0 configured=0
  executable="$(command -v "$command_name" 2>/dev/null || true)"
  [ -z "$executable" ] || installed=1
  if [ -e "$config1" ] || [ -L "$config1" ] || { [ -n "$config2" ] && { [ -e "$config2" ] || [ -L "$config2" ]; }; }; then configured=1; fi
  if [ "$JSON" -eq 1 ]; then
    [ "$FIRST_UNSUPPORTED" -eq 1 ] || printf ','
    FIRST_UNSUPPORTED=0
    printf '\n    {"name":"%s","installed":%s,"configured":%s,"reason":"adapter not implemented"}' \
      "$(json_string "$name")" "$(bool "$installed")" "$(bool "$configured")"
  else
    printf '  %s: installed=%s configured=%s (adapter not implemented)\n' "$name" "$(bool "$installed")" "$(bool "$configured")"
  fi
}

shared_instruction="$HOME/AGENTS.md"
shared_skill="$HOME/.agents/skills/ponytail"
shared_code_intelligence="$HOME/.agents/instructions/code-intelligence.md"
shared_instruction_status="$(instruction_status "$shared_instruction")"
shared_skill_status="$(skill_status "$shared_skill")"
shared_skill_target="$(skill_link_target "$shared_skill")"
shared_code_intelligence_status="$(code_intelligence_status "$shared_code_intelligence")"
register_extension_directories
discover_vscode_extensions
if [ "$shared_instruction_status" != healthy ] || [ "$shared_skill_status" != healthy ] || [ "$shared_code_intelligence_status" != healthy ]; then FAILED=1; fi

if [ "$JSON" -eq 1 ]; then
  printf '{\n  "operating_system":"%s",\n' "$(json_string "$OS")"
  printf '  "vscode":{"cli_path":"%s","extension_list_status":"%s"},\n' "$(json_string "$VSCODE_CLI")" "$VSCODE_LIST_STATUS"
  printf '  "shared":{"instruction":{"path":"%s","status":"%s"},"skill":{"path":"%s","status":"%s","link_target":"%s"},"code_intelligence":{"path":"%s","status":"%s"}},\n' \
    "$(json_string "$shared_instruction")" "$shared_instruction_status" "$(json_string "$shared_skill")" "$shared_skill_status" "$(json_string "$shared_skill_target")" \
    "$(json_string "$shared_code_intelligence")" "$shared_code_intelligence_status"
  printf '  "agents":['
else
  printf 'dev-agent-config verification\n'
  printf 'Operating system: %s\n' "$OS"
  if [ -n "$VSCODE_CLI" ]; then printf 'VS Code CLI: %s (extension list: %s)\n' "$VSCODE_CLI" "$VSCODE_LIST_STATUS"; else printf 'VS Code CLI: not found\n'; fi
  printf '\nShared configuration\n'
  printf '  instructions: %s [%s]\n' "$shared_instruction" "$shared_instruction_status"
  printf '  skill: %s' "$shared_skill"
  [ -z "$shared_skill_target" ] || printf ' -> %s' "$shared_skill_target"
  printf ' [%s]\n' "$shared_skill_status"
  printf '  code-intelligence instructions: %s [%s]\n' "$shared_code_intelligence" "$shared_code_intelligence_status"
fi

emit_agent Codex codex "$HOME/.codex" "$HOME/.codex/AGENTS.md" "$shared_skill" openai.chatgpt
emit_agent 'Claude Code' claude "$HOME/.claude" "$HOME/.claude/CLAUDE.md" "$HOME/.claude/skills/ponytail" anthropic.claude-code
emit_agent 'Gemini CLI' gemini "$HOME/.gemini" "$HOME/.gemini/GEMINI.md" "$HOME/.gemini/skills/ponytail" google.geminicodeassist
emit_agent OpenCode opencode "$HOME/.config/opencode" "$HOME/.config/opencode/AGENTS.md" "$HOME/.config/opencode/skills/ponytail" ''

if [ "$JSON" -eq 1 ]; then
  printf '\n  ],\n  "unsupported":['
else
  printf '\nUnsupported adapters\n'
fi
emit_unsupported Cursor cursor "$HOME/.cursor"
emit_unsupported Cline cline "$HOME/.cline" "$HOME/Documents/Cline"
emit_unsupported Antigravity antigravity "$HOME/.gemini/antigravity"

if [ "$JSON" -eq 1 ]; then
  printf '\n  ],\n  "runtime_skill_activation":"unverified",\n  "healthy":%s\n}\n' "$( [ "$FAILED" -eq 0 ] && printf true || printf false )"
else
  printf '\nRuntime skill activation: unverified (no runtime evidence collected)\n'
  if [ "$FAILED" -eq 0 ]; then printf 'PASS: configured targets are healthy\n'; else printf 'FAIL: configuration problems found\n'; fi
fi
exit "$FAILED"
