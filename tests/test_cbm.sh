#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
fakebin="$SANDBOX/fakebin"
mkdir -p "$fakebin"

cat > "$fakebin/codebase-memory-mcp" <<'CBM'
#!/usr/bin/env bash
[ "${1:-}" = --version ] || exit 2
printf 'codebase-memory-mcp v0.11.0\n'
CBM
chmod +x "$fakebin/codebase-memory-mcp"

cat > "$fakebin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
out=''; url=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output|-o) out="$2"; shift 2 ;;
    --*) shift ;;
    *) url="$1"; shift ;;
  esac
done
[ -n "$out" ] && [ -n "$url" ] || exit 2
printf '%s\n' "$url" >> "${CBM_TEST_LOG:?}"
case "$url" in
  https://api.github.com/repos/DeusData/codebase-memory-mcp/releases/latest)
    printf '{"tag_name":"v0.12.0"}\n' > "$out" ;;
  */releases/download/v*/checksums.txt)
    version="$(printf '%s' "$url" | sed -n 's#.*download/v\([^/]*\)/.*#\1#p')"
    cp "$CBM_TEST_RELEASES/$version/checksums.txt" "$out" ;;
  */releases/download/v*/*.tar.gz)
    version="$(printf '%s' "$url" | sed -n 's#.*download/v\([^/]*\)/.*#\1#p')"
    asset="${url##*/}"
    cp "$CBM_TEST_RELEASES/$version/$asset" "$out" ;;
  *) exit 3 ;;
esac
CURL
chmod +x "$fakebin/curl"
cat > "$fakebin/uname" <<'UNAME'
#!/usr/bin/env sh
case "$1" in -s) printf '%s\n' "${CBM_TEST_OS:-Linux}" ;; -m) printf '%s\n' "${CBM_TEST_ARCH:-x86_64}" ;; *) /usr/bin/uname "$@" ;; esac
UNAME
chmod +x "$fakebin/uname"
cat > "$fakebin/mv" <<'MV'
#!/usr/bin/env bash
if [ "${CBM_FAIL_ACTIVE_WRITE:-0}" = 1 ] && [ "${2:-}" = "${CBM_ACTIVE_FILE:-}" ] && [ ! -e "${CBM_FAIL_MARKER:?}" ]; then
  : > "$CBM_FAIL_MARKER"
  exit 1
fi
exec /bin/mv "$@"
MV
chmod +x "$fakebin/mv"

release_root="$SANDBOX/releases"
mkdir -p "$release_root"
make_release() {
  local version="$1" os="$2" arch="$3" release asset hash
  release="$release_root/$version"; mkdir -p "$release"
  [ -e "$release/checksums.txt" ] || : > "$release/checksums.txt"
  if [ "$os" = linux ]; then asset="codebase-memory-mcp-$os-$arch-portable.tar.gz"
  else asset="codebase-memory-mcp-$os-$arch.tar.gz"; fi
  printf '#!/usr/bin/env sh\necho "codebase-memory-mcp v%s"\n' "$version" > "$release/codebase-memory-mcp"
  chmod +x "$release/codebase-memory-mcp"
  tar -czf "$release/$asset" -C "$release" codebase-memory-mcp
  if command -v sha256sum >/dev/null 2>&1; then hash="$(sha256sum "$release/$asset" | awk '{print $1}')"
  else hash="$(shasum -a 256 "$release/$asset" | awk '{print $1}')"; fi
  printf '%s  %s\n' "$hash" "$asset" >> "$release/checksums.txt"
}
make_release 0.11.0 linux amd64
make_release 0.11.0 linux arm64
make_release 0.11.0 darwin arm64
make_release 0.11.0 darwin amd64
make_release 0.12.0 linux amd64
make_release 0.12.0 linux arm64
make_release 0.12.0 darwin arm64
make_release 0.12.0 darwin amd64

