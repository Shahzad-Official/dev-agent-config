#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CLI="$ROOT/dev-agent-config"
action="${1:-}"
shift || true
bin_dir="${DEV_AGENT_CONFIG_BIN:-$HOME/.local/bin}"
dry=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --bin-dir) shift; [ "$#" -gt 0 ] || { echo 'ERROR: --bin-dir requires a path' >&2; exit 2; }; bin_dir="$1" ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

case "$action" in install|uninstall) ;; *) echo 'Usage: dev-agent-config cli {install|uninstall} [--dry-run] [--bin-dir PATH]' >&2; exit 2 ;; esac
case "$bin_dir" in "$HOME"/*) ;; *) echo "ERROR: CLI bin directory must be inside HOME: $bin_dir" >&2; exit 1 ;; esac
case "$bin_dir" in *'/../'*|*'/..') echo 'ERROR: CLI bin directory must not contain ..' >&2; exit 1 ;; esac

current="$bin_dir"
while [ "$current" != "$HOME" ]; do
  [ ! -L "$current" ] || { echo "ERROR: Refusing symlinked CLI bin path: $current" >&2; exit 1; }
  parent="$(dirname "$current")"
  [ "$parent" != "$current" ] || { echo 'ERROR: Invalid CLI bin path' >&2; exit 1; }
  current="$parent"
done

target="$bin_dir/dev-agent-config"
if [ "$action" = install ]; then
  if [ -L "$target" ]; then
    [ "$(readlink "$target")" = "$CLI" ] || { echo "ERROR: Refusing existing CLI symlink: $target" >&2; exit 1; }
    echo "UNCHANGED CLI link: $target"
  elif [ -e "$target" ]; then
    echo "ERROR: Refusing to overwrite existing CLI path: $target" >&2
    exit 1
  else
    echo "$( [ "$dry" -eq 1 ] && printf WOULD_LINK || printf LINKING ) $target -> $CLI"
    [ "$dry" -eq 1 ] || { mkdir -p "$bin_dir" && ln -s "$CLI" "$target"; }
  fi
else
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    echo "UNCHANGED CLI link: not installed at $target"
  elif [ -L "$target" ] && [ "$(readlink "$target")" = "$CLI" ]; then
    echo "$( [ "$dry" -eq 1 ] && printf WOULD_UNLINK || printf UNLINKING ) $target"
    [ "$dry" -eq 1 ] || rm "$target"
  else
    echo "ERROR: Refusing to remove a CLI path not owned by this checkout: $target" >&2
    exit 1
  fi
fi

case ":${PATH:-}:" in
  *":$bin_dir:"*) echo "CLI directory is already in PATH: $bin_dir" ;;
  *) echo "Add this to your shell profile to use the short command: export PATH=\"$bin_dir:\$PATH\"" ;;
esac
