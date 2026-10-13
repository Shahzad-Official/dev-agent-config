#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
. "$ROOT/tools/graphify/tool.conf"

PINNED_VERSION="$PACKAGE_VERSION"
PINNED_WHEEL_FILE="$WHEEL_FILE"
PINNED_WHEEL_URL="$WHEEL_URL"
PINNED_WHEEL_SHA256="$WHEEL_SHA256"
STAGE=''
INSTALL_TARGET=''
RESTORE_BACKUP=''
INSTALL_LOG=''
verbose=0

say() { printf '%s\n' "$*"; }
fail() {
  printf 'ERROR: %s\n' "$*" >&2
  if [ -n "${INSTALL_LOG:-}" ]; then
    printf 'Details: %s\n' "$INSTALL_LOG" >&2
    if [ -s "$INSTALL_LOG" ] && [ "${verbose:-0}" -eq 0 ]; then tail -n 20 "$INSTALL_LOG" >&2; fi
  fi
  exit 1
}

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

cleanup_install() {
  local target="${INSTALL_TARGET:-}" restore="${RESTORE_BACKUP:-}"
  [ -n "$target" ] || return 0
  INSTALL_TARGET=''
  RESTORE_BACKUP=''
  if [ "$(path_type "$target")" = missing ]; then
    if [ -n "$restore" ] && [ -d "$restore" ] && [ ! -L "$restore" ]; then
      mkdir -p "$(dirname "$target")" && cp -a "$restore" "$target" || return 1
    fi
  elif { [ -f "$target/.dev-agent-config-installing" ] && [ ! -L "$target/.dev-agent-config-installing" ]; } ||
    { [ -f "$target/.dev-agent-config-tool" ] && [ ! -L "$target/.dev-agent-config-tool" ] && expected_marker | cmp -s - "$target/.dev-agent-config-tool"; }; then
    rm -rf -- "$target" || return 1
    if [ -n "$restore" ] && [ -d "$restore" ] && [ ! -L "$restore" ]; then
      cp -a "$restore" "$target" || return 1
    fi
  else
    printf 'ERROR: Refusing to clean an installation path without its temporary ownership marker: %s\n' "$target" >&2
    return 1
  fi
}

on_exit() {
  local status=$?
  trap - EXIT
  if ! cleanup_stage && [ "$status" -eq 0 ]; then status=1; fi
  if ! cleanup_install && [ "$status" -eq 0 ]; then status=1; fi
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

entrypoint_interpreter() {
  local line interpreter
  IFS= read -r line < "$graphify" || return 1
  case "$line" in '#!'*) ;; *) return 1 ;; esac
  interpreter="${line#\#!}"
  interpreter="${interpreter%% *}"
  printf '%s\n' "$interpreter"
}

