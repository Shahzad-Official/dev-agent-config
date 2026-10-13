#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$ROOT/scripts/lib/config.sh"

DRY=0
BACKUP=''
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    *) [ -z "$BACKUP" ] || fail "Usage: $0 [--dry-run] [BACKUP_DIR]"; BACKUP="$arg" ;;
  esac
done
if [ -z "$BACKUP" ]; then
  state="$HOME/.agents/dev-agent-config/last-backup"
  [ -f "$state" ] && [ ! -L "$state" ] || fail 'No safe last-backup record found'
  BACKUP="$(sed -n '1p' "$state")"
fi
case "$BACKUP" in "$HOME/.agents/dev-agent-config/backups/"*) ;; *) fail "Invalid backup path: $BACKUP" ;; esac
[ -f "$BACKUP/manifest.tsv" ] || fail "Missing backup manifest: $BACKUP"

SAFETY="$HOME/.agents/dev-agent-config/backups/rollback-$(date +%Y%m%d-%H%M%S)-$$"

tail -n +2 "$BACKUP/manifest.tsv" | while IFS="$(printf '\t')" read -r type target saved; do
  validate_target "$target"
  current="$(path_type "$target")"
  say "$( [ "$DRY" -eq 1 ] && printf WOULD_RESTORE || printf RESTORED ) $target ($type)"
  [ "$DRY" -eq 0 ] || continue
  if [ "$current" != missing ]; then
    recovery="$SAFETY/current/${target#"$HOME"/}"
    mkdir -p "$(dirname "$recovery")"
    cp -a "$target" "$recovery"
  fi
  if [ "$current" != missing ]; then rm -rf "$target"; fi
  if [ "$type" != missing ]; then
    mkdir -p "$(dirname "$target")"
    cp -a "$saved" "$target"
  fi
done
say "Rollback complete: $BACKUP"
if [ "$DRY" -eq 0 ] && [ -d "$SAFETY" ]; then say "Pre-rollback safety copy: $SAFETY"; fi