cat > "$fakebin/codex" <<'CODEX'
#!/usr/bin/env bash
set -euo pipefail
config="${CODEX_HOME:?}/config.toml"
state="$CODEX_HOME/.cbm-test-entry"
[ "${1:-}" = mcp ] || exit 2
action="${2:-}"; shift 2
case "$action" in
  get)
    name="${1:-}"
    [ "$name" = codebase-memory-mcp ] && [ -f "$state" ] || exit 1
    printf '{"name":"%s","command":"%s","args":[],"enabled":true}\n' "$name" "$(cat "$state")"
    ;;
  add)
    name="${1:-}"; shift
    [ "$name" = codebase-memory-mcp ] && [ "${1:-}" = -- ] || exit 2
    shift; command="$1"
    [ ! -e "$state" ] || exit 1
    mkdir -p "$CODEX_HOME"
    printf '%s\n' "$command" > "$state"
    { [ ! -f "$config" ] || cat "$config"; printf '\n[mcp_servers.codebase-memory-mcp]\ncommand = "%s"\n' "$command"; } > "$config.new"
    [ ! -f "$config" ] || chmod 600 "$config.new"
    mv "$config.new" "$config"
    ;;
  remove)
    name="${1:-}"
    [ "$name" = codebase-memory-mcp ] && [ -f "$state" ] || exit 1
    awk '
      /^\[mcp_servers\.codebase-memory-mcp\]/ { skip=1; next }
      skip && /^\[/ { skip=0 }
      !skip { print }
    ' "$config" > "$config.new"
    mv "$config.new" "$config"
    rm "$state"
    ;;
  *) exit 2 ;;
esac
CODEX
chmod +x "$fakebin/codex"

new_home() {
  local home="$SANDBOX/$1"
  mkdir -p "$home/.local/share/codebase-memory-mcp" "$home/.local/bin" "$home/codex"
  cp "$fakebin/codebase-memory-mcp" "$home/.local/share/codebase-memory-mcp/codebase-memory-mcp"
  ln -s "$home/.local/share/codebase-memory-mcp/codebase-memory-mcp" "$home/.local/bin/codebase-memory-mcp"
  printf '%s\n' "$home"
}
run_cbm() {
  local home="$1" codex_home="$2"
  shift 2
  HOME="$home" XDG_STATE_HOME="$home/state" CODEX_HOME="$codex_home" \
    PATH="$fakebin:/usr/bin:/bin" "$ROOT/scripts/tools.sh" codebase-memory-mcp "$@"
}
run_manager() {
  local home="$1"; shift
  HOME="$home" XDG_STATE_HOME="$home/state" XDG_DATA_HOME="$home/.local/share" \
    CBM_TEST_RELEASES="$release_root" CBM_TEST_LOG="$SANDBOX/downloads.log" \
    PATH="$fakebin:/usr/bin:/bin" "$ROOT/scripts/tools.sh" codebase-memory-mcp "$@"
}

# Existing installation is verified and adopted as external without touching binary.
home="$(new_home existing)"; codex_home="$home/codex"
original="$(cksum "$home/.local/share/codebase-memory-mcp/codebase-memory-mcp")"
dry="$(run_cbm "$home" "$codex_home" adopt --dry-run)"
case "$dry" in *'WOULD_RECORD external CBM installation'*) ;; *) exit 1 ;; esac
[ ! -e "$home/state/dev-agent-config/tools/codebase-memory-mcp/adoption.tsv" ]
result="$(run_cbm "$home" "$codex_home" verify)"
grep -q 'Version: codebase-memory-mcp v0.11.0' <<< "$result"
run_cbm "$home" "$codex_home" adopt >/dev/null
result="$(run_cbm "$home" "$codex_home" adopt)"
grep -q 'UNCHANGED' <<< "$result"
[ "$original" = "$(cksum "$home/.local/share/codebase-memory-mcp/codebase-memory-mcp")" ]
grep -q $'^ownership\texternal$' "$home/state/dev-agent-config/tools/codebase-memory-mcp/adoption.tsv"

# Missing and broken binaries are reported, never followed or repaired.
missing="$SANDBOX/missing"; mkdir -p "$missing/.local/bin" "$missing/codex"
if HOME="$missing" XDG_STATE_HOME="$missing/state" CODEX_HOME="$missing/codex" PATH="/usr/bin:/bin" \
  "$ROOT/scripts/tools.sh" codebase-memory-mcp verify >/dev/null 2>&1; then echo 'Missing CBM passed verify' >&2; exit 1; fi
