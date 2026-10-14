#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
home="$SANDBOX/home"
bin="$home/.local/bin"
projects="$SANDBOX/projects"
mkdir -p "$bin" "$projects/retail api" "$projects/other api" "$projects/external api"
real_python="$(command -v python3)"
cat > "$bin/python3" <<'PYSH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = - ]; then
  source_code="$(cat)"
  case "$source_code" in
    *HTTPConnection*) [ -f "${CBM_FAKE_DASHBOARD_READY:-/nonexistent}" ]; exit ;;
    *'s.bind(("127.0.0.1"'*) [ "${CBM_FAKE_PORT_STATE:-free}" != busy ] && [ ! -f "${CBM_FAKE_DASHBOARD_READY:-/nonexistent}" ]; exit ;;
    *'s.connect(("127.0.0.1"'*) [ "${CBM_FAKE_PORT_STATE:-free}" != busy ]; exit ;;
  esac
  printf '%s\n' "$source_code" | exec "${CBM_REAL_PYTHON:?}" "$@"
fi
if [[ "$*" == *'s.bind(("127.0.0.1"'* ]]; then [ "${CBM_FAKE_PORT_STATE:-free}" != busy ]; exit; fi
if [[ "$*" == *'s.connect(("127.0.0.1"'* ]]; then [ "${CBM_FAKE_PORT_STATE:-free}" != busy ]; exit; fi
exec "${CBM_REAL_PYTHON:?}" "$@"
PYSH
chmod +x "$bin/python3"
export CBM_REAL_PYTHON="$real_python"
export CBM_FAKE_DASHBOARD_READY="$home/dashboard-ready" CBM_TEST_BINARY="$bin/codebase-memory-mcp"
cat > "$bin/ps" <<'PSSH'
#!/usr/bin/env sh
if [ -n "${CBM_DAC_EXPECTED_NONCE:-}" ]; then
  printf '%s %s\n' "$CBM_DAC_RUNNER" "$CBM_DAC_EXPECTED_NONCE"
  exit 0
fi
if [ -f "${CBM_FAKE_DASHBOARD_READY:-/nonexistent}" ]; then
  printf '%s --cbm-daemon-internal\n' "${CBM_TEST_BINARY:?}"
  exit 0
fi
if [ "${CBM_FAKE_PORT_STATE:-free}" = busy ]; then echo '/usr/bin/unrelated-listener'; exit 0; fi
exit 1
PSSH
chmod +x "$bin/ps"
cat > "$bin/lsof" <<'LSS'
#!/usr/bin/env sh
if [ -f "${CBM_FAKE_DASHBOARD_READY:-/nonexistent}" ] || [ "${CBM_FAKE_PORT_STATE:-free}" = busy ]; then echo 9876; exit 0; fi
exit 1
LSS
chmod +x "$bin/lsof"
git -C "$projects/retail api" init -q
git -C "$projects/other api" init -q
git -C "$projects/external api" init -q
export HOME="$home" XDG_STATE_HOME="$home/state" CBM_FAKE_PROJECTS="$home/projects.json"
mkdir -p "$home/.local/share"
printf '{"projects":[]}\n' > "$CBM_FAKE_PROJECTS"
python3 - "$CBM_FAKE_PROJECTS" "$projects/external api" <<'PY'
import json,os,sys
json.dump({"projects":[{"name":"external-api","repo_path":os.path.realpath(sys.argv[2])}]},open(sys.argv[1],"w"))
PY

cat > "$bin/codebase-memory-mcp" <<'CBM'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = --version ]; then echo 'codebase-memory-mcp v0.11.0'; exit 0; fi
if [ "${1:-}" = --ui=true ]; then
  : > "$CBM_FAKE_DASHBOARD_READY"
  sleep 600 & child=$!
  trap 'kill "$child" 2>/dev/null || :; wait "$child" 2>/dev/null || :; rm -f "$CBM_FAKE_DASHBOARD_READY"; exit 0' TERM INT
  wait "$child"
fi
[ "${1:-}" = cli ] || [ "${1:-}" = config ] || exit 2
if [ "$1" = config ]; then
  action="${2:-}"; setting="${3:-}"
  if [ "$action" = get ]; then
    case "$setting" in watcher_enabled) printf 'true\n' ;; auto_watch) printf 'true\n' ;; *) exit 1 ;; esac
    exit 0
  fi
  if [ "$action" = set ]; then printf '%s=%s\n' "$setting" "${4:-}" > "$HOME/config-setting"; exit 0; fi
