#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
. "$ROOT/tools/codebase-memory-mcp/tool.conf"

SERVER_NAME=codebase-memory-mcp
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$STATE_HOME/dev-agent-config/tools/codebase-memory-mcp"
ADOPTION="$STATE_DIR/adoption.tsv"
MCP_OWNERSHIP="$STATE_DIR/codex-mcp.tsv"
BACKUPS="$STATE_DIR/backups"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
MANAGED_DIR="$DATA_HOME/dev-agent-config/tools/codebase-memory-mcp"
VERSIONS_DIR="$MANAGED_DIR/versions"
ACTIVE_FILE="$STATE_DIR/active-version"
TRANSACTION_FILE="$STATE_DIR/last-upgrade.tsv"
BIN_DIR="$HOME/.local/bin"
MANAGED_LINK="$BIN_DIR/codebase-memory-mcp"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_CONFIG="$CODEX_HOME/config.toml"
OPENCODE_CONFIG="${OPENCODE_CONFIG:-${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}/opencode.json}"
OPENCODE_OWNERSHIP="$STATE_DIR/opencode-mcp.tsv"
DASHBOARD_DIR="$STATE_DIR/dashboard"
DASHBOARD_META="$DASHBOARD_DIR/process.tsv"
RUNNER="$ROOT/scripts/tools/cbm-dashboard-runner.py"
SERVICE_META="$STATE_DIR/dashboard-service.tsv"
SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SYSTEMD_UNIT="$SYSTEMD_DIR/dev-agent-config-cbm-dashboard.service"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT="$LAUNCH_AGENT_DIR/org.dev-agent-config.cbm-dashboard.plist"
SERVICE_LABEL=org.dev-agent-config.cbm-dashboard

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
usage() {
  cat <<EOF
Usage: dev-agent-config tools codebase-memory-mcp COMMAND [OPTIONS]

Commands:
  status [--project PATH]        Report binary state or project index status
  verify                         Check executable and safe --version health
  install [--dry-run]            Install the verified pinned official binary
  check-update [--dry-run]       Report the latest stable version
  upgrade [--dry-run]            Install latest stable, retain previous version
  rollback [--dry-run]           Reactivate the previous managed version
  remove [--dry-run]             Remove manager-owned binary files only
  adopt [--dry-run]              Record an existing installation as external
  mcp status [codex|opencode]    Report MCP registration and ownership
  mcp enable {codex|opencode} [--dry-run]
  mcp disable {codex|opencode} [--dry-run]
  index [--project PATH]       Index the selected repository (defaults to valid PWD)
  project status [--project PATH]
  refresh [--project PATH] [--dry-run]
  clean [--project PATH] [--dry-run]  Delete only indexes created by this manager
  dashboard start [--port N] [--dry-run]
  dashboard stop [--dry-run]
  dashboard status
  service install [--port N] [--dry-run]
  service enable|disable|verify|remove [--dry-run]
  watcher status | watcher set {enabled|disabled} [--dry-run]
  run [--dry-run] [--no-dashboard] [--no-mcp] [--agent codex|opencode] [--refresh] [--port N]
                               Bootstrap CBM for the current Git repository

Adoption never installs, moves, or owns the CBM binary. MCP changes preserve
unrelated settings. Project cleanup only targets manager-mapped CBM indexes.
EOF
  exit "${1:-0}"
}

safe_user_path() {
  local path="$1" current remainder component
  case "$path" in /*) ;; *) die "Path must be absolute: $path" ;; esac
  case "$path" in *'/../'*|*'/..') die "Path must not contain ..: $path" ;; esac
  case "$path" in
    "$HOME"|"$HOME"/*)
      [ ! -L "$HOME" ] || die "Refusing symlink HOME: $HOME"
      current="$(cd -P "$HOME" && pwd)"
      remainder="${path#"$HOME"}"
      while [ -n "$remainder" ]; do
        remainder="${remainder#/}"
        component="${remainder%%/*}"
        [ -n "$component" ] || break
        current="$current/$component"
        [ ! -L "$current" ] || die "Refusing symlink path component: $current"
        remainder="${remainder#"$component"}"
      done
      ;;
    *)
      # CODEX_HOME/XDG roots explicitly outside HOME are caller-selected; reject
      # a symlink target itself but allow platform aliases in ancestor paths.
      [ ! -L "$path" ] || die "Refusing symlink path: $path"
      ;;
  esac
}

safe_state() {
  local path="$STATE_HOME" part
  safe_user_path "$STATE_HOME"
  [ ! -L "$path" ] || die "Refusing symlink manager state root: $path"
  [ ! -e "$path" ] || [ -d "$path" ] || die "Manager state root is not a directory: $path"
  for part in dev-agent-config tools codebase-memory-mcp; do
    path="$path/$part"
    [ ! -L "$path" ] || die "Refusing symlink manager state path: $path"
    [ ! -e "$path" ] || [ -d "$path" ] || die "Manager state path is not a directory: $path"
  done
}

prepare_state() {
  local path="$STATE_HOME" part
  safe_state
  [ -d "$path" ] || mkdir -p "$path"
  for part in dev-agent-config tools codebase-memory-mcp; do
    path="$path/$part"
    [ -d "$path" ] || mkdir "$path"
  done
}

find_binary() {
  local candidate="$HOME/.local/bin/codebase-memory-mcp"
  if [ -L "$candidate" ] || [ -e "$candidate" ]; then printf '%s\n' "$candidate"; return; fi
  command -v codebase-memory-mcp 2>/dev/null || true
}

resolved_binary() {
  local path="$1" dir target hops=0
  [ -n "$path" ] || return 1
  case "$path" in /*) ;; *) path="$(command -v "$path" 2>/dev/null || printf '%s' "$path")" ;; esac
  while [ -L "$path" ]; do
    hops=$((hops + 1)); [ "$hops" -le 40 ] || return 1
    dir="$(cd -P "$(dirname "$path")" 2>/dev/null && pwd)" || return 1
    target="$(readlink "$path")" || return 1
    case "$target" in /*) path="$target" ;; *) path="$dir/$target" ;; esac
  done
  [ -f "$path" ] && [ -x "$path" ] || return 1
  dir="$(cd -P "$(dirname "$path")" && pwd)" || return 1
  printf '%s/%s\n' "$dir" "$(basename "$path")"
}

version_of() {
  local binary="$1" output
  output="$("$binary" --version 2>&1)" || return 1
  [ -n "$output" ] || return 1
  printf '%s\n' "$output" | tr '\n' ' '
}

codex_cli() {
  local cli
  cli="$(command -v codex 2>/dev/null || true)"
  [ -n "$cli" ] || die "Codex CLI is required to safely manage MCP entries; config: $CODEX_CONFIG"
  CODEX_HOME="$CODEX_HOME" "$cli" "$@"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else die 'SHA-256 utility required (sha256sum or shasum)'; fi
}

platform_asset() {
  local os arch
  case "$(uname -s)" in Darwin) os=darwin ;; Linux) os=linux ;; *) die "Unsupported OS: $(uname -s)" ;; esac
  case "$(uname -m)" in x86_64|amd64) arch=amd64 ;; arm64|aarch64) arch=arm64 ;; *) die "Unsupported architecture: $(uname -m)" ;; esac
  if [ "$os" = linux ]; then printf 'codebase-memory-mcp-%s-%s-portable.tar.gz\n' "$os" "$arch"
  else printf 'codebase-memory-mcp-%s-%s.tar.gz\n' "$os" "$arch"; fi
}

download_file() {
  local url="$1" destination="$2" progress="${3:-0}"
  case "$url" in https://github.com/DeusData/codebase-memory-mcp/*|https://api.github.com/repos/DeusData/codebase-memory-mcp/*) ;; *) die "Refusing non-official download URL: $url" ;; esac
  if command -v curl >/dev/null 2>&1; then
    if [ "$progress" = 1 ]; then
      curl --fail --show-error --location --progress-bar --proto '=https' --proto-redir '=https' --output "$destination" "$url"
    else curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --output "$destination" "$url"; fi
  elif command -v wget >/dev/null 2>&1; then
    if [ "$progress" = 1 ]; then wget --https-only --show-progress --output-document="$destination" "$url"
    else wget --https-only --quiet --output-document="$destination" "$url"; fi
  else die 'Install requires curl or wget'; fi
}

latest_stable_version() {
  local response tag
  response="$(mktemp "${TMPDIR:-/tmp}/dev-agent-config-cbm-release.XXXXXX")" || die 'Could not create a private release metadata file'
  [ ! -L "$response" ] || die 'Private release metadata path is a symlink'
  if ! download_file 'https://api.github.com/repos/DeusData/codebase-memory-mcp/releases/latest' "$response"; then
    rm -f "$response"
    die 'Could not query GitHub for the latest stable CBM release'
  fi
  tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([0-9][0-9.]*\)".*/\1/p' "$response" | head -n 1)"
  rm -f "$response"
  [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'GitHub latest-release response did not contain a stable semantic version'
  printf '%s\n' "$tag"
}

version_dir() { printf '%s/%s\n' "$VERSIONS_DIR" "$1"; }
version_meta() { printf '%s/.manager-owned.tsv\n' "$(version_dir "$1")"; }

is_manager_version() {
  local version="$1" dir meta binary expected actual
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  dir="$(version_dir "$version")"; meta="$(version_meta "$version")"; binary="$dir/codebase-memory-mcp"
  [ -d "$dir" ] && [ ! -L "$dir" ] && [ -f "$meta" ] && [ ! -L "$meta" ] && [ -f "$binary" ] && [ ! -L "$binary" ] && [ -x "$binary" ] || return 1
  grep -qFx "ownership${TAB}dev-agent-config" "$meta" || return 1
  grep -qFx "version${TAB}$version" "$meta" || return 1
  expected="$(awk -F '\t' '$1 == "binary_sha256" {print $2}' "$meta")"
  [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || return 1
  actual="$(sha256_file "$binary")" || return 1
  [ "$actual" = "$expected" ]
}

active_version() {
  local version
  ensure_manager_roots
  [ -f "$ACTIVE_FILE" ] && [ ! -L "$ACTIVE_FILE" ] || return 1
  version="$(sed -n '1p' "$ACTIVE_FILE")"
  is_manager_version "$version" || return 1
  printf '%s\n' "$version"
}

ensure_manager_roots() {
  local dir
  safe_state
  safe_user_path "$DATA_HOME"
  safe_user_path "$BIN_DIR"
  for dir in "$DATA_HOME" "$DATA_HOME/dev-agent-config" "$DATA_HOME/dev-agent-config/tools" "$MANAGED_DIR" "$VERSIONS_DIR" "$BIN_DIR"; do
    [ ! -L "$dir" ] || die "Refusing symlink in manager installation path: $dir"
    [ ! -e "$dir" ] || [ -d "$dir" ] || die "Manager installation path is not a directory: $dir"
  done
}

check_link_ownership() {
  local target current
  if [ -e "$MANAGED_LINK" ] || [ -L "$MANAGED_LINK" ]; then
    [ -L "$MANAGED_LINK" ] || die "Refusing to overwrite existing executable: $MANAGED_LINK"
    target="$(resolved_binary "$MANAGED_LINK" 2>/dev/null || true)"
    [ -n "$target" ] || die "Refusing broken or unsafe executable symlink: $MANAGED_LINK"
    current="$(active_version 2>/dev/null || true)"
    [ -n "$current" ] || die "Existing executable symlink is not proven manager-owned: $MANAGED_LINK -> $target"
    [ "$target" = "$(resolved_binary "$(version_dir "$current")/codebase-memory-mcp")" ] || die "Executable symlink conflicts with manager metadata: $MANAGED_LINK -> $target"
  fi
}

activate_version() {
  local version="$1" link_tmp="$BIN_DIR/.codebase-memory-mcp.link.$$" active_tmp="$ACTIVE_FILE.tmp.$$" existing=''
  if [ -e "$ACTIVE_FILE" ] || [ -L "$ACTIVE_FILE" ]; then
    [ -f "$ACTIVE_FILE" ] && [ ! -L "$ACTIVE_FILE" ] || die "Unexpected active-version metadata: $ACTIVE_FILE"
    existing="$(active_version 2>/dev/null || true)"
    [ -n "$existing" ] || die "Active-version metadata is invalid: $ACTIVE_FILE"
  fi
  ensure_manager_roots
  prepare_state
  is_manager_version "$version" || die "Version $version is not a valid manager-owned installation"
  check_link_ownership
  mkdir -p "$BIN_DIR"
  [ ! -e "$link_tmp" ] && [ ! -L "$link_tmp" ] || die "Temporary activation path exists: $link_tmp"
  ln -s "$(version_dir "$version")/codebase-memory-mcp" "$link_tmp"
  if [ -e "$MANAGED_LINK" ] || [ -L "$MANAGED_LINK" ]; then mv -f "$link_tmp" "$MANAGED_LINK"; else mv "$link_tmp" "$MANAGED_LINK"; fi
  (umask 077; printf '%s\n' "$version" > "$active_tmp")
  if ! mv "$active_tmp" "$ACTIVE_FILE"; then
    if [ -n "$existing" ] && is_manager_version "$existing"; then
      ln -s "$(version_dir "$existing")/codebase-memory-mcp" "$link_tmp" 2>/dev/null && mv -f "$link_tmp" "$MANAGED_LINK" || :
    else rm -f "$MANAGED_LINK"; fi
    rm -f "$active_tmp"
    die "Could not commit active CBM version $version; restored prior executable selection"
  fi
}

install_version() {
  local version="$1" dry="$2" asset archive checksums expected actual stage final old created_final=0 checksum_size
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid release version: $version"
  ensure_manager_roots
  check_link_ownership
  final="$(version_dir "$version")"
  if is_manager_version "$version"; then
    if [ "$dry" -eq 1 ]; then say "WOULD_ACTIVATE existing verified manager-owned CBM $version"; return; fi
    old="$(active_version 2>/dev/null || true)"
    if [ "$old" = "$version" ]; then say "UNCHANGED: manager-owned CBM $version is healthy"; return; fi
    [ -n "$old" ] || old=none
    activate_version "$version"
    [ "$old" = none ] || printf 'previous\t%s\nnext\t%s\n' "$old" "$version" > "$TRANSACTION_FILE"
    say "UNCHANGED: manager-owned CBM $version is healthy"
    return
  fi
  if [ -e "$final" ] || [ -L "$final" ]; then die "Unexpected version path exists; refusing overwrite: $final"; fi
  asset="$(platform_asset)"
  if [ "$dry" -eq 1 ]; then
    say "WOULD_INSTALL CBM $version for $(uname -s)/$(uname -m)"
    say "Official archive: https://github.com/DeusData/codebase-memory-mcp/releases/download/v$version/$asset"
    say "Destination: $final"
    return
  fi
  mkdir -p "$VERSIONS_DIR"
  stage="$MANAGED_DIR/.stage.$$.${RANDOM:-0}"
  [ ! -e "$stage" ] && [ ! -L "$stage" ] || die "Staging path exists: $stage"
  mkdir "$stage"
  trap 'stage_cleanup' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  archive="$stage/$asset"; checksums="$stage/checksums.txt"
  say "Downloading official CBM $version release archive..."
  download_file "https://github.com/DeusData/codebase-memory-mcp/releases/download/v$version/$asset" "$archive" 1 || die "Download failed; staging data: $stage"
  say 'Downloading official release checksums...'
  download_file "https://github.com/DeusData/codebase-memory-mcp/releases/download/v$version/checksums.txt" "$checksums" 1 || die "Official release checksum file unavailable; staging data: $stage"
  checksum_size="$(wc -c < "$checksums" | tr -d '[:space:]')"
  [[ "$checksum_size" =~ ^[0-9]+$ ]] && [ "$checksum_size" -le 1048576 ] || die 'Official release checksum file is invalid or too large'
  expected="$(awk -v file="$asset" '
    $2 == file || $2 == "*" file {
      value=tolower($1)
      if (length(value)!=64 || value ~ /[^a-f0-9]/) bad=1
      if (found && digest!=value) bad=1
      digest=value; found=1
    }
    END { if (bad || !found) exit 1; print digest }
  ' "$checksums")" || die "Official release checksum missing, invalid, or conflicting for $asset"
  say 'Verifying release SHA-256...'
  actual="$(sha256_file "$archive")"
  expected="$(printf '%s' "$expected" | tr 'A-F' 'a-f')"
  actual="$(printf '%s' "$actual" | tr 'A-F' 'a-f')"
  [ "$actual" = "$expected" ] || die "SHA-256 mismatch for $asset; no installation activated"
  tar -tzf "$archive" > "$stage/members.txt" || die 'Downloaded release archive is invalid'
  # Only the exact binary member is streamed to stdout; other archive paths are
  # never extracted into the filesystem, so harmless upstream metadata is safe.
  awk '$0 == "codebase-memory-mcp" {count++} END{exit !(count==1)}' "$stage/members.txt" || die 'Release archive must contain exactly one codebase-memory-mcp executable'
  tar -xOzf "$archive" codebase-memory-mcp > "$stage/codebase-memory-mcp" || die 'Could not extract the verified CBM executable'
  chmod 755 "$stage/codebase-memory-mcp"
  say 'Checking downloaded CBM executable...'
  version_output="$("$stage/codebase-memory-mcp" --version 2>&1)" || die 'Staged CBM executable failed --version'
  case "$version_output" in *"$version"*) ;; *) die "Staged binary version mismatch: expected $version; got $version_output" ;; esac
  actual="$(sha256_file "$stage/codebase-memory-mcp")"
  mkdir "$final"
  created_final=1
  mv "$stage/codebase-memory-mcp" "$final/codebase-memory-mcp"
  (umask 077; printf 'ownership\tdev-agent-config\nversion\t%s\nplatform\t%s/%s\narchive\t%s\narchive_sha256\t%s\nbinary_sha256\t%s\nsource\t%s\nlicense\t%s\n' \
    "$version" "$(uname -s)" "$(uname -m)" "$asset" "$expected" "$actual" "$SOURCE_URL" "$LICENSE" > "$final/.manager-owned.tsv")
  is_manager_version "$version" || die 'Installed binary failed manager ownership/integrity validation'
  version_output="$("$final/codebase-memory-mcp" --version 2>&1)" || die 'Final-destination CBM binary failed --version'
  case "$version_output" in *"$version"*) ;; *) die "Final-destination CBM version mismatch: expected $version; got $version_output" ;; esac
  old="$(active_version 2>/dev/null || true)"
  [ -n "$old" ] || old=none
  say 'Activating verified CBM installation...'
  activate_version "$version"
  [ "$old" = none ] || printf 'previous\t%s\nnext\t%s\n' "$old" "$version" > "$TRANSACTION_FILE"
  created_final=0
  rm -rf "$stage"
  trap - EXIT HUP INT TERM
  say "INSTALLED: CBM $version ($(uname -s)/$(uname -m))"
  say "Executable: $MANAGED_LINK"
  say "Verified SHA-256: $actual"
}

