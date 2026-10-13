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
    *urlopen*) [ "${FAKE_PYPI_FAIL:-0}" != 1 ] || { printf 'unexpected PyPI lookup\n' >&2; exit 77; }; printf '%s\tgraphifyy-%s-py3-none-any.whl\thttps://files.pythonhosted.org/packages/test/graphifyy-%s-py3-none-any.whl\t04e5a44c0ff94554315e03d39d8eccfddb2850b77837ede23d75f0f63dc4e66d\n' "${FAKE_LATEST_VERSION:-0.9.88}" "${FAKE_LATEST_VERSION:-0.9.88}" "${FAKE_LATEST_VERSION:-0.9.88}" ;;
    *'a=tuple'*) case "$3:$4" in 0.9.89:0.9.88|0.9.90:0.9.88|0.9.90:0.9.89) exit 0 ;; *) exit 1 ;; esac ;;
    *'version("graphifyy")'*) if [ -f "$(dirname "$0")/VERSION" ]; then cat "$(dirname "$0")/VERSION"; else printf '%s\n' "${FAKE_LATEST_VERSION:-0.9.88}"; fi ;;
    *json.load*) case "$(tr -d '[:space:]' < "$3")" in *'"nodes":['*'"links":['*) ;; *) exit 1 ;; esac ;;
    *sys.version_info*) printf '3.11.0\n' ;;
  esac
  exit 0
fi
if [ "${1:-}" = -m ] && [ "${2:-}" = http.server ]; then
  printf '%s\n' "$*" >> "${FAKE_GRAPHIFY_LOG:?}.server"
  if [ "${FAKE_SERVER_WAIT:-0}" = 1 ]; then
    while [ ! -e "${FAKE_SERVER_STOP:?}" ]; do sleep 0.02; done
  fi
  exit "${FAKE_SERVER_EXIT:-0}"
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
  printf 'Collecting graphifyy fixture dependency\n'
  dest=''
  while [ "$#" -gt 0 ]; do
    [ "$1" != --dest ] || { shift; dest="$1"; }
    case "$1" in https://files.pythonhosted.org/*) wheel_name="${1##*/}" ;; esac
    shift
  done
  mkdir -p "$dest"
  printf 'fixture wheel\n' > "$dest/${wheel_name:-graphifyy-${FAKE_LATEST_VERSION:-0.9.88}-py3-none-any.whl}"
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
printf '%s %s\n' "$(cat "$(dirname "$0")/VERSION")" "$*" >> "${FAKE_GRAPHIFY_LOG:?}.versions"
if [ "${1:-}" = extract ]; then
  [ "${3:-}" = --out ] && [ "${5:-}" = --code-only ] || { printf 'bad args: %s\n' "$*" >&2; exit 3; }
  for key in OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY GOOGLE_API_KEY MOONSHOT_API_KEY DEEPSEEK_API_KEY AWS_ACCESS_KEY_ID OLLAMA_BASE_URL; do
    eval '[ "${'"$key"'+x}" != x ]' || { printf 'credential leaked: %s\n' "$key" >&2; exit 4; }
  done
  [ "${GRAPHIFY_QUERY_LOG_DISABLE:-}" = 1 ]
  [ "${GRAPHIFY_OUT:-}" = "$4/graphify-out" ]
  [ "${FAKE_INDEX_FAIL:-0}" != 1 ] || { printf 'fixture extraction failed\n' >&2; exit 11; }
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
  [ "${FAKE_QUERY_FAIL:-0}" != 1 ] || { printf 'fixture query failed\n' >&2; exit 12; }
  [ "${GRAPHIFY_QUERY_LOG_DISABLE:-}" = 1 ] || exit 7
  [ -z "${OPENAI_API_KEY:-}${ANTHROPIC_API_KEY:-}${GEMINI_API_KEY:-}${GOOGLE_API_KEY:-}${AWS_ACCESS_KEY_ID:-}${OLLAMA_BASE_URL:-}" ] || exit 10
  printf '%s\n' "$*" >> "${FAKE_GRAPHIFY_LOG:?}"
  printf 'query fixture output\n'
