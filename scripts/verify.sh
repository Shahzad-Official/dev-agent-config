#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0
check_rules() {
  local file="$1"
  if [ -f "$file" ] && grep -qF '# >>> dev-agent-config managed >>>' "$file" && grep -qF 'Preserve established architecture' "$file"; then
    echo "PASS rules: $file"
  else
    echo "FAIL rules: $file"; failed=1
  fi
}
check_skill() {
  local path="$1"
  if [ -f "$path/SKILL.md" ]; then
    echo "PASS accessible skill: $path"
  else
    echo "FAIL accessible skill: $path"; failed=1
  fi
}
check_rules "$HOME/AGENTS.md"
check_skill "$HOME/.agents/skills/ponytail"
if [ -d "$HOME/.codex" ]; then check_rules "$HOME/.codex/AGENTS.md"; fi
if [ -d "$HOME/.claude" ]; then check_rules "$HOME/.claude/CLAUDE.md"; check_skill "$HOME/.claude/skills/ponytail"; fi
if [ -d "$HOME/.gemini" ]; then check_rules "$HOME/.gemini/GEMINI.md"; check_skill "$HOME/.gemini/skills/ponytail"; fi
if [ -d "$HOME/.config/opencode" ]; then
  check_rules "$HOME/.config/opencode/AGENTS.md"
  check_skill "$HOME/.config/opencode/skills/ponytail"
fi
if [ "$failed" -eq 0 ]; then echo 'PASS: filesystem checks complete'; else echo 'FAIL: filesystem checks'; fi
echo 'NOTE: Runtime loading and automatic skill invocation require a fresh agent session.'
exit "$failed"