ln -s "$missing/no-such-file" "$missing/.local/bin/codebase-memory-mcp"
if HOME="$missing" XDG_STATE_HOME="$missing/state" CODEX_HOME="$missing/codex" PATH="/usr/bin:/bin" \
  "$ROOT/scripts/tools.sh" codebase-memory-mcp adopt >/dev/null 2>&1; then echo 'Broken CBM symlink adopted' >&2; exit 1; fi

# An existing CBM entry is external, even when it uses the same canonical name.
home="$(new_home external-mcp)"; codex_home="$home/codex"
printf '%s\n' "$home/.local/bin/codebase-memory-mcp" > "$codex_home/.cbm-test-entry"
cat > "$codex_home/config.toml" <<EOF
model = "custom-model"

[mcp_servers.codebase-memory-mcp]
command = "$home/.local/bin/codebase-memory-mcp"
EOF
before="$(cksum "$codex_home/config.toml")"
result="$(run_cbm "$home" "$codex_home" mcp status codex)"; grep -q 'externally managed' <<< "$result"
result="$(run_cbm "$home" "$codex_home" mcp enable codex --dry-run)"; grep -q 'EXTERNAL' <<< "$result"
result="$(run_cbm "$home" "$codex_home" mcp enable codex)"; grep -q 'EXTERNAL' <<< "$result"
[ "$before" = "$(cksum "$codex_home/config.toml")" ]
[ ! -e "$home/state/dev-agent-config/tools/codebase-memory-mcp/codex-mcp.tsv" ]

# MCP changes respect CODEX_HOME, preserve unrelated TOML, back up, and are idempotent.
home="$(new_home mcp-owned)"; codex_home="$home/custom-codex-home"
mkdir -p "$codex_home"
cat > "$codex_home/config.toml" <<'TOML'
model = "preserve-me"

[mcp_servers.other]
command = "other-server"
args = ["--keep"]

[notice]
value = "also-keep"
TOML
before="$(cksum "$codex_home/config.toml")"
run_cbm "$home" "$codex_home" mcp enable codex --dry-run >/dev/null
[ "$before" = "$(cksum "$codex_home/config.toml")" ]
[ ! -e "$home/state/dev-agent-config/tools/codebase-memory-mcp/backups" ]
[ ! -e "$home/state" ]
run_cbm "$home" "$codex_home" mcp enable codex >/dev/null
result="$(run_cbm "$home" "$codex_home" mcp enable codex)"; grep -q 'UNCHANGED' <<< "$result"
grep -q 'model = "preserve-me"' "$codex_home/config.toml"
grep -q 'command = "other-server"' "$codex_home/config.toml"
result="$(run_cbm "$home" "$codex_home" mcp status codex)"; grep -q 'manager-owned, unchanged' <<< "$result"
before="$(cksum "$codex_home/config.toml")"
run_cbm "$home" "$codex_home" mcp disable codex --dry-run >/dev/null
[ "$before" = "$(cksum "$codex_home/config.toml")" ]
[ -f "$home/state/dev-agent-config/tools/codebase-memory-mcp/codex-mcp.tsv" ]
run_cbm "$home" "$codex_home" mcp disable codex >/dev/null
result="$(run_cbm "$home" "$codex_home" mcp disable codex)"; grep -q 'not registered' <<< "$result"
grep -q 'model = "preserve-me"' "$codex_home/config.toml"
grep -q 'command = "other-server"' "$codex_home/config.toml"
! grep -q 'codebase-memory-mcp' "$codex_home/config.toml"
find "$home/state/dev-agent-config/tools/codebase-memory-mcp/backups" -name config.toml | grep -q .
run_cbm "$home" "$codex_home" mcp enable codex >/dev/null
run_cbm "$home" "$codex_home" mcp disable codex >/dev/null