fi
shift
while [ "${1:-}" = --quiet ] || [ "${1:-}" = --progress ]; do shift; done
tool="${1:-}"; shift || true
case "$tool" in
  list_projects) cat "$CBM_FAKE_PROJECTS" ;;
  index_repository)
    path=''
    while [ "$#" -gt 0 ]; do case "$1" in --repo-path) path="$2"; shift 2 ;; *) shift ;; esac; done
    python3 - "$CBM_FAKE_PROJECTS" "$path" <<'PY'
import json,os,sys
p=sys.argv[1]; path=os.path.realpath(sys.argv[2]); data=json.load(open(p))
items=[x for x in data["projects"] if os.path.realpath(x["repo_path"])!=path]
items.append({"name":os.path.basename(path).replace(" ","-"),"repo_path":path})
json.dump({"projects":items},open(p,"w"))
PY
    echo indexed ;;
  index_status) printf '{"state":"indexed","project":"%s","watch":{"strategy":"git"}}\n' "${2:-}" ;;
  delete_project)
    name=''
    while [ "$#" -gt 0 ]; do case "$1" in --project) name="$2"; shift 2 ;; *) shift ;; esac; done
    python3 - "$CBM_FAKE_PROJECTS" "$name" <<'PY'
import json,sys
p=sys.argv[1]; name=sys.argv[2]; data=json.load(open(p))
data["projects"]=[x for x in data["projects"] if x["name"]!=name]
json.dump(data,open(p,"w"))
PY
    ;;
  *) echo "unexpected fake CBM operation: $tool" >&2; exit 2 ;;
esac
CBM
chmod +x "$bin/codebase-memory-mcp"

run_cbm() {
  PATH="$bin:/usr/bin:/bin" "$ROOT/scripts/tools.sh" codebase-memory-mcp "$@"
}
source_one="$projects/retail api/README.md"
printf 'preserve retail source\n' > "$source_one"
source_two="$projects/other api/README.md"
printf 'preserve other source\n' > "$source_two"
printf 'preserve external source\n' > "$projects/external api/README.md"
source_before="$(cksum "$source_one" "$source_two" "$projects/external api/README.md")"

# Invocation is from a directory different from the manager repo. PWD defaults,
# explicit --project wins, and paths containing spaces survive normalization.
result="$(cd "$projects/retail api" && run_cbm index)"; grep -q 'manager-owned project mapping' <<< "$result"
result="$(run_cbm status --project "$projects/retail api")"; grep -q 'Project: ' <<< "$result"
grep -q 'Git branch:' <<< "$result"
grep -q 'Project watcher registration: reported by CBM (strategy=git)' <<< "$result"
grep -q 'Source changes detected: unverified' <<< "$result"
result="$(cd "$projects/retail api" && run_cbm project status)"; grep -q 'Project: ' <<< "$result"
result="$(cd "$projects/retail api" && run_cbm index --dry-run)"; grep -q "retail api" <<< "$result"
result="$(cd "$projects/retail api" && run_cbm index --project "$projects/other api")"; grep -q 'other-api' <<< "$result"
python3 - "$CBM_FAKE_PROJECTS" "$projects/retail api" "$projects/other api" <<'PY'
import json,os,sys
d=json.load(open(sys.argv[1])); paths={x["repo_path"] for x in d["projects"]}
assert os.path.realpath(sys.argv[2]) in paths and os.path.realpath(sys.argv[3]) in paths
PY
if (cd "$SANDBOX" && run_cbm project status); then echo 'Default project status accepted non-repository cwd' >&2; exit 1; fi
if run_cbm status --project "$SANDBOX/no-such-project" >/dev/null 2>&1; then echo 'Invalid explicit project was accepted' >&2; exit 1; fi
if run_cbm status --project "$SANDBOX" >/dev/null 2>&1; then echo 'Unindexed project was treated as indexed' >&2; exit 1; fi