elif [ "${1:-}" = export ] && [ "${2:-}" = html ]; then
  [ "${3:-}" = --graph ] || exit 8
  printf '%s\n' "$*" >> "${FAKE_GRAPHIFY_LOG:?}"
  printf '<html>fixture graph</html>\n' > "$GRAPHIFY_OUT/graph.html"
else
  printf 'unexpected fake graphify invocation: %s\n' "$*" >&2
  exit 2
fi
GRAPHIFY
  chmod +x "$dest/bin/graphify"
  exit 0
fi
if [ "${1:-}" = -m ] && [ "${2:-}" = pip ] && [ "${3:-}" = install ]; then
  [ "${FAKE_STAGE_FAIL:-0}" != 1 ] || { printf 'fixture wheel install failed\n' >&2; exit 8; }
  printf 'Installing collected packages: graphifyy\n'
  for arg in "$@"; do case "$arg" in *.whl) printf '%s\n' "$arg" | sed -n 's#.*graphifyy-\([0-9.]*\)-py3-none-any\.whl#\1#p' > "$(dirname "$0")/VERSION" ;; esac; done
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

run_tool_from() {
  local project_dir="$1" home="$2"
  shift 2
  (cd "$project_dir" && run_tool "$home" "$@")
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
if FAKE_STAGE_FAIL=1 run_tool "$home" install >"$home/install-failure.out" 2>&1; then echo 'Staging failure was accepted' >&2; exit 1; fi
grep -q 'Details: .*install-.*\.log' "$home/install-failure.out"
grep -q 'fixture wheel install failed' "$home/install-failure.out"
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

# Installation output stays concise unless verbose mode is explicitly requested.
home="$(new_home install-output)"
install_output="$(run_tool "$home" install)"
case "$install_output" in *'Collecting graphifyy'*) echo 'Routine pip output leaked by default' >&2; exit 1 ;; esac
case "$install_output" in *'INSTALLED Graphify 0.9.88'*'Install log:'*) ;; *) echo 'Install summary omitted version or log path' >&2; exit 1 ;; esac
install_log="$(printf '%s\n' "$install_output" | sed -n 's/^Install log: //p')"
grep -q 'Collecting graphifyy' "$install_log"
home="$(new_home install-verbose)"
verbose_output="$(run_tool "$home" install --verbose)"
case "$verbose_output" in *'Collecting graphifyy'*'Installing collected packages'*) ;; *) echo 'Verbose install omitted pip diagnostics' >&2; exit 1 ;; esac

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

# Index defaults to its current directory and always keeps code-only output outside it.
home="$(new_home index)"
run_tool "$home" install >/dev/null
project="$home/project"
output="$home/graphs/nest-test"
mkdir -p "$project"
printf 'export const value = 1;\n' > "$project/app.ts"
run_tool_from "$project" "$home" index >/dev/null
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
if FAKE_QUERY_FAIL=1 run_tool "$home" query --project "$project" failure > "$home/query-failure.out" 2>&1; then echo 'Graphify query failure was hidden' >&2; exit 1; fi
grep -q 'ERROR: Graphify query failed' "$home/query-failure.out"
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
serve_output="$(SSH_CONNECTION=fixture run_tool "$home" serve --project "$project" --port 8123)"
printf '%s\n' "$serve_output" | grep 'http://127.0.0.1:8123/graph.html' >/dev/null
printf '%s\n' "$serve_output" | grep 'forward port 8123' >/dev/null
grep -qFx -- "-m http.server 8123 --bind 127.0.0.1 --directory $indexed_root/graphify-out" "$home/graphify.log.server"
if run_tool "$home" serve --project "$project" --port 0 >/dev/null 2>&1; then echo 'Serve accepted invalid port' >&2; exit 1; fi
FAKE_UNAME=Linux DISPLAY=:fixture run_tool "$home" visualize --project "$project" --open >/dev/null
grep -q '^xdg-open ' "$home/graphify.log.browser"
browser_count="$(wc -l < "$home/graphify.log.browser" | tr -d ' ')"
FAKE_UNAME=Linux DISPLAY= WAYLAND_DISPLAY= run_tool "$home" visualize --project "$project" --open > "$home/headless-visualize.out"
grep -q 'No desktop display detected' "$home/headless-visualize.out"
[ "$browser_count" = "$(wc -l < "$home/graphify.log.browser" | tr -d ' ')" ]
[ "$extract_count" = "$(grep -c '^extract ' "$home/graphify.log")" ]