# Modified manager entry and unowned entries cannot be removed.
home="$(new_home modified)"; codex_home="$home/codex"
run_cbm "$home" "$codex_home" mcp enable codex >/dev/null
printf '%s\n' "$home/.local/bin/other-binary" > "$codex_home/.cbm-test-entry"
if run_cbm "$home" "$codex_home" mcp disable codex >/dev/null 2>&1; then echo 'Modified MCP entry removed' >&2; exit 1; fi
[ -f "$codex_home/.cbm-test-entry" ]
home="$(new_home unowned)"; codex_home="$home/codex"
printf '%s\n' "$home/.local/bin/codebase-memory-mcp" > "$codex_home/.cbm-test-entry"
printf '[mcp_servers.codebase-memory-mcp]\ncommand = "%s/.local/bin/codebase-memory-mcp"\n' "$home" > "$codex_home/config.toml"
if run_cbm "$home" "$codex_home" mcp disable codex >/dev/null 2>&1; then echo 'Unowned MCP entry removed' >&2; exit 1; fi

# A symlinked Codex config is refused before backup or writes.
home="$(new_home config-symlink)"; codex_home="$home/codex"
printf 'keep\n' > "$home/external-config.toml"
ln -s "$home/external-config.toml" "$codex_home/config.toml"
if run_cbm "$home" "$codex_home" mcp enable codex >/dev/null 2>&1; then echo 'Symlinked Codex config was modified' >&2; exit 1; fi
[ "$(cat "$home/external-config.toml")" = keep ]
[ -L "$codex_home/config.toml" ]

# Verified manager-owned installation is staged, checksummed, and activated only
# after its executable health check passes. Old versions remain for rollback.
install_home="$SANDBOX/manager install"; mkdir -p "$install_home/.local/share" "$install_home/.local/bin"
dry="$(run_manager "$install_home" install --dry-run)"
case "$dry" in *'WOULD_INSTALL CBM 0.11.0'*) ;; *) echo "$dry" >&2; exit 1 ;; esac
[ ! -e "$install_home/state" ] && [ ! -e "$install_home/.local/share/dev-agent-config" ]
run_manager "$install_home" install >/dev/null
grep -q '^0.11.0$' "$install_home/state/dev-agent-config/tools/codebase-memory-mcp/active-version"
[ "$(readlink "$install_home/.local/bin/codebase-memory-mcp")" = "$install_home/.local/share/dev-agent-config/tools/codebase-memory-mcp/versions/0.11.0/codebase-memory-mcp" ]
result="$(run_manager "$install_home" install)"; grep -q 'UNCHANGED' <<< "$result"
result="$(run_manager "$install_home" verify)"; grep -q 'v0.11.0' <<< "$result"
result="$(run_manager "$install_home" check-update)"; grep -q 'Available stable: 0.12.0' <<< "$result"
result="$(run_manager "$install_home" upgrade --dry-run)"; grep -q 'WOULD_UPGRADE: 0.11.0 -> 0.12.0' <<< "$result"
run_manager "$install_home" upgrade >/dev/null
grep -q '^0.12.0$' "$install_home/state/dev-agent-config/tools/codebase-memory-mcp/active-version"
result="$(run_manager "$install_home" install)"; grep -q 'UNCHANGED: manager-owned CBM 0.12.0' <<< "$result"
grep -q '^0.12.0$' "$install_home/state/dev-agent-config/tools/codebase-memory-mcp/active-version"
[ -x "$install_home/.local/share/dev-agent-config/tools/codebase-memory-mcp/versions/0.11.0/codebase-memory-mcp" ]
run_manager "$install_home" rollback >/dev/null
grep -q '^0.11.0$' "$install_home/state/dev-agent-config/tools/codebase-memory-mcp/active-version"
run_manager "$install_home" rollback >/dev/null
grep -q '^0.12.0$' "$install_home/state/dev-agent-config/tools/codebase-memory-mcp/active-version"
run_manager "$install_home" remove --dry-run >/dev/null
[ -L "$install_home/.local/bin/codebase-memory-mcp" ]
run_manager "$install_home" remove >/dev/null
[ ! -e "$install_home/.local/bin/codebase-memory-mcp" ] && [ ! -e "$install_home/.local/share/dev-agent-config/tools/codebase-memory-mcp/versions" ]

