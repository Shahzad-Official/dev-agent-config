#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
[ "$#" -eq 2 ] || { echo "Usage: $0 REPOSITORY OUTPUT_DIR" >&2; exit 2; }
SOURCE_REPO="$(cd "$1" && pwd -P)"
OUTPUT="$2"
[ ! -e "$OUTPUT" ] || { echo "Output already exists: $OUTPUT" >&2; exit 1; }
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd -P)"
case "$OUTPUT/" in "$SOURCE_REPO/"*) echo 'Output must be outside the source repository' >&2; exit 1 ;; esac

for variant in default rules rules-ponytail; do
  mkdir -p "$OUTPUT/$variant/home" "$OUTPUT/$variant/workspace"
  cp -a "$SOURCE_REPO/." "$OUTPUT/$variant/workspace/"
done

HOME="$OUTPUT/rules/home" "$ROOT/scripts/install.sh" --mode=replace >/dev/null
mkdir -p "$OUTPUT/rules-ponytail/home/.codex"
HOME="$OUTPUT/rules-ponytail/home" "$ROOT/scripts/install.sh" --mode=replace >/dev/null
rm "$OUTPUT/rules/home/.agents/skills/ponytail"

cat <<EOF
Prepared isolated benchmark variants in $OUTPUT

Run the same agent version, exact model, prompt, permissions, and test command in:
  default:          HOME=$OUTPUT/default/home workspace=$OUTPUT/default/workspace
  rules:            HOME=$OUTPUT/rules/home workspace=$OUTPUT/rules/workspace
  rules-ponytail:   HOME=$OUTPUT/rules-ponytail/home workspace=$OUTPUT/rules-ponytail/workspace

Record duration, code diff, and test result for every run. Record tokens, cost, and
tool calls only when the agent reports them. The prepared copies contain no credentials.
EOF
