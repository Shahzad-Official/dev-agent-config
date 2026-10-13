#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SANDBOX="$(mktemp -d)"
SYSTEM_PATH='/usr/bin:/bin'
trap 'rm -rf "$SANDBOX"' EXIT

new_home() {
  local name="$1" home
  home="$SANDBOX/$name"
  mkdir -p "$home/.codex" "$home/.claude" "$home/.gemini" "$home/.config/opencode"
  printf '%s\n' "$home"
}

assert_contains() { grep -qF "$2" "$1" || { echo "Expected '$2' in $1" >&2; exit 1; }; }
assert_not_contains() { ! grep -qF "$2" "$1" || { echo "Unexpected '$2' in $1" >&2; exit 1; }; }

# Fresh install and all verified instruction adapters.
home="$(new_home fresh)"
HOME="$home" "$ROOT/scripts/install.sh" --dry-run >/dev/null
[ ! -e "$home/AGENTS.md" ]
HOME="$home" "$ROOT/scripts/install.sh" >/dev/null
for file in "$home/AGENTS.md" "$home/.codex/AGENTS.md" "$home/.claude/CLAUDE.md" "$home/.gemini/GEMINI.md" "$home/.config/opencode/AGENTS.md"; do
  assert_contains "$file" 'Preserve established architecture'
done
HOME="$home" PATH="$SYSTEM_PATH" "$ROOT/scripts/verify.sh" >/dev/null

# Merge preserves existing instructions and an existing same-name skill.
home="$(new_home merge)"
printf 'Keep my rule.\n' > "$home/.codex/AGENTS.md"
mkdir -p "$home/.agents/skills/ponytail"
printf 'local skill\n' > "$home/.agents/skills/ponytail/SKILL.md"
HOME="$home" "$ROOT/scripts/install.sh" --mode=merge >/dev/null
assert_contains "$home/.codex/AGENTS.md" 'Keep my rule.'
assert_contains "$home/.agents/skills/ponytail/SKILL.md" 'local skill'

# Replace removes old instructions/skill content, creates a manifest, and rolls back exactly.
home="$(new_home replace)"
printf 'Old private rule.\n' > "$home/.claude/CLAUDE.md"
mkdir -p "$home/.claude/skills/ponytail"
printf 'old skill\n' > "$home/.claude/skills/ponytail/SKILL.md"
chmod 600 "$home/.claude/CLAUDE.md"
HOME="$home" "$ROOT/scripts/install.sh" --mode=replace >/dev/null
assert_not_contains "$home/.claude/CLAUDE.md" 'Old private rule.'
[ -L "$home/.claude/skills/ponytail" ]
[ "$(stat -f '%Lp' "$home/.claude/CLAUDE.md" 2>/dev/null || stat -c '%a' "$home/.claude/CLAUDE.md")" = 600 ]
backup="$(sed -n '1p' "$home/.agents/dev-agent-config/last-backup")"
[ -f "$backup/manifest.tsv" ]
HOME="$home" "$ROOT/scripts/rollback.sh" "$backup" >/dev/null
assert_contains "$home/.claude/CLAUDE.md" 'Old private rule.'
[ -f "$home/.claude/skills/ponytail/SKILL.md" ] && [ ! -L "$home/.claude/skills/ponytail" ]

# Repeated installation is idempotent and creates no second transaction.
home="$(new_home repeat)"
HOME="$home" "$ROOT/scripts/install.sh" >/dev/null
cp "$home/AGENTS.md" "$SANDBOX/first-agents.md"
before="$(find "$home/.agents/dev-agent-config/backups" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
HOME="$home" "$ROOT/scripts/install.sh" >/dev/null
cmp -s "$home/AGENTS.md" "$SANDBOX/first-agents.md"
after="$(find "$home/.agents/dev-agent-config/backups" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
[ "$before" = "$after" ]