# Agent integrations use the stable manager link, so an explicit upgrade
# transparently selects the active version without rewriting user MCP config.
managed_mcp_home="$SANDBOX/managed-mcp"; codex_home="$managed_mcp_home/codex"
mkdir -p "$managed_mcp_home/.local/share" "$managed_mcp_home/.local/bin" "$codex_home"
run_manager "$managed_mcp_home" install >/dev/null
HOME="$managed_mcp_home" XDG_STATE_HOME="$managed_mcp_home/state" XDG_DATA_HOME="$managed_mcp_home/.local/share" CODEX_HOME="$codex_home" \
  CBM_TEST_RELEASES="$release_root" CBM_TEST_LOG="$SANDBOX/downloads.log" PATH="$fakebin:/usr/bin:/bin" \
  "$ROOT/scripts/tools.sh" codebase-memory-mcp mcp enable codex >/dev/null
[ "$(cat "$codex_home/.cbm-test-entry")" = "$managed_mcp_home/.local/bin/codebase-memory-mcp" ]
run_manager "$managed_mcp_home" upgrade >/dev/null
[ "$(readlink "$managed_mcp_home/.local/bin/codebase-memory-mcp")" = "$managed_mcp_home/.local/share/dev-agent-config/tools/codebase-memory-mcp/versions/0.12.0/codebase-memory-mcp" ]
result="$(HOME="$managed_mcp_home" XDG_STATE_HOME="$managed_mcp_home/state" XDG_DATA_HOME="$managed_mcp_home/.local/share" CODEX_HOME="$codex_home" PATH="$fakebin:/usr/bin:/bin" "$ROOT/scripts/tools.sh" codebase-memory-mcp mcp status codex)"
grep -q 'manager-owned, unchanged' <<< "$result"
HOME="$managed_mcp_home" XDG_STATE_HOME="$managed_mcp_home/state" CODEX_HOME="$codex_home" PATH="$fakebin:/usr/bin:/bin" \
  "$ROOT/scripts/tools.sh" codebase-memory-mcp mcp disable codex >/dev/null
run_manager "$managed_mcp_home" remove >/dev/null

# Failed upgrades preserve the previous active version and leave no candidate.
failed_upgrade_home="$SANDBOX/failed-upgrade"; mkdir -p "$failed_upgrade_home/.local/share" "$failed_upgrade_home/.local/bin"
run_manager "$failed_upgrade_home" install >/dev/null
cp "$release_root/0.12.0/checksums.txt" "$SANDBOX/upgrade-checksums.saved"
printf '%064d  codebase-memory-mcp-linux-amd64-portable.tar.gz\n' 0 > "$release_root/0.12.0/checksums.txt"
if run_manager "$failed_upgrade_home" upgrade >/dev/null 2>&1; then echo 'Upgrade accepted an invalid checksum' >&2; exit 1; fi
grep -q '^0.11.0$' "$failed_upgrade_home/state/dev-agent-config/tools/codebase-memory-mcp/active-version"
[ "$(readlink "$failed_upgrade_home/.local/bin/codebase-memory-mcp")" = "$failed_upgrade_home/.local/share/dev-agent-config/tools/codebase-memory-mcp/versions/0.11.0/codebase-memory-mcp" ]
[ ! -e "$failed_upgrade_home/.local/share/dev-agent-config/tools/codebase-memory-mcp/versions/0.12.0" ]
mv "$SANDBOX/upgrade-checksums.saved" "$release_root/0.12.0/checksums.txt"

# Failure to commit active-version after the executable link is switched must
# restore the previous pointer and remove the uncommitted candidate.
interrupted_home="$SANDBOX/interrupted-upgrade"; mkdir -p "$interrupted_home/.local/share" "$interrupted_home/.local/bin"
run_manager "$interrupted_home" install >/dev/null
if HOME="$interrupted_home" XDG_STATE_HOME="$interrupted_home/state" XDG_DATA_HOME="$interrupted_home/.local/share" \
  CBM_TEST_RELEASES="$release_root" CBM_TEST_LOG="$SANDBOX/downloads.log" \
  CBM_ACTIVE_FILE="$interrupted_home/state/dev-agent-config/tools/codebase-memory-mcp/active-version" \
  CBM_FAIL_MARKER="$SANDBOX/fail-active-write" CBM_FAIL_ACTIVE_WRITE=1 PATH="$fakebin:/usr/bin:/bin" \
  "$ROOT/scripts/tools.sh" codebase-memory-mcp upgrade >/dev/null 2>&1; then
  echo 'Interrupted activation unexpectedly succeeded' >&2; exit 1
