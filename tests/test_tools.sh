#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in */graphify) script="$1"; shift; exec bash "$script" "$@" ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

fakebin="$SANDBOX/fakebin"
mkdir -p "$fakebin"

cat > "$fakebin/python3" <<'PYTHON'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = -c ]; then
  case "${2:-}" in
    *urlopen*) printf '%s\tgraphifyy-%s-py3-none-any.whl\thttps://files.pythonhosted.org/packages/test/graphifyy-%s.whl\t04e5a44c0ff94554315e03d39d8eccfddb2850b77837ede23d75f0f63dc4e66d\n' "${FAKE_LATEST_VERSION:-0.9.88}" "${FAKE_LATEST_VERSION:-0.9.88}" "${FAKE_LATEST_VERSION:-0.9.88}" ;;
    *'a=tuple'*) [[ "$3" > "$4" ]] ;;
    *'version("graphifyy")'*) if [ -f "$(dirname "$0")/VERSION" ]; then cat "$(dirname "$0")/VERSION"; else printf '%s\n' "${FAKE_LATEST_VERSION:-0.9.88}"; fi ;;
    *json.load*) case "$(tr -d '[:space:]' < "$3")" in *'"nodes":['*'"links":['*) ;; *) exit 1 ;; esac ;;
    *sys.version_info*) printf '3.11.0\n' ;;
  esac
  exit 0
fi
if [ "${1:-}" = -m ] && [ "${2:-}" = pip ] && [ "${3:-}" = --version ]; then
  case "$0:${FAKE_VENV_MODE:-}" in
    "$FAKE_PYTHON":*) exit 1 ;;
    *:no-pip|*:no-ensurepip) [ -f "$(dirname "$0")/.pip-ready" ] || exit 1 ;;
  esac
  printf 'pip 25.0\n'
  exit 0
fi
if [ "${1:-}" = -m ] && [ "${2:-}" = ensurepip ]; then
  [ "${FAKE_VENV_MODE:-}" != no-ensurepip ] || exit 1
  touch "$(dirname "$0")/.pip-ready"
  exit 0
fi
if [ "${1:-}" = -m ] && [ "${2:-}" = pip ] && [ "${3:-}" = download ]; then
  [ "$0" != "$FAKE_PYTHON" ] || exit 6
  dest=''
  while [ "$#" -gt 0 ]; do
    [ "$1" != --dest ] || { shift; dest="$1"; }
    shift
  done
  mkdir -p "$dest"
  printf 'fixture wheel\n' > "$dest/graphifyy-${FAKE_LATEST_VERSION:-0.9.88}-py3-none-any.whl"
  exit 0
fi
if [ "${1:-}" = -m ] && [ "${2:-}" = venv ]; then
  [ "${FAKE_VENV_MODE:-}" != no-venv ] || exit 1
  dest="$3"
  mkdir -p "$dest/bin"
  cp "$0" "$dest/bin/python"
  printf '%s\n' "${FAKE_LATEST_VERSION:-0.9.88}" > "$dest/bin/VERSION"
  printf '#!%s/bin/python\n' "$dest" > "$dest/bin/graphify"
  cat >> "$dest/bin/graphify" <<'GRAPHIFY'
set -euo pipefail
if [ "${1:-}" = --version ]; then printf 'graphify %s\n' "$(cat "$(dirname "$0")/VERSION")"; exit 0; fi
if [ "${1:-}" = extract ]; then
  [ "${3:-}" = --out ] && [ "${5:-}" = --code-only ] || { printf 'bad args: %s\n' "$*" >&2; exit 3; }
  for key in OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY GOOGLE_API_KEY MOONSHOT_API_KEY DEEPSEEK_API_KEY AWS_ACCESS_KEY_ID OLLAMA_BASE_URL; do
    eval '[ "${'"$key"'+x}" != x ]' || { printf 'credential leaked: %s\n' "$key" >&2; exit 4; }
  done
  [ "${GRAPHIFY_QUERY_LOG_DISABLE:-}" = 1 ]
  [ "${GRAPHIFY_OUT:-}" = "$4/graphify-out" ]
  mkdir -p "$4/graphify-out"
  if [ "${FAKE_INVALID_GRAPH:-0}" = 1 ]; then
    printf '{"nodes":[],"edges":[]}\n' > "$4/graphify-out/graph.json"
  else
    printf '{"nodes":[{"id":"fixture"}],"links":[{"source":"fixture","target":"fixture"}]}\n' > "$4/graphify-out/graph.json"
  fi
  printf '%s\n' "$*" > "${FAKE_GRAPHIFY_LOG:?}"
