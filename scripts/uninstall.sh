#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
START='# >>> dev-agent-config managed >>>'
END='# <<< dev-agent-config managed <<<'
DRY=1
[ "${1:-}" = '--apply' ] && DRY=0
[ "$#" -eq 0 ] || [ "$#" -eq 1 ] && { [ "$#" -eq 0 ] || [ "$1" = '--apply' ]; } || { echo 'Usage: uninstall.sh [--apply]' >&2; exit 2; }
BACKUP="$HOME/.agents/backups/uninstall-$(date +%Y%m%d-%H%M%S)-$$"
for file in "$HOME/AGENTS.md" "$HOME/.codex/AGENTS.md" "$HOME/.claude/CLAUDE.md" "$HOME/.gemini/GEMINI.md"; do
  [ -f "$file" ] || continue
  grep -qFx "$START" "$file" || continue
  echo "REMOVE managed section: $file"
  if [ "$DRY" -eq 0 ]; then
    mkdir -p "$BACKUP"
    cp -p "$file" "$BACKUP/$(printf '%s' "${file#"$HOME"/}" | tr '/' '_')"
    tmp="$(mktemp)"
    awk -v start="$START" -v end="$END" '
      $0 == start { inside=1; next }
      $0 == end && inside { inside=0; next }
      !inside { lines[++n]=$0 }
      END { while (n > 0 && lines[n] == "") n--; for (i=1; i<=n; i++) print lines[i] }
    ' "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
  fi
done
for path in "$HOME/.agents/skills/ponytail" "$HOME/.codex/skills/ponytail" "$HOME/.claude/skills/ponytail" "$HOME/.gemini/skills/ponytail" "$HOME/.cursor/skills/ponytail" "$HOME/.cline/skills/ponytail" "$HOME/.config/opencode/skills/ponytail"; do
  if [ -L "$path" ] && [ "$(readlink "$path")" = "$ROOT/skills/ponytail" ]; then
    echo "UNLINK: $path"
    if [ "$DRY" -eq 0 ]; then rm "$path"; fi
  fi
done
if [ "$DRY" -eq 1 ]; then echo 'Dry run only. Pass --apply to uninstall managed sections and links.'; else echo "Uninstall complete. Backups, if any: $BACKUP"; fi
