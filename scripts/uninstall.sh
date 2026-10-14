#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$ROOT/scripts/lib/config.sh"

DRY=1
[ "${1:-}" = --apply ] && DRY=0
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != --apply ]; }; then fail 'Usage: uninstall.sh [--apply]'; fi

# Refuse unsafe paths before removing the first managed entry.
check_state_target
check_instruction_target "$HOME/AGENTS.md"
check_skill_target "$HOME/.agents/skills/ponytail"
check_skill_target "$HOME/.agents/instructions/code-intelligence.md"
check_instruction_target "$HOME/.codex/AGENTS.md"
check_instruction_target "$HOME/.claude/CLAUDE.md"
check_skill_target "$HOME/.claude/skills/ponytail"
check_instruction_target "$HOME/.gemini/GEMINI.md"
check_skill_target "$HOME/.gemini/skills/ponytail"
check_instruction_target "$HOME/.config/opencode/AGENTS.md"
check_skill_target "$HOME/.config/opencode/skills/ponytail"
init_transaction uninstall "$DRY"

remove_instructions() {
  local target="$1" type tmp write_tmp
  validate_target "$target"
  type="$(path_type "$target")"
  [ "$type" = missing ] && return
  [ "$type" != symlink ] || fail "Refusing instruction symlink: $target"
  [ "$type" = file ] || fail "Unsupported instruction target: $target ($type)"
  grep -qFx "$START" "$target" || return
  say "$( [ "$DRY" -eq 1 ] && printf WOULD_REMOVE || printf REMOVED ) managed instructions: $target"
  if [ "$DRY" -eq 0 ]; then
    record_and_prepare "$target"
    tmp="$(mktemp)"
    strip_managed "$target" > "$tmp"
    if [ -s "$tmp" ]; then
      write_tmp="$(mktemp "$(dirname "$target")/.dev-agent-config.XXXXXX")"
      cat "$tmp" > "$write_tmp"
      chmod "$(stat_mode "$target")" "$write_tmp"
      mv "$write_tmp" "$target"
    else
      rm "$target"
    fi
    rm -f "$tmp"
  fi
  CHANGES=$((CHANGES + 1))
}

remove_skill() {
  local target="$1" origin="$2"
  validate_target "$target"
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$origin" ]; then
    say "$( [ "$DRY" -eq 1 ] && printf WOULD_UNLINK || printf UNLINKED ) skill: $target"
    if [ "$DRY" -eq 0 ]; then record_and_prepare "$target"; rm "$target"; fi
    CHANGES=$((CHANGES + 1))
  fi
}

remove_instruction_link() {
  local target="$1" origin="$2"
  validate_target "$target"
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$origin" ]; then
    say "$( [ "$DRY" -eq 1 ] && printf WOULD_UNLINK || printf UNLINKED ) code-intelligence instructions: $target"
    if [ "$DRY" -eq 0 ]; then record_and_prepare "$target"; rm "$target"; fi
    CHANGES=$((CHANGES + 1))
  fi
}

remove_instructions "$HOME/AGENTS.md"
remove_skill "$HOME/.agents/skills/ponytail" "$ROOT/skills/ponytail"
remove_instruction_link "$HOME/.agents/instructions/code-intelligence.md" "$ROOT/instructions/code-intelligence.md"
remove_instructions "$HOME/.codex/AGENTS.md"
remove_instructions "$HOME/.claude/CLAUDE.md"
remove_skill "$HOME/.claude/skills/ponytail" "$ROOT/skills/ponytail"
remove_instructions "$HOME/.gemini/GEMINI.md"
remove_skill "$HOME/.gemini/skills/ponytail" "$ROOT/skills/ponytail"
remove_instructions "$HOME/.config/opencode/AGENTS.md"
remove_skill "$HOME/.config/opencode/skills/ponytail" "$ROOT/skills/ponytail"
finish_transaction
[ "$DRY" -eq 0 ] || say 'Dry run only. Pass --apply to uninstall.'
