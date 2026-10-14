#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
HOME="$SANDBOX/home"
target="$HOME/.agents/instructions/code-intelligence.md"
source="$ROOT/instructions/code-intelligence.md"
mkdir -p "$HOME"
mkdir -p "$HOME/.codex" "$HOME/.claude" "$HOME/.gemini" "$HOME/.config/opencode"

HOME="$HOME" "$ROOT/scripts/install.sh" --dry-run > "$SANDBOX/dry-run"
[ ! -e "$target" ]
grep -q 'WOULD_LINK code-intelligence instructions' "$SANDBOX/dry-run"

# Fresh install gives every supported agent one stable, shared path to the same source.
HOME="$HOME" "$ROOT/scripts/install.sh" >/dev/null
[ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]
grep -qF '~/.agents/instructions/code-intelligence.md' "$HOME/AGENTS.md"
grep -q 'otherwise skip it' "$HOME/AGENTS.md"
for instruction_file in "$HOME/.codex/AGENTS.md" "$HOME/.claude/CLAUDE.md" "$HOME/.gemini/GEMINI.md" "$HOME/.config/opencode/AGENTS.md"; do
  grep -qF '~/.agents/instructions/code-intelligence.md' "$instruction_file"
done
external_project="$SANDBOX/another project"
mkdir -p "$external_project"
(cd "$external_project" && [ -f "$HOME/.agents/instructions/code-intelligence.md" ] && grep -q 'Use Codebase Memory MCP' "$HOME/.agents/instructions/code-intelligence.md")
HOME="$HOME" "$ROOT/scripts/verify.sh" > "$SANDBOX/verify"
grep -q 'code-intelligence instructions: .*\[healthy\]' "$SANDBOX/verify"
json="$(HOME="$HOME" "$ROOT/scripts/verify.sh" --json)"
grep -q '"code_intelligence".*"status":"healthy"' <<< "$json"

# Repeated install updates through the shared symlink without creating a second source.
before="$(find "$HOME/.agents/instructions" -maxdepth 1 -type f | wc -l | tr -d ' ')"
HOME="$HOME" "$ROOT/scripts/install.sh" >/dev/null
after="$(find "$HOME/.agents/instructions" -maxdepth 1 -type f | wc -l | tr -d ' ')"
[ "$before" = "$after" ]

# Merge preserves a user file at the managed path; replace backs it up and rollback restores it.
rm "$target"
printf 'user-owned\n' > "$target"
HOME="$HOME" "$ROOT/scripts/install.sh" --mode=merge >/dev/null
[ -f "$target" ] && [ ! -L "$target" ]
grep -qFx user-owned "$target"
HOME="$HOME" "$ROOT/scripts/install.sh" --mode=replace >/dev/null
[ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]
backup="$(sed -n '1p' "$HOME/.agents/dev-agent-config/last-backup")"
HOME="$HOME" "$ROOT/scripts/rollback.sh" "$backup" >/dev/null
[ -f "$target" ] && [ ! -L "$target" ]
grep -qFx user-owned "$target"

# Replace repairs a broken conflicting link; rollback preserves the original link without following it.
rm "$target"
ln -s "$SANDBOX/missing-original" "$target"
if HOME="$HOME" "$ROOT/scripts/verify.sh" > "$SANDBOX/broken-link-verify" 2>&1; then
  echo 'Broken code-intelligence link passed verification' >&2
  exit 1
fi
grep -q 'code-intelligence.*\[broken-link\]' "$SANDBOX/broken-link-verify"
HOME="$HOME" "$ROOT/scripts/install.sh" --mode=replace >/dev/null
[ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]
backup="$(sed -n '1p' "$HOME/.agents/dev-agent-config/last-backup")"
HOME="$HOME" "$ROOT/scripts/rollback.sh" "$backup" >/dev/null
[ -L "$target" ] && [ "$(readlink "$target")" = "$SANDBOX/missing-original" ]
[ ! -e "$SANDBOX/missing-original" ]

# Uninstall removes only this checkout's symlink; a conflicting user path survives.
HOME="$HOME" "$ROOT/scripts/install.sh" --mode=replace >/dev/null
HOME="$HOME" "$ROOT/scripts/uninstall.sh" --apply >/dev/null
[ ! -e "$target" ] && [ ! -L "$target" ]
printf 'user-owned-again\n' > "$target"
HOME="$HOME" "$ROOT/scripts/uninstall.sh" --apply >/dev/null
grep -qFx user-owned-again "$target"

echo 'PASS code intelligence: install, shared discovery, verify, update, rollback, uninstall, broken-link recovery'