elif [ "${1:-}" = cluster-only ]; then
  [ -z "${OPENAI_API_KEY:-}${ANTHROPIC_API_KEY:-}${GEMINI_API_KEY:-}${GOOGLE_API_KEY:-}${AWS_ACCESS_KEY_ID:-}${OLLAMA_BASE_URL:-}" ] || exit 9
  [ "${3:-}" = --graph ] && [ "${5:-}" = --no-label ] && [ "${6:-}" = --no-viz ] || { printf 'bad cluster args: %s\n' "$*" >&2; exit 5; }
  printf '%s\n' "$*" > "${FAKE_GRAPHIFY_LOG:?}.cluster"
  [ "${FAKE_REPORT_FAIL:-0}" != 1 ] || exit 6
  printf '# report\n' > "$GRAPHIFY_OUT/GRAPH_REPORT.md"
elif [ "${1:-}" = query ]; then
  [ "${GRAPHIFY_QUERY_LOG_DISABLE:-}" = 1 ] || exit 7
  [ -z "${OPENAI_API_KEY:-}${ANTHROPIC_API_KEY:-}${GEMINI_API_KEY:-}${GOOGLE_API_KEY:-}${AWS_ACCESS_KEY_ID:-}${OLLAMA_BASE_URL:-}" ] || exit 10
  printf '%s\n' "$*" >> "${FAKE_GRAPHIFY_LOG:?}"
  printf 'query fixture output\n'
elif [ "${1:-}" = export ] && [ "${2:-}" = html ]; then
  [ "${3:-}" = --graph ] || exit 8
  printf '%s\n' "$*" >> "${FAKE_GRAPHIFY_LOG:?}"
  printf '<html>fixture graph</html>\n' > "$GRAPHIFY_OUT/graph.html"
else
  exit 2
fi
GRAPHIFY
  chmod +x "$dest/bin/graphify"
  exit 0
fi
if [ "${1:-}" = -m ] && [ "${2:-}" = pip ] && [ "${3:-}" = install ]; then
  [ "${FAKE_STAGE_FAIL:-0}" != 1 ] || exit 8
  exit 0
fi
if [ "${1:-}" = -m ] && [ "${2:-}" = pip ] && [ "${3:-}" = freeze ]; then
  printf 'graphifyy==%s\nnetworkx==3.4.2\n' "$(cat "$(dirname "$0")/VERSION")"
  exit 0
fi
printf 'unexpected fake python invocation: %s\n' "$*" >&2
exit 9
PYTHON
chmod +x "$fakebin/python3"
FAKE_PYTHON="$fakebin/python3"
export FAKE_PYTHON

cat > "$fakebin/sha256sum" <<'HASH'
#!/usr/bin/env bash
printf '04e5a44c0ff94554315e03d39d8eccfddb2850b77837ede23d75f0f63dc4e66d  %s\n' "$1"
HASH
chmod +x "$fakebin/sha256sum"

cat > "$fakebin/rm" <<'REMOVE'
#!/usr/bin/env bash
if [ "${FAKE_CLEANUP_FAIL:-0}" = 1 ]; then
  for arg in "$@"; do case "$arg" in *dev-agent-config-graphify-preflight*) exit 7 ;; esac; done
fi
exec /bin/rm "$@"
REMOVE
chmod +x "$fakebin/rm"

for opener in open xdg-open gio; do
  cat > "$fakebin/$opener" <<'OPEN'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "${FAKE_GRAPHIFY_LOG:?}.browser"