fi
[ "$(cat "$interrupted_home/state/dev-agent-config/tools/codebase-memory-mcp/active-version")" = 0.11.0 ]
[ "$(readlink "$interrupted_home/.local/bin/codebase-memory-mcp")" = "$interrupted_home/.local/share/dev-agent-config/tools/codebase-memory-mcp/versions/0.11.0/codebase-memory-mcp" ]
[ ! -e "$interrupted_home/.local/share/dev-agent-config/tools/codebase-memory-mcp/versions/0.12.0" ]

modified_home="$SANDBOX/modified-manager"; mkdir -p "$modified_home/.local/share" "$modified_home/.local/bin"
run_manager "$modified_home" install >/dev/null
printf 'changed\n' >> "$modified_home/.local/share/dev-agent-config/tools/codebase-memory-mcp/versions/0.11.0/codebase-memory-mcp"
if run_manager "$modified_home" remove >/dev/null 2>&1; then echo 'Modified manager binary was removed' >&2; exit 1; fi
[ -L "$modified_home/.local/bin/codebase-memory-mcp" ]

# Corrupt archives are rejected before activation and leave no ownership metadata.
bad_home="$SANDBOX/bad-checksum"; mkdir -p "$bad_home/.local/share" "$bad_home/.local/bin"
bad_checksum="$release_root/0.11.0/checksums.txt"
cp "$bad_checksum" "$SANDBOX/checksums.saved"
printf '%064d  codebase-memory-mcp-darwin-arm64.tar.gz\n' 0 > "$bad_checksum"
if run_manager "$bad_home" install >/dev/null 2>&1; then echo 'Bad release checksum accepted' >&2; exit 1; fi
[ ! -e "$bad_home/.local/bin/codebase-memory-mcp" ]
[ ! -e "$bad_home/.local/share/dev-agent-config/tools/codebase-memory-mcp/versions/0.11.0" ]
mv "$SANDBOX/checksums.saved" "$bad_checksum"

# Existing unowned executable and broken/foreign symlink conflicts are never replaced.
conflict_home="$SANDBOX/binary-conflict"; mkdir -p "$conflict_home/.local/bin" "$conflict_home/.local/share"
printf 'user binary\n' > "$conflict_home/.local/bin/codebase-memory-mcp"; chmod +x "$conflict_home/.local/bin/codebase-memory-mcp"
if run_manager "$conflict_home" install >/dev/null 2>&1; then echo 'Existing executable was overwritten' >&2; exit 1; fi
[ "$(cat "$conflict_home/.local/bin/codebase-memory-mcp")" = 'user binary' ]
symlink_home="$SANDBOX/symlink-conflict"; mkdir -p "$symlink_home/.local/bin" "$symlink_home/.local/share"
ln -s "$SANDBOX/not-managed" "$symlink_home/.local/bin/codebase-memory-mcp"
if run_manager "$symlink_home" install >/dev/null 2>&1; then echo 'Broken executable symlink was replaced' >&2; exit 1; fi
[ -L "$symlink_home/.local/bin/codebase-memory-mcp" ]

# OS/architecture selection is explicit and independently verified by the URL log.
mac_home="$SANDBOX/mac-install"; mkdir -p "$mac_home/.local/share" "$mac_home/.local/bin"
CBM_TEST_OS=Darwin CBM_TEST_ARCH=arm64 HOME="$mac_home" XDG_STATE_HOME="$mac_home/state" XDG_DATA_HOME="$mac_home/.local/share" \
  CBM_TEST_RELEASES="$release_root" CBM_TEST_LOG="$SANDBOX/downloads.log" PATH="$fakebin:/usr/bin:/bin" \
  "$ROOT/scripts/tools.sh" codebase-memory-mcp install >/dev/null
grep -q 'codebase-memory-mcp-darwin-arm64.tar.gz' "$SANDBOX/downloads.log"