# The installed release, not tool.conf's older fresh-install fallback, drives
# every operation against an existing installation.
home_active="$(new_home active-version)"
FAKE_LATEST_VERSION=0.9.89 run_tool "$home_active" install >/dev/null
active_project="$home_active/project"
mkdir -p "$active_project"
FAKE_PYPI_FAIL=1 run_tool "$home_active" verify | grep 'Graphify 0.9.89: healthy' >/dev/null
FAKE_PYPI_FAIL=1 run_tool "$home_active" index --project "$active_project" >/dev/null
active_root="$(project_index_root "$active_project")"
FAKE_PYPI_FAIL=1 run_tool "$home_active" query --project "$active_project" 'active version?' >/dev/null
FAKE_PYPI_FAIL=1 run_tool "$home_active" report --project "$active_project" >/dev/null
FAKE_PYPI_FAIL=1 run_tool "$home_active" visualize --project "$active_project" >/dev/null
run_tool "$home_active" check-update | grep 'Current Graphify: 0.9.89' >/dev/null
grep -q '^0.9.89 extract ' "$home_active/graphify.log.versions"
grep -q '^0.9.89 query ' "$home_active/graphify.log.versions"
grep -q '^0.9.89 cluster-only ' "$home_active/graphify.log.versions"
grep -q '^0.9.89 export html ' "$home_active/graphify.log.versions"
active_entrypoint="$(tool_dir "$home_active" 0.9.89)/venv/bin/graphify"
sed '1c\
#!/missing/active-graphify-interpreter
' "$active_entrypoint" > "$home_active/broken-entrypoint"
chmod +x "$home_active/broken-entrypoint"
mv "$home_active/broken-entrypoint" "$active_entrypoint"
FAKE_PYPI_FAIL=1 run_tool "$home_active" repair >/dev/null
run_tool "$home_active" verify | grep 'Graphify 0.9.89: healthy' >/dev/null
FAKE_LATEST_VERSION=0.9.88 run_tool "$home_active" upgrade >"$home_active/no-downgrade.out" 2>&1
grep 'already current' "$home_active/no-downgrade.out" >/dev/null || { cat "$home_active/no-downgrade.out" >&2; exit 1; }
verify_active="$(run_tool "$home_active" verify)"
case "$verify_active" in *'Graphify 0.9.89: healthy'*) ;; *) printf '%s\n' "$verify_active" >&2; exit 1 ;; esac
FAKE_LATEST_VERSION=0.9.90 run_tool "$home_active" upgrade >/dev/null
run_tool "$home_active" verify | grep 'Graphify 0.9.90: healthy' >/dev/null
upgrade_backup="$(sed -n '1p' "$home_active/state/dev-agent-config/tools/graphify/last-backup")"
run_tool "$home_active" rollback "$upgrade_backup" >/dev/null
run_tool "$home_active" verify | grep 'Graphify 0.9.89: healthy' >/dev/null
FAKE_PYPI_FAIL=1 run_tool "$home_active" remove >/dev/null
remove_backup="$(sed -n '1p' "$home_active/state/dev-agent-config/tools/graphify/last-backup")"
run_tool "$home_active" rollback "$remove_backup" >/dev/null
run_tool "$home_active" verify | grep 'Graphify 0.9.89: healthy' >/dev/null

home_missing="$(new_home graph-operations-missing)"
run_tool "$home_missing" install >/dev/null
mkdir -p "$home_missing/project"
if run_tool "$home_missing" query --project "$home_missing/project" test >/dev/null 2>&1; then echo 'query accepted a missing graph' >&2; exit 1; fi
if run_tool "$home_missing" report --project "$home_missing/project" >/dev/null 2>&1; then echo 'report accepted a missing graph' >&2; exit 1; fi
if run_tool "$home_missing" visualize --project "$home_missing/project" >/dev/null 2>&1; then echo 'visualize accepted a missing graph' >&2; exit 1; fi

