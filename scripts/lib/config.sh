#!/usr/bin/env bash

START='# >>> dev-agent-config managed >>>'
END='# <<< dev-agent-config managed <<<'
CHANGES=0
BACKUP=''
MANIFEST=''
DRY=0

say() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

path_type() {
  if [ -L "$1" ]; then printf symlink
  elif [ -f "$1" ]; then printf file
  elif [ -d "$1" ]; then printf directory
  elif [ -e "$1" ]; then printf other
  else printf missing; fi
}

validate_target() {
  local target="$1" parent current rest part
  case "$target" in "$HOME"/*) ;; *) fail "Target is outside HOME: $target" ;; esac
  parent="$(dirname "$target")"
  current="$HOME"
  rest="${parent#"$HOME"/}"
  [ "$parent" = "$HOME" ] && return
  while [ -n "$rest" ]; do
    part="${rest%%/*}"
    current="$current/$part"
    [ ! -L "$current" ] || fail "Refusing symlinked parent: $current"
    [ ! -e "$current" ] || [ -d "$current" ] || fail "Parent is not a directory: $current"
    [ "$rest" = "$part" ] && break
    rest="${rest#*/}"
  done
}

init_transaction() {
  DRY="$2"
  BACKUP="$HOME/.agents/dev-agent-config/backups/$(date +%Y%m%d-%H%M%S)-$$"
  MANIFEST="$BACKUP/manifest.tsv"
  say "Mode: $1"
  [ "$DRY" -eq 0 ] || say 'Dry run: no files will change'
}

backup_target() {
  local target="$1" type rel saved
  type="$(path_type "$target")"
  rel="${target#"$HOME"/}"
  saved="$BACKUP/original/$rel"
  mkdir -p "$(dirname "$saved")"
  if [ "$type" != missing ]; then cp -a "$target" "$saved"; fi
  printf '%s\t%s\t%s\n' "$type" "$target" "$saved" >> "$MANIFEST"
}

record_and_prepare() {
  local target="$1"
  validate_target "$target"
  [ "$DRY" -eq 0 ] || return
  mkdir -p "$BACKUP" "$(dirname "$target")"
  [ -f "$MANIFEST" ] || printf 'type\ttarget\tbackup\n' > "$MANIFEST"
  backup_target "$target"
}

strip_managed() {
  awk -v start="$START" -v end="$END" '
    $0 == start { inside=1; next }
    $0 == end && inside { inside=0; next }
    !inside { lines[++n]=$0 }
    END { while (n > 0 && lines[n] == "") n--; for (i=1; i<=n; i++) print lines[i] }
  ' "$1"
}

build_instruction_file() {
  local target="$1" mode="$2" output="$3"
  if [ "$mode" = merge ] && [ -f "$target" ]; then strip_managed "$target" > "$output"; fi
  if [ -s "$output" ]; then printf '\n' >> "$output"; fi
  printf '%s\n' "$START" >> "$output"
  cat "$ROOT/AGENTS.md" >> "$output"
  printf '%s\n' "$END" >> "$output"
}

stat_mode() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then stat -f '%Lp' "$1"; else stat -c '%a' "$1"; fi
}

check_instruction_target() {
  local target="$1" type
  validate_target "$target"
  type="$(path_type "$target")"
  [ "$type" != symlink ] || fail "Refusing instruction symlink: $target"
  [ "$type" = missing ] || [ "$type" = file ] || fail "Unsupported instruction target: $target ($type)"
}

check_skill_target() {
  local target="$1" type
  validate_target "$target"
  type="$(path_type "$target")"
  [ "$type" != other ] || fail "Unsupported skill target: $target ($type)"
}

check_state_target() {
  local target="$HOME/.agents/dev-agent-config/last-backup" type
  validate_target "$target"
  type="$(path_type "$target")"
  [ "$type" != symlink ] || fail "Refusing symlinked state file: $target"
  [ "$type" = missing ] || [ "$type" = file ] || fail "Unsupported state target: $target ($type)"
}

install_instructions() {
  local target="$1" mode="$2" type tmp write_tmp
  check_instruction_target "$target"
  type="$(path_type "$target")"
  tmp="$(mktemp)"
  build_instruction_file "$target" "$mode" "$tmp"
  if [ "$type" = file ] && cmp -s "$target" "$tmp"; then
    say "UNCHANGED instructions: $target"
    rm -f "$tmp"
    return
  fi
  say "$( [ "$DRY" -eq 1 ] && printf WOULD_UPDATE || printf UPDATED ) instructions: $target"
  if [ "$DRY" -eq 0 ]; then
    record_and_prepare "$target"
    write_tmp="$(mktemp "$(dirname "$target")/.dev-agent-config.XXXXXX")"
    cat "$tmp" > "$write_tmp"
    if [ "$type" = file ]; then chmod "$(stat_mode "$target")" "$write_tmp"; else chmod 644 "$write_tmp"; fi
    mv "$write_tmp" "$target"
  fi
  rm -f "$tmp"
  CHANGES=$((CHANGES + 1))
}

install_skill() {
  local destination="$1" origin="$2" mode="$3" type
  check_skill_target "$destination"
  type="$(path_type "$destination")"
  if [ "$type" = symlink ] && [ "$(readlink "$destination")" = "$origin" ]; then
    say "UNCHANGED skill: $destination"
    return
  fi
  if [ "$type" != missing ] && [ "$mode" = merge ]; then
    say "PRESERVED existing skill: $destination"
    return
  fi
  say "$( [ "$DRY" -eq 1 ] && printf WOULD_LINK || printf LINKED ) skill: $destination"
  if [ "$DRY" -eq 0 ]; then
    record_and_prepare "$destination"
    if [ "$type" != missing ]; then rm -rf "$destination"; fi
    ln -s "$origin" "$destination"
  fi
  CHANGES=$((CHANGES + 1))
}

finish_transaction() {
  local state="$HOME/.agents/dev-agent-config/last-backup"
  say "Changes: $CHANGES"
  if [ "$DRY" -eq 0 ] && [ "$CHANGES" -gt 0 ]; then
    printf '%s\n' "$BACKUP" > "$state"
    say "Backup: $BACKUP"
    say "Rollback: $ROOT/scripts/rollback.sh '$BACKUP'"
  fi
  say 'Installed skills are discoverable; activation must be verified in an agent session.'
}