OPEN
  chmod +x "$fakebin/$opener"
done

cat > "$fakebin/uname" <<'UNAME'
#!/usr/bin/env bash
if [ -n "${FAKE_UNAME:-}" ]; then printf '%s\n' "$FAKE_UNAME"; else exec /usr/bin/uname "$@"; fi
UNAME
chmod +x "$fakebin/uname"

new_home() {
  local name="$1" home="$SANDBOX/$1"
  mkdir -p "$home"
  printf '%s\n' "$home"
}

run_tool() {
  local home="$1"
  shift
  mkdir -p "$home/tmp"
  HOME="$home" XDG_DATA_HOME="$home/data" XDG_STATE_HOME="$home/state" \
    PATH="$fakebin:/usr/bin:/bin" FAKE_GRAPHIFY_LOG="$home/graphify.log" \
    TMPDIR="$home/tmp" \
    "$ROOT/scripts/tools.sh" graphify "$@"
}

tool_dir() { printf '%s/data/dev-agent-config/tools/graphify/%s\n' "$1" "${2:-0.9.88}"; }
project_index_root() {
  local project="$1" name key
  project="$(cd "$project" && pwd -P)"
  name="$(basename "$project" | tr -c 'A-Za-z0-9._-' '_')"
  key="$(printf '%s' "$project" | cksum | awk '{print $1}')"
  printf '%s/data/dev-agent-config/graphify/indexes/%s-%s\n' "$home" "$name" "$key"
}

# Preflight does not need system pip, bootstraps missing venv pip, and explains blockers.
home="$(new_home preflight-no-system-pip)"
preflight_output="$(run_tool "$home" install --dry-run)"
case "$preflight_output" in *'installation can proceed'*) ;; *) exit 1 ;; esac
[ ! -e "$(tool_dir "$home")" ]

home="$(new_home preflight-ensurepip)"
preflight_output="$(FAKE_VENV_MODE=no-pip run_tool "$home" install --dry-run)"
case "$preflight_output" in *'installation can proceed'*) ;; *) exit 1 ;; esac

home="$(new_home preflight-no-venv)"
if FAKE_VENV_MODE=no-venv run_tool "$home" install --dry-run >"$home/out" 2>&1; then echo 'Missing venv was accepted' >&2; exit 1; fi
grep -q 'python3-venv\|includes venv' "$home/out"
grep -q 'Then retry:' "$home/out"
grep -q 'No files were downloaded or installed' "$home/out"
[ ! -e "$(tool_dir "$home")" ]

home="$(new_home preflight-no-pip)"
if FAKE_VENV_MODE=no-ensurepip run_tool "$home" install --dry-run >"$home/out" 2>&1; then echo 'Missing virtualenv pip was accepted' >&2; exit 1; fi
grep -q 'ensurepip could not provide it' "$home/out"

home="$(new_home cleanup-failure)"
if FAKE_CLEANUP_FAIL=1 run_tool "$home" install --dry-run >/dev/null 2>&1; then echo 'Cleanup failure was ignored' >&2; exit 1; fi
[ ! -e "$(tool_dir "$home")" ]

home="$(new_home staging-failure)"
if FAKE_STAGE_FAIL=1 run_tool "$home" install >/dev/null 2>&1; then echo 'Staging failure was accepted' >&2; exit 1; fi
[ ! -e "$(tool_dir "$home")" ]
[ ! -e "$home/state/dev-agent-config/tools/graphify/current-release.tsv" ]

home="$(new_home interrupted)"
stale="$home/data/dev-agent-config/tools/graphify/.graphify-0.9.88.staging.interrupted"
mkdir -p "$stale"
printf '0.9.88\n' > "$stale/.dev-agent-config-stage"
run_tool "$home" install >/dev/null
[ ! -e "$stale" ]
run_tool "$home" verify >/dev/null