# Only the index created by this manager gets a cleanup mapping. Dry-run does
# not mutate CBM state and clean never touches repository sources.
one_meta="$(find "$home/state/dev-agent-config/tools/codebase-memory-mcp/projects" -type f -name '*.tsv' | head -n1)"
[ -f "$one_meta" ]
before="$(cksum "$CBM_FAKE_PROJECTS" "$one_meta")"
result="$(run_cbm clean --project "$projects/retail api" --dry-run)"
grep -q 'WOULD_CLEAN project:' <<< "$result"
[ "$before" = "$(cksum "$CBM_FAKE_PROJECTS" "$one_meta")" ]
run_cbm clean --project "$projects/retail api" >/dev/null
result="$(run_cbm clean --project "$projects/retail api")"; grep -q 'ALREADY CLEAN' <<< "$result"
python3 - "$CBM_FAKE_PROJECTS" "$projects/other api" "$projects/external api" <<'PY'
import json,os,sys
d=json.load(open(sys.argv[1])); paths={x["repo_path"] for x in d["projects"]}
assert len(paths)==2 and os.path.realpath(sys.argv[2]) in paths and os.path.realpath(sys.argv[3]) in paths
PY
[ "$(cksum "$source_one" "$source_two" "$projects/external api/README.md")" = "$source_before" ]
if run_cbm clean --project "$projects/external api" >/dev/null 2>&1; then echo 'External project index was deleted' >&2; exit 1; fi

# A stale manager mapping is safely reportable and removable without treating
# dry-run as a mutation.
(cd "$projects/retail api" && run_cbm index >/dev/null)
stale_meta=''
while IFS= read -r candidate; do
  if grep -Fqx "project_path$(printf '\t')$(cd -P "$projects/retail api" && pwd)" "$candidate"; then stale_meta="$candidate"; break; fi
done < <(find "$home/state/dev-agent-config/tools/codebase-memory-mcp/projects" -type f -name '*.tsv')
[ -n "$stale_meta" ]
python3 - "$CBM_FAKE_PROJECTS" "$projects/retail api" <<'PY'
import json,os,sys
p=sys.argv[1]; path=os.path.realpath(sys.argv[2]); data=json.load(open(p))
data['projects']=[x for x in data['projects'] if os.path.realpath(x['repo_path'])!=path]
json.dump(data,open(p,'w'))
PY
result="$(run_cbm clean --project "$projects/retail api" --dry-run)"
grep -q 'WOULD_REMOVE stale manager mapping:' <<< "$result"
[ -f "$stale_meta" ]
run_cbm clean --project "$projects/retail api" >/dev/null
[ ! -e "$stale_meta" ]

# Dashboard lifecycle is loopback-only, process-token owned, and clean refuses
# to run while that project's visualization is active.
(cd "$projects/other api" && run_cbm index >/dev/null)
port=39487
result="$(run_cbm dashboard start --project "$projects/other api" --port "$port" --dry-run)"; grep -q "http://127.0.0.1:$port" <<< "$result"
run_cbm dashboard start --project "$projects/other api" --port "$port" >/dev/null
result="$(run_cbm dashboard status)"; grep -q 'running (manager-owned' <<< "$result"
if run_cbm clean --project "$projects/other api" >/dev/null 2>&1; then echo 'Clean proceeded while dashboard was active' >&2; exit 1; fi
result="$(run_cbm dashboard stop --dry-run)"; grep -q 'WOULD_STOP' <<< "$result"
run_cbm dashboard stop >/dev/null
result="$(run_cbm dashboard status)"; grep -q 'stopped' <<< "$result"

# Port conflicts fail closed using the isolated port-probe fixture.
port=39488
if CBM_FAKE_PORT_STATE=busy run_cbm dashboard start --project "$projects/other api" --port "$port" >/dev/null 2>&1; then echo 'Dashboard ignored occupied port' >&2; exit 1; fi

# Watcher settings are opt-in and do not imply confirmed runtime activity.
[ ! -e "$home/config-setting" ]
result="$(run_cbm watcher set enabled --dry-run)"; grep -q 'WOULD_SET' <<< "$result"
[ ! -e "$home/config-setting" ]
result="$(run_cbm watcher set enabled)"; grep -q 'CONFIGURED' <<< "$result"
result="$(run_cbm watcher status)"; grep -q 'auto_watch): true' <<< "$result"
grep -q 'source-change detection' <<< "$result"
if run_cbm service verify >/dev/null 2>&1; then echo 'Uninstalled persistent service passed verification' >&2; exit 1; fi

echo 'PASS CBM projects: cwd/explicit paths, safe mapping and clean, dashboard ownership, watcher evidence'