stage_cleanup() {
  local status=$?
  if [ -n "${stage:-}" ] && [ -d "$stage" ] && [ ! -L "$stage" ]; then rm -rf "$stage" 2>/dev/null || :; fi
  if [ "$status" -ne 0 ]; then
    # A failed candidate must not become active or leave misleading ownership.
    if [ "${created_final:-0}" -eq 1 ]; then
      local pointed=''
      [ ! -L "$MANAGED_LINK" ] || pointed="$(resolved_binary "$MANAGED_LINK" 2>/dev/null || true)"
      if [ "$pointed" = "$(resolved_binary "$final/codebase-memory-mcp" 2>/dev/null || true)" ]; then
        if [[ "${old:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && is_manager_version "$old"; then
          local restore_link="$BIN_DIR/.codebase-memory-mcp.restore.$$" restore_active="$ACTIVE_FILE.restore.$$"
          if [ ! -e "$restore_link" ] && [ ! -L "$restore_link" ] && [ ! -e "$restore_active" ] && [ ! -L "$restore_active" ]; then
            ln -s "$(version_dir "$old")/codebase-memory-mcp" "$restore_link" && mv -f "$restore_link" "$MANAGED_LINK" || :
            (umask 077; printf '%s\n' "$old" > "$restore_active") && mv -f "$restore_active" "$ACTIVE_FILE" || :
          fi
        elif [ "${old:-}" = none ]; then
          rm -f "$MANAGED_LINK"
          [ "$(sed -n '1p' "$ACTIVE_FILE" 2>/dev/null || true)" != "$(basename "$final")" ] || rm -f "$ACTIVE_FILE"
        fi
      fi
    fi
    if [ "${created_final:-0}" -eq 1 ] && [ -d "$final" ] && [ ! -L "$final" ]; then
      local recorded
      if [ -f "$final/.manager-owned.tsv" ] && [ ! -L "$final/.manager-owned.tsv" ] &&
        grep -qFx $'ownership\tdev-agent-config' "$final/.manager-owned.tsv" &&
        grep -qFx $'version\t'"$(basename "$final")" "$final/.manager-owned.tsv" &&
        [ -f "$final/codebase-memory-mcp" ] && [ ! -L "$final/codebase-memory-mcp" ]; then
        recorded="$(awk -F '\t' '$1=="binary_sha256"{print $2}' "$final/.manager-owned.tsv")"
        if [ "$recorded" = "$(sha256_file "$final/codebase-memory-mcp" 2>/dev/null || true)" ]; then
          rm "$final/codebase-memory-mcp" "$final/.manager-owned.tsv" 2>/dev/null || :
          rmdir "$final" 2>/dev/null || :
        fi
      elif [ -f "$final/codebase-memory-mcp" ] && [ ! -L "$final/codebase-memory-mcp" ] &&
        [[ "${actual:-}" =~ ^[a-fA-F0-9]{64}$ ]] &&
        [ "$(sha256_file "$final/codebase-memory-mcp" 2>/dev/null || true)" = "$actual" ]; then
        rm "$final/codebase-memory-mcp" 2>/dev/null || :
        rmdir "$final" 2>/dev/null || :
      elif [ -z "$(find "$final" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
        rmdir "$final" 2>/dev/null || :
      fi
    fi
  fi
  return "$status"
}

check_update() {
  local dry="$1" current latest
  [ "$dry" -eq 0 ] || { say "WOULD_CHECK_UPDATE official GitHub latest stable release"; return; }
  current="$(active_version 2>/dev/null || adoption_version 2>/dev/null || printf unknown)"
  latest="$(latest_stable_version)"
  say "Current: $current"
  say "Available stable: $latest"
  [ "$current" = "$latest" ] && say 'Status: up to date' || say 'Status: update available (run upgrade explicitly)'
}

adoption_version() {
  [ -f "$ADOPTION" ] && [ ! -L "$ADOPTION" ] || return 1
  awk -F '\t' '$1 == "version" {print $2}' "$ADOPTION" | head -n1
}

remove_managed() {
  local dry="$1" version dir meta binary active
  ensure_manager_roots
  active="$(active_version 2>/dev/null || true)"
  [ -n "$active" ] || die 'No validated manager-owned CBM installation to remove; external installations are never removed'
  if [ -e "$DASHBOARD_META" ] || [ -L "$DASHBOARD_META" ]; then
    dashboard_owned_process "$(dashboard_pid)" "$(dashboard_nonce)" && die 'Stop the manager-owned dashboard before removing CBM binaries'
    dashboard_status >/dev/null
  fi
  check_link_ownership
  [ "$dry" -eq 1 ] && { say "WOULD_REMOVE manager-owned CBM version $active"; say "Executable link: $MANAGED_LINK"; say "Managed versions: $VERSIONS_DIR"; say 'Caches, indexes, MCP config, and dashboard settings will be preserved.'; return; }
  if [ -e "$MANAGED_LINK" ] || [ -L "$MANAGED_LINK" ]; then
    [ -L "$MANAGED_LINK" ] || die "Refusing to remove unexpected executable: $MANAGED_LINK"
    [ "$(resolved_binary "$MANAGED_LINK")" = "$(resolved_binary "$(version_dir "$active")/codebase-memory-mcp")" ] || die 'Active executable link changed; refusing removal'
  fi
  for dir in "$VERSIONS_DIR"/*; do
    [ -e "$dir" ] || [ -L "$dir" ] || continue
    [ -d "$dir" ] && [ ! -L "$dir" ] || die "Unexpected manager version entry; refusing remove: $dir"
    version="$(basename "$dir")"; is_manager_version "$version" || die "Modified/unowned version; refusing remove: $dir"
    meta="$dir/.manager-owned.tsv"; binary="$dir/codebase-memory-mcp"
    [ "$(find "$dir" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 2 ] || die "Unexpected files in manager-owned version; refusing remove: $dir"
    [ ! -L "$meta" ] && [ ! -L "$binary" ] || die "Symlink conflict in manager-owned version: $dir"
  done
  [ ! -L "$MANAGED_LINK" ] || rm "$MANAGED_LINK"
  # Remove inactive versions first so an interrupted cleanup leaves the active
  # pointer valid and makes a retry safe.
  for dir in "$VERSIONS_DIR"/*; do
    [ -e "$dir" ] || [ -L "$dir" ] || continue
    version="$(basename "$dir")"
    [ "$version" = "$active" ] && continue
    meta="$dir/.manager-owned.tsv"; binary="$dir/codebase-memory-mcp"
    rm "$binary" "$meta"; rmdir "$dir"
  done
  dir="$(version_dir "$active")"; meta="$dir/.manager-owned.tsv"; binary="$dir/codebase-memory-mcp"
  if [ -d "$dir" ] && [ ! -L "$dir" ]; then rm "$binary" "$meta"; rmdir "$dir"; fi
  rmdir "$VERSIONS_DIR" 2>/dev/null || :
  rm "$ACTIVE_FILE"; [ ! -e "$TRANSACTION_FILE" ] || rm "$TRANSACTION_FILE"
  say 'REMOVED manager-owned CBM binaries and executable link.'
  say 'External binaries, caches, indexes, MCP config, and dashboard settings were preserved.'
}

rollback_managed() {
  local dry="$1" previous next current
  [ -f "$TRANSACTION_FILE" ] && [ ! -L "$TRANSACTION_FILE" ] || die 'No recorded managed upgrade to roll back'
  previous="$(awk -F '\t' '$1 == "previous" {print $2}' "$TRANSACTION_FILE")"
  next="$(awk -F '\t' '$1 == "next" {print $2}' "$TRANSACTION_FILE")"
  current="$(active_version 2>/dev/null || true)"
  [ "$current" = "$next" ] || die 'Active version differs from the recorded upgrade; refusing rollback'
  is_manager_version "$previous" || die "Previous version $previous is unavailable or modified"
  [ "$dry" -eq 0 ] || { say "WOULD_ROLLBACK CBM $current -> $previous"; return; }
  check_link_ownership
  activate_version "$previous"
  printf 'previous\t%s\nnext\t%s\n' "$current" "$previous" > "$TRANSACTION_FILE"
  say "ROLLED BACK: CBM $current -> $previous"
}

mcp_get() {
  CODEX_HOME="$CODEX_HOME" "$(command -v codex)" mcp get "$SERVER_NAME" --json 2>/dev/null
}

config_entry_snapshot() {
  awk '
    /^# >>> dev-agent-config CBM >>>$/ {inside=1}
    inside {print}
    /^# <<< dev-agent-config CBM <<<$/ {exit}
  ' "$CODEX_CONFIG" | cksum | awk '{print $1 ":" $2}'
}

mcp_present_in_config() {
  [ -f "$CODEX_CONFIG" ] && [ ! -L "$CODEX_CONFIG" ] || return 1
  # Detection only; Codex CLI remains the sole writer. Catch the canonical
  # entry and custom-named MCP entries that reference CBM, without parsing TOML.
  awk '
    /^\[mcp_servers\./ {
      in_mcp=1; key=$0
      sub(/^\[mcp_servers\./,"",key); sub(/\]$/,"",key); gsub(/"/,"",key)
      if (key == "codebase-memory-mcp") found=1
      next
    }
    /^\[/ { in_mcp=0 }
    in_mcp && /codebase-memory-mcp/ { found=1 }
    END { exit !found }
  ' "$CODEX_CONFIG"
}

is_owned_mcp() {
  local current expected mode
  [ -f "$MCP_OWNERSHIP" ] && [ ! -L "$MCP_OWNERSHIP" ] || return 1
  expected="$(awk -F '\t' '$1 == "snapshot_cksum" { print $2 }' "$MCP_OWNERSHIP")"
  [ -n "$expected" ] || return 1
  mode="$(awk -F '\t' '$1 == "snapshot_mode" {print $2}' "$MCP_OWNERSHIP")"
  if [ "$mode" = config-block ]; then
    [ -f "$CODEX_CONFIG" ] && [ ! -L "$CODEX_CONFIG" ] || return 1
    current="$(config_entry_snapshot)"
  else
    current="$(mcp_get 2>/dev/null)" || return 1
    current="$(printf '%s' "$current" | cksum | awk '{print $1 ":" $2}')"
  fi
  [ "$current" = "$expected" ]
}

adoption_state() {
  if [ -f "$ADOPTION" ] && [ ! -L "$ADOPTION" ]; then
    awk -F '\t' '$1 == "ownership" {print $2}' "$ADOPTION"
  else printf 'not-adopted\n'; fi
}

status() {
  local link binary version ownership mcp active
  active="$(active_version 2>/dev/null || true)"
  if [ -n "$active" ]; then link="$MANAGED_LINK"; else link="$(find_binary)"; fi
  binary="$(resolved_binary "$link" 2>/dev/null || true)"
  version='unavailable'
  if [ -n "$binary" ]; then version="$(version_of "$binary" 2>/dev/null || printf 'unhealthy')"; fi
  if [ -L "$link" ]; then
    if [ -n "$binary" ]; then say "Symlink: valid ($link -> $binary)"; else say "Symlink: broken or unsafe ($link)"; fi
  elif [ -n "$binary" ]; then say "Symlink: not a symlink (executable file)"
  else say 'Symlink: not detected'; fi
  [ -n "$link" ] || link='not detected'
  [ -n "$binary" ] || binary='not available'
  if [ -n "$active" ]; then ownership='manager-owned'
  else ownership="$(adoption_state)"; [ "$ownership" = external ] || ownership='not adopted (external ownership not recorded)'; fi
  if is_owned_mcp; then mcp='enabled (manager-owned)'
  elif mcp_present_in_config || mcp_get >/dev/null 2>&1; then mcp='enabled (externally managed)'
  else mcp='not registered'; fi
  say "CBM binary: $link"
  say "Resolved executable: $binary"
  say "Version: $version"
  say "Binary ownership: $ownership"
  say "Codex MCP: $mcp"
  say "Codex config: $CODEX_CONFIG"
}

verify() {
  local link='' binary='' version active expected
  active="$(active_version 2>/dev/null || true)"
  if [ -e "$ACTIVE_FILE" ] || [ -L "$ACTIVE_FILE" ]; then
    [ -n "$active" ] || die "Manager-owned CBM metadata or binary is invalid; refusing to report healthy: $ACTIVE_FILE"
  fi
  if [ -n "$active" ]; then
    link="$MANAGED_LINK"
    [ -L "$link" ] || die "Manager-owned CBM executable link is missing: $link"
    binary="$(resolved_binary "$link" 2>/dev/null)" || die "Manager-owned CBM executable link is broken: $link"
    expected="$(resolved_binary "$(version_dir "$active")/codebase-memory-mcp")"
    [ "$binary" = "$expected" ] || die "Manager-owned CBM link does not match active version $active: $binary"
  else link="$(find_binary)"; fi
  [ -n "$link" ] || die 'CBM executable was not found (checked ~/.local/bin and PATH)'
  [ -n "$binary" ] || binary="$(resolved_binary "$link" 2>/dev/null)" || die "CBM executable is missing, non-executable, or has an invalid symlink: $link"
  version="$(version_of "$binary" 2>/dev/null)" || die "CBM --version health check failed: $binary"
  say "OK: CBM executable is healthy"
  say "Path: $link"
  say "Resolved executable: $binary"
  say "Version: $version"
}

write_adoption() {
  local binary="$1" version="$2" tmp
  prepare_state
  if [ -e "$ADOPTION" ] || [ -L "$ADOPTION" ]; then
    [ -f "$ADOPTION" ] && [ ! -L "$ADOPTION" ] || die "Unexpected adoption metadata path: $ADOPTION"
    die "Existing CBM adoption metadata differs; refusing to overwrite: $ADOPTION"
  fi
  tmp="$ADOPTION.tmp.$$"
  (umask 077; printf 'ownership\texternal\nbinary\t%s\nversion\t%s\n' "$binary" "$version" > "$tmp")
  mv "$tmp" "$ADOPTION"
}

adopt() {
  local dry=0 arg link binary version
  for arg in "$@"; do case "$arg" in --dry-run) dry=1 ;; *) usage 2 ;; esac; done
  if active_version >/dev/null 2>&1; then
    say 'UNCHANGED: an existing CBM version is already manager-owned; adoption does not change ownership'
    return
  fi
  link="$(find_binary)"
  [ -n "$link" ] || die 'No existing CBM executable found to adopt'
  binary="$(resolved_binary "$link" 2>/dev/null)" || die "Existing CBM binary or symlink is invalid: $link"
  version="$(version_of "$binary" 2>/dev/null)" || die "Existing CBM failed --version; refusing adoption: $binary"
  if [ "$dry" -eq 1 ]; then
    say "WOULD_RECORD external CBM installation"
    say "Binary link: $link"
    say "Resolved executable: $binary"
    say "Version: $version"
    say "Target metadata: $ADOPTION"
    return
  fi
  if [ -f "$ADOPTION" ] && [ ! -L "$ADOPTION" ] &&
    grep -qFx "ownership${TAB}external" "$ADOPTION" &&
    grep -qFx "binary${TAB}$binary" "$ADOPTION" && grep -qFx "version${TAB}$version" "$ADOPTION"; then
    say "UNCHANGED: external CBM adoption already recorded ($version)"
    return
  fi
  write_adoption "$binary" "$version"
  say "ADOPTED as external installation: $version"
  say "The binary remains externally owned and was not changed."
}

backup_config() {
  local backup stamp
  safe_user_path "$CODEX_HOME"
  [ ! -L "$CODEX_CONFIG" ] || die "Refusing symlink Codex config: $CODEX_CONFIG"
  [ ! -e "$CODEX_CONFIG" ] || [ -f "$CODEX_CONFIG" ] || die "Codex config is not a regular file: $CODEX_CONFIG"
  prepare_state
  [ ! -L "$BACKUPS" ] || die "Refusing symlink backup directory: $BACKUPS"
  if [ ! -e "$BACKUPS" ]; then mkdir "$BACKUPS"; fi
  [ -d "$BACKUPS" ] || die "Backup path is not a directory: $BACKUPS"
  stamp="$(date '+%Y%m%dT%H%M%S')-$$"
  backup="$BACKUPS/$stamp"
  (umask 077; mkdir "$backup")
  (
    umask 077
    if [ -f "$CODEX_CONFIG" ]; then
      cp -p "$CODEX_CONFIG" "$backup/config.toml"
      chmod 600 "$backup/config.toml"
      printf 'original\tpresent\npath\t%s\n' "$CODEX_CONFIG" > "$backup/manifest.tsv"
    else
      printf 'original\tabsent\npath\t%s\n' "$CODEX_CONFIG" > "$backup/manifest.tsv"
    fi
  )
  printf '%s\n' "$backup"
}

mcp_status() {
  if is_owned_mcp; then say "Codex MCP '$SERVER_NAME': enabled (manager-owned, unchanged)"
  elif mcp_get >/dev/null 2>&1; then say "Codex MCP '$SERVER_NAME': enabled (externally managed)"
  elif mcp_present_in_config; then say "Codex MCP '$SERVER_NAME': configured in TOML (external; CLI could not confirm)"
  else say "Codex MCP '$SERVER_NAME': not registered"; fi
  say "Codex config: $CODEX_CONFIG"
}

write_codex_fallback_entry() {
  local binary="$1" escaped temp env_vars=''
  command -v python3 >/dev/null 2>&1 || die 'Codex CLI is absent and safe config-file fallback requires Python 3'
  escaped="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$binary")"
  [ -z "${CBM_CACHE_DIR:-}" ] || env_vars='env_vars = ["CBM_CACHE_DIR"]'
  [ ! -L "$CODEX_HOME" ] || die "Refusing symlink Codex home: $CODEX_HOME"
  [ ! -L "$CODEX_CONFIG" ] || die "Refusing symlink Codex config: $CODEX_CONFIG"
  [ ! -e "$CODEX_CONFIG" ] || [ -f "$CODEX_CONFIG" ] || die "Codex config is not a regular file: $CODEX_CONFIG"
  mkdir -p "$CODEX_HOME"
  temp="$CODEX_CONFIG.tmp.$$"
  [ ! -e "$temp" ] && [ ! -L "$temp" ] || die "Temporary config path exists: $temp"
  if [ -f "$CODEX_CONFIG" ]; then cp -p "$CODEX_CONFIG" "$temp"; else : > "$temp"; chmod 600 "$temp"; fi
  {
    [ ! -s "$temp" ] || printf '\n'
    printf '# >>> dev-agent-config CBM >>>\n[mcp_servers.codebase-memory-mcp]\ncommand = %s\nargs = []\n%s\n# <<< dev-agent-config CBM <<<\n' "$escaped" "$env_vars"
  } >> "$temp"
  mv "$temp" "$CODEX_CONFIG"
}

remove_codex_fallback_entry() {
  python3 - "$CODEX_CONFIG" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
b = p.read_bytes()
start = b"# >>> dev-agent-config CBM >>>\n"
end = b"# <<< dev-agent-config CBM <<<\n"
if b.count(start) != 1 or b.count(end) != 1:
    raise SystemExit("managed Codex block markers are missing or ambiguous")
a = b.index(start)
z = b.index(end, a) + len(end)
if b.find(start, a + 1) >= 0 or b.find(end, z) >= 0:
    raise SystemExit("managed Codex block markers are ambiguous")
p.write_bytes(b[:a] + b[z:])
PY
}

opencode_python() {
  command -v python3 >/dev/null 2>&1 || die 'OpenCode config management requires Python 3'
}

opencode_status() {
  if [ -f "$OPENCODE_CONFIG" ] && [ ! -L "$OPENCODE_CONFIG" ] && command -v python3 >/dev/null 2>&1; then
    if is_owned_opencode_entry; then say "OpenCode MCP '$SERVER_NAME': enabled (manager-owned, unchanged)"
    elif python3 - "$OPENCODE_CONFIG" <<'PY'
import json, pathlib, sys
try: d=json.loads(pathlib.Path(sys.argv[1]).read_text())
except Exception: raise SystemExit(2)
raise SystemExit(0 if "codebase-memory-mcp" in d.get("mcp",{}) else 1)
PY
    then say "OpenCode MCP '$SERVER_NAME': configured (externally managed)"
    else say 'OpenCode MCP: not registered or config is unsupported JSONC/invalid; left untouched'; fi
  else say "OpenCode MCP '$SERVER_NAME': not registered"; fi
  say "OpenCode config: $OPENCODE_CONFIG"
}

opencode_entry_fingerprint() {
  python3 - "$OPENCODE_CONFIG" <<'PY'
import json, pathlib, sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text())
e=d.get("mcp",{}).get("codebase-memory-mcp")
if e is None: raise SystemExit(1)
print(json.dumps(e, sort_keys=True, separators=(",",":")))
PY
}

is_owned_opencode_entry() {
  local current expected
  [ -f "$OPENCODE_OWNERSHIP" ] && [ ! -L "$OPENCODE_OWNERSHIP" ] || return 1
  current="$(opencode_entry_fingerprint 2>/dev/null)" || return 1
  expected="$(awk -F '\t' '$1=="snapshot_cksum"{print $2}' "$OPENCODE_OWNERSHIP")"
  [ -n "$expected" ] && [ "$(printf '%s' "$current" | cksum | awk '{print $1 ":" $2}')" = "$expected" ]
}

opencode_mcp_enable() {
  local dry="$1" binary version backup tmp fingerprint mode
  binary="$(integration_binary)"
  version="$(version_of "$binary" 2>/dev/null)" || die 'CBM --version health check failed'
  opencode_python
  safe_user_path "$OPENCODE_CONFIG"
  [ ! -L "$OPENCODE_CONFIG" ] || die "Refusing symlink OpenCode config: $OPENCODE_CONFIG"
  if is_owned_opencode_entry; then
    say "UNCHANGED: OpenCode MCP '$SERVER_NAME' is already enabled and manager-owned"; return
  fi
  if [ -e "$OPENCODE_OWNERSHIP" ] || [ -L "$OPENCODE_OWNERSHIP" ]; then die "Stale or unexpected OpenCode ownership metadata: $OPENCODE_OWNERSHIP"; fi
  if [ -e "$OPENCODE_CONFIG" ]; then
    [ -f "$OPENCODE_CONFIG" ] || die "OpenCode config is not a regular file: $OPENCODE_CONFIG"
    if ! python3 - "$OPENCODE_CONFIG" <<'PY'
import json,pathlib,sys
try: d=json.loads(pathlib.Path(sys.argv[1]).read_text())
except Exception: raise SystemExit("invalid/JSONC config; refusing modification")
if "codebase-memory-mcp" in d.get("mcp",{}): raise SystemExit("EXTERNAL")
PY
    then
      say "EXTERNAL/UNSUPPORTED: OpenCode CBM entry exists or config is JSONC/invalid; unchanged"
      return
    fi
  fi
  [ "$dry" -eq 0 ] || { say "WOULD_ENABLE OpenCode MCP '$SERVER_NAME' -> $binary"; say "Config: $OPENCODE_CONFIG"; return; }
  backup="$(backup_opencode_config)"
  tmp="$OPENCODE_CONFIG.tmp.$$"
  mkdir -p "$(dirname "$OPENCODE_CONFIG")"
  python3 - "$OPENCODE_CONFIG" "$tmp" "$binary" "${CBM_CACHE_DIR:-}" <<'PY'
import json, pathlib, sys
src,dst,binary,cache_dir=sys.argv[1:]
data=json.loads(pathlib.Path(src).read_text()) if pathlib.Path(src).exists() else {}
entry={"type":"local","command":[binary],"enabled":True}
if cache_dir: entry["environment"]={"CBM_CACHE_DIR":cache_dir}
data.setdefault("mcp",{})["codebase-memory-mcp"]=entry
pathlib.Path(dst).write_text(json.dumps(data,indent=2)+"\n")
PY
  if [ -f "$OPENCODE_CONFIG" ]; then
    mode="$(file_mode "$OPENCODE_CONFIG")"
    chmod "$mode" "$tmp"
  else chmod 600 "$tmp"; fi
  mv "$tmp" "$OPENCODE_CONFIG"
  fingerprint="$(opencode_entry_fingerprint)" || die "OpenCode entry was written but could not be verified; backup: $backup"
  (umask 077; printf 'ownership\tmanager\nversion\t%s\nsnapshot_cksum\t%s\n' "$version" "$(printf '%s' "$fingerprint" | cksum | awk '{print $1 ":" $2}')" > "$OPENCODE_OWNERSHIP")
  say "ENABLED OpenCode MCP '$SERVER_NAME'"
  say "Backup: $backup"
}

backup_opencode_config() {
  local stamp backup
  prepare_state
  [ ! -L "$OPENCODE_CONFIG" ] || die "Refusing symlink OpenCode config: $OPENCODE_CONFIG"
  [ ! -e "$OPENCODE_CONFIG" ] || [ -f "$OPENCODE_CONFIG" ] || die 'OpenCode config is not a regular file'
  [ ! -L "$BACKUPS" ] || die "Refusing symlink backup directory: $BACKUPS"
  [ -d "$BACKUPS" ] || mkdir -p "$BACKUPS"
  stamp="$(date '+%Y%m%dT%H%M%S')-opencode-$$"; backup="$BACKUPS/$stamp"
  (umask 077; mkdir "$backup")
  if [ -f "$OPENCODE_CONFIG" ]; then cp -p "$OPENCODE_CONFIG" "$backup/opencode.json"; printf 'original\tpresent\npath\t%s\n' "$OPENCODE_CONFIG" > "$backup/manifest.tsv"
  else printf 'original\tabsent\npath\t%s\n' "$OPENCODE_CONFIG" > "$backup/manifest.tsv"; fi
  printf '%s\n' "$backup"
}

file_mode() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then stat -f '%Lp' "$1"
  else stat -c '%a' "$1"; fi
}

opencode_mcp_disable() {
  local dry="$1" current expected backup tmp
  if [ ! -e "$OPENCODE_OWNERSHIP" ] && [ ! -L "$OPENCODE_OWNERSHIP" ]; then say "UNCHANGED: OpenCode MCP '$SERVER_NAME' is not manager-owned"; return; fi
  [ -f "$OPENCODE_OWNERSHIP" ] && [ ! -L "$OPENCODE_OWNERSHIP" ] || die 'Unexpected OpenCode MCP ownership metadata'
  opencode_python
  current="$(opencode_entry_fingerprint 2>/dev/null)" || die 'Owned OpenCode MCP entry is missing or config is invalid'
  expected="$(awk -F '\t' '$1=="snapshot_cksum"{print $2}' "$OPENCODE_OWNERSHIP")"
  [ "$(printf '%s' "$current" | cksum | awk '{print $1 ":" $2}')" = "$expected" ] || die 'Refusing to remove modified OpenCode MCP entry'
  [ "$dry" -eq 0 ] || { say "WOULD_DISABLE manager-owned OpenCode MCP '$SERVER_NAME'"; return; }
  backup="$(backup_opencode_config)"
  tmp="$OPENCODE_CONFIG.tmp.$$"
  python3 - "$OPENCODE_CONFIG" "$tmp" <<'PY'
import json,pathlib,sys
src,dst=sys.argv[1:]
d=json.loads(pathlib.Path(src).read_text())
del d["mcp"]["codebase-memory-mcp"]
if not d["mcp"]: del d["mcp"]
pathlib.Path(dst).write_text(json.dumps(d,indent=2)+"\n")
PY
  chmod 600 "$tmp"; mv "$tmp" "$OPENCODE_CONFIG"; rm "$OPENCODE_OWNERSHIP"
  say "DISABLED manager-owned OpenCode MCP '$SERVER_NAME'"
  say "Backup: $backup"
}

mcp_enable() {
  local dry=0 arg binary version backup current snapshot_mode mode
  for arg in "$@"; do case "$arg" in --dry-run) dry=1 ;; *) usage 2 ;; esac; done
  binary="$(integration_binary)"
  version="$(version_of "$binary" 2>/dev/null)" || die "CBM --version health check failed: $binary"
  if mcp_get >/dev/null 2>&1 || mcp_present_in_config; then
    if is_owned_mcp; then
      say "UNCHANGED: Codex MCP '$SERVER_NAME' is already enabled and manager-owned"
    else say "EXTERNAL: Codex MCP entry exists; it was not modified or adopted"; fi
    return
  fi
  safe_state
  if [ -e "$MCP_OWNERSHIP" ] || [ -L "$MCP_OWNERSHIP" ]; then
    die "Stale or unexpected Codex MCP ownership metadata exists: $MCP_OWNERSHIP"
  fi
  [ "$dry" -eq 1 ] && { say "WOULD_ENABLE Codex MCP '$SERVER_NAME' -> $binary"; say "Config: $CODEX_CONFIG"; return; }
  backup="$(backup_config)"
  if command -v codex >/dev/null 2>&1; then
    if [ -n "${CBM_CACHE_DIR:-}" ]; then
      codex_cli mcp add "$SERVER_NAME" --env "CBM_CACHE_DIR=$CBM_CACHE_DIR" -- "$binary" || die "Codex CLI failed to add MCP entry. Original config backup: $backup"
    else codex_cli mcp add "$SERVER_NAME" -- "$binary" || die "Codex CLI failed to add MCP entry. Original config backup: $backup"; fi
    current="$(mcp_get 2>/dev/null)" || die "Codex did not report the new MCP entry; backup: $backup"
    snapshot_mode=codex-cli
    current="$(printf '%s' "$current" | cksum | awk '{print $1 ":" $2}')"
  else
    write_codex_fallback_entry "$binary" || die "Could not write managed Codex MCP block. Original config backup: $backup"
    current="$(config_entry_snapshot)"
    snapshot_mode=config-block
  fi
  local ownership_tmp="$MCP_OWNERSHIP.tmp.$$"
  (umask 077; printf 'ownership\tmanager\nserver\t%s\nbinary\t%s\nversion\t%s\nsnapshot_mode\t%s\nsnapshot_cksum\t%s\n' \
    "$SERVER_NAME" "$binary" "$version" "$snapshot_mode" "$current" > "$ownership_tmp") ||
    die "Codex entry was added but ownership metadata could not be written. Config backup: $backup"
  mv "$ownership_tmp" "$MCP_OWNERSHIP" || die "Codex entry was added but ownership metadata could not be committed. Config backup: $backup"
  say "ENABLED Codex MCP '$SERVER_NAME' using $binary"
  say "Backup: $backup"
}

mcp_disable() {
  local dry=0 arg backup mode
  for arg in "$@"; do case "$arg" in --dry-run) dry=1 ;; *) usage 2 ;; esac; done
  if { [ ! -e "$MCP_OWNERSHIP" ] && [ ! -L "$MCP_OWNERSHIP" ]; } &&
    ! mcp_get >/dev/null 2>&1 && ! mcp_present_in_config; then
    say "UNCHANGED: Codex MCP '$SERVER_NAME' is not registered"
    return
  fi
  [ -f "$MCP_OWNERSHIP" ] && [ ! -L "$MCP_OWNERSHIP" ] || die "Refusing to disable an unowned Codex MCP entry '$SERVER_NAME'"
  is_owned_mcp || die "Refusing to remove Codex MCP '$SERVER_NAME': entry is missing or has changed; inspect it manually"
  if [ "$dry" -eq 1 ]; then say "WOULD_DISABLE manager-owned Codex MCP '$SERVER_NAME'"; say "Config: $CODEX_CONFIG"; return; fi
  mode="$(awk -F '\t' '$1 == "snapshot_mode" {print $2}' "$MCP_OWNERSHIP")"
  backup="$(backup_config)"
  if [ "$mode" = config-block ]; then
    remove_codex_fallback_entry || die "Could not remove managed Codex block safely. Backup: $backup"
  else
    codex_cli mcp remove "$SERVER_NAME" || die "Codex CLI failed to remove '$SERVER_NAME'. Backup: $backup"
    if mcp_get >/dev/null 2>&1; then die "Codex still reports '$SERVER_NAME' after removal. Backup: $backup"; fi
  fi
  rm "$MCP_OWNERSHIP"
  say "DISABLED manager-owned Codex MCP '$SERVER_NAME'"
  say "Backup: $backup"
}

selected_binary() {
  local active
  active="$(active_version 2>/dev/null || true)"
  if { [ -e "$ACTIVE_FILE" ] || [ -L "$ACTIVE_FILE" ]; } && [ -z "$active" ]; then
    die "Manager-owned CBM active-version metadata is invalid; verify or repair before continuing: $ACTIVE_FILE"
  fi
  if [ -n "$active" ]; then
    local link_target expected
    [ -L "$MANAGED_LINK" ] || die "Manager-owned CBM executable symlink is missing: $MANAGED_LINK"
    link_target="$(resolved_binary "$MANAGED_LINK" 2>/dev/null)" || die "Manager-owned CBM executable symlink is broken: $MANAGED_LINK"
    expected="$(resolved_binary "$(version_dir "$active")/codebase-memory-mcp")"
    [ "$link_target" = "$expected" ] || die "Manager-owned CBM link does not match active version $active"
    printf '%s\n' "$expected"
  else local found; found="$(find_binary)"; [ -n "$found" ] || die 'CBM executable not found; run install or adopt first'; resolved_binary "$found" || die "CBM executable is invalid: $found"; fi
}

integration_binary() {
  local active binary
  active="$(active_version 2>/dev/null || true)"
  binary="$(selected_binary)"
  if [ -n "$active" ]; then printf '%s\n' "$MANAGED_LINK"; else printf '%s\n' "$binary"; fi
}

normalize_project_path() {
  local input="$1" physical repo
  [ -n "$input" ] || die 'Project path is empty'
  case "$input" in *$'\n'*|*$'\t'*) die 'Project path may not contain tab or newline characters' ;; esac
  case "$input" in /*) ;; *) input="$PWD/$input" ;; esac
  [ -d "$input" ] || die "Project directory does not exist: $input"
  physical="$(cd -P "$input" 2>/dev/null && pwd)" || die "Cannot resolve project directory: $input"
  repo="$(git -C "$physical" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$repo" ]; then physical="$(cd -P "$repo" && pwd)"; fi
  printf '%s\n' "$physical"
}

project_from_args() {
  local project="$PWD" explicit=0 arg
  while [ "$#" -gt 0 ]; do
    arg="$1"; shift
    case "$arg" in
      --project) [ "$#" -gt 0 ] || die '--project requires a path'; project="$1"; shift; explicit=1 ;;
      --project=*) project="${arg#*=}"; explicit=1 ;;
      --dry-run) ;;
      *) die "Unknown project option: $arg" ;;
    esac
  done
  if [ "$explicit" -eq 0 ]; then
    git -C "$project" rev-parse --show-toplevel >/dev/null 2>&1 || die "Current directory is not a Git repository: $project; pass --project PATH explicitly"
  fi
  normalize_project_path "$project"
}

project_id() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then printf '%s' "$path" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then printf '%s' "$path" | shasum -a 256 | awk '{print $1}'
  else die 'SHA-256 utility required to manage project mapping'; fi
}

project_meta_path() { printf '%s/projects/%s.tsv\n' "$STATE_DIR" "$(project_id "$1")"; }

project_list_json() {
  local binary="$1"
  "$binary" cli --quiet list_projects --format json
}

project_name_for_path() {
  local json="$1" project="$2"
  command -v python3 >/dev/null 2>&1 || die 'Project mapping requires Python 3 for safe JSON parsing'
  python3 -c 'import json,os,sys
target=os.path.realpath(sys.argv[1])
try: data=json.loads(sys.argv[2])
except Exception: raise SystemExit(1)
found=[]
def visit(value):
 if isinstance(value,dict):
  path=next((value[k] for k in ("repo_path","repository_path","root_path","path") if isinstance(value.get(k),str)),None)
  name=next((value[k] for k in ("name","project_name","id") if isinstance(value.get(k),str)),None)
  if path and name and os.path.realpath(path)==target: found.append(name)
  for item in value.values(): visit(item)
 elif isinstance(value,list):
  for item in value: visit(item)
visit(data)
names=list(dict.fromkeys(found))
if len(names)==1: print(names[0])
elif len(names)>1: raise SystemExit(2)
else: raise SystemExit(1)' "$project" "$json"
}

project_list_complete() {
  local json="$1"
  python3 -c 'import json,sys
try: data=json.loads(sys.argv[1])
except Exception: raise SystemExit(1)
projects=data.get("projects") if isinstance(data,dict) else data
if not isinstance(projects,list): raise SystemExit(1)
keys=("repo_path","repository_path","root_path","path")
for item in projects:
 if not isinstance(item,dict) or not any(isinstance(item.get(k),str) for k in keys): raise SystemExit(1)
raise SystemExit(0)' "$json"
}

project_owned() {
  local project="$1" file="$2"
  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  grep -qFx $'ownership\tdev-agent-config' "$file" &&
    grep -qFx $'project_path\t'"$project" "$file"
}

record_project_owner() {
  local project="$1" name="$2" version="$3" dir file tmp
  dir="$STATE_DIR/projects"; file="$(project_meta_path "$project")"
  prepare_state
  [ ! -L "$dir" ] || die "Refusing symlink project mapping directory: $dir"
  [ -d "$dir" ] || mkdir "$dir"
  if [ -e "$file" ] || [ -L "$file" ]; then
    project_owned "$project" "$file" || die "Existing project mapping is not manager-owned: $file"
    grep -qFx $'project_name\t'"$name" "$file" || die "Project mapping name changed; refusing overwrite: $file"
    return
  fi
  tmp="$file.tmp.$$"
  (umask 077; printf 'ownership\tdev-agent-config\nproject_path\t%s\nproject_name\t%s\nindexed_with\t%s\n' "$project" "$name" "$version" > "$tmp")
  mv "$tmp" "$file"
}

project_existing_name() {
  local project="$1" binary="$2" json
  json="$(project_list_json "$binary")" || die 'CBM list_projects failed; verify the installation and retry'
  project_name_for_path "$json" "$project" 2>/dev/null || return 1
}

run_project_index() {
  local action="$1" project="$2" binary="$3" json name existing version before_complete
  version="$(version_of "$binary" 2>/dev/null)" || die "CBM version check failed: $binary"
  json="$(project_list_json "$binary")" || die 'CBM list_projects failed; verify the installation and retry'
  existing="$(project_name_for_path "$json" "$project" 2>/dev/null || true)"
  before_complete=0; project_list_complete "$json" >/dev/null 2>&1 && before_complete=1 || :
  if [ "$action" = refresh ] && [ -z "$existing" ]; then die "No indexed project matches $project; run index first"; fi
  say "Project: $project"
  if [ "$action" = index ] && [ -n "$existing" ]; then say "Existing CBM index: $existing (not manager-owned; index will refresh it, clean remains unavailable)"; fi
  "$binary" cli --progress index_repository --repo-path "$project" || die "CBM $action failed for $project"
  json="$(project_list_json "$binary")" || die "Index command succeeded, but CBM project verification failed for $project"
  name="$(project_name_for_path "$json" "$project" 2>/dev/null || true)"
  if [ "$action" = index ] && [ -z "$existing" ] && [ "$before_complete" -eq 1 ] && [ -n "$name" ]; then
    record_project_owner "$project" "$name" "$version"
    say "INDEXED: $project -> $name (manager-owned project mapping)"
  elif [ -n "$name" ]; then say "REFRESHED: $project -> $name"
  else say "INDEXED: $project (CBM succeeded; canonical project path could not be verified, so safe clean is unavailable)"; fi
}

project_status() {
  local project="$1" binary="$2" name output branch
  local all
  all="$(project_list_json "$binary")" || die 'CBM list_projects failed'
  project_list_complete "$all" || die 'CBM list_projects did not expose verifiable project paths; refusing an ambiguous project status'
  name="$(project_name_for_path "$all" "$project" 2>/dev/null || true)"
  [ -n "$name" ] || die "Project has not been indexed in CBM: $project; run index --project \"$project\""
  say "Project: $project"
  branch="$(git -C "$project" branch --show-current 2>/dev/null || true)"
  say "Git branch: ${branch:-detached or unavailable}"
  say "CBM project: $name"
  output="$("$binary" cli --quiet index_status --project "$name" --format json 2>&1)" || die "CBM could not read index status for $project: $output"
  say "$output"
  python3 - "$output" <<'PY'
import json,sys
try: data=json.loads(sys.argv[1])
except Exception:
    print('Project watcher registration: unverified (CBM status was not JSON)')
else:
    watch=data.get('watch') if isinstance(data,dict) else None
    strategy=watch.get('strategy') if isinstance(watch,dict) else None
    if strategy in ('git','tree'): print('Project watcher registration: reported by CBM (strategy=%s); live poller health unverified' % strategy)
    elif strategy=='pending': print('Project watcher registration: pending first poll')
    elif strategy=='none': print('Project watcher registration: not active (strategy=none)')
    else: print('Project watcher registration: not reported by this CBM version')
print('Source changes detected: unverified by this command')
print('Index updated after source changes: unverified by this command')
PY
}

project_clean() {
  local project="$1" dry="$2" binary="$3" file name json current
  file="$(project_meta_path "$project")"
  safe_state
  [ ! -L "$STATE_DIR/projects" ] || die "Refusing symlink project mapping directory: $STATE_DIR/projects"
  [ ! -L "$file" ] || die "Refusing symlink project mapping: $file"
  if [ ! -e "$file" ]; then
    json="$(project_list_json "$binary")" || die 'CBM list_projects failed; no data was deleted'
    project_list_complete "$json" || die 'CBM project paths are unavailable; refusing ambiguous clean'
    current="$(project_name_for_path "$json" "$project" 2>/dev/null || true)"
    [ -z "$current" ] || die "Refusing clean: CBM index '$current' is not manager-owned"
    say "ALREADY CLEAN: no manager-owned CBM index for $project"
    return
  fi
  project_owned "$project" "$file" || die "Refusing clean: no manager-owned CBM index mapping for $project"
  if [ -e "$DASHBOARD_META" ] || [ -L "$DASHBOARD_META" ]; then
    [ -f "$DASHBOARD_META" ] && [ ! -L "$DASHBOARD_META" ] || die 'Unexpected dashboard process metadata; refusing clean'
    local dashboard_project dashboard_process
    dashboard_project="$(awk -F '\t' '$1=="project_path"{print $2}' "$DASHBOARD_META")"
    if [ "$dashboard_project" = "$project" ]; then
      dashboard_process="$(dashboard_pid)"
      dashboard_owned_process "$dashboard_process" "$(dashboard_nonce)" && die "Stop the active dashboard before cleaning $project: dashboard stop"
      dashboard_status >/dev/null
    fi
  fi
  name="$(awk -F '\t' '$1=="project_name"{print $2}' "$file")"
  json="$(project_list_json "$binary")" || die 'CBM list_projects failed; no data was deleted'
  project_list_complete "$json" || die 'CBM project paths are unavailable; refusing ambiguous clean'
  current="$(project_name_for_path "$json" "$project" 2>/dev/null || true)"
  if [ -z "$current" ]; then
    [ "$dry" -eq 1 ] && { say "WOULD_REMOVE stale manager mapping: $file"; say "Project: $project"; say 'No CBM index exists; source files and other projects will be untouched.'; return; }
    rm "$file"; say "CLEANED stale manager mapping for $project (index already absent)"; return
  fi
  [ "$current" = "$name" ] || die "CBM project mapping changed ($name -> $current); refusing deletion"
  [ "$dry" -eq 0 ] || { say "WOULD_CLEAN project: $project"; say "CBM index: $name"; say 'Source files and other projects will be untouched.'; return; }
  "$binary" cli --quiet delete_project --project "$name" || die "CBM refused to delete its index '$name'; source files were not touched"
  json="$(project_list_json "$binary")" || die 'Index delete returned success but verification failed; manager mapping retained'
  project_list_complete "$json" || die 'Deleted index, but CBM project paths are no longer verifiable; manager mapping retained'
  [ -z "$(project_name_for_path "$json" "$project" 2>/dev/null || true)" ] || die "CBM still lists the index '$name'; manager mapping retained"
  rm "$file"
  say "CLEANED CBM index '$name' for $project; source files were not touched."
}

project_command() {
  local action="$1" dry=0 project binary arg
  shift
  for arg in "$@"; do [ "$arg" = --dry-run ] && dry=1; done
  project="$(project_from_args "$@")"
  binary="$(selected_binary)"
  [ "$action" != clean ] || { project_clean "$project" "$dry" "$binary"; return; }
  if [ "$dry" -eq 1 ]; then say "WOULD_$([ "$action" = refresh ] && printf REFRESH || printf INDEX) project: $project"; say "CBM executable: $binary"; return; fi
  run_project_index "$action" "$project" "$binary"
}

port_is_free() {
  python3 - "$1" <<'PY'
import socket,sys
s=socket.socket()
try: s.bind(("127.0.0.1",int(sys.argv[1])))
except OSError: raise SystemExit(1)
finally: s.close()
PY
}

port_is_open() {
  python3 - "$1" <<'PY'
import socket,sys
s=socket.socket(); s.settimeout(.2)
try: s.connect(("127.0.0.1",int(sys.argv[1])))
except OSError: raise SystemExit(1)
finally: s.close()
PY
}

port_listener_pids() {
  local port="$1" pids
  if command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -nP -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk '/^[0-9]+$/ && !seen[$0]++')"
    [ -n "$pids" ] && { printf '%s\n' "$pids"; return 0; }
  fi
  if command -v fuser >/dev/null 2>&1; then
    pids="$(fuser -n tcp "$port" 2>/dev/null | tr ' ' '\n' | awk '/^[0-9]+$/ && !seen[$0]++')"
    [ -n "$pids" ] && { printf '%s\n' "$pids"; return 0; }
  fi
  if [ -r /proc/net/tcp ] && [ -d /proc/self/fd ]; then
    pids="$(python3 - "$port" <<'PY'
import os,sys
target=f"{int(sys.argv[1]):04X}"
inodes=set()
try:
    with open('/proc/net/tcp') as f:
        for line in f.readlines()[1:]:
            fields=line.split()
            if len(fields)>9 and fields[1].rsplit(':',1)[-1].upper()==target and fields[3]=='0A':
                inodes.add(fields[9])
except OSError: raise SystemExit(2)
for pid in os.listdir('/proc'):
    if not pid.isdigit(): continue
    try:
        for fd in os.listdir(f'/proc/{pid}/fd'):
            try: link=os.readlink(f'/proc/{pid}/fd/{fd}')
            except OSError: continue
            if link.startswith('socket:[') and link[8:-1] in inodes:
                print(pid); break
    except OSError: continue
PY
)" || return 2
    [ -n "$pids" ] && { printf '%s\n' "$pids" | awk '!seen[$0]++'; return 0; }
    return 1
  fi
  return 1
}

cbm_daemon_listener() {
  local pid="$1" binary="$2" command
  command="$(ps -ww -p "$pid" -o command= 2>/dev/null || ps -p "$pid" -o command= 2>/dev/null || true)"
  [ -n "$command" ] || return 1
  case "$command" in *--cbm-daemon-internal*) ;; *) return 1 ;; esac
  python3 - "$command" "$binary" <<'PY'
import os,shlex,shutil,sys
try: args=shlex.split(sys.argv[1])
except ValueError: raise SystemExit(1)
if not args or '--cbm-daemon-internal' not in args: raise SystemExit(1)
expected=os.path.realpath(sys.argv[2])
executable=args[0]
if not os.path.isabs(executable): executable=shutil.which(executable) or executable
raise SystemExit(0 if os.path.realpath(executable)==expected else 1)
PY
}

cbm_ui_healthy() {
  python3 - "$1" <<'PY'
import http.client,sys
try:
    c=http.client.HTTPConnection('127.0.0.1',int(sys.argv[1]),timeout=0.5)
    c.request('GET','/',headers={'Accept-Encoding':'identity'})
    r=c.getresponse(); body=r.read(131072)
    ok=r.status==200 and r.getheader('Content-Type','').lower().startswith('text/html') and bool(body)
    c.close()
except Exception: ok=False
raise SystemExit(0 if ok else 1)
PY
}

dashboard_port_kind() {
  local port="$1" binary="$2" pids pid rc
  if port_is_free "$port" >/dev/null 2>&1; then printf 'free\n'; return; fi
  if pids="$(port_listener_pids "$port")"; then :; else
    rc=$?
    if [ "$rc" -eq 1 ] && port_is_free "$port" >/dev/null 2>&1; then printf 'free\n'; return; fi
    printf 'unknown\n'; return
  fi
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    cbm_daemon_listener "$pid" "$binary" || { printf 'unrelated\n'; return; }
  done <<< "$pids"
  if cbm_ui_healthy "$port"; then printf 'healthy\n'; else printf 'starting\n'; fi
}

dashboard_url_for() {
  local name="$1" port="$2" encoded
  encoded="$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$name")"
  printf 'http://127.0.0.1:%s/?project=%s\n' "$port" "$encoded"
}

dashboard_pid() {
  [ -f "$DASHBOARD_META" ] && [ ! -L "$DASHBOARD_META" ] || return 1
  awk -F '\t' '$1=="pid"{print $2}' "$DASHBOARD_META"
}

dashboard_nonce() {
  [ -f "$DASHBOARD_META" ] && [ ! -L "$DASHBOARD_META" ] || return 1
  awk -F '\t' '$1=="nonce"{print $2}' "$DASHBOARD_META"
}

dashboard_owned_process() {
  local pid="$1" nonce="$2" args
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  args="$(dashboard_process_args "$pid" "$nonce")" || return $?
  case "$args" in *"$RUNNER"*"$nonce"*) return 0 ;; *) return 1 ;; esac
}

dashboard_process_args() {
  local pid="$1" nonce="${2:-}" args rc
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  if args="$(CBM_DAC_RUNNER="$RUNNER" CBM_DAC_EXPECTED_NONCE="$nonce" ps -ww -p "$pid" -o command= 2>/dev/null)"; then rc=0; else rc=$?; fi
  if [ "$rc" -ne 0 ]; then
    if args="$(CBM_DAC_RUNNER="$RUNNER" CBM_DAC_EXPECTED_NONCE="$nonce" ps -p "$pid" -o command= 2>/dev/null)"; then rc=0; else rc=$?; fi
  fi
  [ "$rc" -eq 0 ] && [ -n "$args" ] || return 2
  printf '%s\n' "$args"
}

dashboard_status() {
  local pid nonce port project url binary kind
  if [ ! -e "$DASHBOARD_META" ] && [ ! -L "$DASHBOARD_META" ]; then
    binary="$(selected_binary 2>/dev/null || true)"
    if [ -n "$binary" ]; then
      kind="$(dashboard_port_kind 9749 "$binary")"
      case "$kind" in
        healthy) say 'Dashboard: healthy (shared CBM daemon; not manager-owned)'; say 'Project selection: use the CBM project menu or a project-specific URL' ; say 'URL: http://127.0.0.1:9749'; return ;;
        starting) say 'Dashboard: compatible CBM daemon is starting on port 9749; HTTP UI is not ready yet'; return ;;
        unrelated) say 'Dashboard: port 9749 is occupied by a non-CBM or incompatible process'; return ;;
        unknown) say 'Dashboard: port 9749 is occupied, but its process could not be verified safely'; return ;;
      esac
    fi
    say 'Dashboard: stopped (no manager-owned process record)'; return
  fi
  [ -f "$DASHBOARD_META" ] && [ ! -L "$DASHBOARD_META" ] || die "Unexpected dashboard process metadata: $DASHBOARD_META"
  grep -qFx $'ownership\tdev-agent-config' "$DASHBOARD_META" || die 'Dashboard process record has unexpected ownership'
  pid="$(dashboard_pid)"; nonce="$(dashboard_nonce)"
  port="$(awk -F '\t' '$1=="port"{print $2}' "$DASHBOARD_META")"
  project="$(awk -F '\t' '$1=="project_path"{print $2}' "$DASHBOARD_META")"
  if dashboard_owned_process "$pid" "$nonce"; then
    url="http://127.0.0.1:$port"
    say "Dashboard: runner running (manager-owned PID $pid)"
    say "Project: $project"
    say "URL: $url"
    if cbm_ui_healthy "$port"; then say 'CBM UI: healthy'
    else say 'CBM UI: not responding yet'; fi
  else
    local state=0
    dashboard_process_args "$pid" >/dev/null 2>&1 || state=$?
    [ "$state" -eq 1 ] || { [ "$state" -eq 2 ] && die "Could not verify PID $pid ownership; refusing process control"; die "PID $pid is running but does not match the manager's dashboard identity; refusing process control"; }
    say "Dashboard: stopped (stale manager-owned record)"
  fi
}

dashboard_start() {
  local port=9749 project='' dry=0 arg binary name nonce pid log url encoded kind attempt
  while [ "$#" -gt 0 ]; do
    arg="$1"; shift
    case "$arg" in
      --port) [ "$#" -gt 0 ] || die '--port requires a number'; port="$1"; shift ;;
      --port=*) port="${arg#*=}" ;;
      --project) [ "$#" -gt 0 ] || die '--project requires a path'; project="$1"; shift ;;
      --project=*) project="${arg#*=}" ;;
      --dry-run) dry=1 ;;
      *) usage 2 ;;
    esac
  done
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || die "Invalid TCP port: $port"
  if [ -z "$project" ]; then project="$(project_from_args)"; else project="$(normalize_project_path "$project")"; fi
  binary="$(selected_binary)"
  name="$(project_existing_name "$project" "$binary" 2>/dev/null || true)"
  [ -n "$name" ] || die "Project has no CBM index: $project; run index --project "$project" first"
  encoded="$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$name")"
  if [ -e "$DASHBOARD_META" ] || [ -L "$DASHBOARD_META" ]; then
    if dashboard_owned_process "$(dashboard_pid)" "$(dashboard_nonce)"; then
      [ "$(awk -F '\t' '$1=="project_path"{print $2}' "$DASHBOARD_META")" = "$project" ] &&
        [ "$(awk -F '\t' '$1=="port"{print $2}' "$DASHBOARD_META")" = "$port" ] &&
        { say "UNCHANGED: dashboard already serving $project on port $port"; say "URL: http://127.0.0.1:$port/?project=$encoded"; return; }
      die 'Another manager-owned dashboard is running; stop it before starting a different project or port'
    fi
    dashboard_status >/dev/null
    rm "$DASHBOARD_META"
  fi
  kind="$(dashboard_port_kind "$port" "$binary")"
  case "$kind" in
    healthy)
      url="$(dashboard_url_for "$name" "$port")"
      say "UNCHANGED: healthy CBM UI is already served by the shared daemon (not manager-owned)"
      say "URL: $url"
      return
      ;;
    starting)
      say "CBM's compatible internal daemon is binding port $port; waiting briefly for its UI to become healthy or release the port..."
      attempt=0
      while [ "$attempt" -lt 20 ]; do
        sleep 0.25
        kind="$(dashboard_port_kind "$port" "$binary")"
        case "$kind" in
          free) break ;;
          healthy)
            url="$(dashboard_url_for "$name" "$port")"
            say 'UNCHANGED: CBM UI became healthy on the shared daemon (not manager-owned)'
            say "URL: $url"
            return
            ;;
          starting) ;;
          unrelated) die "Port $port changed to an unrelated or incompatible listener while waiting; no process was stopped" ;;
          *) die "Port $port is occupied but its listener cannot be verified; install lsof/fuser or inspect it manually. Nothing was stopped" ;;
        esac
        attempt=$((attempt + 1))
      done
      [ "$kind" = free ] || die "CBM's internal daemon kept port $port but its UI did not become healthy within 5 seconds; no process was stopped. Check the CBM daemon log under the selected cache, or retry with --port N after it exits."
      ;;
    unrelated) die "Port $port is occupied by a non-CBM or incompatible process; choose another port. Nothing was stopped" ;;
    unknown) die "Port $port is occupied but its process could not be verified safely; install lsof/fuser or inspect it manually. Nothing was stopped" ;;
  esac
  url="http://127.0.0.1:$port"
  [ "$dry" -eq 0 ] || { say "WOULD_START CBM dashboard for $project"; say "URL: $url/?project=$encoded"; say "CBM executable: $binary"; return; }
  command -v python3 >/dev/null 2>&1 || die 'Dashboard lifecycle requires Python 3'
  [ -f "$RUNNER" ] && [ ! -L "$RUNNER" ] || die "Dashboard runner is unavailable: $RUNNER"
  prepare_state
  [ ! -L "$DASHBOARD_DIR" ] || die "Refusing symlink dashboard state directory: $DASHBOARD_DIR"
  [ -d "$DASHBOARD_DIR" ] || mkdir "$DASHBOARD_DIR"
  log="$DASHBOARD_DIR/dashboard.log"
  [ ! -L "$log" ] || die "Refusing symlink dashboard log: $log"
  nonce="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  nohup python3 "$RUNNER" "$binary" "$port" "$log" "$nonce" >> "$log" 2>&1 </dev/null &
  pid=$!
  # Wait briefly for the local listener; never treat process creation as readiness.
  local attempt=0
  while [ "$attempt" -lt 30 ]; do
    if port_is_open "$port" >/dev/null 2>&1; then break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1; attempt=$((attempt + 1))
  done
  if ! port_is_open "$port" >/dev/null 2>&1; then
    kill -TERM "$pid" 2>/dev/null || :
    die "Dashboard failed to open port $port. Log: $log"
  fi
  if ! dashboard_owned_process "$pid" "$nonce"; then
    local state=0
    dashboard_process_args "$pid" "$nonce" >/dev/null 2>&1 || state=$?
    [ "$state" -eq 2 ] && die "Could not verify dashboard process ownership. Log: $log"
    [ ! -s "$log" ] || tail -n 10 "$log" >&2
    die "Dashboard process identity could not be verified. Log: $log"
  fi
  local tmp="$DASHBOARD_META.tmp.$$"
  (umask 077; printf 'ownership\tdev-agent-config\npid\t%s\nnonce\t%s\nbinary\t%s\nport\t%s\nproject_path\t%s\nproject_name\t%s\nlog\t%s\n' \
    "$pid" "$nonce" "$binary" "$port" "$project" "$name" "$log" > "$tmp")
  mv "$tmp" "$DASHBOARD_META"
  say "STARTED: CBM dashboard for $project"
  say "URL: $url/?project=$encoded"
  say "Stop with: dev-agent-config tools codebase-memory-mcp dashboard stop"
}

dashboard_stop() {
  local dry="$1" pid nonce port binary kind
  if [ ! -e "$DASHBOARD_META" ] && [ ! -L "$DASHBOARD_META" ]; then say 'UNCHANGED: dashboard is not running'; return; fi
  [ -f "$DASHBOARD_META" ] && [ ! -L "$DASHBOARD_META" ] && grep -qFx $'ownership\tdev-agent-config' "$DASHBOARD_META" || die 'Refusing unexpected dashboard process record'
  pid="$(dashboard_pid)"; nonce="$(dashboard_nonce)"
  if ! dashboard_owned_process "$pid" "$nonce"; then
    local state=0
    dashboard_process_args "$pid" >/dev/null 2>&1 || state=$?
    [ "$state" -eq 1 ] || { [ "$state" -eq 2 ] && die "Could not verify PID $pid ownership; refusing to stop it"; die "PID $pid is not the manager's dashboard; refusing to stop it"; }
    [ "$dry" -eq 0 ] && rm "$DASHBOARD_META"
    say 'UNCHANGED: dashboard process is already stopped'
    return
  fi
  port="$(awk -F '\t' '$1=="port"{print $2}' "$DASHBOARD_META")"
  binary="$(awk -F '\t' '$1=="binary"{print $2}' "$DASHBOARD_META")"
  [ "$dry" -eq 0 ] || { say "WOULD_STOP manager-owned dashboard PID $pid"; return; }
  kill -TERM "$pid" || die "Could not stop manager-owned dashboard PID $pid"
  local attempts=0
  while kill -0 "$pid" 2>/dev/null && [ "$attempts" -lt 50 ]; do sleep 0.1; attempts=$((attempts + 1)); done
  kill -0 "$pid" 2>/dev/null && die "Dashboard PID $pid did not stop; log: $DASHBOARD_DIR/dashboard.log"
  rm "$DASHBOARD_META"
  say "STOPPED: manager-owned dashboard PID $pid"
  kind="$(dashboard_port_kind "$port" "$binary")"
  case "$kind" in
    healthy) say "The shared CBM daemon still serves the UI on port $port; it was left running because other CBM sessions may depend on it." ;;
    starting) say "The shared CBM daemon is still releasing port $port; it was left running rather than killed." ;;
  esac
}

watcher_status() {
  local binary setting
  binary="$(selected_binary)"
  setting="$("$binary" config get watcher_enabled 2>/dev/null)" || die 'Could not read CBM watcher_enabled setting'
  say "Watcher subsystem configured (watcher_enabled): $setting"
  setting="$("$binary" config get auto_watch 2>/dev/null || true)"
  say "MCP-session project registration setting (auto_watch): ${setting:-unavailable in this version}"
  say 'Project registration, source-change detection, and reindex completion require project index_status/live verification; not inferred from global settings.'
}

watcher_set() {
  local setting="$1" dry="$2" value binary
  case "$setting" in enabled) value=true ;; disabled) value=false ;; *) usage 2 ;; esac
  binary="$(selected_binary)"
  [ "$dry" -eq 0 ] || { say "WOULD_SET CBM watcher_enabled=$value"; say 'Active watcher runtime state remains unverified; CBM may require daemon restart.'; return; }
  "$binary" config set watcher_enabled "$value" || die "Could not set watcher_enabled=$value"
  say "CONFIGURED: CBM watcher_enabled=$value"
  say 'This records a global setting only. A project is registered by an open MCP session; active polling and source-change reindexing remain unverified.'
}

service_platform() {
  case "$(uname -s)" in Linux) printf linux ;; Darwin) printf darwin ;; *) die "Persistent dashboard service unsupported on $(uname -s)" ;; esac
}

service_definition_path() {
  case "$(service_platform)" in linux) printf '%s\n' "$SYSTEMD_UNIT" ;; darwin) printf '%s\n' "$LAUNCH_AGENT" ;; esac
}

service_definition_hash() { sha256_file "$1"; }

service_owned() {
  local path="$1" expected actual recorded_path
  safe_state
  [ -f "$SERVICE_META" ] && [ ! -L "$SERVICE_META" ] && [ -f "$path" ] && [ ! -L "$path" ] || return 1
  grep -qFx $'ownership\tdev-agent-config' "$SERVICE_META" || return 1
  recorded_path="$(awk -F '\t' '$1=="path"{print $2}' "$SERVICE_META")"
  [ "$recorded_path" = "$path" ] || return 1
  expected="$(awk -F '\t' '$1=="sha256"{print $2}' "$SERVICE_META")"
  [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || return 1
  actual="$(service_definition_hash "$path")" || return 1
  [ "$expected" = "$actual" ]
}

service_require_manager_binary() {
  local active binary output
  active="$(active_version 2>/dev/null || true)"
  [ -n "$active" ] || die 'Persistent dashboard services require a manager-owned CBM installation; adopt-only external binaries are not sufficient'
  binary="$(selected_binary)"
  output="$(version_of "$binary" 2>/dev/null)" || die 'Managed CBM executable failed health verification'
  case "$output" in *"$active"*) ;; *) die "Managed CBM version mismatch: expected $active, got $output" ;; esac
  [ -f "$RUNNER" ] && [ ! -L "$RUNNER" ] || die "Dashboard runner is unavailable: $RUNNER"
  command -v python3 >/dev/null 2>&1 || die 'Persistent dashboard services require Python 3'
  # A stable link keeps integrations on the active version after upgrades.
  printf '%s\n' "$MANAGED_LINK"
}

service_render() {
  local path="$1" port="$2" binary="$3" py="$4" log="$5" nonce="$6"
  case "$(service_platform)" in
    linux)
      python3 - "$path" "$py" "$RUNNER" "$binary" "$port" "$log" "$nonce" <<'PY'
import pathlib,sys
path,*args=sys.argv[1:]
def quote(s):
    if any(ord(c)<32 for c in s): raise SystemExit('service argument contains a control character')
    return '"'+s.replace('\\','\\\\').replace('"','\\"').replace('%','%%')+'"'
lines=['# Managed by dev-agent-config; do not edit',
       '[Unit]','Description=dev-agent-config local CBM dashboard','After=default.target',
       '[Service]','Type=simple','ExecStart='+' '.join(map(quote,args)),
       'Restart=on-failure','RestartSec=3','NoNewPrivileges=true',
       '[Install]','WantedBy=default.target','']
pathlib.Path(path).write_text('\n'.join(lines))
PY
      ;;
    darwin)
      python3 - "$path" "$SERVICE_LABEL" "$py" "$RUNNER" "$binary" "$port" "$log" "$nonce" <<'PY'
import pathlib,plistlib,sys
path,label,*args=sys.argv[1:]
data={'Label':label,'ProgramArguments':args,'RunAtLoad':True,'KeepAlive':True,
      'StandardOutPath':args[-2],'StandardErrorPath':args[-2]}
pathlib.Path(path).write_bytes(plistlib.dumps(data,fmt=plistlib.FMT_XML,sort_keys=True))
PY
      ;;
  esac
}

service_install() {
  local port=9749 dry=0 arg path binary py log nonce tmp hash dir
  while [ "$#" -gt 0 ]; do arg="$1"; shift; case "$arg" in
    --port) [ "$#" -gt 0 ] || die '--port requires a number'; port="$1"; shift ;;
    --port=*) port="${arg#*=}" ;;
    --dry-run) dry=1 ;;
    *) usage 2 ;;
  esac; done
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || die "Invalid TCP port: $port"
  binary="$(service_require_manager_binary)"
  path="$(service_definition_path)"; safe_user_path "$path"
  case "$path$binary$RUNNER" in *$'\n'*|*$'\t'*) die 'Service paths may not contain tabs or newlines' ;; esac
  if service_owned "$path"; then
    [ "$(awk -F '\t' '$1=="port"{print $2}' "$SERVICE_META")" = "$port" ] || die 'A manager-owned service uses a different port; remove it before changing the port'
    say "UNCHANGED: verified manager-owned service definition: $path"; return
  fi
  if [ -e "$path" ] || [ -L "$path" ]; then die "Service path exists but is not unchanged manager-owned content: $path"; fi
  if [ -e "$SERVICE_META" ] || [ -L "$SERVICE_META" ]; then die "Unexpected or stale service ownership metadata: $SERVICE_META"; fi
  [ "$dry" -eq 0 ] || { say "WOULD_INSTALL $(service_platform) user dashboard service"; say "Definition: $path"; say "Port: $port (CBM's documented loopback UI)"; say "CBM executable: $binary"; return; }
  dir="$(dirname "$path")"; safe_user_path "$dir"
  [ ! -L "$dir" ] || die "Refusing symlink service directory: $dir"
  mkdir -p "$dir"; prepare_state
  py="$(command -v python3)"; log="$DASHBOARD_DIR/dashboard-service.log"; nonce="service-$$"
  [ ! -L "$DASHBOARD_DIR" ] || die "Refusing symlink dashboard state directory: $DASHBOARD_DIR"
  [ -d "$DASHBOARD_DIR" ] || mkdir "$DASHBOARD_DIR"
  [ ! -L "$log" ] || die "Refusing symlink dashboard service log: $log"
  tmp="$path.tmp.$$"; [ ! -e "$tmp" ] && [ ! -L "$tmp" ] || die "Temporary service path exists: $tmp"
  service_render "$tmp" "$port" "$binary" "$py" "$log" "$nonce" || { rm -f "$tmp"; die 'Could not generate service definition'; }
  chmod 600 "$tmp"; mv "$tmp" "$path"
  hash="$(service_definition_hash "$path")"
  (umask 077; printf 'ownership\tdev-agent-config\nos\t%s\npath\t%s\nsha256\t%s\nport\t%s\n' "$(service_platform)" "$path" "$hash" "$port" > "$SERVICE_META.tmp.$$")
  mv "$SERVICE_META.tmp.$$" "$SERVICE_META" || { rm -f "$path"; die 'Could not record service ownership'; }
  say "INSTALLED: manager-owned user service definition: $path"
  say 'Not enabled or started; run service enable explicitly.'
}

service_manager_state() {
  local path="$1" os uid output
  os="$(service_platform)"
  if [ "$os" = linux ]; then
    command -v systemctl >/dev/null 2>&1 || die 'systemctl is unavailable; user service operations are unsupported in this environment'
    output="$(systemctl --user show dev-agent-config-cbm-dashboard.service --property=FragmentPath --value 2>/dev/null || true)"
    [ -z "$output" ] || [ "$output" = "$path" ] || die "A different systemd unit owns this service name: $output"
    if systemctl --user is-active --quiet dev-agent-config-cbm-dashboard.service 2>/dev/null; then printf active
    elif systemctl --user is-enabled --quiet dev-agent-config-cbm-dashboard.service 2>/dev/null; then printf enabled-inactive
    elif [ -n "$output" ]; then printf inactive
    else printf absent; fi
  else
    command -v launchctl >/dev/null 2>&1 || die 'launchctl is unavailable; LaunchAgent operations are unsupported in this environment'
    uid="$(id -u)"
    if output="$(launchctl print "gui/$uid/$SERVICE_LABEL" 2>/dev/null)"; then
      printf '%s\n' "$output" | grep -Fq "$path" || die 'A different launchd job owns the CBM dashboard label; refusing control'
      if printf '%s\n' "$output" | grep -Eq 'state = running|pid = [0-9]+'; then printf active; else printf loaded; fi
    else
      output="$(launchctl print-disabled "gui/$uid" 2>/dev/null || true)"
      if printf '%s\n' "$output" | grep -Eq "['\"]$SERVICE_LABEL['\"][[:space:]]*=>[[:space:]]*(true|disabled)"; then printf disabled
      elif [ -f "$path" ]; then printf inactive
      else printf absent; fi
    fi
  fi
}

service_verify() {
  local path state os
  path="$(service_definition_path)"
  service_owned "$path" || die "Service definition is absent, unowned, or modified: $path"
  os="$(service_platform)"; state="$(service_manager_state "$path")"
  say "Service definition: healthy (manager-owned, $os)"
  say "Service state: $state"
  if [ "$os" = linux ]; then
    local linger
    if command -v loginctl >/dev/null 2>&1; then linger="$(loginctl show-user "$(id -u)" --property=Linger --value 2>/dev/null || printf unknown)"; else linger=unknown; fi
    say "systemd linger: $linger (manager will not change it)"
    [ "$linger" = yes ] || say 'Persistence after logout requires explicit administrator-approved: loginctl enable-linger'
  else say 'launchd user agent runs in the logged-in GUI session and stops at logout.'; fi
}

service_enable() {
  local dry="$1" path state port
  path="$(service_definition_path)"; service_owned "$path" || die "Install and verify the manager-owned service definition first: $path"
  state="$(service_manager_state "$path")"
  [ "$state" != active ] || { say 'UNCHANGED: manager-owned dashboard service is already active'; return; }
  [ "$state" != loaded ] || die 'LaunchAgent is loaded but not running; disable it and inspect its log before retrying'
  port="$(awk -F '\t' '$1=="port"{print $2}' "$SERVICE_META")"
  port_is_free "$port" || die "Port $port is already in use; service was not enabled"
  [ "$dry" -eq 0 ] || { say "WOULD_ENABLE manager-owned dashboard service ($path)"; return; }
  if [ "$(service_platform)" = linux ]; then
    systemctl --user daemon-reload || die 'systemd user manager is unavailable; log in to a user session and retry'
    systemctl --user enable --now dev-agent-config-cbm-dashboard.service || die 'systemd failed to enable/start the manager-owned service'
  else
    launchctl enable "gui/$(id -u)/$SERVICE_LABEL" || die 'launchd could not enable the manager-owned LaunchAgent'
    launchctl bootstrap "gui/$(id -u)" "$path" || die 'launchd failed to bootstrap the manager-owned LaunchAgent'
    state="$(service_manager_state "$path")"
    [ "$state" = active ] || die "LaunchAgent was bootstrapped but its process is not confirmed running (state: $state)"
  fi
  say 'ENABLED: manager-owned CBM dashboard service'
}

service_disable() {
  local dry="$1" path state
  path="$(service_definition_path)"; service_owned "$path" || die "Refusing service control: definition is absent, unowned, or modified: $path"
  state="$(service_manager_state "$path")"
  case "$state" in active|loaded|enabled-inactive) ;; *) say 'UNCHANGED: manager-owned dashboard service is already disabled or stopped'; return ;; esac
  [ "$dry" -eq 0 ] || { say 'WOULD_DISABLE/STOP manager-owned dashboard service'; return; }
  if [ "$(service_platform)" = linux ]; then
    systemctl --user disable --now dev-agent-config-cbm-dashboard.service || die 'systemd failed to disable/stop the manager-owned service'
    systemctl --user daemon-reload || die 'systemd daemon-reload failed after disable'
  else
    if [ "$state" = active ] || [ "$state" = loaded ]; then launchctl bootout "gui/$(id -u)" "$path" || die 'launchd failed to stop the verified manager-owned LaunchAgent'; fi
    launchctl disable "gui/$(id -u)/$SERVICE_LABEL" || die 'launchd could not persistently disable the manager-owned LaunchAgent'
  fi
  say 'DISABLED: manager-owned CBM dashboard service'
}

service_remove() {
  local dry="$1" path state
  path="$(service_definition_path)"; service_owned "$path" || die "Refusing removal: service definition is absent, unowned, or modified: $path"
  state="$(service_manager_state "$path")"
  if [ "$dry" -eq 1 ]; then
    case "$state" in active|loaded|enabled-inactive) say 'WOULD_DISABLE/STOP manager-owned service before removal' ;; esac
    say "WOULD_REMOVE manager-owned service definition: $path"
    return
  fi
  service_disable 0
  service_owned "$path" || die 'Service definition changed during removal; preserving it'
  rm "$path" "$SERVICE_META"
  if [ "$(service_platform)" = linux ]; then systemctl --user daemon-reload || die 'Definition removed, but systemd daemon-reload failed'
  else launchctl enable "gui/$(id -u)/$SERVICE_LABEL" || die 'Definition removed, but launchd override cleanup failed'; fi
  say "REMOVED manager-owned dashboard service definition: $path"
}

agent_available() {
  case "$1" in
    codex) command -v codex >/dev/null 2>&1 || [ -d "$CODEX_HOME" ] || [ -f "$CODEX_CONFIG" ] ;;
    opencode) command -v opencode >/dev/null 2>&1 || [ -d "$(dirname "$OPENCODE_CONFIG")" ] || [ -f "$OPENCODE_CONFIG" ] ;;
    *) return 1 ;;
  esac
}

run_freshness() {
  python3 -c 'import json,sys
try: d=json.loads(sys.argv[1])
except Exception: raise SystemExit("unknown")
if not isinstance(d,dict): print("unknown"); raise SystemExit
targets=[d]
for key in ("index","index_status","freshness"):
 value=d.get(key) if isinstance(d,dict) else None
 if isinstance(value,dict): targets.append(value)
for value in targets:
 if any(value.get(key) is True for key in ("stale","is_stale")): print("stale"); raise SystemExit
 for key in ("freshness","sync_status","state","status"):
  item=value.get(key)
  if isinstance(item,str) and item.lower() in ("stale","outdated","needs_refresh"): print("stale"); raise SystemExit
print("not-confirmed-stale")' "$1"
}

run_watch_evidence() {
  local binary="$1" json="$2" strategy watcher auto
  watcher="$("$binary" config get watcher_enabled 2>/dev/null || printf unavailable)"
  auto="$("$binary" config get auto_watch 2>/dev/null || printf unavailable)"
  strategy="$(python3 -c 'import json,sys
try: d=json.loads(sys.argv[1])
except Exception: d={}
w=d.get("watch",{}) if isinstance(d,dict) else {}
print(w.get("strategy","not-reported") if isinstance(w,dict) else "not-reported")' "$json")"
  say "Watcher configuration: watcher_enabled=$watcher, auto_watch=$auto (runtime activity unverified)"
  case "$strategy" in
    git|tree) say "Project watcher registration: CBM reports strategy=$strategy; poller health unverified" ;;
    pending) say 'Project watcher registration: pending first poll' ;;
    none) say 'Project watcher registration: not active (strategy=none)' ;;
    *) say 'Project watcher registration: not reported by this CBM version' ;;
  esac
  say 'Source-change synchronization: not verified by this bootstrap run'
}

run_summary() {
  say 'CBM bootstrap summary:'
  say "  project: $1"
  say "  binary: $2 ($3)"
  say "  MCP: $4"
  say "  index: $5"
  say "  dashboard: $6"
  say '  watcher: configuration/registration evidence reported above; future synchronization unverified'
}

reuse_managed_service() {
  local project_name="$1" port="$2" path state encoded
  [ -z "${CBM_CACHE_DIR:-}" ] || return 1
  path="$(service_definition_path 2>/dev/null)" || return 1
  service_owned "$path" || return 1
  [ "$(awk -F '\t' '$1=="port"{print $2}' "$SERVICE_META")" = "$port" ] || return 1
  state="$(service_manager_state "$path" 2>/dev/null)" || return 1
  [ "$state" = active ] || return 1
  port_is_open "$port" || return 1
  encoded="$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$project_name")"
  printf 'http://127.0.0.1:%s/?project=%s\n' "$port" "$encoded"
}

cbm_run() {
  local dry=0 no_dashboard=0 no_mcp=0 force_refresh=0 port=9749 arg project active binary version ownership
  local agent mcp_summary='skipped by --no-mcp' output found requested_count=0 candidate_count=0 dashboard_url=disabled
  local -a requested=() candidates=()
  while [ "$#" -gt 0 ]; do
    arg="$1"; shift
    case "$arg" in
      -h|--help|help) usage 0 ;;
      --dry-run) dry=1 ;;
      --no-dashboard) no_dashboard=1 ;;
      --no-mcp) no_mcp=1 ;;
      --refresh) force_refresh=1 ;;
      --agent)
        [ "$#" -gt 0 ] || die '--agent requires codex or opencode'
        case "$1" in codex|opencode) ;; *) die "Unsupported CBM MCP agent: $1 (supported: codex, opencode)" ;; esac
        requested+=("$1"); requested_count=$((requested_count + 1)); shift
        ;;
      --port) [ "$#" -gt 0 ] || die '--port requires a number'; port="$1"; shift ;;
      --port=*) port="$(printf '%s' "$arg" | cut -d= -f2-)" ;;
      *) usage 2 ;;
    esac
  done
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || die "Invalid TCP port: $port"
  project="$(project_from_args)"
  say "Project: $project"
  if [ -n "${CBM_CACHE_DIR:-}" ]; then say "CBM cache/runtime selection: explicit CBM_CACHE_DIR=$CBM_CACHE_DIR"; fi

  active="$(active_version 2>/dev/null || true)"
  if [ -e "$ACTIVE_FILE" ] || [ -L "$ACTIVE_FILE" ]; then
    [ -n "$active" ] || die 'CBM manager metadata is invalid; run tools codebase-memory-mcp verify before bootstrap'
  fi
  if [ -n "$active" ]; then
    binary="$(selected_binary)"
    version="$(version_of "$binary" 2>/dev/null)" || die "Managed CBM $active failed --version verification"
    case "$version" in *"$active"*) ;; *) die "Managed CBM version mismatch: metadata=$active, executable=$version" ;; esac
    ownership='manager-owned'
    say "CBM binary: $version ($ownership; $binary)"
  else
    found="$(find_binary)"
    if [ -n "$found" ]; then
      binary="$(resolved_binary "$found" 2>/dev/null)" || die "Existing CBM path is broken or unsafe: $found; repair it manually before bootstrap"
      version="$(version_of "$binary" 2>/dev/null)" || die "Existing CBM binary failed --version: $binary; it was left untouched"
      ownership="$(adoption_state)"
      [ "$ownership" = external ] || ownership='external (ownership not adopted)'
      say "CBM binary: $version ($ownership; $binary)"
    elif [ "$dry" -eq 1 ]; then
      binary='not installed'; version="$VERSION"; ownership='would install manager-owned'
      say "CBM binary: WOULD_INSTALL pinned $version (official SHA-256 verification required)"
    else
      say "Installing official pinned CBM $VERSION..."
      install_version "$VERSION" 0
      binary="$(selected_binary)"
      version="$(version_of "$binary" 2>/dev/null)" || die 'Installed CBM failed final --version verification'
      ownership='manager-owned'
      say "CBM binary: $version ($ownership; $binary)"
    fi
  fi

  if [ "$dry" -eq 1 ]; then
    bash "$ROOT/scripts/install.sh" --mode=merge --dry-run || die 'Global instruction dry-run failed'
    say 'Global instructions: planned'
  else
    bash "$ROOT/scripts/install.sh" --mode=merge || die 'Could not install shared global instructions; project files were not touched'
    say 'Global instructions: installed/verified through merge installer'
  fi

  if [ "$dry" -eq 1 ] && [ "$binary" = 'not installed' ] && [ "$no_mcp" -eq 0 ]; then
    mcp_summary='would configure eligible agent entries after verified install'
    say "MCP: $mcp_summary"
  elif [ "$no_mcp" -eq 0 ]; then
    if [ "$requested_count" -gt 0 ]; then
      for agent in "${requested[@]}"; do
        candidates+=("$agent"); candidate_count=$((candidate_count + 1))
      done
    else
      for agent in codex opencode; do
        if agent_available "$agent"; then candidates+=("$agent"); candidate_count=$((candidate_count + 1)); fi
      done
    fi
    if [ "$candidate_count" -eq 0 ]; then
      mcp_summary='no supported agent configuration detected'
      say "MCP: $mcp_summary; pass --agent codex|opencode to select one, or --no-mcp to skip"
    else
      mcp_summary=''
      for agent in "${candidates[@]}"; do
        if ! agent_available "$agent"; then output="$agent unavailable (not configured/installed); skipped"
        elif [ "$dry" -eq 1 ]; then
          if [ "$agent" = codex ]; then output="$(mcp_enable --dry-run 2>&1)" || die "Codex MCP preflight failed: $output"
          else output="$(opencode_mcp_enable 1 2>&1)" || die "OpenCode MCP preflight failed: $output"; fi
        else
          if [ "$agent" = codex ]; then output="$(mcp_enable 2>&1)" || die "Codex MCP setup failed: $output"
          else output="$(opencode_mcp_enable 0 2>&1)" || die "OpenCode MCP setup failed: $output"; fi
        fi
        if [ -n "$mcp_summary" ]; then mcp_summary+='; '; fi
        case "$output" in
          *EXTERNAL*|*'externally managed'*)
            mcp_summary+="$agent externally managed (preserved)"
            [ -z "${CBM_CACHE_DIR:-}" ] || mcp_summary+="; verify its existing entry uses CBM_CACHE_DIR=$CBM_CACHE_DIR"
            ;;
          *UNCHANGED*) mcp_summary+="$agent already configured" ;;
          *ENABLED*) mcp_summary+="$agent configured" ;;
          *WOULD_ENABLE*) mcp_summary+="$agent would configure" ;;
          *) mcp_summary+="$agent: $output" ;;
        esac
        say "MCP $agent: $output"
      done
    fi
  fi

  if [ "$dry" -eq 1 ]; then
    index_state='not queried (dry-run does not contact CBM runtime)'
    say 'Index: WOULD_CHECK; index only if missing'
    [ "$force_refresh" -eq 0 ] || say 'Refresh: explicitly requested'
    if [ "$no_dashboard" -eq 0 ]; then
      say "Dashboard: WOULD_START_OR_REUSE http://127.0.0.1:$port (no process started)"
      dashboard_url="http://127.0.0.1:$port (planned)"
    fi
    say 'Watcher configuration/registration: not queried during dry-run'
    run_summary "$project" "$version" "$ownership" "$mcp_summary" "$index_state" "$dashboard_url"
    return
  fi

  if ! list_json="$(project_list_json "$binary" 2>&1)"; then
    die "CBM project check failed: $list_json. No process was stopped. Check '$binary daemon status'; resolve any build/cache mismatch explicitly, then rerun."
  fi
  project_list_complete "$list_json" || die 'CBM project listing is incomplete or unparseable; refusing to mistake an unknown index for a missing one'
  existing="$(project_name_for_path "$list_json" "$project" 2>/dev/null || true)"
  if [ -z "$existing" ]; then
    say 'Index: missing; indexing project now'
    run_project_index index "$project" "$binary" || die "Index failed for $project; no dashboard was started"
    list_json="$(project_list_json "$binary" 2>&1)" || die 'CBM indexing returned success but project verification failed; check daemon/cache compatibility'
    project_list_complete "$list_json" || die 'CBM indexing returned success but project listing could not verify the resulting index'
    name="$(project_name_for_path "$list_json" "$project" 2>/dev/null || true)"
    [ -n "$name" ] || die "Index command returned success but CBM did not register $project; inspect '$binary daemon status' and retry"
    index_state="indexed ($name)"
    status_json="$("$binary" cli --quiet index_status --project "$name" --format json 2>&1)" || die "Indexed project could not provide status: $status_json"
  else
    name="$existing"
    if ! status_json="$("$binary" cli --quiet index_status --project "$name" --format json 2>&1)"; then
      die "Could not read CBM freshness for $project: $status_json. The existing index was left unchanged; check '$binary daemon status'."
    fi
    freshness="$(run_freshness "$status_json")"
    if [ "$force_refresh" -eq 1 ] || [ "$freshness" = stale ]; then
      if [ "$force_refresh" -eq 1 ]; then say 'Index: refresh explicitly requested'
      else say 'Index: CBM confirmed stale; refreshing'; fi
      run_project_index refresh "$project" "$binary" || die "Refresh failed for $project; the dashboard was not started"
      index_state="refreshed ($name; $freshness)"
      status_json="$("$binary" cli --quiet index_status --project "$name" --format json 2>&1)" || die 'Refresh succeeded but follow-up index status failed'
    else
      index_state="present ($name; stale state not confirmed, no refresh performed)"
    fi
  fi
  say "Index: $index_state"
  run_watch_evidence "$binary" "$status_json"

  if [ "$no_dashboard" -eq 0 ]; then
    if dashboard_url="$(reuse_managed_service "$name" "$port" 2>/dev/null)"; then
      say "Dashboard: reused active manager-owned service"
    else
      if ! output="$(dashboard_start --project "$project" --port "$port" 2>&1)"; then
        printf '%s\n' "$output" >&2
        die 'Dashboard setup failed safely; no external process was stopped. Resolve the port/process conflict, or rerun with --no-dashboard.'
      fi
      say "Dashboard: $output"
      dashboard_url="$(printf '%s\n' "$output" | sed -n 's/^URL: //p' | tail -n 1)"
      [ -n "$dashboard_url" ] || dashboard_url="http://127.0.0.1:$port"
    fi
  fi
  run_summary "$project" "$version" "$ownership" "$mcp_summary" "$index_state" "$dashboard_url"
}

TAB="$(printf '\t')"
action="${1:-}"
[ -n "$action" ] || usage 2
shift
case "$action" in
  -h|--help|help) usage 0 ;;
  run) cbm_run "$@" ;;
  status)
    if [ "$#" -eq 0 ]; then status
    else project="$(project_from_args "$@")"; project_status "$project" "$(selected_binary)"; fi
    ;;
  verify) [ "$#" -eq 0 ] || usage 2; verify ;;
  install)
    dry=0
    for arg in "$@"; do case "$arg" in --dry-run) dry=1 ;; *) usage 2 ;; esac; done
    current="$(active_version 2>/dev/null || true)"
    if [ -n "$current" ]; then
      selected_binary >/dev/null
      version_output="$(version_of "$(selected_binary)" 2>/dev/null)" || die "Manager-owned CBM $current failed health verification; use verify before install"
      case "$version_output" in *"$current"*) ;; *) die "Manager-owned CBM version mismatch: metadata=$current, executable=$version_output" ;; esac
      if [ "$dry" -eq 0 ]; then say "UNCHANGED: manager-owned CBM $current is already active"
      else say "WOULD_KEEP existing manager-owned CBM $current"; fi
    else install_version "$VERSION" "$dry"; fi
    ;;
  check-update)
    dry=0
    for arg in "$@"; do case "$arg" in --dry-run) dry=1 ;; *) usage 2 ;; esac; done
    check_update "$dry"
    ;;
  upgrade)
    dry=0
    for arg in "$@"; do case "$arg" in --dry-run) dry=1 ;; *) usage 2 ;; esac; done
    current="$(active_version 2>/dev/null || true)"
    [ -n "$current" ] || die 'Upgrade is available only for a validated manager-owned installation; external installs are never overwritten'
    current_binary="$(selected_binary)"
    current_output="$(version_of "$current_binary" 2>/dev/null)" || die 'Current manager-owned CBM failed health verification; repair before upgrading'
    case "$current_output" in *"$current"*) ;; *) die "Current managed version mismatch: metadata=$current, executable=$current_output" ;; esac
    latest="$(latest_stable_version)"
    if [ "$dry" -eq 1 ]; then
      say "Current: $current"
      say "Available stable: $latest"
      [ "$current" = "$latest" ] && say 'WOULD_CHANGE: none (already current)' || say "WOULD_UPGRADE: $current -> $latest (official checksum will be verified)"
      exit 0
    fi
    [ "$latest" != "$current" ] || { say "UNCHANGED: CBM $current is already latest stable"; exit 0; }
    install_version "$latest" 0
    ;;
  rollback)
    dry=0
    for arg in "$@"; do case "$arg" in --dry-run) dry=1 ;; *) usage 2 ;; esac; done
    rollback_managed "$dry"
    ;;
  remove|uninstall)
    dry=0
    for arg in "$@"; do case "$arg" in --dry-run) dry=1 ;; *) usage 2 ;; esac; done
    remove_managed "$dry"
    ;;
  adopt) adopt "$@" ;;
  mcp)
    sub="${1:-}"; shift || true
    case "$sub" in
      status)
        agent="${1:-codex}"; [ "$#" -le 1 ] || usage 2
        case "$agent" in codex) mcp_status ;; opencode) opencode_status ;; *) usage 2 ;; esac
        ;;
      enable)
        agent="${1:-}"; shift || true
        case "$agent" in
          codex) mcp_enable "$@" ;;
          opencode) dry=0; for arg in "$@"; do case "$arg" in --dry-run) dry=1 ;; *) usage 2 ;; esac; done; opencode_mcp_enable "$dry" ;;
          *) usage 2 ;;
        esac
        ;;
      disable)
        agent="${1:-}"; shift || true
        case "$agent" in
          codex) mcp_disable "$@" ;;
          opencode) dry=0; for arg in "$@"; do case "$arg" in --dry-run) dry=1 ;; *) usage 2 ;; esac; done; opencode_mcp_disable "$dry" ;;
          *) usage 2 ;;
        esac
        ;;
      -h|--help|help) usage 0 ;;
      *) usage 2 ;;
    esac
    ;;
  index|refresh|clean)
    project_command "$action" "$@"
    ;;
  project)
    sub="${1:-}"; shift || true
    case "$sub" in
      status) project="$(project_from_args "$@")"; project_status "$project" "$(selected_binary)" ;;
      *) usage 2 ;;
    esac
    ;;
  dashboard)
    sub="${1:-}"; shift || true
    case "$sub" in
      start) dashboard_start "$@" ;;
      stop)
        dry=0; for arg in "$@"; do case "$arg" in --dry-run) dry=1 ;; *) usage 2 ;; esac; done
        dashboard_stop "$dry"
        ;;
      status) [ "$#" -eq 0 ] || usage 2; dashboard_status ;;
      -h|--help|help) usage 0 ;;
      *) usage 2 ;;
    esac
    ;;
  watcher)
    sub="${1:-}"; shift || true
    case "$sub" in
      status) [ "$#" -eq 0 ] || usage 2; watcher_status ;;
      set)
        setting="${1:-}"; shift || true
        dry=0; for arg in "$@"; do case "$arg" in --dry-run) dry=1 ;; *) usage 2 ;; esac; done
        watcher_set "$setting" "$dry"
        ;;
      *) usage 2 ;;
    esac
    ;;
  service)
    sub="${1:-}"; shift || true
    case "$sub" in
      install) service_install "$@" ;;
      enable) dry=0; for arg in "$@"; do case "$arg" in --dry-run) dry=1 ;; *) usage 2 ;; esac; done; service_enable "$dry" ;;
      disable) dry=0; for arg in "$@"; do case "$arg" in --dry-run) dry=1 ;; *) usage 2 ;; esac; done; service_disable "$dry" ;;
      verify|status) [ "$#" -eq 0 ] || usage 2; service_verify ;;
      remove) dry=0; for arg in "$@"; do case "$arg" in --dry-run) dry=1 ;; *) usage 2 ;; esac; done; service_remove "$dry" ;;
      -h|--help|help) usage 0 ;;
      *) usage 2 ;;
    esac
    ;;
  *) usage 2 ;;
esac
