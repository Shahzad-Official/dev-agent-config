#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
. "$ROOT/tools/graphify/tool.conf"

say() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
case "$data_home:$state_home" in /*:/*) ;; *) fail 'HOME/XDG data and state paths must be absolute' ;; esac
case "$data_home:$state_home" in *'/../'*|*'/..:'*|*':../'*|*':..') fail 'HOME/XDG paths must not contain ..' ;; esac

tool_parent="$data_home/dev-agent-config/tools/graphify"
tool_dir="$tool_parent/$PACKAGE_VERSION"
state_dir="$state_home/dev-agent-config/tools/graphify"
last_backup="$state_dir/last-backup"
marker="$tool_dir/.dev-agent-config-tool"
graphify="$tool_dir/venv/bin/graphify"

path_type() {
  if [ -L "$1" ]; then printf symlink
  elif [ -f "$1" ]; then printf file
  elif [ -d "$1" ]; then printf directory
  elif [ -e "$1" ]; then printf other
  else printf missing; fi
}

validate_path() {
  local path="$1" current anchor=''
  case "$path" in /*) ;; *) fail "Path must be absolute: $path" ;; esac
  case "$path" in /|"$HOME") fail "Refusing broad path: $path" ;; esac
  case "$path" in *'/../'*|*'/..') fail "Path must not contain ..: $path" ;; esac
  case "$path" in
    "$data_home"|"$data_home"/*) anchor="$data_home" ;;
    "$state_home"|"$state_home"/*) anchor="$state_home" ;;
    "$HOME"/*) anchor="$HOME" ;;
    *) fail "Path is outside HOME and the configured XDG roots: $path" ;;
  esac
  current="$path"
  while [ "$current" != "$anchor" ]; do
    [ ! -L "$current" ] || fail "Refusing symlink path: $current"
    current="$(dirname "$current")"
  done
}

physical_path() {
  local path="$1" suffix=''
  while [ ! -d "$path" ]; do
    suffix="/$(basename "$path")$suffix"
    path="$(dirname "$path")"
  done
  printf '%s%s\n' "$(cd "$path" && pwd -P)" "$suffix"
}

expected_marker() {
  printf '%s\n' \
    "tool=$TOOL_NAME" \
    "package=$PACKAGE_NAME" \
    "version=$PACKAGE_VERSION" \
    "wheel_sha256=$WHEEL_SHA256"
}

marker_valid() {
  [ -f "$marker" ] && [ ! -L "$marker" ] && expected_marker | cmp -s - "$marker"
}

installed_version() {
  "$tool_dir/venv/bin/python" -c 'from importlib.metadata import version; print(version("graphifyy"))' 2>/dev/null
}

cli_healthy() {
  local output
  output="$("$graphify" --version 2>/dev/null)" || return 1
  case "$output" in *"$PACKAGE_VERSION"*) return 0 ;; *) return 1 ;; esac
}

healthy() {
  marker_valid && [ -x "$graphify" ] &&
    [ "$(installed_version || true)" = "$PACKAGE_VERSION" ] &&
    cli_healthy &&
    [ -f "$tool_dir/dependencies.txt" ] && [ ! -L "$tool_dir/dependencies.txt" ]
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else fail 'Need sha256sum or shasum to verify the Graphify wheel'; fi
}

python_command() {
  local candidate
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 &&
      "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))' >/dev/null 2>&1; then
      command -v "$candidate"
      return
    fi
  done
  fail 'Graphify requires Python 3.10 or newer with venv support'
}

new_backup() {
  local action="$1" backup type saved
  backup="$state_dir/backups/$(date +%Y%m%d-%H%M%S)-$$-$action"
  mkdir -p "$backup"
  type="$(path_type "$tool_dir")"
  saved="$backup/original"
  if [ "$type" != missing ]; then cp -a "$tool_dir" "$saved"; fi
  {
    printf 'tool\tversion\taction\ttype\ttarget\tbackup\n'
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$TOOL_NAME" "$PACKAGE_VERSION" "$action" "$type" "$tool_dir" "$saved"
  } > "$backup/manifest.tsv"
  mkdir -p "$state_dir"
  printf '%s\n' "$backup" > "$last_backup"
  printf '%s\n' "$backup"
}

install_tool() {
  local dry="$1" python stage wheel actual backup
  validate_path "$tool_dir"
  case "$(path_type "$tool_dir")" in
    missing) ;;
    directory)
      if healthy; then say "UNCHANGED Graphify $PACKAGE_VERSION: $tool_dir"; return; fi
      fail "Refusing existing or corrupted tool directory: $tool_dir"
      ;;
    *) fail "Refusing conflicting tool path: $tool_dir" ;;
  esac
  say "$( [ "$dry" -eq 1 ] && printf WOULD_INSTALL || printf INSTALLING ) Graphify $PACKAGE_VERSION: $tool_dir"
  say "Wheel SHA-256: $WHEEL_SHA256"
  [ "$dry" -eq 0 ] || return 0
  python="$(python_command)"
  validate_path "$tool_parent"
  mkdir -p "$tool_parent"
  stage="$(mktemp -d "$tool_parent/.graphify-$PACKAGE_VERSION.XXXXXX")"
  trap 'rm -rf "$stage"' EXIT
  "$python" -m pip download --disable-pip-version-check --no-deps --dest "$stage" "$WHEEL_URL"
  wheel="$stage/$WHEEL_FILE"
  [ -f "$wheel" ] || fail "Downloaded wheel not found: $wheel"
  actual="$(sha256_file "$wheel")"
  [ "$actual" = "$WHEEL_SHA256" ] || fail "Graphify wheel checksum mismatch: $actual"
  "$python" -m venv "$stage/venv"
  "$stage/venv/bin/python" -m pip install --disable-pip-version-check "$wheel"
  [ "$("$stage/venv/bin/python" -c 'from importlib.metadata import version; print(version("graphifyy"))')" = "$PACKAGE_VERSION" ] || fail 'Installed package version mismatch'
  case "$("$stage/venv/bin/graphify" --version 2>/dev/null)" in
    *"$PACKAGE_VERSION"*) ;;
    *) fail 'Graphify CLI version check failed' ;;
  esac
  "$stage/venv/bin/python" -m pip freeze --all > "$stage/dependencies.txt"
  expected_marker > "$stage/.dev-agent-config-tool"
  backup="$(new_backup install)"
  mv "$stage" "$tool_dir"
  trap - EXIT
  say "INSTALLED Graphify $PACKAGE_VERSION"
  say "Dependencies: $tool_dir/dependencies.txt"
  say "Rollback: $ROOT/scripts/tools.sh graphify rollback '$backup'"
}

verify_tool() {
  validate_path "$tool_dir"
  case "$(path_type "$tool_dir")" in
    missing) say "Graphify $PACKAGE_VERSION: not installed"; return 1 ;;
    directory) ;;
    *) fail "Graphify path conflict: $tool_dir ($(path_type "$tool_dir"))" ;;
  esac
  marker_valid || fail "Graphify ownership metadata is missing or changed: $marker"
  [ -x "$graphify" ] || fail "Graphify executable is missing: $graphify"
  [ "$(installed_version || true)" = "$PACKAGE_VERSION" ] || fail "Graphify package is not version $PACKAGE_VERSION"
  cli_healthy || fail 'Graphify CLI health check failed'
  [ -f "$tool_dir/dependencies.txt" ] && [ ! -L "$tool_dir/dependencies.txt" ] || fail 'Dependency record is missing or unsafe'
  say "Graphify $PACKAGE_VERSION: healthy"
  say "Environment: $tool_dir/venv"
  say "Dependencies: $tool_dir/dependencies.txt"
}

remove_tool() {
  local dry="$1" backup
  validate_path "$tool_dir"
  case "$(path_type "$tool_dir")" in
    missing) say "UNCHANGED Graphify $PACKAGE_VERSION: not installed"; return ;;
    directory) ;;
    *) fail "Refusing conflicting tool path: $tool_dir" ;;
  esac
  marker_valid || fail "Refusing non-managed or modified tool directory: $tool_dir"
  say "$( [ "$dry" -eq 1 ] && printf WOULD_REMOVE || printf REMOVING ) Graphify $PACKAGE_VERSION: $tool_dir"
  [ "$dry" -eq 0 ] || return 0
  backup="$(new_backup remove)"
  rm -rf "$tool_dir"
  say "REMOVED Graphify $PACKAGE_VERSION"
  say "Rollback: $ROOT/scripts/tools.sh graphify rollback '$backup'"
}

rollback_tool() {
  local dry="$1" backup="${2:-}" line tool version action type target saved current
  if [ -z "$backup" ]; then
    [ -f "$last_backup" ] && [ ! -L "$last_backup" ] || fail 'No safe Graphify backup record found'
    backup="$(sed -n '1p' "$last_backup")"
  fi
  validate_path "$backup"
  case "$backup" in "$state_dir/backups/"*) ;; *) fail "Invalid Graphify backup path: $backup" ;; esac
  [ -f "$backup/manifest.tsv" ] && [ ! -L "$backup/manifest.tsv" ] || fail "Missing safe manifest: $backup"
  line="$(sed -n '2p' "$backup/manifest.tsv")"
  IFS="$(printf '\t')" read -r tool version action type target saved <<EOF
$line
EOF
  [ "$tool" = "$TOOL_NAME" ] && [ "$version" = "$PACKAGE_VERSION" ] && [ "$target" = "$tool_dir" ] || fail 'Backup does not match this managed Graphify installation'
  [ "$saved" = "$backup/original" ] || fail 'Backup contains an unexpected restore path'
  validate_path "$target"
  current="$(path_type "$target")"
  if [ "$type" = missing ]; then
    if [ "$current" = missing ]; then say "UNCHANGED rollback: $target is already absent"; return; fi
    [ "$current" = directory ] && marker_valid && healthy || fail 'Refusing to remove an unexpected or modified path during rollback'
    say "$( [ "$dry" -eq 1 ] && printf WOULD_RESTORE || printf RESTORED ) missing state: $target"
    [ "$dry" -eq 1 ] || rm -rf "$target"
  elif [ "$type" = directory ]; then
    [ -d "$saved" ] && [ ! -L "$saved" ] || fail 'Managed backup payload is missing or unsafe'
    if [ "$current" != missing ]; then fail 'Refusing to overwrite an existing path during rollback'; fi
    say "$( [ "$dry" -eq 1 ] && printf WOULD_RESTORE || printf RESTORED ) Graphify: $target"
    if [ "$dry" -eq 0 ]; then mkdir -p "$(dirname "$target")"; cp -a "$saved" "$target"; fi
  else
    fail "Unsupported original path type in backup: $type"
  fi
  [ "$dry" -eq 1 ] || say "Rollback complete: $backup"
}

index_project() {
  local dry="$1" project="$2" output="$3" name key final output_physical
  [ -n "$project" ] || fail 'Indexing requires --project PATH'
  [ -d "$project" ] && [ ! -L "$project" ] || fail "Project must be a real directory, not a symlink: $project"
  project="$(cd "$project" && pwd -P)"
  if [ -z "$output" ]; then
    name="$(basename "$project" | tr -c 'A-Za-z0-9._-' '_')"
    key="$(printf '%s' "$project" | cksum | awk '{print $1}')"
    output="$data_home/dev-agent-config/graphify/indexes/$name-$key"
  fi
  case "$output" in /*) ;; *) fail "Output root must be absolute: $output" ;; esac
  output="${output%/}"
  validate_path "$output"
  output_physical="$(physical_path "$output")"
  case "$output_physical" in "$project"|"$project"/*) fail 'Graphify output must be outside the source project' ;; esac
  healthy || fail "Graphify $PACKAGE_VERSION is not installed and healthy"
  final="$output/graphify-out"
  say "$( [ "$dry" -eq 1 ] && printf WOULD_INDEX || printf INDEXING ) code: $project"
  say "Graph output: $final"
  [ "$dry" -eq 0 ] || return 0
  mkdir -p "$output"
  env \
    -u OPENAI_API_KEY -u ANTHROPIC_API_KEY -u GEMINI_API_KEY -u GOOGLE_API_KEY \
    -u MOONSHOT_API_KEY -u DEEPSEEK_API_KEY -u AZURE_OPENAI_API_KEY -u AZURE_OPENAI_ENDPOINT \
    -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_PROFILE \
    -u AWS_REGION -u AWS_DEFAULT_REGION -u OLLAMA_BASE_URL -u GRAPHIFY_BACKEND \
    GRAPHIFY_OUT=graphify-out GRAPHIFY_QUERY_LOG_DISABLE=1 GRAPHIFY_NO_TIPS=1 GRAPHIFY_NO_CTA=1 \
    "$graphify" extract "$project" --out "$output" --code-only
  [ -f "$final/graph.json" ] || fail "Graphify did not create expected output: $final/graph.json"
  [ -f "$final/GRAPH_REPORT.md" ] || fail "Graphify did not create expected output: $final/GRAPH_REPORT.md"
  [ -f "$final/graph.html" ] || fail "Graphify did not create expected output: $final/graph.html"
  say "INDEXED code-only graph: $final"
}

usage() {
  printf 'Usage: %s {install|verify|remove|rollback|index} [OPTIONS]\n' "$ROOT/scripts/tools.sh graphify" >&2
  exit 1
}

action="${1:-}"
shift || true
dry=0
project=''
output=''
backup=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --project) shift; [ "$#" -gt 0 ] || usage; project="$1" ;;
    --output) shift; [ "$#" -gt 0 ] || usage; output="$1" ;;
    --*) usage ;;
    *) [ "$action" = rollback ] && [ -z "$backup" ] || usage; backup="$1" ;;
  esac
  shift
done

case "$action" in
  install) [ -z "$project$output$backup" ] || usage; install_tool "$dry" ;;
  verify) [ "$dry" -eq 0 ] && [ -z "$project$output$backup" ] || usage; verify_tool ;;
  remove) [ -z "$project$output$backup" ] || usage; remove_tool "$dry" ;;
  rollback) [ -z "$project$output" ] || usage; rollback_tool "$dry" "$backup" ;;
  index) [ -z "$backup" ] || usage; index_project "$dry" "$project" "$output" ;;
  *) usage ;;
esac