# Dry-run and fresh/repeated installation never touch real HOME or the network.
home="$(new_home install)"
run_tool "$home" install --dry-run >/dev/null
[ ! -e "$(tool_dir "$home")" ]
run_tool "$home" install >/dev/null
run_tool "$home" verify >/dev/null
entrypoint="$(tool_dir "$home")/venv/bin/graphify"
shebang="$(sed -n '1s/^#!//p' "$entrypoint")"
[ "$shebang" = "$(tool_dir "$home")/venv/bin/python" ]
[ -x "$shebang" ]
case "$shebang" in *staging*) echo 'Installed entry point references staging' >&2; exit 1 ;; esac
grep -qFx 'graphifyy==0.9.88' "$(tool_dir "$home")/dependencies.txt"
before="$(find "$home/state/dev-agent-config/tools/graphify/backups" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
repeat_output="$(run_tool "$home" install)"
case "$repeat_output" in UNCHANGED*) ;; *) echo 'Repeated install was not unchanged' >&2; exit 1 ;; esac
after="$(find "$home/state/dev-agent-config/tools/graphify/backups" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
[ "$before" = "$after" ]

# Update checks are read-only; upgrades are explicit and roll back to the prior release.
update_output="$(FAKE_LATEST_VERSION=0.9.89 run_tool "$home" check-update)"
case "$update_output" in *'Current Graphify: 0.9.88'*'Latest stable Graphify: 0.9.89'*'Upgrade available'*) ;; *) echo 'Update report was incomplete' >&2; exit 1 ;; esac
if FAKE_LATEST_VERSION=0.9.90 FAKE_STAGE_FAIL=1 run_tool "$home" upgrade >/dev/null 2>&1; then echo 'Failed upgrade was accepted' >&2; exit 1; fi
verify_output="$(run_tool "$home" verify)"
case "$verify_output" in *'Graphify 0.9.88: healthy'*) ;; *) echo 'Failed upgrade damaged current release' >&2; exit 1 ;; esac
[ ! -e "$(tool_dir "$home" 0.9.90)" ]
FAKE_LATEST_VERSION=0.9.89 run_tool "$home" upgrade --dry-run >/dev/null
[ ! -e "$(tool_dir "$home" 0.9.89)" ]
FAKE_LATEST_VERSION=0.9.89 run_tool "$home" upgrade >/dev/null
verify_output="$(run_tool "$home" verify)"
case "$verify_output" in *'Graphify 0.9.89: healthy'*) ;; *) exit 1 ;; esac
upgrade_backup="$(sed -n '1p' "$home/state/dev-agent-config/tools/graphify/last-backup")"
run_tool "$home" rollback "$upgrade_backup" >/dev/null
verify_output="$(run_tool "$home" verify)"
case "$verify_output" in *'Graphify 0.9.88: healthy'*) ;; *) exit 1 ;; esac
[ ! -e "$(tool_dir "$home" 0.9.89)" ]

# A stale staging interpreter is diagnosed and repaired only on explicit request.
entrypoint="$(tool_dir "$home")/venv/bin/graphify"
sed "1c\\
#!/missing/.graphify-0.9.88.staging.old/venv/bin/python
" "$entrypoint" > "$home/broken-graphify"
chmod +x "$home/broken-graphify"
mv "$home/broken-graphify" "$entrypoint"
if run_tool "$home" verify >"$home/verify-out" 2>&1; then echo 'Corrupted tool verified successfully' >&2; exit 1; fi
grep -q 'points to a missing interpreter' "$home/verify-out" || { cat "$home/verify-out" >&2; exit 1; }
grep -q 'graphify repair --dry-run' "$home/verify-out"
if run_tool "$home" install >/dev/null 2>&1; then echo 'Corrupted tool was overwritten' >&2; exit 1; fi
run_tool "$home" repair --dry-run >/dev/null
run_tool "$home" repair >/dev/null
run_tool "$home" verify >/dev/null

