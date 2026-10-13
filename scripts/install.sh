#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    *) echo "Usage: $0 [--dry-run]" >&2; exit 2 ;;
  esac
done

START='# >>> dev-agent-config managed >>>'
END='# <<< dev-agent-config managed <<<'
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.agents/backups/$STAMP-$$"
CHANGES=0

say() { printf '%s\n' "$*"; }
perform() { if [ "$DRY" -eq 0 ]; then "$@"; fi; }

# Managed sections preserve the user's existing surrounding instructions.
update_instructions() {
  local target="$1" tmp base
  tmp="$(mktemp)"
  if [ -f "$target" ]; then
    awk -v start="$START" -v end="$END" '
      $0 == start { inside=1; next }
      $0 == end && inside { inside=0; next }
      !inside { lines[++n]=$0 }
      END { while (n > 0 && lines[n] == "") n--; for (i=1; i<=n; i++) print lines[i] }
    ' "$target" > "$tmp"
  fi
  # Append without assuming other agents understand Markdown include directives.
  { printf '\n%s\n' "$START"; cat "$ROOT/AGENTS.md"; printf '%s\n' "$END"; } >> "$tmp"
  if [ -f "$target" ] && cmp -s "$target" "$tmp"; then
    say "UNCHANGED instructions: $target"
  else
    say "$( [ "$DRY" -eq 1 ] && echo WOULD_UPDATE || echo UPDATED ) instructions: $target"
    if [ "$DRY" -eq 0 ]; then
      mkdir -p "$(dirname "$target")" "$BACKUP"
      if [ -e "$target" ]; then
        base="$(printf '%s' "${target#"$HOME"/}" | tr '/' '_')"
        cp -p "$target" "$BACKUP/$base"
      fi
      cat "$tmp" > "$target"
    fi
    CHANGES=$((CHANGES + 1))
  fi
  rm -f "$tmp"
}

link_skill() {
  local destination="$1" origin="$2"
  if [ -L "$destination" ] && [ "$(readlink "$destination")" = "$origin" ]; then
    say "UNCHANGED skill: $destination"
  elif [ -e "$destination" ] || [ -L "$destination" ]; then
    say "SKIPPED existing skill: $destination (review manually)"
  else
    say "$( [ "$DRY" -eq 1 ] && echo WOULD_LINK || echo LINKED ) skill: $destination"
    perform mkdir -p "$(dirname "$destination")"
    perform ln -s "$origin" "$destination"
    CHANGES=$((CHANGES + 1))
  fi
}

if [ ! -f "$ROOT/skills/ponytail/SKILL.md" ]; then
  echo 'Missing repository skill' >&2; exit 1
fi

# The ~/.agents directory is a public skill discovery location, not the source.
link_skill "$HOME/.agents/skills/ponytail" "$ROOT/skills/ponytail"
update_instructions "$HOME/AGENTS.md"

# Only integrate agents with an existing config directory: no unused scaffolding.
if [ -d "$HOME/.codex" ]; then
  update_instructions "$HOME/.codex/AGENTS.md"
  link_skill "$HOME/.codex/skills/ponytail" "$ROOT/skills/ponytail"
fi
if [ -d "$HOME/.claude" ]; then
  update_instructions "$HOME/.claude/CLAUDE.md"
  link_skill "$HOME/.claude/skills/ponytail" "$ROOT/skills/ponytail"
fi
if [ -d "$HOME/.gemini" ]; then
  update_instructions "$HOME/.gemini/GEMINI.md"
  link_skill "$HOME/.gemini/skills/ponytail" "$ROOT/skills/ponytail"
fi
if [ -d "$HOME/.cursor" ]; then
  link_skill "$HOME/.cursor/skills/ponytail" "$ROOT/skills/ponytail"
fi
if [ -d "$HOME/.cline" ]; then
  link_skill "$HOME/.cline/skills/ponytail" "$ROOT/skills/ponytail"
fi
if [ -d "$HOME/.config/opencode" ]; then
  link_skill "$HOME/.config/opencode/skills/ponytail" "$ROOT/skills/ponytail"
fi
say "Changes: $CHANGES"
if [ "$DRY" -eq 0 ] && [ -d "$BACKUP" ]; then say "Backups: $BACKUP"; fi
say 'Skill accessibility does not confirm automatic activation; test in each agent.'
