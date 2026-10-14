#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
REAL_PYTHON="$(command -v python3)"

run_case() {
  local os="$1" case_home fakebin
  case_home="$SANDBOX/$os"; fakebin="$case_home/bin"
  mkdir -p "$fakebin" "$case_home/.local/bin" "$case_home/data/dev-agent-config/tools/codebase-memory-mcp/versions/0.11.0" "$case_home/state/dev-agent-config/tools/codebase-memory-mcp"
  cat > "$fakebin/uname" <<SH
#!/bin/sh
case "${1:-}" in -s) echo "$os" ;; -m) echo arm64 ;; *) echo "$os" ;; esac
SH
  cat > "$fakebin/systemctl" <<'SH'
#!/bin/sh
[ "${1:-}" = --user ] || exit 2
shift
case "${1:-}" in
 show) [ -f "$HOME/.config/systemd/user/dev-agent-config-cbm-dashboard.service" ] && printf '%s\n' "$HOME/.config/systemd/user/dev-agent-config-cbm-dashboard.service";;
 is-active) [ -f "$HOME/service.active" ] && exit 0 || exit 3;;
 is-enabled) [ -f "$HOME/service.enabled" ] && exit 0 || exit 1;;
 enable) : > "$HOME/service.enabled"; : > "$HOME/service.active";;
 disable) rm -f "$HOME/service.active" "$HOME/service.enabled";;
 daemon-reload) :;;
 *) exit 2;;
esac
SH
  cat > "$fakebin/launchctl" <<'SH'
#!/bin/sh
case "${1:-}" in
 print) [ -f "$HOME/service.active" ] && { printf 'path = %s\nstate = running\npid = 1234\n' "$HOME/Library/LaunchAgents/org.dev-agent-config.cbm-dashboard.plist"; exit 0; }; exit 113;;
 print-disabled) [ -f "$HOME/service.disabled" ] && printf '"org.dev-agent-config.cbm-dashboard" => true\n';;
 enable) rm -f "$HOME/service.disabled";;
 disable) : > "$HOME/service.disabled";;
 bootstrap) : > "$HOME/service.active";;
 bootout) rm -f "$HOME/service.active";;
 *) exit 2;;
esac
SH
  chmod +x "$fakebin/uname" "$fakebin/systemctl" "$fakebin/launchctl"
  cat > "$fakebin/python3" <<'SH'
#!/bin/sh
if [ "${1:-}" = - ]; then
  source="$(cat)"
  case "$source" in *'s.bind(("127.0.0.1"'*) exit 0 ;; esac
  printf '%s\n' "$source" | exec "$CBM_REAL_PYTHON" "$@"
fi
case "$*" in *'s.bind(("127.0.0.1"'*) exit 0 ;; esac
exec "$CBM_REAL_PYTHON" "$@"
SH
  chmod +x "$fakebin/python3"
  local executable="$case_home/data/dev-agent-config/tools/codebase-memory-mcp/versions/0.11.0/codebase-memory-mcp"
  cat > "$executable" <<'CBM'
#!/bin/sh
echo 'codebase-memory-mcp v0.11.0'
CBM
  chmod 755 "$executable"
  local hash
  hash="$(shasum -a 256 "$executable" | awk '{print $1}')"
  printf 'ownership\tdev-agent-config\nversion\t0.11.0\nbinary_sha256\t%s\n' "$hash" > "$(dirname "$executable")/.manager-owned.tsv"
  printf '0.11.0\n' > "$case_home/state/dev-agent-config/tools/codebase-memory-mcp/active-version"
  ln -s "$executable" "$case_home/.local/bin/codebase-memory-mcp"

  run() {
    HOME="$case_home" CBM_REAL_PYTHON="$REAL_PYTHON" XDG_STATE_HOME="$case_home/state" XDG_DATA_HOME="$case_home/data" XDG_CONFIG_HOME="$case_home/.config" PATH="$fakebin:/usr/bin:/bin" \
      "$ROOT/scripts/tools.sh" codebase-memory-mcp service "$@"
  }

  local def
  if [ "$os" = Linux ]; then def="$case_home/.config/systemd/user/dev-agent-config-cbm-dashboard.service"; else def="$case_home/Library/LaunchAgents/org.dev-agent-config.cbm-dashboard.plist"; fi
  result="$(run install --port 19749 --dry-run)"
  grep -q 'WOULD_INSTALL' <<< "$result"
  [ ! -e "$def" ]
  result="$(run install --port 19749)"
  grep -q 'Not enabled or started' <<< "$result"
  [ -f "$def" ] && [ -f "$case_home/state/dev-agent-config/tools/codebase-memory-mcp/dashboard-service.tsv" ]
  grep -Fq "$case_home/.local/bin/codebase-memory-mcp" "$def"
  grep -Fq "$ROOT/scripts/tools/cbm-dashboard-runner.py" "$def"
  grep -q '19749' "$def"
  if [ "$os" = Darwin ]; then
    "$REAL_PYTHON" - "$def" "$case_home/.local/bin/codebase-memory-mcp" <<'PY'
