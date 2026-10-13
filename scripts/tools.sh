#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

tool="${1:-}"
[ -n "$tool" ] || { printf 'Usage: %s TOOL ACTION [OPTIONS]\n' "$0" >&2; exit 1; }
case "$tool" in *[!a-z0-9_-]*|'') printf 'ERROR: Invalid tool: %s\n' "$tool" >&2; exit 1 ;; esac
shift

adapter="$ROOT/scripts/tools/$tool.sh"
[ -f "$adapter" ] || { printf 'ERROR: Unsupported tool: %s\n' "$tool" >&2; exit 1; }
exec bash "$adapter" "$@"