# Omitting --project consistently selects the command's current directory.
home_cwd="$(new_home current-directory-project)"
run_tool "$home_cwd" install >/dev/null
cwd_project="$home_cwd/workspace/project with spaces"
mkdir -p "$cwd_project"
run_tool_from "$cwd_project" "$home_cwd" index > "$home_cwd/index.out"
grep -q "using current directory: $(cd "$cwd_project" && pwd -P)" "$home_cwd/index.out"
run_tool_from "$cwd_project" "$home_cwd" query 'current directory query' >/dev/null
run_tool_from "$cwd_project" "$home_cwd" report >/dev/null
run_tool_from "$cwd_project" "$home_cwd" visualize >/dev/null
serve_cwd="$(SSH_CONNECTION=fixture run_tool_from "$cwd_project" "$home_cwd" serve)"
printf '%s\n' "$serve_cwd" | grep 'http://127.0.0.1:8080/graph.html' >/dev/null
run_tool_from "$cwd_project" "$home_cwd" clean --dry-run | grep 'WOULD_CLEAN' >/dev/null
run_tool_from "$cwd_project" "$home_cwd" clean >/dev/null
saved_home="$home"
home="$home_cwd"
cwd_graph="$(project_index_root "$cwd_project")/graphify-out"
home="$saved_home"
[ ! -e "$cwd_graph" ]
[ -x "$(tool_dir "$home_cwd")/venv/bin/graphify" ]

# An explicit project wins from another caller directory and symlinked project
# paths normalize to the same physical project mapping.
other_project="$home_cwd/other project"
mkdir -p "$other_project"
run_tool_from "$cwd_project" "$home_cwd" index --project "$other_project" > "$home_cwd/explicit-project.out"
grep -qF "extract $(cd "$other_project" && pwd -P) --out" "$home_cwd/graphify.log"
saved_home="$home"
home="$home_cwd"
other_graph="$(project_index_root "$other_project")/graphify-out/graph.json"
home="$saved_home"
[ -f "$other_graph" ]
project_link="$home_cwd/other-project-link"
ln -s "$other_project" "$project_link"
run_tool_from "$cwd_project" "$home_cwd" report --project "$project_link" >/dev/null
home="$home_cwd"
[ -f "$(project_index_root "$other_project")/graphify-out/GRAPH_REPORT.md" ]
home="$saved_home"
if run_tool_from "$cwd_project" "$home_cwd" query --project "$home_cwd/missing project" invalid > "$home_cwd/invalid-project.out" 2>&1; then
  echo 'Explicit invalid project fell back to caller directory' >&2; exit 1
fi
grep -q 'Project directory does not exist' "$home_cwd/invalid-project.out"
if run_tool_from "$cwd_project" "$home_cwd" clean --project '' --dry-run > "$home_cwd/empty-project.out" 2>&1; then
  echo 'Explicit empty project fell back to caller directory' >&2; exit 1
fi
grep -q 'Project path is empty' "$home_cwd/empty-project.out"