import plistlib,sys
d=plistlib.load(open(sys.argv[1],'rb'))
assert d['RunAtLoad'] and d['KeepAlive']
assert sys.argv[2] in d['ProgramArguments']
PY
  fi
  result="$(run verify)"
  grep -q 'Service definition: healthy' <<< "$result"
  cp -p "$def" "$def.saved"
  printf '\n# local edit\n' >> "$def"
  if run verify >/dev/null 2>&1; then echo 'Modified manager service definition passed verification' >&2; exit 1; fi
  mv "$def.saved" "$def"
  run verify >/dev/null
  result="$(run enable --dry-run)"
  grep -q 'WOULD_ENABLE' <<< "$result"
  [ ! -e "$case_home/service.active" ]
  run enable >/dev/null
  result="$(run enable)"
  grep -q 'already active' <<< "$result"
  result="$(run disable --dry-run)"
  grep -q 'WOULD_DISABLE/STOP' <<< "$result"
  [ -e "$case_home/service.active" ]
  result="$(run remove --dry-run)"
  grep -q 'WOULD_REMOVE' <<< "$result"
  grep -q 'WOULD_DISABLE/STOP' <<< "$result"
  [ -f "$def" ]
  run disable >/dev/null
  [ ! -e "$case_home/service.active" ]
  run remove >/dev/null
  [ ! -e "$def" ] && [ ! -e "$case_home/state/dev-agent-config/tools/codebase-memory-mcp/dashboard-service.tsv" ]
}

run_case Linux
run_case Darwin

# An existing external service definition is never overwritten.
home="$SANDBOX/conflict"
fakebin="$SANDBOX/conflict-bin"
mkdir -p "$fakebin" "$home/.local/bin" "$home/data/dev-agent-config/tools/codebase-memory-mcp/versions/0.11.0" "$home/state/dev-agent-config/tools/codebase-memory-mcp" "$home/.config/systemd/user"
cat > "$fakebin/uname" <<'SH'
#!/bin/sh
echo Linux
SH
chmod +x "$fakebin/uname"
executable="$home/data/dev-agent-config/tools/codebase-memory-mcp/versions/0.11.0/codebase-memory-mcp"
printf '#!/bin/sh\necho v0.11.0\n' > "$executable"; chmod +x "$executable"
hash="$(shasum -a 256 "$executable" | awk '{print $1}')"
printf 'ownership\tdev-agent-config\nversion\t0.11.0\nbinary_sha256\t%s\n' "$hash" > "$(dirname "$executable")/.manager-owned.tsv"
printf '0.11.0\n' > "$home/state/dev-agent-config/tools/codebase-memory-mcp/active-version"
ln -s "$executable" "$home/.local/bin/codebase-memory-mcp"
def="$home/.config/systemd/user/dev-agent-config-cbm-dashboard.service"
printf 'user content\n' > "$def"
before="$(cksum "$def")"
if HOME="$home" XDG_STATE_HOME="$home/state" XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/.config" PATH="$fakebin:/usr/bin:/bin" "$ROOT/scripts/tools.sh" codebase-memory-mcp service install >/dev/null 2>&1; then
  echo 'External service definition was overwritten' >&2; exit 1
fi
[ "$before" = "$(cksum "$def")" ]
rm "$def"
ln -s "$home/user-owned-target" "$def"
printf 'target stays intact\n' > "$home/user-owned-target"
if HOME="$home" XDG_STATE_HOME="$home/state" XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/.config" PATH="$fakebin:/usr/bin:/bin" "$ROOT/scripts/tools.sh" codebase-memory-mcp service install >/dev/null 2>&1; then
  echo 'Service install accepted a symlink conflict' >&2; exit 1
fi
[ -L "$def" ] && [ "$(cat "$home/user-owned-target")" = 'target stays intact' ]
echo 'PASS CBM service: Linux systemd/macOS launchd definitions, dry-run, ownership and lifecycle fixtures'
