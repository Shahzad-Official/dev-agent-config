#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
REAL_PYTHON="$(command -v python3)"
BIN="$SANDBOX/bin"
RELEASE="$SANDBOX/release"
mkdir -p "$BIN" "$RELEASE"

cat > "$BIN/uname" <<'SH'
#!/bin/sh
case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; *) echo Linux ;; esac
SH
cat > "$BIN/curl" <<'SH'
#!/bin/sh
out=''; url=''
if [ -n "${CBM_CURL_LOG:-}" ]; then printf '%s\n' "$*" >> "$CBM_CURL_LOG"; fi
while [ "$#" -gt 0 ]; do
  case "$1" in --output|-o) out="$2"; shift 2 ;; --*) shift ;; *) url="$1"; shift ;; esac
done
case "$url" in
  */releases/download/v*/checksums.txt) cp "$CBM_TEST_RELEASE/checksums.txt" "$out" ;;
  */releases/download/v*/*.tar.gz) cp "$CBM_TEST_RELEASE/$(basename "$url")" "$out" ;;
  *) exit 2 ;;
esac
SH
cat > "$BIN/ps" <<'SH'
#!/bin/sh
if [ -n "${CBM_DAC_EXPECTED_NONCE:-}" ]; then
  printf '%s %s\n' "$CBM_DAC_RUNNER" "$CBM_DAC_EXPECTED_NONCE"
  exit 0
fi
if [ -n "${CBM_FAKE_PORT_MODE:-}" ]; then
  case "$CBM_FAKE_PORT_MODE" in
    unrelated) printf '/usr/bin/unrelated-listener\n'; exit 0 ;;
    cbm-transient|cbm-healthy|cbm-timeout) printf '%s --cbm-daemon-internal\n' "$CBM_TEST_BINARY"; exit 0 ;;
  esac
fi
exit 1
SH
cat > "$BIN/lsof" <<'SH'
#!/bin/sh
case "${CBM_FAKE_PORT_MODE:-}" in
  cbm-transient)
    n=0; [ ! -f "$CBM_FAKE_PORT_STATE" ] || n="$(cat "$CBM_FAKE_PORT_STATE")"
    n=$((n + 1)); printf '%s\n' "$n" > "$CBM_FAKE_PORT_STATE"
    [ "$n" -le 2 ] && echo 4242
    ;;
  cbm-healthy|cbm-timeout) echo 4242 ;;
  unrelated) echo 4343 ;;
  *) exit 1 ;;
esac
SH
cat > "$BIN/python3" <<'SH'
#!/bin/sh
if [ "$1" = - ]; then
  source="$(cat)"
  case "$source" in
    *"HTTPConnection('127.0.0.1'"*) [ "${CBM_FAKE_UI_HEALTHY:-0}" = 1 ] && exit 0 || exit 1 ;;
    *'s.bind(("127.0.0.1"'*)
      if [ "${CBM_FAKE_PORT_MODE:-}" = cbm-transient ]; then
        n=0; [ ! -f "$CBM_FAKE_PORT_STATE" ] || n="$(cat "$CBM_FAKE_PORT_STATE")"
        [ "$n" -lt 3 ] && exit 1
      elif [ -n "${CBM_FAKE_PORT_MODE:-}" ] || [ "${CBM_FAKE_PORT_BUSY:-0}" = 1 ]; then exit 1; fi
      ;;
  esac
  printf '%s\n' "$source" | exec "$CBM_REAL_PYTHON" "$@"
fi
exec "$CBM_REAL_PYTHON" "$@"
SH
chmod +x "$BIN"/*

cat > "$RELEASE/codebase-memory-mcp" <<'CBM'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = --version ]; then echo 'codebase-memory-mcp v0.11.0'; exit 0; fi
printf '%s cache=%s\n' "$*" "${CBM_CACHE_DIR:-unset}" >> "$CBM_CALL_LOG"
[ "$1" = cli ] || [ "$1" = config ] || exit 2
if [ "$1" = config ]; then
  case "$3" in watcher_enabled|auto_watch) echo true ;; *) exit 1 ;; esac
  exit 0
fi
shift
while [ "$1" = --quiet ] || [ "$1" = --progress ]; do shift; done
tool="$1"; shift
case "$tool" in
  list_projects) cat "$CBM_FAKE_PROJECTS" ;;
  index_status) printf '{"state":"%s","watch":{"strategy":"git"}}\n' "${CBM_FAKE_STATE:-indexed}" ;;
  index_repository)
    repo=''
    while [ "$#" -gt 0 ]; do case "$1" in --repo-path) repo="$2"; shift 2 ;; *) shift ;; esac; done
    "$CBM_REAL_PYTHON" - "$CBM_FAKE_PROJECTS" "$repo" <<'PY'
import json,os,sys
p,repo=sys.argv[1:]; d=json.load(open(p)); root=os.path.realpath(repo)
items=[x for x in d["projects"] if os.path.realpath(x["repo_path"]) != root]
items.append({"name":os.path.basename(root).replace(" ","-"),"repo_path":root})
json.dump({"projects":items},open(p,"w"))
PY
    echo indexed ;;
  *) exit 2 ;;
esac
CBM
chmod +x "$RELEASE/codebase-memory-mcp"
tar -czf "$RELEASE/codebase-memory-mcp-linux-amd64-portable.tar.gz" -C "$RELEASE" codebase-memory-mcp
hash="$(shasum -a 256 "$RELEASE/codebase-memory-mcp-linux-amd64-portable.tar.gz" | awk '{print $1}')"
printf '%s  codebase-memory-mcp-linux-amd64-portable.tar.gz\n' "$hash" > "$RELEASE/checksums.txt"

make_project() { mkdir -p "$1"; git -C "$1" init -q; printf 'project rule\n' > "$1/AGENTS.md"; }
run() (
  home="$1"; project="$2"; log="$3"; shift 3
  cd "$project"
  HOME="$home" CODEX_HOME="$home/.codex" XDG_STATE_HOME="$home/state" XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" \
    CBM_CACHE_DIR="$home/isolate/cache" CBM_FAKE_PROJECTS="$home/projects.json" CBM_CALL_LOG="$log" \
    CBM_TEST_BINARY="$home/data/dev-agent-config/tools/codebase-memory-mcp/versions/0.11.0/codebase-memory-mcp" \
    CBM_FAKE_PORT_MODE="${CBM_FAKE_PORT_MODE:-}" CBM_FAKE_UI_HEALTHY="${CBM_FAKE_UI_HEALTHY:-0}" \
    CBM_FAKE_PORT_BUSY="${CBM_FAKE_PORT_BUSY:-0}" CBM_FAKE_PORT_STATE="${CBM_FAKE_PORT_STATE:-$home/port-state}" \
    CBM_CURL_LOG="$home/curl.log" \
    CBM_TEST_RELEASE="$RELEASE" CBM_REAL_PYTHON="$REAL_PYTHON" PATH="$BIN:/usr/bin:/bin" \
    "$ROOT/dev-agent-config" cbm run "$@"
)
run_tool() (
  home="$1"; project="$2"; log="$3"; shift 3
  cd "$project"
  HOME="$home" CODEX_HOME="$home/.codex" XDG_STATE_HOME="$home/state" XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" \
    CBM_CACHE_DIR="$home/isolate/cache" CBM_FAKE_PROJECTS="$home/projects.json" CBM_CALL_LOG="$log" \
    CBM_TEST_BINARY="$home/data/dev-agent-config/tools/codebase-memory-mcp/versions/0.11.0/codebase-memory-mcp" \
    CBM_FAKE_PORT_MODE="${CBM_FAKE_PORT_MODE:-}" CBM_FAKE_UI_HEALTHY="${CBM_FAKE_UI_HEALTHY:-0}" \
    CBM_FAKE_PORT_BUSY="${CBM_FAKE_PORT_BUSY:-0}" CBM_FAKE_PORT_STATE="${CBM_FAKE_PORT_STATE:-$home/port-state}" \
    CBM_TEST_RELEASE="$RELEASE" CBM_REAL_PYTHON="$REAL_PYTHON" PATH="$BIN:/usr/bin:/bin" \
    "$ROOT/dev-agent-config" tools codebase-memory-mcp "$@"
)
write_empty_projects() { printf '{"projects":[]}\n' > "$1/projects.json"; }

graphify_before="$(cksum "$ROOT/scripts/tools/graphify.sh" "$ROOT/tools/graphify/tool.conf" "$ROOT/skills/ponytail/SKILL.md")"

# Install a pinned artifact, install only global instructions, and index once.
home="$SANDBOX/fresh"; project="$SANDBOX/projects/fresh app"; log="$SANDBOX/fresh.log"
mkdir -p "$home/.codex" "$(dirname "$project")"; make_project "$project"; write_empty_projects "$home"
project_rule="$(cksum "$project/AGENTS.md")"
result="$(run "$home" "$project" "$log" --no-dashboard --agent codex)"
grep -q 'CBM binary: codebase-memory-mcp v0.11.0 .*manager-owned' <<< "$result"
grep -q 'Downloading official CBM 0.11.0 release archive' <<< "$result"
grep -q 'Verifying release SHA-256' <<< "$result"
grep -q 'Checking downloaded CBM executable' <<< "$result"
grep -q 'Activating verified CBM installation' <<< "$result"
[ "$(grep -c -- '--progress-bar' "$home/curl.log")" -eq 2 ]
grep -q 'INDEXED:' <<< "$result"
grep -q 'MCP codex: ENABLED' <<< "$result"
grep -q 'Watcher configuration:' <<< "$result"
grep -q 'Project watcher registration: CBM reports strategy=git' <<< "$result"
grep -q 'Source-change synchronization: not verified' <<< "$result"
grep -q 'env_vars = \[\"CBM_CACHE_DIR\"\]' "$home/.codex/config.toml"
grep -q "cache=$home/isolate/cache" "$log" || { cat "$log"; exit 1; }
[ -L "$home/.agents/instructions/code-intelligence.md" ]
[ "$(cksum "$project/AGENTS.md")" = "$project_rule" ]
test -f "$home/data/dev-agent-config/tools/codebase-memory-mcp/versions/0.11.0/.manager-owned.tsv"

# Existing indexes aren't refreshed without a positive stale signal or --refresh.
before="$(grep -c index_repository "$log")"
result="$(run "$home" "$project" "$log" --no-dashboard --agent codex)"
grep -q 'stale state not confirmed, no refresh performed' <<< "$result"
[ "$(grep -c index_repository "$log")" = "$before" ]
result="$(CBM_FAKE_STATE=stale run "$home" "$project" "$log" --no-dashboard --agent codex)"
grep -q 'CBM confirmed stale; refreshing' <<< "$result"
[ "$(grep -c index_repository "$log")" -eq $((before + 1)) ]
result="$(CBM_FAKE_PORT_MODE=cbm-healthy CBM_FAKE_UI_HEALTHY=1 run "$home" "$project" "$log" --agent codex)"
grep -q 'healthy CBM UI is already served by the shared daemon' <<< "$result"
grep -q 'dashboard: http://127.0.0.1:9749/?project=fresh-app' <<< "$result"
[ ! -e "$home/state/dev-agent-config/tools/codebase-memory-mcp/dashboard/process.tsv" ]

# Dry-run with missing installation performs no writes, downloads, or CBM CLI calls.
dryhome="$SANDBOX/dry"; dryproject="$SANDBOX/projects/dry"; drylog="$SANDBOX/dry.log"
mkdir -p "$dryhome/.codex"; make_project "$dryproject"; write_empty_projects "$dryhome"
before="$(find "$dryhome" -type f -exec cksum {} + | cksum)"
result="$(run "$dryhome" "$dryproject" "$drylog" --dry-run --no-mcp --no-dashboard)"
grep -q 'WOULD_INSTALL pinned 0.11.0' <<< "$result"
grep -q 'not queried (dry-run does not contact CBM runtime)' <<< "$result"
[ ! -e "$dryhome/data/dev-agent-config/tools/codebase-memory-mcp/versions/0.11.0/codebase-memory-mcp" ]
[ ! -e "$drylog" ]
[ "$(find "$dryhome" -type f -exec cksum {} + | cksum)" = "$before" ]

# External executable and Codex MCP are recognized but never changed.
ext="$SANDBOX/external"; extproject="$SANDBOX/projects/external"; extlog="$SANDBOX/external.log"
mkdir -p "$ext/.local/bin" "$ext/.codex"; make_project "$extproject"
cp "$RELEASE/codebase-memory-mcp" "$ext/.local/bin/codebase-memory-mcp"; chmod 755 "$ext/.local/bin/codebase-memory-mcp"
binhash="$(cksum "$ext/.local/bin/codebase-memory-mcp")"
printf '{"projects":[{"name":"external","repo_path":"%s"}]}\n' "$extproject" > "$ext/projects.json"
cat > "$ext/.codex/config.toml" <<EOF
model = "custom-model"
[mcp_servers.codebase-memory-mcp]
command = "/external/cbm"
args = ["--custom"]
EOF
confighash="$(cksum "$ext/.codex/config.toml")"
result="$(run "$ext" "$extproject" "$extlog" --no-dashboard)"
grep -q 'external (ownership not adopted' <<< "$result"
grep -q 'MCP codex: EXTERNAL:' <<< "$result"
grep -q 'externally managed (preserved)' <<< "$result"
grep -q 'stale state not confirmed, no refresh performed' <<< "$result"
[ "$binhash" = "$(cksum "$ext/.local/bin/codebase-memory-mcp")" ]
[ "$confighash" = "$(cksum "$ext/.codex/config.toml")" ]
[ ! -e "$ext/state/dev-agent-config/tools/codebase-memory-mcp/codex-mcp.tsv" ]

# OpenCode selection preserves its unrelated MCP config and receives the isolated cache path.
oc="$SANDBOX/opencode"; ocproject="$SANDBOX/projects/opencode"; oclog="$SANDBOX/opencode.log"
mkdir -p "$oc/.local/bin" "$oc/config/opencode"; make_project "$ocproject"
cp "$RELEASE/codebase-memory-mcp" "$oc/.local/bin/codebase-memory-mcp"; chmod 755 "$oc/.local/bin/codebase-memory-mcp"
printf '{"projects":[{"name":"opencode","repo_path":"%s"}]}' "$ocproject" > "$oc/projects.json"
printf '{"mcp":{"other":{"type":"local","command":["other-mcp"]}}}\n' > "$oc/config/opencode/opencode.json"
result="$(run "$oc" "$ocproject" "$oclog" --no-dashboard)"
grep -q 'MCP opencode: ENABLED' <<< "$result"
"$REAL_PYTHON" - "$oc/config/opencode/opencode.json" "$oc/isolate/cache" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d['mcp']['other']['command']==['other-mcp']
assert d['mcp']['codebase-memory-mcp']['environment']['CBM_CACHE_DIR']==sys.argv[2]
PY
# No supported agent is a clean skip; unsupported explicit selection fails early.
none="$SANDBOX/no-agent"; noneproject="$SANDBOX/projects/no-agent"; nonelog="$SANDBOX/no-agent.log"
mkdir -p "$none/bin"; make_project "$noneproject"; cp "$RELEASE/codebase-memory-mcp" "$none/bin/codebase-memory-mcp"
printf '{"projects":[]}\n' > "$none/projects.json"
result="$(HOME="$none" XDG_STATE_HOME="$none/state" XDG_DATA_HOME="$none/data" XDG_CONFIG_HOME="$none/config" \
  CBM_FAKE_PROJECTS="$none/projects.json" CBM_CALL_LOG="$nonelog" CBM_REAL_PYTHON="$REAL_PYTHON" PATH="$none/bin:$BIN:/usr/bin:/bin" \
  "$ROOT/dev-agent-config" cbm run --no-dashboard)"
grep -q 'no supported agent configuration detected' <<< "$result"
if HOME="$none" XDG_STATE_HOME="$none/state" XDG_DATA_HOME="$none/data" XDG_CONFIG_HOME="$none/config" \
  PATH="$none/bin:$BIN:/usr/bin:/bin" "$ROOT/dev-agent-config" cbm run --agent cursor --no-dashboard > "$SANDBOX/unsupported" 2>&1; then
  echo 'Unsupported MCP agent was accepted' >&2; exit 1
fi
grep -q 'Unsupported CBM MCP agent: cursor' "$SANDBOX/unsupported"

# Reuse an exact manager-owned dashboard; an occupied external port fails closed.
meta="$home/state/dev-agent-config/tools/codebase-memory-mcp/dashboard/process.tsv"
mkdir -p "$(dirname "$meta")"
project_real="$(cd -P "$project" && pwd)"
printf 'ownership\tdev-agent-config\npid\t%s\nnonce\tfixture-nonce\nbinary\t%s\nport\t9749\nproject_path\t%s\nproject_name\tfresh-app\n' \
  "$$" "$home/.local/bin/codebase-memory-mcp" "$project_real" > "$meta"
result="$(run "$home" "$project" "$log" --agent codex)"
grep -q 'UNCHANGED: dashboard already serving' <<< "$result"
grep -q 'dashboard: http://127.0.0.1:9749/?project=fresh-app' <<< "$result"
rm "$meta"
if CBM_FAKE_PORT_BUSY=1 run "$home" "$project" "$log" --agent codex > "$SANDBOX/port-conflict" 2>&1; then
  echo 'Dashboard ignored occupied port' >&2; exit 1
fi
grep -q 'Dashboard setup failed safely' "$SANDBOX/port-conflict"
[ ! -e "$meta" ]

# A healthy CBM-owned UI is reused; an indexing daemon's short-lived bind is
# waited out, while unrelated listeners and stuck daemons are never taken over.
result="$(CBM_FAKE_PORT_MODE=cbm-healthy CBM_FAKE_UI_HEALTHY=1 run_tool "$home" "$project" "$log" dashboard start --port 9749)"
grep -q 'healthy CBM UI is already served by the shared daemon' <<< "$result"
[ ! -e "$meta" ]
result="$(CBM_FAKE_PORT_MODE=cbm-healthy CBM_FAKE_UI_HEALTHY=1 run_tool "$home" "$project" "$log" dashboard status)"
grep -q 'healthy (shared CBM daemon; not manager-owned)' <<< "$result"
rm -f "$home/port-state"
result="$(CBM_FAKE_PORT_MODE=cbm-transient CBM_FAKE_PORT_STATE="$home/port-state" run_tool "$home" "$project" "$log" dashboard start --port 9749 --dry-run)"
grep -q 'waiting briefly' <<< "$result"
grep -q 'WOULD_START CBM dashboard' <<< "$result"
if CBM_FAKE_PORT_MODE=unrelated run_tool "$home" "$project" "$log" dashboard start --port 9749 --dry-run > "$SANDBOX/unrelated-port" 2>&1; then
  echo 'Unrelated listener was accepted as a CBM dashboard' >&2; exit 1
fi
grep -q 'non-CBM or incompatible process' "$SANDBOX/unrelated-port"
if CBM_FAKE_PORT_MODE=cbm-timeout run_tool "$home" "$project" "$log" dashboard start --port 9749 --dry-run > "$SANDBOX/cbm-timeout" 2>&1; then
  echo 'Unhealthy persistent daemon UI did not time out safely' >&2; exit 1
fi
grep -q 'did not become healthy within 5 seconds' "$SANDBOX/cbm-timeout"

[ "$graphify_before" = "$(cksum "$ROOT/scripts/tools/graphify.sh" "$ROOT/tools/graphify/tool.conf" "$ROOT/skills/ponytail/SKILL.md")" ]
echo 'PASS CBM run: install/adoption, MCP preservation, index freshness, dry-run, dashboard reuse/conflict, isolation'