# One-command workflow installs only when missing, indexes/reuses safely, and
# keeps the old index when a changed-project rebuild fails.
home_run="$(new_home graphify-run)"
home="$home_run"
run_project="$home_run/project with spaces"
mkdir -p "$run_project"
printf 'const one = 1;\n' > "$run_project/app.ts"
dry_run="$(run_tool_from "$run_project" "$home_run" run --dry-run --no-serve)"
case "$dry_run" in *'Graphify: installation required'*'Plan: create a code-only graph'*'Plan: do not start a dashboard server'*) ;; *) printf '%s\n' "$dry_run" >&2; exit 1 ;; esac
[ ! -e "$(tool_dir "$home_run")" ]
run_output="$(run_tool_from "$run_project" "$home_run" run --no-serve)"
case "$run_output" in *'INSTALLED Graphify'*'INDEXED code-only graph:'*'VISUALIZATION:'*) ;; *) printf '%s\n' "$run_output" >&2; exit 1 ;; esac
run_index="$(project_index_root "$run_project")/graphify-out"
[ -s "$run_index/graph.json" ] && [ -s "$run_index/GRAPH_REPORT.md" ] && [ -s "$run_index/graph.html" ]
run_extracts="$(grep -c ' extract ' "$home_run/graphify.log.versions")"
run_reuse="$(run_tool_from "$run_project" "$home_run" run --no-serve)"
case "$run_reuse" in *'UNCHANGED Graphify index:'*'REPORT: reused'*'VISUALIZATION: reused'*) ;; *) printf '%s\n' "$run_reuse" >&2; exit 1 ;; esac
[ "$run_extracts" = "$(grep -c ' extract ' "$home_run/graphify.log.versions")" ]
rm "$run_index/GRAPH_REPORT.md"
run_missing_report="$(run_tool_from "$run_project" "$home_run" run --no-serve)"
case "$run_missing_report" in *'UNCHANGED Graphify index:'*'REPORT:'*'VISUALIZATION: reused'*) ;; *) printf '%s\n' "$run_missing_report" >&2; exit 1 ;; esac
[ -s "$run_index/GRAPH_REPORT.md" ]
[ "$run_extracts" = "$(grep -c ' extract ' "$home_run/graphify.log.versions")" ]
explicit_run_project="$home_run/explicit project"
mkdir -p "$explicit_run_project"
run_tool_from "$run_project" "$home_run" run --no-serve --project "$explicit_run_project" >/dev/null
[ -s "$(project_index_root "$explicit_run_project")/graphify-out/graph.json" ]
printf 'const one = 2;\n' > "$run_project/app.ts"
if FAKE_INDEX_FAIL=1 run_tool_from "$run_project" "$home_run" run --no-serve > "$home_run/run-failed.out" 2>&1; then
  echo 'Failed run rebuild was accepted' >&2; exit 1
fi
grep -q 'Restored previous Graphify index' "$home_run/run-failed.out"
grep -q '"id":"fixture"' "$run_index/graph.json"
if FAKE_INVALID_GRAPH=1 run_tool_from "$run_project" "$home_run" run --no-serve --force > "$home_run/invalid-rebuild.out" 2>&1; then
  echo 'Run accepted an invalid rebuilt graph' >&2; exit 1
fi
grep -q 'Restored previous Graphify index' "$home_run/invalid-rebuild.out"
grep -q '"id":"fixture"' "$run_index/graph.json"
run_tool_from "$run_project" "$home_run" run --no-serve --force --output "$home_run/custom output" >/dev/null
[ -s "$home_run/custom output/graphify-out/graph.json" ]

home_run_dry="$(new_home graphify-run-dry)"
home="$home_run_dry"
run_dry_project="$home_run_dry/project"
mkdir -p "$run_dry_project"
run_tool_from "$run_dry_project" "$home_run_dry" run --dry-run --no-serve >/dev/null
[ ! -e "$(tool_dir "$home_run_dry")" ]
[ ! -e "$(project_index_root "$run_dry_project")" ]

home_run_prerequisite="$(new_home graphify-run-prerequisite)"
home="$home_run_prerequisite"
mkdir -p "$home_run_prerequisite/project"
if FAKE_VENV_MODE=no-venv run_tool_from "$home_run_prerequisite/project" "$home_run_prerequisite" run --dry-run --no-serve > "$home_run_prerequisite/preflight.out" 2>&1; then
  echo 'Run ignored missing Python venv support' >&2; exit 1
fi
grep -q 'python3-venv\|includes venv' "$home_run_prerequisite/preflight.out"
[ ! -e "$(tool_dir "$home_run_prerequisite")" ]

home_run_server="$(new_home graphify-run-server)"
home="$home_run_server"
server_project="$home_run_server/project"
mkdir -p "$server_project"
if FAKE_SERVER_EXIT=1 run_tool_from "$server_project" "$home_run_server" run --port 9177 > "$home_run_server/server-failed.out" 2>&1; then
  echo 'Run hid a dashboard port conflict' >&2; exit 1
fi
grep -q 'Dashboard server exited with status' "$home_run_server/server-failed.out"
home="$saved_home"