# A link at the managed path is refused without following or changing it.
home="$(new_home symlink)"
foreign="$SANDBOX/foreign"
mkdir -p "$foreign" "$(dirname "$(tool_dir "$home")")"
printf 'keep\n' > "$foreign/file"
ln -s "$foreign" "$(tool_dir "$home")"
if run_tool "$home" install >/dev/null 2>&1; then echo 'Symlink conflict was accepted' >&2; exit 1; fi
grep -qFx keep "$foreign/file"

# Install rollback removes only the unchanged manager-owned environment.
home="$(new_home install-rollback)"
run_tool "$home" install >/dev/null
backup="$(sed -n '1p' "$home/state/dev-agent-config/tools/graphify/last-backup")"
run_tool "$home" rollback --dry-run "$backup" >/dev/null
[ -d "$(tool_dir "$home")" ]
run_tool "$home" rollback "$backup" >/dev/null
[ ! -e "$(tool_dir "$home")" ]

# Remove is backed up and rollback restores it; modified ownership is refused.
home="$(new_home remove-rollback)"
run_tool "$home" install >/dev/null
run_tool "$home" remove --dry-run >/dev/null
[ -d "$(tool_dir "$home")" ]
run_tool "$home" remove >/dev/null
backup="$(sed -n '1p' "$home/state/dev-agent-config/tools/graphify/last-backup")"
run_tool "$home" rollback "$backup" >/dev/null
run_tool "$home" verify >/dev/null
printf 'changed\n' > "$(tool_dir "$home")/.dev-agent-config-tool"
if run_tool "$home" remove >/dev/null 2>&1; then echo 'Modified ownership metadata was accepted' >&2; exit 1; fi

# Index requires an explicit real project and always writes code-only output outside it.
home="$(new_home index)"
run_tool "$home" install >/dev/null
project="$home/project"
output="$home/graphs/nest-test"
mkdir -p "$project"
printf 'export const value = 1;\n' > "$project/app.ts"
if run_tool "$home" index >/dev/null 2>&1; then echo 'Index accepted no project' >&2; exit 1; fi
if run_tool "$home" index --project "$project" --output "$project/output" >/dev/null 2>&1; then echo 'Index accepted in-project output' >&2; exit 1; fi
OPENAI_API_KEY=secret ANTHROPIC_API_KEY=secret OLLAMA_BASE_URL=http://example.invalid \
  HOME="$home" XDG_DATA_HOME="$home/data" XDG_STATE_HOME="$home/state" \
  PATH="$fakebin:/usr/bin:/bin" FAKE_GRAPHIFY_LOG="$home/graphify.log" \
  "$ROOT/scripts/tools.sh" graphify index --project "$project" --output "$output" >/dev/null
project_physical="$(cd "$project" && pwd -P)"
grep -qFx "extract $project_physical --out $output --code-only" "$home/graphify.log"
[ -f "$output/graphify-out/graph.json" ]
[ -f "$output/graphify-out/GRAPH_REPORT.md" ]
grep -q '"nodes"' "$output/graphify-out/graph.json"
grep -q '"links"' "$output/graphify-out/graph.json"
grep -qFx "cluster-only $output --graph $output/graphify-out/graph.json --no-label --no-viz" "$home/graphify.log.cluster"
report_failure_output="$(FAKE_REPORT_FAIL=1 run_tool "$home" index --project "$project" --output "$home/graphs/report-failure" 2>&1)"
case "$report_failure_output" in *'INDEXED code-only graph:'*'optional report could not be generated'*) ;; *) echo 'Report failure was not reported separately' >&2; exit 1 ;; esac
[ -f "$home/graphs/report-failure/graphify-out/graph.json" ]
[ ! -e "$home/graphs/report-failure/graphify-out/GRAPH_REPORT.md" ]
if FAKE_INVALID_GRAPH=1 run_tool "$home" index --project "$project" --output "$home/graphs/invalid" >/dev/null 2>&1; then echo 'Invalid graph JSON was accepted' >&2; exit 1; fi
[ ! -e "$project/graphify-out" ]
grep -qFx 'export const value = 1;' "$project/app.ts"

