#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.codex" "$T/.claude"
printf 'Keep this custom rule.\n' > "$T/AGENTS.md"
printf 'Keep existing Codex rule.\n' > "$T/.codex/AGENTS.md"
HOME="$T" bash "$REPO/scripts/install.sh" --dry-run >/dev/null
[[ ! -d "$T/.agents" ]]
HOME="$T" bash "$REPO/scripts/install.sh" >/dev/null
HOME="$T" bash "$REPO/scripts/install.sh" >/dev/null
HOME="$T" bash "$REPO/scripts/verify.sh"
[[ $(grep -Fc '# >>> dev-agent-config managed >>>' "$T/AGENTS.md") -eq 1 ]]
grep -Fq 'Keep this custom rule.' "$T/AGENTS.md"
grep -Fq 'Keep existing Codex rule.' "$T/.codex/AGENTS.md"
echo 'PASS smoke: dry run, preservation, idempotence, verification'