for tuple in 'Linux arm64 linux-arm64-portable' 'Darwin x86_64 darwin-amd64'; do
  set -- $tuple
  matrix_home="$SANDBOX/matrix-$1-$2"; mkdir -p "$matrix_home/.local/share" "$matrix_home/.local/bin"
  CBM_TEST_OS="$1" CBM_TEST_ARCH="$2" HOME="$matrix_home" XDG_STATE_HOME="$matrix_home/state" XDG_DATA_HOME="$matrix_home/.local/share" \
    CBM_TEST_RELEASES="$release_root" CBM_TEST_LOG="$SANDBOX/downloads.log" PATH="$fakebin:/usr/bin:/bin" \
    "$ROOT/scripts/tools.sh" codebase-memory-mcp install >/dev/null
  grep -q "codebase-memory-mcp-$3.tar.gz" "$SANDBOX/downloads.log"
done

# Codex VS Code users without the CLI can use a clearly marked, reversible block.
fallback_home="$SANDBOX/codex-no-cli"; mkdir -p "$fallback_home/.local/share/codebase-memory-mcp" "$fallback_home/.local/bin" "$fallback_home/codex"
cp "$fakebin/codebase-memory-mcp" "$fallback_home/.local/share/codebase-memory-mcp/codebase-memory-mcp"
ln -s "$fallback_home/.local/share/codebase-memory-mcp/codebase-memory-mcp" "$fallback_home/.local/bin/codebase-memory-mcp"
printf 'model = "preserve-this"\n' > "$fallback_home/codex/config.toml"
before="$(cksum "$fallback_home/codex/config.toml")"
HOME="$fallback_home" XDG_STATE_HOME="$fallback_home/state" CODEX_HOME="$fallback_home/codex" PATH="/usr/bin:/bin" \
  "$ROOT/scripts/tools.sh" codebase-memory-mcp mcp enable codex --dry-run >/dev/null
[ "$before" = "$(cksum "$fallback_home/codex/config.toml")" ]
HOME="$fallback_home" XDG_STATE_HOME="$fallback_home/state" CODEX_HOME="$fallback_home/codex" PATH="/usr/bin:/bin" \
  "$ROOT/scripts/tools.sh" codebase-memory-mcp mcp enable codex >/dev/null
grep -q 'dev-agent-config CBM' "$fallback_home/codex/config.toml"
grep -q 'model = "preserve-this"' "$fallback_home/codex/config.toml"
HOME="$fallback_home" XDG_STATE_HOME="$fallback_home/state" CODEX_HOME="$fallback_home/codex" PATH="/usr/bin:/bin" \
  "$ROOT/scripts/tools.sh" codebase-memory-mcp mcp disable codex >/dev/null
[ "$(cat "$fallback_home/codex/config.toml")" = 'model = "preserve-this"' ]

# OpenCode JSON config changes preserve unrelated servers/settings and disable
# refuses modified manager-owned content.
opencode_home="$SANDBOX/opencode"; mkdir -p "$opencode_home/.local/share/codebase-memory-mcp" "$opencode_home/.local/bin" "$opencode_home/config"
cp "$fakebin/codebase-memory-mcp" "$opencode_home/.local/share/codebase-memory-mcp/codebase-memory-mcp"
ln -s "$opencode_home/.local/share/codebase-memory-mcp/codebase-memory-mcp" "$opencode_home/.local/bin/codebase-memory-mcp"
printf '{"model":"keep","mcp":{"other":{"type":"local","command":["other"]}}}\n' > "$opencode_home/config/opencode.json"
opencode_run() { HOME="$opencode_home" XDG_STATE_HOME="$opencode_home/state" OPENCODE_CONFIG="$opencode_home/config/opencode.json" PATH="$fakebin:/usr/bin:/bin" "$ROOT/scripts/tools.sh" codebase-memory-mcp "$@"; }
before="$(cksum "$opencode_home/config/opencode.json")"
opencode_run mcp enable opencode --dry-run >/dev/null
[ "$before" = "$(cksum "$opencode_home/config/opencode.json")" ]
opencode_run mcp enable opencode >/dev/null
result="$(opencode_run mcp enable opencode)"; grep -q 'UNCHANGED' <<< "$result"
result="$(opencode_run mcp status opencode)"; grep -q 'manager-owned' <<< "$result"
python3 - "$opencode_home/config/opencode.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert d["model"]=="keep" and d["mcp"]["other"]["command"]==["other"]
assert d["mcp"]["codebase-memory-mcp"]["enabled"] is True
PY
opencode_run mcp disable opencode --dry-run >/dev/null
opencode_run mcp disable opencode >/dev/null
python3 - "$opencode_home/config/opencode.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert d["model"]=="keep" and "codebase-memory-mcp" not in d["mcp"]
PY
opencode_run mcp enable opencode >/dev/null
python3 - "$opencode_home/config/opencode.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["mcp"]["codebase-memory-mcp"]["command"]=["/changed"]; json.dump(d,open(p,"w"))
PY
if opencode_run mcp disable opencode >/dev/null 2>&1; then echo 'Modified OpenCode entry removed' >&2; exit 1; fi

