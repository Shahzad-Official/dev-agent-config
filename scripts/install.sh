#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$ROOT/scripts/lib/config.sh"

MODE=merge
DRY=0
for arg in "$@"; do
  case "$arg" in
    --mode=merge) MODE=merge ;;
    --mode=replace) MODE=replace ;;
    --dry-run) DRY=1 ;;
    *) fail "Usage: $0 [--mode=merge|--mode=replace] [--dry-run]" ;;
  esac
done

[ -f "$ROOT/AGENTS.md" ] || fail "Missing canonical AGENTS.md"
[ -f "$ROOT/skills/ponytail/SKILL.md" ] || fail "Missing Ponytail skill"
[ -f "$ROOT/instructions/code-intelligence.md" ] || fail "Missing code-intelligence instructions"

# Validate every selected path before making the first change.
check_instruction_target "$HOME/AGENTS.md"
check_skill_target "$HOME/.agents/skills/ponytail"
check_skill_target "$HOME/.agents/instructions/code-intelligence.md"
check_state_target
if [ -d "$HOME/.codex" ]; then check_instruction_target "$HOME/.codex/AGENTS.md"; fi
if [ -d "$HOME/.claude" ]; then check_instruction_target "$HOME/.claude/CLAUDE.md"; check_skill_target "$HOME/.claude/skills/ponytail"; fi
if [ -d "$HOME/.gemini" ]; then check_instruction_target "$HOME/.gemini/GEMINI.md"; check_skill_target "$HOME/.gemini/skills/ponytail"; fi
if [ -d "$HOME/.config/opencode" ]; then check_instruction_target "$HOME/.config/opencode/AGENTS.md"; check_skill_target "$HOME/.config/opencode/skills/ponytail"; fi
init_transaction "$MODE" "$DRY"

install_instructions "$HOME/AGENTS.md" "$MODE"
install_skill "$HOME/.agents/skills/ponytail" "$ROOT/skills/ponytail" "$MODE"
install_instruction_link "$HOME/.agents/instructions/code-intelligence.md" "$ROOT/instructions/code-intelligence.md" "$MODE"

# A detected config directory is the only opt-in needed for an agent adapter.
if [ -d "$HOME/.codex" ]; then install_instructions "$HOME/.codex/AGENTS.md" "$MODE"; fi
if [ -d "$HOME/.claude" ]; then
  install_instructions "$HOME/.claude/CLAUDE.md" "$MODE"
  install_skill "$HOME/.claude/skills/ponytail" "$ROOT/skills/ponytail" "$MODE"
fi
if [ -d "$HOME/.gemini" ]; then
  install_instructions "$HOME/.gemini/GEMINI.md" "$MODE"
  install_skill "$HOME/.gemini/skills/ponytail" "$ROOT/skills/ponytail" "$MODE"
fi
if [ -d "$HOME/.config/opencode" ]; then
  install_instructions "$HOME/.config/opencode/AGENTS.md" "$MODE"
  install_skill "$HOME/.config/opencode/skills/ponytail" "$ROOT/skills/ponytail" "$MODE"
fi
finish_transaction
