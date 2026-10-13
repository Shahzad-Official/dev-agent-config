#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
. "$ROOT/tools/graphify/tool.conf"

PINNED_VERSION="$PACKAGE_VERSION"
PINNED_WHEEL_FILE="$WHEEL_FILE"
PINNED_WHEEL_URL="$WHEEL_URL"
PINNED_WHEEL_SHA256="$WHEEL_SHA256"
STAGE=''

say() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
case "$data_home:$state_home" in /*:/*) ;; *) fail 'HOME/XDG data and state paths must be absolute' ;; esac
case "$data_home:$state_home" in *'/../'*|*'/..:'*|*':../'*|*':..') fail 'HOME/XDG paths must not contain ..' ;; esac

state_dir="$state_home/dev-agent-config/tools/graphify"
last_backup="$state_dir/last-backup"
current_release="$state_dir/current-release.tsv"
tool_parent="$data_home/dev-agent-config/tools/graphify"

set_release() {
  PACKAGE_VERSION="$1"
  WHEEL_FILE="$2"
  WHEEL_URL="$3"
  WHEEL_SHA256="$4"
  tool_dir="$tool_parent/$PACKAGE_VERSION"
  marker="$tool_dir/.dev-agent-config-tool"
  graphify="$tool_dir/venv/bin/graphify"
}

set_release "$PACKAGE_VERSION" "$WHEEL_FILE" "$WHEEL_URL" "$WHEEL_SHA256"

cleanup_stage() {
  local doomed="${STAGE:-}"
  [ -n "$doomed" ] || return 0
  STAGE=''
  if ! rm -rf -- "$doomed"; then
    printf 'ERROR: Could not clean temporary staging directory: %s\n' "$doomed" >&2
    return 1
  fi
}

on_exit() {
  local status=$?
  trap - EXIT
  if ! cleanup_stage && [ "$status" -eq 0 ]; then status=1; fi
  exit "$status"
}
trap on_exit EXIT

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

cleanup_stale_stages() {
  local stale
  for stale in "$tool_parent"/.graphify-*.staging.*; do
    [ -e "$stale" ] || [ -L "$stale" ] || continue
    [ -d "$stale" ] && [ ! -L "$stale" ] || fail "Refusing unsafe staging path: $stale"
    [ -f "$stale/.dev-agent-config-stage" ] && [ ! -L "$stale/.dev-agent-config-stage" ] || fail "Refusing unowned staging path: $stale"
    rm -rf -- "$stale" || fail "Could not remove interrupted staging directory: $stale"
  done
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
  return 1
}

prerequisite_hint() {
  local id='' command=''
  if [ -r /etc/os-release ]; then
    id="$(sed -n 's/^ID=//p' /etc/os-release | head -n 1 | tr -d '"')"
  fi
  case "$id" in
    debian|ubuntu|linuxmint|pop) command='sudo apt install python3-venv' ;;
    fedora|rhel|centos) command='sudo dnf install python3' ;;
    alpine) command='sudo apk add python3 py3-pip' ;;
    arch|manjaro) command='sudo pacman -S python' ;;
  esac
  if [ -z "$command" ] && [ "$(uname -s)" = Darwin ] && command -v brew >/dev/null 2>&1; then
    command='brew install python'
  fi
  if [ -n "$command" ]; then
    say 'Install the missing prerequisite with:'
    say "  $command"
    say ''
    say 'Then retry:'
    say "  $ROOT/scripts/tools.sh graphify install"
    say ''
    say 'No files were downloaded or installed. The manager does not run privileged package commands.'
  else
    say 'Install a Python 3.10+ distribution that includes venv and ensurepip.'
    say ''
    say 'Then retry:'
    say "  $ROOT/scripts/tools.sh graphify install"
    say ''
    say 'No files were downloaded or installed.'
  fi
}

ensure_venv_pip() {
  local python="$1" venv="$2"
  "$python" -m venv "$venv" >/dev/null 2>&1 || return 2
  if "$venv/bin/python" -m pip --version >/dev/null 2>&1; then return 0; fi
  "$venv/bin/python" -m ensurepip --upgrade >/dev/null 2>&1 || return 3
  "$venv/bin/python" -m pip --version >/dev/null 2>&1 || return 3
}

preflight() {
  local python probe result
  if ! python="$(python_command)"; then
    say 'Preflight failed: Graphify requires Python 3.10 or newer.' >&2
    prerequisite_hint >&2
    return 1
  fi
  STAGE="$(mktemp -d "${TMPDIR:-/tmp}/dev-agent-config-graphify-preflight.XXXXXX")"
  probe="$STAGE/venv"
  result=0
  ensure_venv_pip "$python" "$probe" || result=$?
  if [ "$result" -ne 0 ]; then
    cleanup_stage || true
    if [ "$result" -eq 2 ]; then say 'Preflight failed: Python venv support is unavailable.' >&2
    else say 'Preflight failed: pip is unavailable in the virtual environment and ensurepip could not provide it.' >&2; fi
    prerequisite_hint >&2
    return 1
  fi
  cleanup_stage || fail 'Preflight cleanup failed'
  PREFLIGHT_PYTHON="$python"
  say "Preflight: Python $("$python" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))') with venv and virtualenv pip is ready"
}

resolve_latest_release() {
  local python="$1" result
  result="$("$python" -c '
import json,re,sys,urllib.request
data=json.load(urllib.request.urlopen("https://pypi.org/pypi/graphifyy/json", timeout=15))
v=data["info"]["version"]
if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", v): raise SystemExit("latest release is not stable")
for f in data["urls"]:
    if f["filename"]==f"graphifyy-{v}-py3-none-any.whl" and not f.get("yanked"):
        print("\t".join((v,f["filename"],f["url"],f["digests"]["sha256"])))
        break
else: raise SystemExit("no supported universal wheel")
')" || return 1
  IFS="$(printf '\t')" read -r latest_version latest_file latest_url latest_hash <<EOF
$result
EOF
  [ -n "$latest_version" ] && [ -n "$latest_hash" ] || return 1
}

version_is_newer() {
  "$1" -c 'import sys; a=tuple(map(int,sys.argv[1].split("."))); b=tuple(map(int,sys.argv[2].split("."))); raise SystemExit(0 if a>b else 1)' "$2" "$3"
}

load_current_release() {
  local version file url hash
  [ -f "$current_release" ] && [ ! -L "$current_release" ] || return 1
  IFS="$(printf '\t')" read -r version file url hash < "$current_release"
  case "$version" in *[!0-9.]*|'') return 1 ;; esac
  case "$hash" in *[!0-9a-f]*|'') return 1 ;; esac
  [ "${#hash}" -eq 64 ] || return 1
  [ "$file" = "graphifyy-$version-py3-none-any.whl" ] || return 1
  case "$url" in https://files.pythonhosted.org/*) ;; *) return 1 ;; esac
  set_release "$version" "$file" "$url" "$hash"
}

new_backup() {
  local action="$1" backup type saved
  backup="$state_dir/backups/$(date +%Y%m%d-%H%M%S)-$$-$action"
  mkdir -p "$backup"
  type="$(path_type "$tool_dir")"
  saved="$backup/original"
  if [ "$type" != missing ]; then cp -a "$tool_dir" "$saved"; fi
  if [ -f "$current_release" ] && [ ! -L "$current_release" ]; then cp "$current_release" "$backup/previous-release.tsv"; fi
  {
    printf 'tool\tversion\taction\ttype\ttarget\tbackup\n'
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$TOOL_NAME" "$PACKAGE_VERSION" "$action" "$type" "$tool_dir" "$saved"
  } > "$backup/manifest.tsv"
  mkdir -p "$state_dir"
  printf '%s\n' "$backup" > "$last_backup"
  printf '%s\n' "$backup"
}

install_tool() {
  local dry="$1" operation="${2:-install}" python wheel actual backup release_tmp had_current=0
  if load_current_release; then
    had_current=1
    if ! healthy; then fail "Refusing existing or corrupted tool directory: $tool_dir"; fi
    if [ "$operation" = install ]; then
      say "UNCHANGED Graphify $PACKAGE_VERSION: $tool_dir"
      say "Run '$ROOT/scripts/tools.sh graphify check-update' to check for a newer stable release."
      return
    fi
  fi
  preflight || fail 'Graphify prerequisites are not ready; no download or installation was attempted'
  python="$PREFLIGHT_PYTHON"
  if resolve_latest_release "$python"; then
    set_release "$latest_version" "$latest_file" "$latest_url" "$latest_hash"
  elif [ "$operation" = upgrade ]; then
    fail 'Could not resolve the latest stable Graphify release from PyPI'
  else
    say "WARNING: Could not resolve PyPI metadata; using verified fallback Graphify $PINNED_VERSION" >&2
    set_release "$PINNED_VERSION" "$PINNED_WHEEL_FILE" "$PINNED_WHEEL_URL" "$PINNED_WHEEL_SHA256"
  fi
  if [ "$had_current" -eq 1 ]; then
    installed_current="$(cut -f1 "$current_release")"
    if ! version_is_newer "$python" "$PACKAGE_VERSION" "$installed_current"; then
      say "UNCHANGED Graphify $installed_current is already current; latest stable is $PACKAGE_VERSION"
      return
    fi
  fi
  validate_path "$tool_dir"
  case "$(path_type "$tool_dir")" in
    missing) ;;
    directory)
      if healthy; then
        if [ "$dry" -eq 0 ]; then
          mkdir -p "$state_dir"
          printf '%s\t%s\t%s\t%s\n' "$PACKAGE_VERSION" "$WHEEL_FILE" "$WHEEL_URL" "$WHEEL_SHA256" > "$current_release"
        fi
        say "UNCHANGED Graphify $PACKAGE_VERSION: $tool_dir"
        return
      fi
      fail "Refusing existing or corrupted tool directory: $tool_dir"
      ;;
    *) fail "Refusing conflicting tool path: $tool_dir" ;;
  esac
  say "$( [ "$dry" -eq 1 ] && printf WOULD_INSTALL || printf INSTALLING ) Graphify $PACKAGE_VERSION: $tool_dir"
  say "Wheel SHA-256: $WHEEL_SHA256"
  say 'Preflight result: installation can proceed'
  [ "$dry" -eq 0 ] || return 0
  validate_path "$tool_parent"
  mkdir -p "$tool_parent"
  cleanup_stale_stages
  STAGE="$(mktemp -d "$tool_parent/.graphify-$PACKAGE_VERSION.staging.XXXXXX")"
  printf '%s\n' "$PACKAGE_VERSION" > "$STAGE/.dev-agent-config-stage"
  ensure_venv_pip "$python" "$STAGE/venv" || fail 'Could not create a virtual environment with pip after preflight'
  "$STAGE/venv/bin/python" -m pip download --disable-pip-version-check --no-deps --dest "$STAGE" "$WHEEL_URL"
  wheel="$STAGE/$WHEEL_FILE"
  [ -f "$wheel" ] || fail "Downloaded wheel not found: $wheel"
  actual="$(sha256_file "$wheel")"
  [ "$actual" = "$WHEEL_SHA256" ] || fail "Graphify wheel checksum mismatch: $actual"
  "$STAGE/venv/bin/python" -m pip install --disable-pip-version-check "$wheel"
  [ "$("$STAGE/venv/bin/python" -c 'from importlib.metadata import version; print(version("graphifyy"))')" = "$PACKAGE_VERSION" ] || fail 'Installed package version mismatch'
  case "$("$STAGE/venv/bin/graphify" --version 2>/dev/null)" in
    *"$PACKAGE_VERSION"*) ;;
    *) fail 'Graphify CLI version check failed' ;;
  esac
  "$STAGE/venv/bin/python" -m pip freeze --all > "$STAGE/dependencies.txt"
  expected_marker > "$STAGE/.dev-agent-config-tool"
  printf '%s\t%s\t%s\t%s\n' "$PACKAGE_VERSION" "$WHEEL_FILE" "$WHEEL_URL" "$WHEEL_SHA256" > "$STAGE/release.tsv"
  backup="$(new_backup "$operation")"
  mv "$STAGE" "$tool_dir"
  STAGE="$tool_dir"
  mkdir -p "$state_dir"
  release_tmp="$state_dir/.current-release.$$"
  printf '%s\t%s\t%s\t%s\n' "$PACKAGE_VERSION" "$WHEEL_FILE" "$WHEEL_URL" "$WHEEL_SHA256" > "$release_tmp"
  mv "$release_tmp" "$current_release"
  STAGE=''
  say "INSTALLED Graphify $PACKAGE_VERSION"
  say "Dependencies: $tool_dir/dependencies.txt"
  say "Rollback: $ROOT/scripts/tools.sh graphify rollback '$backup'"
}

check_update() {
  local python current='not installed'
  if load_current_release; then current="$PACKAGE_VERSION"; fi
  if ! python="$(python_command)"; then fail 'Update checking requires Python 3.10 or newer'; fi
  resolve_latest_release "$python" || fail 'Could not resolve the latest stable Graphify release from PyPI'
  say "Current Graphify: $current"
  say "Latest stable Graphify: $latest_version"
  if [ "$current" != 'not installed' ] && version_is_newer "$python" "$latest_version" "$current"; then
    say "Upgrade available. Preview with: $ROOT/scripts/tools.sh graphify upgrade --dry-run"
  fi
}

verify_tool() {
  load_current_release || set_release "$PINNED_VERSION" "$PINNED_WHEEL_FILE" "$PINNED_WHEEL_URL" "$PINNED_WHEEL_SHA256"
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
  load_current_release || set_release "$PINNED_VERSION" "$PINNED_WHEEL_FILE" "$PINNED_WHEEL_URL" "$PINNED_WHEEL_SHA256"
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
  if [ -f "$current_release" ] && [ ! -L "$current_release" ]; then rm "$current_release"; fi
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
  if load_current_release; then :
  elif [ -f "$saved/release.tsv" ] && [ ! -L "$saved/release.tsv" ]; then
    IFS="$(printf '\t')" read -r release_version release_file release_url release_hash < "$saved/release.tsv"
    case "$release_version" in *[!0-9.]*|'') fail 'Backup release metadata is invalid' ;; esac
    [ "$release_file" = "graphifyy-$release_version-py3-none-any.whl" ] || fail 'Backup wheel metadata is invalid'
    case "$release_url" in https://files.pythonhosted.org/*) ;; *) fail 'Backup source metadata is invalid' ;; esac
    case "$release_hash" in *[!0-9a-f]*|'') fail 'Backup digest metadata is invalid' ;; esac
    [ "${#release_hash}" -eq 64 ] || fail 'Backup digest metadata is invalid'
    set_release "$release_version" "$release_file" "$release_url" "$release_hash"
  else
    set_release "$PINNED_VERSION" "$PINNED_WHEEL_FILE" "$PINNED_WHEEL_URL" "$PINNED_WHEEL_SHA256"
  fi
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
  if [ "$dry" -eq 0 ]; then
    if [ -f "$backup/previous-release.tsv" ] && [ ! -L "$backup/previous-release.tsv" ]; then
      mkdir -p "$state_dir"
      cp "$backup/previous-release.tsv" "$current_release"
    elif [ -f "$current_release" ] && [ ! -L "$current_release" ]; then
      rm "$current_release"
    fi
  fi
  [ "$dry" -eq 1 ] || say "Rollback complete: $backup"
}

index_project() {
  local dry="$1" project="$2" output="$3" name key final output_physical
  load_current_release || set_release "$PINNED_VERSION" "$PINNED_WHEEL_FILE" "$PINNED_WHEEL_URL" "$PINNED_WHEEL_SHA256"
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
  printf 'Usage: %s {install|check-update|upgrade|verify|remove|rollback|index} [OPTIONS]\n' "$ROOT/scripts/tools.sh graphify" >&2
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
  check-update) [ "$dry" -eq 0 ] && [ -z "$project$output$backup" ] || usage; check_update ;;
  upgrade) [ -z "$project$output$backup" ] || usage; install_tool "$dry" upgrade ;;
  verify) [ "$dry" -eq 0 ] && [ -z "$project$output$backup" ] || usage; verify_tool ;;
  remove) [ -z "$project$output$backup" ] || usage; remove_tool "$dry" ;;
  rollback) [ -z "$project$output" ] || usage; rollback_tool "$dry" "$backup" ;;
  index) [ -z "$backup" ] || usage; index_project "$dry" "$project" "$output" ;;
  *) usage ;;
esac