# The dashboard lock prevents clean while an active server can serve the files.
run_tool_from "$cwd_project" "$home_cwd" index >/dev/null
run_tool_from "$cwd_project" "$home_cwd" visualize >/dev/null
workspace_link="$home_cwd/workspace-link"
ln -s "$cwd_project" "$workspace_link"
run_tool_from "$workspace_link" "$home_cwd" query 'symlinked current directory' >/dev/null
if command -v zsh >/dev/null 2>&1; then
  (cd "$workspace_link" && HOME="$home_cwd" XDG_DATA_HOME="$home_cwd/data" \
    XDG_STATE_HOME="$home_cwd/state" PATH="$fakebin:/usr/bin:/bin" \
    FAKE_GRAPHIFY_LOG="$home_cwd/graphify.log" TMPDIR="$home_cwd/tmp" \
    zsh -c 'cd "$1" && "$2" graphify query "$3"' zsh \
      "$workspace_link" "$ROOT/dev-agent-config" 'zsh current directory') >/dev/null
fi
active_final="$cwd_graph"
operation_lock="$(dirname "$active_final")/.dev-agent-config-operation"
stop_server="$home_cwd/stop-server"
FAKE_SERVER_WAIT=1 FAKE_SERVER_STOP="$stop_server" SSH_CONNECTION=fixture \
  run_tool_from "$cwd_project" "$home_cwd" serve > "$home_cwd/active-server.out" &
server_pid=$!
tries=0
while [ ! -f "$operation_lock/owner" ] && [ "$tries" -lt 200 ]; do
  sleep 0.02
  tries=$((tries + 1))
done
[ -f "$operation_lock/owner" ] || { echo 'Server did not acquire its operation lock' >&2; exit 1; }
if run_tool_from "$cwd_project" "$home_cwd" clean --dry-run > "$home_cwd/active-clean.out" 2>&1; then
  echo 'Clean was allowed while the dashboard server was active' >&2; exit 1
fi
grep -q 'stop it with Ctrl+C before cleaning' "$home_cwd/active-clean.out"
touch "$stop_server"
wait "$server_pid"
[ ! -e "$operation_lock" ]
run_tool_from "$cwd_project" "$home_cwd" clean >/dev/null

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

# Project-scoped clean removes only the recognized generated subtree.
home_clean="$(new_home clean-index)"
run_tool "$home_clean" install >/dev/null
clean_project="$home_clean/project"
clean_output="$home_clean/custom-graphs/nest"
other_clean_project="$home_clean/other-project"
mkdir -p "$clean_project"
mkdir -p "$other_clean_project"
printf 'keep source\n' > "$clean_project/app.ts"
run_tool "$home_clean" index --project "$clean_project" --output "$clean_output" >/dev/null
run_tool "$home_clean" index --project "$other_clean_project" >/dev/null
saved_home="$home"
home="$home_clean"
other_clean_graph="$(project_index_root "$other_clean_project")/graphify-out/graph.json"
home="$saved_home"
realistic="$clean_output/graphify-out"
mkdir -p "$realistic/cache/ast/v0.9.89-s8-gfixture" \
  "$realistic/cache/semantic/p0123456789ab" "$realistic/cache/semantic-deep"
