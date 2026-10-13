#!/usr/bin/env bash
set -euo pipefail

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
  cat > "$dest/bin/graphify" <<'GRAPHIFY'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = --version ]; then printf 'graphify %s\n' "$(cat "$(dirname "$0")/VERSION")"; exit 0; fi
[ "${1:-}" = extract ] || exit 2
[ "${3:-}" = --out ] && [ "${5:-}" = --code-only ] || { printf 'bad args: %s\n' "$*" >&2; exit 3; }
for key in OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY GOOGLE_API_KEY MOONSHOT_API_KEY DEEPSEEK_API_KEY AWS_ACCESS_KEY_ID OLLAMA_BASE_URL; do
  eval '[ "${'"$key"'+x}" != x ]' || { printf 'credential leaked: %s\n' "$key" >&2; exit 4; }
done
[ "${GRAPHIFY_QUERY_LOG_DISABLE:-}" = 1 ]
[ "${GRAPHIFY_OUT:-}" = graphify-out ]
mkdir -p "$4/graphify-out"
printf '{}\n' > "$4/graphify-out/graph.json"
printf '# report\n' > "$4/graphify-out/GRAPH_REPORT.md"
printf '<html></html>\n' > "$4/graphify-out/graph.html"
printf '%s\n' "$*" > "${FAKE_GRAPHIFY_LOG:?}"
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

# Corruption is reported and is never silently replaced.
rm "$(tool_dir "$home")/venv/bin/graphify"
if run_tool "$home" verify >/dev/null 2>&1; then echo 'Corrupted tool verified successfully' >&2; exit 1; fi
if run_tool "$home" install >/dev/null 2>&1; then echo 'Corrupted tool was overwritten' >&2; exit 1; fi
run_tool "$home" remove >/dev/null
[ ! -e "$(tool_dir "$home")" ]

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
[ -f "$output/graphify-out/graph.html" ]
[ ! -e "$project/graphify-out" ]
grep -qFx 'export const value = 1;' "$project/app.ts"

echo 'PASS tools: install, repeat, corruption, symlinks, rollback, remove, code-only index'