# Project operations resolve the default isolated graph without asking for graph.json.
run_tool "$home" index --project "$project" >/dev/null
indexed_root="$(project_index_root "$project")"
indexed_graph="$indexed_root/graphify-out/graph.json"
query_output="$(OPENAI_API_KEY=secret ANTHROPIC_API_KEY=secret OLLAMA_BASE_URL=http://example.invalid run_tool "$home" query --project "$project" 'where is the fixture symbol?' --budget 640)"
case "$query_output" in *'query fixture output'*) ;; *) echo 'Query did not run against indexed graph' >&2; exit 1 ;; esac
grep -qFx "query where is the fixture symbol? --budget 640 --graph $indexed_graph" "$home/graphify.log"
run_tool "$home" query --project "$project" test --output "$output" >/dev/null
grep -qFx "query test --graph $output/graphify-out/graph.json" "$home/graphify.log"
extract_count="$(grep -c '^extract ' "$home/graphify.log")"
run_tool "$home" report --project "$project" >/dev/null
[ -f "$indexed_root/graphify-out/GRAPH_REPORT.md" ]
run_tool "$home" visualize --project "$project" >/dev/null
[ -f "$indexed_root/graphify-out/graph.html" ]
[ ! -e "$home/graphify.log.browser" ]
run_tool "$home" visualize --project "$project" --open >/dev/null
[ -f "$home/graphify.log.browser" ]
grep -qF "$indexed_root/graphify-out/graph.html" "$home/graphify.log.browser"
browser_count="$(wc -l < "$home/graphify.log.browser" | tr -d ' ')"
SSH_CONNECTION=fixture run_tool "$home" visualize --project "$project" --open > "$home/remote-visualize.out"
grep -q 'Remote session detected; not launching a browser' "$home/remote-visualize.out"
[ "$browser_count" = "$(wc -l < "$home/graphify.log.browser" | tr -d ' ')" ]
FAKE_UNAME=Linux DISPLAY=:fixture run_tool "$home" visualize --project "$project" --open >/dev/null
grep -q '^xdg-open ' "$home/graphify.log.browser"
browser_count="$(wc -l < "$home/graphify.log.browser" | tr -d ' ')"
FAKE_UNAME=Linux DISPLAY= WAYLAND_DISPLAY= run_tool "$home" visualize --project "$project" --open > "$home/headless-visualize.out"
grep -q 'No desktop display detected' "$home/headless-visualize.out"
[ "$browser_count" = "$(wc -l < "$home/graphify.log.browser" | tr -d ' ')" ]
[ "$extract_count" = "$(grep -c '^extract ' "$home/graphify.log")" ]

home_missing="$(new_home graph-operations-missing)"
run_tool "$home_missing" install >/dev/null
mkdir -p "$home_missing/project"
if run_tool "$home_missing" query --project "$home_missing/project" test >/dev/null 2>&1; then echo 'query accepted a missing graph' >&2; exit 1; fi
if run_tool "$home_missing" report --project "$home_missing/project" >/dev/null 2>&1; then echo 'report accepted a missing graph' >&2; exit 1; fi
if run_tool "$home_missing" visualize --project "$home_missing/project" >/dev/null 2>&1; then echo 'visualize accepted a missing graph' >&2; exit 1; fi

# Operation helpers reject symlinked graph data rather than following it.
outside_graph="$SANDBOX/outside-graph.json"
printf '{"nodes":[],"links":[]}\n' > "$outside_graph"
rm "$indexed_graph"
ln -s "$outside_graph" "$indexed_graph"
if run_tool "$home" query --project "$project" test >/dev/null 2>&1; then echo 'Query followed a graph symlink' >&2; exit 1; fi
rm "$indexed_graph"
printf '{"nodes":{},"links":[]}\n' > "$indexed_graph"
if run_tool "$home" query --project "$project" test > "$home/invalid-query.out" 2>&1; then echo 'Query accepted an invalid node-link graph' >&2; exit 1; fi
grep -q 'expected nodes and links arrays' "$home/invalid-query.out"

echo 'PASS tools: install, repeat, corruption, symlinks, rollback, remove, code-only index'