entrypoint_healthy() {
  local interpreter
  interpreter="$(entrypoint_interpreter)" || return 1
  case "$interpreter" in
    /*) [ -x "$interpreter" ] ;;
    /usr/bin/env) return 0 ;;
    *) return 1 ;;
  esac
}

healthy() {
  marker_valid && [ -x "$graphify" ] &&
    entrypoint_healthy &&
    [ "$(installed_version || true)" = "$PACKAGE_VERSION" ] &&
    cli_healthy &&
    [ -f "$tool_dir/dependencies.txt" ] && [ ! -L "$tool_dir/dependencies.txt" ]
}

run_graphify() {
  env \
    -u OPENAI_API_KEY -u OPENAI_BASE_URL -u ANTHROPIC_API_KEY -u ANTHROPIC_BASE_URL \
    -u GEMINI_API_KEY -u GOOGLE_API_KEY -u GOOGLE_APPLICATION_CREDENTIALS \
    -u MOONSHOT_API_KEY -u DEEPSEEK_API_KEY -u AZURE_OPENAI_API_KEY -u AZURE_OPENAI_ENDPOINT \
    -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_PROFILE \
    -u AWS_REGION -u AWS_DEFAULT_REGION -u AWS_WEB_IDENTITY_TOKEN_FILE -u AWS_ROLE_ARN \
    -u OLLAMA_BASE_URL -u GRAPHIFY_BACKEND \
    GRAPHIFY_QUERY_LOG_DISABLE=1 GRAPHIFY_NO_TIPS=1 GRAPHIFY_NO_CTA=1 \
    "$graphify" "$@"
}

run_graphify_checked() {
  local operation="$1" command="$2" status=0
  shift 2
  run_graphify "$command" "$@" || status=$?
  [ "$status" -eq 0 ] || fail "Graphify $operation failed (exit $status)"
}

run_install_step() {
  local label="$1" status=0
  shift
  if [ "$verbose" -eq 1 ]; then
    "$@" 2>&1 | tee -a "$INSTALL_LOG" || status=$?
  else
    "$@" >> "$INSTALL_LOG" 2>&1 || status=$?
  fi
  [ "$status" -eq 0 ] || fail "$label failed (exit $status)"
}

valid_node_link_graph() {
  [ -f "$1" ] && [ ! -L "$1" ] &&
    "$tool_dir/venv/bin/python" -c 'import json,sys; data=json.load(open(sys.argv[1], encoding="utf-8")); assert isinstance(data.get("nodes"), list) and isinstance(data.get("links"), list)' "$1" >/dev/null 2>&1
}

project_index_root() {
  local project="$1" name key
  name="$(basename "$project" | tr -c 'A-Za-z0-9._-' '_')"
  key="$(printf '%s' "$project" | cksum | awk '{print $1}')"
  printf '%s/dev-agent-config/graphify/indexes/%s-%s\n' "$data_home" "$name" "$key"
}

expected_index_marker() { printf 'project=%s\n' "$project"; }

resolve_project_graph() {
  local selected="$1" output="${2:-}" output_physical
  [ -n "$selected" ] || fail 'This operation requires --project PATH'
  [ -d "$selected" ] && [ ! -L "$selected" ] || fail "Project must be a real directory, not a symlink: $selected"
  project="$(cd "$selected" && pwd -P)"
  [ -n "$output" ] || output="$(project_index_root "$project")"
  case "$output" in /*) ;; *) fail "Output root must be absolute: $output" ;; esac
  output="${output%/}"
  validate_path "$output/graphify-out/graph.json"
  output_physical="$(physical_path "$output")"
  case "$output_physical" in "$project"|"$project"/*) fail 'Managed Graphify output must be outside the source project' ;; esac
  graph="$output/graphify-out/graph.json"
  [ -f "$graph" ] && [ ! -L "$graph" ] || fail "No indexed Graphify graph for this project: $graph. Run '$ROOT/scripts/tools.sh graphify index --project '$project'' first."
  resolve_active_release || fail 'No validated active Graphify installation is recorded; install Graphify first'
  healthy || fail "Graphify $PACKAGE_VERSION is not installed and healthy"
  valid_node_link_graph "$graph" || fail "Invalid Graphify node-link graph (expected nodes and links arrays): $graph. Re-index this project with '$ROOT/scripts/tools.sh graphify index --project '$project'' (and its original --output root, if customized)."
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
  ' 2>> "${INSTALL_LOG:-/dev/null}")" || return 1
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

# Existing-installation operations must use the release recorded by the manager,
# never the trusted fresh-install fallback in tool.conf.
resolve_active_release() {
  if [ ! -e "$current_release" ] && [ ! -L "$current_release" ]; then return 1; fi
  load_current_release || fail "Active Graphify release metadata is missing, unsafe, or invalid: $current_release"
  validate_path "$tool_dir"
  [ "$(path_type "$tool_dir")" = directory ] || fail "Active Graphify installation is missing or conflicting: $tool_dir"
  marker_valid || fail "Active Graphify ownership metadata is missing or changed: $marker"
}

new_backup() {
  local action="$1" backup type saved
  backup="$state_dir/backups/$(date +%Y%m%d-%H%M%S)-$$-$action"
  mkdir -p "$backup"
  type="$(path_type "$tool_dir")"
  saved="$backup/original"
  if [ "$type" != missing ]; then cp -a "$tool_dir" "$saved"; fi
  if [ -f "$current_release" ] && [ ! -L "$current_release" ]; then cp "$current_release" "$backup/previous-release.tsv"; fi
  printf '%s\t%s\t%s\t%s\n' "$PACKAGE_VERSION" "$WHEEL_FILE" "$WHEEL_URL" "$WHEEL_SHA256" > "$backup/release.tsv"
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
  if resolve_active_release; then
    had_current=1
    if [ "$operation" = repair ]; then
      marker_valid || fail "Refusing to repair a directory without valid manager ownership: $tool_dir"
      if healthy; then say "UNCHANGED Graphify $PACKAGE_VERSION is already healthy"; return; fi
    elif ! healthy; then
      fail "Graphify $PACKAGE_VERSION is manager-owned but unhealthy. Run: $ROOT/scripts/tools.sh graphify repair --dry-run"
    elif [ "$operation" = install ]; then
      say "UNCHANGED Graphify $PACKAGE_VERSION: $tool_dir"
      say "Run '$ROOT/scripts/tools.sh graphify check-update' to check for a newer stable release."
      return
    fi
  elif [ -e "$current_release" ] || [ -L "$current_release" ]; then
    fail "Could not resolve the recorded Graphify installation: $current_release"
  elif [ "$operation" = upgrade ]; then
    fail 'Cannot upgrade Graphify because no validated active installation is recorded; use install first'
  fi
  if [ "$dry" -eq 0 ]; then
    mkdir -p "$state_dir/logs"
    INSTALL_LOG="$state_dir/logs/install-$(date +%Y%m%d-%H%M%S)-$$.log"
    : > "$INSTALL_LOG"
  fi
  preflight || fail 'Graphify prerequisites are not ready; no download or installation was attempted'
  python="$PREFLIGHT_PYTHON"
  if [ "$operation" = repair ]; then
    [ "$had_current" -eq 1 ] || fail 'No recorded Graphify installation is available to repair'
  elif resolve_latest_release "$python"; then
    set_release "$latest_version" "$latest_file" "$latest_url" "$latest_hash"
  elif [ "$operation" = upgrade ]; then
    fail 'Could not resolve the latest stable Graphify release from PyPI'
  else
    say "WARNING: Could not resolve PyPI metadata; using verified fallback Graphify $PINNED_VERSION" >&2
    set_release "$PINNED_VERSION" "$PINNED_WHEEL_FILE" "$PINNED_WHEEL_URL" "$PINNED_WHEEL_SHA256"
  fi
  if [ "$had_current" -eq 1 ] && [ "$operation" = upgrade ]; then
    installed_current="$(cut -f1 "$current_release")"
    if ! version_is_newer "$python" "$PACKAGE_VERSION" "$installed_current"; then
      say "UNCHANGED Graphify $installed_current is already current; latest stable is $PACKAGE_VERSION"
      return
    fi
  fi
  validate_path "$tool_dir"
  case "$(path_type "$tool_dir")" in
    missing) [ "$operation" != repair ] || fail "Repair target is missing: $tool_dir" ;;
    directory)
      if [ "$operation" = repair ]; then
        marker_valid || fail "Refusing to repair a directory without valid manager ownership: $tool_dir"
      elif healthy; then
        if [ "$dry" -eq 0 ]; then
          mkdir -p "$state_dir"
          printf '%s\t%s\t%s\t%s\n' "$PACKAGE_VERSION" "$WHEEL_FILE" "$WHEEL_URL" "$WHEEL_SHA256" > "$current_release"
        fi
        say "UNCHANGED Graphify $PACKAGE_VERSION: $tool_dir"
        return
      fi
      [ "$operation" = repair ] || fail "Refusing existing or corrupted tool directory: $tool_dir"
      ;;
    *) fail "Refusing conflicting tool path: $tool_dir" ;;
  esac
  if [ "$operation" = repair ]; then
    say "$( [ "$dry" -eq 1 ] && printf WOULD_REPAIR || printf REPAIRING ) Graphify $PACKAGE_VERSION: $tool_dir"
  else
    say "$( [ "$dry" -eq 1 ] && printf WOULD_INSTALL || printf INSTALLING ) Graphify $PACKAGE_VERSION: $tool_dir"
  fi
  say "Wheel SHA-256: $WHEEL_SHA256"
  say 'Preflight result: installation can proceed'
  [ "$dry" -eq 0 ] || return 0
  validate_path "$tool_parent"
  mkdir -p "$tool_parent"
  cleanup_stale_stages
  STAGE="$(mktemp -d "$tool_parent/.graphify-$PACKAGE_VERSION.staging.XXXXXX")"
  printf '%s\n' "$PACKAGE_VERSION" > "$STAGE/.dev-agent-config-stage"
  ensure_venv_pip "$python" "$STAGE/download-venv" || fail 'Could not create the temporary download environment after preflight'
  run_install_step 'Graphify wheel download' "$STAGE/download-venv/bin/python" -m pip download --disable-pip-version-check --no-deps --dest "$STAGE" "$WHEEL_URL"
  wheel="$STAGE/$WHEEL_FILE"
  [ -f "$wheel" ] || fail "Downloaded wheel not found: $wheel"
  actual="$(sha256_file "$wheel")"
  [ "$actual" = "$WHEEL_SHA256" ] || fail "Graphify wheel checksum mismatch: $actual"
  backup="$(new_backup "$operation")"
  INSTALL_TARGET="$tool_dir"
  if [ "$operation" = repair ]; then RESTORE_BACKUP="$backup/original"; fi
  if [ "$operation" = repair ]; then rm -rf "$tool_dir"; fi
  mkdir -p "$tool_dir"
  printf '%s\n' "$PACKAGE_VERSION" > "$tool_dir/.dev-agent-config-installing"
  ensure_venv_pip "$python" "$tool_dir/venv" || fail 'Could not create the permanent Graphify virtual environment with pip'
  run_install_step 'Graphify installation' "$tool_dir/venv/bin/python" -m pip install --disable-pip-version-check "$wheel"
  [ "$("$tool_dir/venv/bin/python" -c 'from importlib.metadata import version; print(version("graphifyy"))')" = "$PACKAGE_VERSION" ] || fail 'Installed package version mismatch'
  [ -x "$graphify" ] || fail 'Graphify console script was not installed'
  entrypoint_healthy || fail "Graphify console script has a missing interpreter: $(entrypoint_interpreter || printf unknown)"
  case "$("$graphify" --version 2>/dev/null)" in
    *"$PACKAGE_VERSION"*) ;;
    *) fail 'Graphify CLI version check failed' ;;
  esac
  if [ "$verbose" -eq 1 ]; then
    "$tool_dir/venv/bin/python" -m pip freeze --all 2>&1 | tee "$tool_dir/dependencies.txt" | tee -a "$INSTALL_LOG" || fail 'Dependency recording failed'
  elif "$tool_dir/venv/bin/python" -m pip freeze --all > "$tool_dir/dependencies.txt" 2>> "$INSTALL_LOG"; then
    cat "$tool_dir/dependencies.txt" >> "$INSTALL_LOG"
  else
    fail 'Dependency recording failed'
  fi
  expected_marker > "$tool_dir/.dev-agent-config-tool"
  printf '%s\t%s\t%s\t%s\n' "$PACKAGE_VERSION" "$WHEEL_FILE" "$WHEEL_URL" "$WHEEL_SHA256" > "$tool_dir/release.tsv"
  cleanup_stage || fail 'Could not clean verified download staging directory'
  mkdir -p "$state_dir"
  release_tmp="$state_dir/.current-release.$$"
  printf '%s\t%s\t%s\t%s\n' "$PACKAGE_VERSION" "$WHEEL_FILE" "$WHEEL_URL" "$WHEEL_SHA256" > "$release_tmp"
  rm "$tool_dir/.dev-agent-config-installing"
  mv "$release_tmp" "$current_release"
  INSTALL_TARGET=''
  RESTORE_BACKUP=''
  say "INSTALLED Graphify $PACKAGE_VERSION"
  say "Dependencies: $tool_dir/dependencies.txt"
  say "Install log: $INSTALL_LOG"
  say "Rollback: $ROOT/scripts/tools.sh graphify rollback '$backup'"
}

check_update() {
  local python current='not installed'
  if resolve_active_release; then current="$PACKAGE_VERSION"; fi
  if ! python="$(python_command)"; then fail 'Update checking requires Python 3.10 or newer'; fi
  resolve_latest_release "$python" || fail 'Could not resolve the latest stable Graphify release from PyPI'
  say "Current Graphify: $current"
  say "Latest stable Graphify: $latest_version"
  if [ "$current" != 'not installed' ] && version_is_newer "$python" "$latest_version" "$current"; then
    say "Upgrade available. Preview with: $ROOT/scripts/tools.sh graphify upgrade --dry-run"
  fi
}

verify_tool() {
  local interpreter
  if ! resolve_active_release; then say 'Graphify: not installed'; return 1; fi
  validate_path "$tool_dir"
  case "$(path_type "$tool_dir")" in
    missing) say "Graphify $PACKAGE_VERSION: not installed"; return 1 ;;
    directory) ;;
    *) fail "Graphify path conflict: $tool_dir ($(path_type "$tool_dir"))" ;;
  esac
  marker_valid || fail "Graphify ownership metadata is missing or changed: $marker"
  [ -x "$graphify" ] || fail "Graphify executable is missing: $graphify"
  interpreter="$(entrypoint_interpreter)" || fail "Graphify console script has no valid shebang: $graphify. Repair with: $ROOT/scripts/tools.sh graphify repair --dry-run"
  case "$interpreter" in
    /*) [ -x "$interpreter" ] || fail "Graphify console script points to a missing interpreter: $interpreter. Repair with: $ROOT/scripts/tools.sh graphify repair --dry-run" ;;
    *) fail "Graphify console script has an unsupported interpreter: $interpreter. Repair with: $ROOT/scripts/tools.sh graphify repair --dry-run" ;;
  esac
  [ "$(installed_version || true)" = "$PACKAGE_VERSION" ] || fail "Graphify package is not version $PACKAGE_VERSION"
  cli_healthy || fail 'Graphify CLI health check failed'
  [ -f "$tool_dir/dependencies.txt" ] && [ ! -L "$tool_dir/dependencies.txt" ] || fail 'Dependency record is missing or unsafe'
  say "Graphify $PACKAGE_VERSION: healthy"
  say "Environment: $tool_dir/venv"
  say "Dependencies: $tool_dir/dependencies.txt"
}

remove_tool() {
  local dry="$1" backup
  if ! resolve_active_release; then say 'UNCHANGED Graphify: not installed'; return; fi
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
  if [ -f "$backup/release.tsv" ] && [ ! -L "$backup/release.tsv" ]; then
    IFS="$(printf '\t')" read -r release_version release_file release_url release_hash < "$backup/release.tsv"
    case "$release_version" in *[!0-9.]*|'') fail 'Backup release metadata is invalid' ;; esac
    [ "$release_file" = "graphifyy-$release_version-py3-none-any.whl" ] || fail 'Backup wheel metadata is invalid'
    case "$release_url" in https://files.pythonhosted.org/*) ;; *) fail 'Backup source metadata is invalid' ;; esac
    case "$release_hash" in *[!0-9a-f]*|'') fail 'Backup digest metadata is invalid' ;; esac
    [ "${#release_hash}" -eq 64 ] || fail 'Backup digest metadata is invalid'
    set_release "$release_version" "$release_file" "$release_url" "$release_hash"
  elif [ -e "$current_release" ] || [ -L "$current_release" ]; then
    load_current_release || fail 'Current release metadata is invalid; refusing legacy backup rollback'
  elif [ -f "$saved/release.tsv" ] && [ ! -L "$saved/release.tsv" ]; then
    IFS="$(printf '\t')" read -r release_version release_file release_url release_hash < "$saved/release.tsv"
    case "$release_version" in *[!0-9.]*|'') fail 'Backup release metadata is invalid' ;; esac
    [ "$release_file" = "graphifyy-$release_version-py3-none-any.whl" ] || fail 'Backup wheel metadata is invalid'
    case "$release_url" in https://files.pythonhosted.org/*) ;; *) fail 'Backup source metadata is invalid' ;; esac
    case "$release_hash" in *[!0-9a-f]*|'') fail 'Backup digest metadata is invalid' ;; esac
    [ "${#release_hash}" -eq 64 ] || fail 'Backup digest metadata is invalid'
    set_release "$release_version" "$release_file" "$release_url" "$release_hash"
  elif [ "$version" = "$PINNED_VERSION" ]; then
    set_release "$PINNED_VERSION" "$PINNED_WHEEL_FILE" "$PINNED_WHEEL_URL" "$PINNED_WHEEL_SHA256"
  else
    fail 'Backup release metadata is missing or unsafe'
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
    if [ "$current" != missing ]; then
      if [ "$action" = repair ] && [ "$current" = directory ] && marker_valid && healthy; then
        [ "$dry" -eq 1 ] || rm -rf "$target"
      else
        fail 'Refusing to overwrite an existing or unexpected path during rollback'
      fi
    fi
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
  local dry="$1" project="$2" output="$3" final output_physical report_status index_marker
  resolve_active_release || fail 'No validated active Graphify installation is recorded; install Graphify first'
  [ -n "$project" ] || fail 'Indexing requires --project PATH'
  [ -d "$project" ] && [ ! -L "$project" ] || fail "Project must be a real directory, not a symlink: $project"
  project="$(cd "$project" && pwd -P)"
  if [ -z "$output" ]; then
    output="$(project_index_root "$project")"
  fi
  case "$output" in /*) ;; *) fail "Output root must be absolute: $output" ;; esac
  output="${output%/}"
  validate_path "$output"
  output_physical="$(physical_path "$output")"
  case "$output_physical" in "$project"|"$project"/*) fail 'Graphify output must be outside the source project' ;; esac
  healthy || fail "Graphify $PACKAGE_VERSION is not installed and healthy"
  final="$output/graphify-out"
  index_marker="$final/.dev-agent-config-index"
  if [ -e "$index_marker" ] || [ -L "$index_marker" ]; then
    [ -f "$index_marker" ] && [ ! -L "$index_marker" ] && expected_index_marker | cmp -s - "$index_marker" || fail "Graph output ownership conflict: $index_marker"
  fi
  say "$( [ "$dry" -eq 1 ] && printf WOULD_INDEX || printf INDEXING ) code: $project"
  say "Graph output: $final"
  [ "$dry" -eq 0 ] || return 0
  mkdir -p "$output"
  GRAPHIFY_OUT="$final" run_graphify_checked 'code-only extraction' extract "$project" --out "$output" --code-only
  [ -f "$final/graph.json" ] && [ ! -L "$final/graph.json" ] || fail "Graphify did not create expected output: $final/graph.json"
  valid_node_link_graph "$final/graph.json" || fail "Graphify created invalid node-link JSON: $final/graph.json"
  expected_index_marker > "$index_marker"
  say "INDEXED code-only graph: $final"
  if [ -f "$final/GRAPH_REPORT.md" ]; then
    say "REPORT generated during extraction: $final/GRAPH_REPORT.md"
    return 0
  fi
  if GRAPHIFY_OUT="$final" run_graphify cluster-only "$output" --graph "$final/graph.json" --no-label --no-viz; then
    report_status=generated
  else
    report_status=unavailable
  fi
  if [ "$report_status" = generated ] && [ -f "$final/GRAPH_REPORT.md" ] && [ ! -L "$final/GRAPH_REPORT.md" ]; then
    say "REPORT generated without labels or visualization: $final/GRAPH_REPORT.md"
  else
    say "WARNING: Graph extraction succeeded, but the optional report could not be generated: $final/GRAPH_REPORT.md" >&2
  fi
}

clean_project() {
  local dry="$1" selected="$2" output="$3" project='' expected='' final='' marker='' entry base
  [ -n "$selected" ] || fail 'Clean requires --project PATH'
  [ -d "$selected" ] && [ ! -L "$selected" ] || fail "Project must be a real directory, not a symlink: $selected"
  project="$(cd "$selected" && pwd -P)"
  expected="$(project_index_root "$project")"
  [ -n "$output" ] || output="$expected"
  case "$output" in /*) ;; *) fail "Output root must be absolute: $output" ;; esac
  output="${output%/}"
  validate_path "$output/graphify-out"
  case "$(physical_path "$output")" in "$project"|"$project"/*) fail 'Graphify output must be outside the source project' ;; esac
  final="$output/graphify-out"
  case "$(path_type "$final")" in
    missing) say "UNCHANGED: no generated Graphify index at $final"; return ;;
    directory) ;;
    *) fail "Refusing unsafe generated index path: $final ($(path_type "$final"))" ;;
  esac
  marker="$final/.dev-agent-config-index"
  if [ -e "$marker" ] || [ -L "$marker" ]; then
    [ -f "$marker" ] && [ ! -L "$marker" ] && expected_index_marker | cmp -s - "$marker" || fail "Index ownership metadata is missing, changed, or belongs to another project: $marker"
  else
    [ "$output" = "$expected" ] && [ -f "$final/graph.json" ] && [ ! -L "$final/graph.json" ] || fail "Cannot safely identify this index. Re-index this project with the manager, then retry clean."
  fi
  for entry in "$final"/* "$final"/.[!.]*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    base="$(basename "$entry")"
    case "$base" in graph.json|GRAPH_REPORT.md|graph.html|.dev-agent-config-index) ;; *) fail "Refusing to delete unrecognized index data: $entry" ;; esac
    [ -f "$entry" ] && [ ! -L "$entry" ] || fail "Refusing unsafe index entry: $entry"
  done
  say "$( [ "$dry" -eq 1 ] && printf WOULD_CLEAN || printf CLEANING ) generated Graphify index: $final"
  [ "$dry" -eq 0 ] || return 0
  rm -f -- "$final/graph.json" "$final/GRAPH_REPORT.md" "$final/graph.html" "$marker"
  rmdir "$final" || fail "Index files were removed, but unexpected data remains in: $final"
  say "CLEANED generated Graphify index for $project; Graphify remains installed"
}

query_project() {
  local selected="$1" question="$2" budget="$3" selected_output="$4" project='' graph=''
  [ -n "$question" ] || fail 'Query requires a question in quotes'
  resolve_project_graph "$selected" "$selected_output"
  say "Querying Graphify graph: $graph"
  if [ -n "$budget" ]; then
    run_graphify_checked query query "$question" --budget "$budget" --graph "$graph"
  else
    run_graphify_checked query query "$question" --graph "$graph"
  fi
  say "QUERY completed: $graph"
}

report_project() {
  local selected="$1" selected_output="$2" project='' graph='' output final
  resolve_project_graph "$selected" "$selected_output"
  output="${graph%/graphify-out/graph.json}"
  final="$output/graphify-out"
  say "Generating code-only architecture report from existing graph: $graph"
  GRAPHIFY_OUT="$final" run_graphify_checked report cluster-only "$output" --graph "$graph" --no-label --no-viz
  [ -f "$final/GRAPH_REPORT.md" ] && [ ! -L "$final/GRAPH_REPORT.md" ] || fail "Graphify did not create the expected report: $final/GRAPH_REPORT.md"
  say "REPORT: $final/GRAPH_REPORT.md"
}

open_graph_html() {
  local html="$1" os
  if [ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-}${VSCODE_AGENT_FOLDER:-}${VSCODE_IPC_HOOK_CLI:-}${REMOTE_CONTAINERS:-}" ]; then
    say "Remote session detected; not launching a browser. Open this remote file in VS Code: $html"
    return 0
  fi
  os="$(uname -s)"
  if [ "$os" = Darwin ]; then
    command -v open >/dev/null 2>&1 || { say "WARNING: No macOS browser opener found; HTML: $html" >&2; return 0; }
    open "$html" || say "WARNING: Browser could not open the generated HTML: $html" >&2
  elif [ "$os" = Linux ]; then
    if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
      say "No desktop display detected; not launching a browser. HTML: $html"
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$html" || say "WARNING: Browser could not open the generated HTML: $html" >&2
    elif command -v gio >/dev/null 2>&1; then
      gio open "$html" || say "WARNING: Browser could not open the generated HTML: $html" >&2
    else
      say "WARNING: No Linux browser opener found; HTML: $html" >&2
    fi
  else
    say "WARNING: Browser opening is unsupported on $os; HTML: $html" >&2
  fi
}

visualize_project() {
  local selected="$1" should_open="$2" selected_output="$3" project='' graph='' final html
  resolve_project_graph "$selected" "$selected_output"
  final="$(dirname "$graph")"
  html="$final/graph.html"
  say "Generating native Graphify visualization from existing graph: $graph"
  (cd "$(dirname "$final")" && GRAPHIFY_OUT="$final" run_graphify_checked visualization export html --graph "$graph")
  [ -f "$html" ] && [ ! -L "$html" ] || fail "Graphify did not create the expected visualization: $html"
  say "VISUALIZATION: $html"
  if [ "$should_open" -eq 1 ]; then open_graph_html "$html"; fi
}

usage() {
  printf 'Usage: %s {install|repair|check-update|upgrade|verify|remove|rollback|index|query|report|visualize|clean} [OPTIONS]\n' "$ROOT/scripts/tools.sh graphify" >&2
  exit 1
}

action="${1:-}"
shift || true
dry=0
project=''
output=''
backup=''
question=''
budget=''
should_open=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --project) shift; [ "$#" -gt 0 ] || usage; project="$1" ;;
    --output) shift; [ "$#" -gt 0 ] || usage; output="$1" ;;
    --budget) shift; [ "$#" -gt 0 ] || usage; budget="$1" ;;
    --open) should_open=1 ;;
    --verbose) verbose=1 ;;
    --*) usage ;;
    *)
      if [ "$action" = rollback ] && [ -z "$backup" ]; then backup="$1"
      elif [ "$action" = query ] && [ -z "$question" ]; then question="$1"
      else usage
      fi
      ;;
  esac
  shift
done

case "$action" in
  install) [ -z "$project$output$backup" ] || usage; install_tool "$dry" ;;
  repair) [ -z "$project$output$backup" ] || usage; install_tool "$dry" repair ;;
  check-update) [ "$dry" -eq 0 ] && [ -z "$project$output$backup" ] || usage; check_update ;;
  upgrade) [ -z "$project$output$backup" ] || usage; install_tool "$dry" upgrade ;;
  verify) [ "$dry" -eq 0 ] && [ -z "$project$output$backup" ] || usage; verify_tool ;;
  remove) [ -z "$project$output$backup" ] || usage; remove_tool "$dry" ;;
  rollback) [ -z "$project$output" ] || usage; rollback_tool "$dry" "$backup" ;;
  index) [ -z "$backup$budget$question" ] && [ "$should_open" -eq 0 ] || usage; index_project "$dry" "$project" "$output" ;;
  query)
    [ "$dry" -eq 0 ] && [ -z "$backup" ] && [ "$should_open" -eq 0 ] || usage
    case "$budget" in ''|*[!0-9]*|0*) [ -z "$budget" ] || usage ;; esac
    query_project "$project" "$question" "$budget" "$output"
    ;;
  report) [ "$dry" -eq 0 ] && [ -z "$backup$budget$question" ] && [ "$should_open" -eq 0 ] || usage; report_project "$project" "$output" ;;
  visualize) [ "$dry" -eq 0 ] && [ -z "$backup$budget$question" ] || usage; visualize_project "$project" "$should_open" "$output" ;;
  clean) [ -z "$backup$budget$question" ] && [ "$should_open" -eq 0 ] || usage; clean_project "$dry" "$project" "$output" ;;
  *) usage ;;
esac