# Instruction symlinks and symlinked parents are refused before any mutation.
home="$(new_home symlink-file)"
printf 'outside\n' > "$SANDBOX/outside"
ln -s "$SANDBOX/outside" "$home/.codex/AGENTS.md"
if HOME="$home" "$ROOT/scripts/install.sh" >/dev/null 2>&1; then echo 'Instruction symlink was accepted' >&2; exit 1; fi
[ ! -e "$home/AGENTS.md" ]
assert_contains "$SANDBOX/outside" outside

home="$SANDBOX/symlink-parent"
mkdir -p "$home" "$SANDBOX/foreign-codex"
ln -s "$SANDBOX/foreign-codex" "$home/.codex"
if HOME="$home" "$ROOT/scripts/install.sh" >/dev/null 2>&1; then echo 'Symlinked parent was accepted' >&2; exit 1; fi
[ ! -e "$home/AGENTS.md" ]

# A conflicting skill link is preserved by merge and replaced without following it.
home="$(new_home symlink-skill)"
mkdir -p "$SANDBOX/foreign-skill" "$home/.agents/skills"
printf 'foreign\n' > "$SANDBOX/foreign-skill/SKILL.md"
ln -s "$SANDBOX/foreign-skill" "$home/.agents/skills/ponytail"
HOME="$home" "$ROOT/scripts/install.sh" --mode=merge >/dev/null
[ "$(readlink "$home/.agents/skills/ponytail")" = "$SANDBOX/foreign-skill" ]
HOME="$home" "$ROOT/scripts/install.sh" --mode=replace >/dev/null
[ "$(readlink "$home/.agents/skills/ponytail")" = "$ROOT/skills/ponytail" ]
assert_contains "$SANDBOX/foreign-skill/SKILL.md" foreign
backup="$(sed -n '1p' "$home/.agents/dev-agent-config/last-backup")"
HOME="$home" "$ROOT/scripts/rollback.sh" "$backup" >/dev/null
[ "$(readlink "$home/.agents/skills/ponytail")" = "$SANDBOX/foreign-skill" ]

# Uninstall preserves unrelated text and can itself be rolled back.
home="$(new_home uninstall)"
printf 'Keep this.\n' > "$home/AGENTS.md"
HOME="$home" "$ROOT/scripts/install.sh" >/dev/null
HOME="$home" "$ROOT/scripts/uninstall.sh" --apply >/dev/null
assert_contains "$home/AGENTS.md" 'Keep this.'
assert_not_contains "$home/AGENTS.md" '# >>> dev-agent-config managed >>>'
[ ! -L "$home/.agents/skills/ponytail" ]
uninstall_backup="$(sed -n '1p' "$home/.agents/dev-agent-config/last-backup")"
HOME="$home" "$ROOT/scripts/rollback.sh" "$uninstall_backup" >/dev/null
assert_contains "$home/AGENTS.md" '# >>> dev-agent-config managed >>>'

# Benchmark preparation is isolated and leaves the source untouched.
fixture="$SANDBOX/fixture"
mkdir -p "$fixture"
printf 'fixture\n' > "$fixture/file.txt"
HOME="$SANDBOX/unused-home" "$ROOT/scripts/benchmark.sh" "$fixture" "$SANDBOX/benchmark" >/dev/null
[ -f "$SANDBOX/benchmark/default/workspace/file.txt" ]
[ ! -e "$SANDBOX/benchmark/default/home/AGENTS.md" ]
[ -f "$SANDBOX/benchmark/rules/home/AGENTS.md" ]
[ ! -e "$SANDBOX/benchmark/rules/home/.agents/skills/ponytail" ]
[ -L "$SANDBOX/benchmark/rules-ponytail/home/.agents/skills/ponytail" ]
assert_contains "$fixture/file.txt" fixture

echo 'PASS: fresh, merge, replace, repeat, symlink safety, rollback, uninstall, adapters, benchmark isolation'
