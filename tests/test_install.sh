#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME"' EXIT
mkdir -p "$FAKE_HOME/.codex/skills" "$FAKE_HOME/.claude/skills"
printf 'Keep my custom home rules.\n' > "$FAKE_HOME/AGENTS.md"
printf 'Keep my Codex rules.\n' > "$FAKE_HOME/.codex/AGENTS.md"
printf 'Keep my Claude rules.\n' > "$FAKE_HOME/.claude/CLAUDE.md"
HOME="$FAKE_HOME" "$ROOT/scripts/install.sh" --dry-run >/dev/null
[ ! -e "$FAKE_HOME/.agents" ] || { echo 'Dry run mutated HOME' >&2; exit 1; }
HOME="$FAKE_HOME" "$ROOT/scripts/install.sh" >/dev/null
HOME="$FAKE_HOME" "$ROOT/scripts/verify.sh" >/dev/null
shasum_before="$(sha256sum "$FAKE_HOME/AGENTS.md" | cut -d' ' -f1)"
HOME="$FAKE_HOME" "$ROOT/scripts/install.sh" >/dev/null
shasum_after="$(sha256sum "$FAKE_HOME/AGENTS.md" | cut -d' ' -f1)"
[ "$shasum_before" = "$shasum_after" ] || { echo 'Not idempotent' >&2; exit 1; }
grep -qF 'Keep my custom home rules.' "$FAKE_HOME/AGENTS.md"
grep -qF 'Keep my Codex rules.' "$FAKE_HOME/.codex/AGENTS.md"
grep -qF 'Keep my Claude rules.' "$FAKE_HOME/.claude/CLAUDE.md"
HOME="$FAKE_HOME" "$ROOT/scripts/uninstall.sh" --apply >/dev/null
! grep -qF '# >>> dev-agent-config managed >>>' "$FAKE_HOME/AGENTS.md"
[ ! -L "$FAKE_HOME/.agents/skills/ponytail" ]
grep -qF 'Keep my custom home rules.' "$FAKE_HOME/AGENTS.md"
echo 'PASS: dry run, install, verify, re-install, preserve existing, uninstall'