printf '{"cached":true}\n' > "$realistic/cache/$(printf 'e%.0s' {1..64}).json"
printf '{"nodes":[],"links":[]}\n' > "$realistic/cache/ast/v0.9.89-s8-gfixture/$(printf 'a%.0s' {1..64}).json"
printf '{"nodes":[]}\n' > "$realistic/cache/semantic/p0123456789ab/$(printf 'b%.0s' {1..64}).json"
printf 'partial\n' > "$realistic/cache/semantic-deep/$(printf 'c%.0s' {1..64}).json.tmp"
printf '{}\n' > "$realistic/cache/stat-index.json"
printf '{"version":"0.9.89"}\n' > "$realistic/manifest.json"
printf '{"cost":0}\n' > "$realistic/cost.json"
printf '/tmp/project\n' > "$realistic/.graphify_root"
printf '{}\n' > "$realistic/.graphify_extract.json"
printf 'chunk\n' > "$realistic/.graphify_chunk_2_files.txt"
printf '<html>call flow</html>\n' > "$realistic/sample-project-callflow.html"
run_tool "$home_clean" visualize --project "$clean_project" --output "$clean_output" >/dev/null
clean_dry="$(run_tool "$home_clean" clean --project "$clean_project" --output "$clean_output" --dry-run)"
case "$clean_dry" in *"Project: $(cd "$clean_project" && pwd -P)"*"Index target: $realistic"*'WOULD_CLEAN'*) ;; *) echo 'Clean dry-run omitted resolved project or target' >&2; exit 1 ;; esac
[ -f "$clean_output/graphify-out/graph.json" ]
run_tool "$home_clean" clean --project "$clean_project" --output "$clean_output" >/dev/null
[ ! -e "$clean_output/graphify-out" ]
[ -f "$other_clean_graph" ]
[ -f "$(tool_dir "$home_clean")/venv/bin/graphify" ]
grep -qFx 'keep source' "$clean_project/app.ts"
run_tool "$home_clean" clean --project "$clean_project" --output "$clean_output" | grep 'no generated Graphify index' >/dev/null

# A partial cleanup interrupted after removing generated files is resumable.
run_tool "$home_clean" index --project "$clean_project" --output "$clean_output" >/dev/null
partial="$clean_output/graphify-out"
rm -f "$partial/graph.html" "$partial/GRAPH_REPORT.md"
run_tool "$home_clean" clean --project "$clean_project" --output "$clean_output" >/dev/null
[ ! -e "$partial" ]
run_tool "$home_clean" clean --project "$clean_project" --output "$clean_output" >/dev/null
mkdir -p "$home_clean/unrelated/graphify-out"
printf '{}\n' > "$home_clean/unrelated/graphify-out/graph.json"
if run_tool "$home_clean" clean --project "$clean_project" --output "$home_clean/unrelated" >/dev/null 2>&1; then echo 'Clean accepted an unowned custom index' >&2; exit 1; fi
run_tool "$home_clean" index --project "$clean_project" >/dev/null
saved_home="$home"
home="$home_clean"
clean_default="$(project_index_root "$clean_project")/graphify-out"
home="$saved_home"
mkdir -p "$clean_default/cache/ast/v0.9.89-s8-gfixture"
printf 'foreign cache content\n' > "$clean_default/cache/ast/v0.9.89-s8-gfixture/unrecognized.txt"
if run_tool "$home_clean" clean --project "$clean_project" >/dev/null 2>&1; then echo 'Clean accepted an unexpected nested cache file' >&2; exit 1; fi
[ -f "$clean_default/graph.json" ]
rm "$clean_default/cache/ast/v0.9.89-s8-gfixture/unrecognized.txt"
printf 'foreign\n' > "$home_clean/foreign-file"
ln -s "$home_clean/foreign-file" "$clean_default/cache/ast/v0.9.89-s8-gfixture/$(printf 'd%.0s' {1..64}).json"
if run_tool "$home_clean" clean --project "$clean_project" >/dev/null 2>&1; then echo 'Clean accepted a nested cache symlink' >&2; exit 1; fi
[ -f "$clean_default/graph.json" ]
rm "$clean_default/cache/ast/v0.9.89-s8-gfixture/$(printf 'd%.0s' {1..64}).json"
rm -r "$clean_default/cache"
ln -s "$home_clean/foreign-file" "$clean_default/graph.html"
if run_tool "$home_clean" clean --project "$clean_project" >/dev/null 2>&1; then echo 'Clean accepted a symlink conflict' >&2; exit 1; fi
grep -qFx foreign "$home_clean/foreign-file"
rm "$clean_default/graph.html"
printf 'project=/some/other/project\n' > "$clean_default/.dev-agent-config-index"
if run_tool "$home_clean" clean --project "$clean_project" >/dev/null 2>&1; then echo 'Clean accepted changed ownership metadata' >&2; exit 1; fi
[ -f "$clean_default/graph.json" ]

echo 'PASS tools: install, repeat, corruption, symlinks, rollback, remove, code-only index'