# Antigravity's documented global MCP config preserves unrelated values and only
# removes an unchanged entry with manager ownership evidence.
antigravity_home="$SANDBOX/antigravity"; mkdir -p "$antigravity_home/.local/share" "$antigravity_home/.local/bin" "$antigravity_home/.gemini/config"
run_manager "$antigravity_home" install >/dev/null
printf '{"theme":"preserve","mcpServers":{"other":{"command":"other","args":[]}}}\n' > "$antigravity_home/.gemini/config/mcp_config.json"
antigravity_run() {
  HOME="$antigravity_home" XDG_STATE_HOME="$antigravity_home/state" XDG_DATA_HOME="$antigravity_home/.local/share" \
    ANTIGRAVITY_CONFIG="$antigravity_home/.gemini/config/mcp_config.json" PATH="$fakebin:/usr/bin:/bin" \
    "$ROOT/scripts/tools.sh" codebase-memory-mcp "$@"
}
before="$(cksum "$antigravity_home/.gemini/config/mcp_config.json")"
antigravity_run mcp enable antigravity --dry-run >/dev/null
[ "$before" = "$(cksum "$antigravity_home/.gemini/config/mcp_config.json")" ]
antigravity_run mcp enable antigravity >/dev/null
result="$(antigravity_run mcp enable antigravity)"; grep -q 'UNCHANGED' <<< "$result"
result="$(antigravity_run mcp status antigravity)"; grep -q 'manager-owned, unchanged' <<< "$result"
python3 - "$antigravity_home/.gemini/config/mcp_config.json" "$antigravity_home/.local/share/dev-agent-config/tools/codebase-memory-mcp/versions/0.11.0/codebase-memory-mcp" <<'PY'
import json,pathlib,sys
d=json.load(open(sys.argv[1])); e=d['mcpServers']['codebase-memory-mcp']
assert pathlib.Path(e['command']).resolve()==pathlib.Path(sys.argv[2]).resolve() and e['args']==[] and d['theme']=='preserve' and 'other' in d['mcpServers']
PY
antigravity_run mcp disable antigravity --dry-run >/dev/null
antigravity_run mcp disable antigravity >/dev/null
python3 - "$antigravity_home/.gemini/config/mcp_config.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d['theme']=='preserve' and 'other' in d['mcpServers'] and 'codebase-memory-mcp' not in d['mcpServers']
PY
antigravity_run mcp enable antigravity >/dev/null
python3 - "$antigravity_home/.gemini/config/mcp_config.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['mcpServers']['codebase-memory-mcp']['command']='/changed'; json.dump(d,open(p,'w'))
PY
if antigravity_run mcp disable antigravity >/dev/null 2>&1; then echo 'Modified Antigravity entry removed' >&2; exit 1; fi
rm "$antigravity_home/state/dev-agent-config/tools/codebase-memory-mcp/antigravity-mcp.tsv"
before="$(cksum "$antigravity_home/.gemini/config/mcp_config.json")"
result="$(antigravity_run mcp enable antigravity)"; grep -q EXTERNAL <<< "$result"
[ "$before" = "$(cksum "$antigravity_home/.gemini/config/mcp_config.json")" ]
result="$(antigravity_run mcp status antigravity)"; grep -q 'externally managed' <<< "$result"

# Graphify remains independently dispatched and its fixture suite is exercised separately.
"$ROOT/scripts/tools.sh" codebase-memory-mcp --help >/dev/null
echo 'PASS CBM: adoption, verified install/update/rollback/remove, Codex/OpenCode/Antigravity MCP ownership and preservation'
