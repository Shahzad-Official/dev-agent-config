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
for agent in codex claude gemini; do
  [ -d "$HOME/.$agent" ] || continue
  case "$agent" in
    codex) check_rules "$HOME/.codex/AGENTS.md" ;;
    claude) check_rules "$HOME/.claude/CLAUDE.md" ;;
    gemini) check_rules "$HOME/.gemini/GEMINI.md" ;;
  esac
  check_skill "$HOME/.$agent/skills/ponytail"
done
for agent in cursor cline; do
  [ -d "$HOME/.$agent" ] || continue
  check_skill "$HOME/.$agent/skills/ponytail"
done
if [ -d "$HOME/.config/opencode" ]; then
  check_skill "$HOME/.config/opencode/skills/ponytail"
fi
if [ "$failed" -eq 0 ]; then echo 'PASS: filesystem checks complete'; else echo 'FAIL: filesystem checks'; fi
echo 'NOTE: Runtime loading and automatic skill invocation require a fresh agent session.'
exit "$failed"
