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
    *'version("graphifyy")'*) printf '0.9.88\n' ;;
  esac
  exit 0
fi
if [ "${1:-}" = -m ] && [ "${2:-}" = pip ] && [ "${3:-}" = download ]; then
  dest=''
  while [ "$#" -gt 0 ]; do
    [ "$1" != --dest ] || { shift; dest="$1"; }
    shift
  done
  mkdir -p "$dest"
  printf 'fixture wheel\n' > "$dest/graphifyy-0.9.88-py3-none-any.whl"
  exit 0
fi
if [ "${1:-}" = -m ] && [ "${2:-}" = venv ]; then
  dest="$3"
  mkdir -p "$dest/bin"
  cp "$0" "$dest/bin/python"
  cat > "$dest/bin/graphify" <<'GRAPHIFY'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = --version ]; then printf 'graphify 0.9.88\n'; exit 0; fi
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
if [ "${1:-}" = -m ] && [ "${2:-}" = pip ] && [ "${3:-}" = install ]; then exit 0; fi
if [ "${1:-}" = -m ] && [ "${2:-}" = pip ] && [ "${3:-}" = freeze ]; then
  printf 'graphifyy==0.9.88\nnetworkx==3.4.2\n'
  exit 0
fi
printf 'unexpected fake python invocation: %s\n' "$*" >&2
exit 9
PYTHON
chmod +x "$fakebin/python3"

cat > "$fakebin/sha256sum" <<'HASH'
#!/usr/bin/env bash
printf '04e5a44c0ff94554315e03d39d8eccfddb2850b77837ede23d75f0f63dc4e66d  %s\n' "$1"
HASH
chmod +x "$fakebin/sha256sum"

new_home() {
  local name="$1" home="$SANDBOX/$1"
  mkdir -p "$home"
  printf '%s\n' "$home"
}

run_tool() {
  local home="$1"
  shift
  HOME="$home" XDG_DATA_HOME="$home/data" XDG_STATE_HOME="$home/state" \
    PATH="$fakebin:/usr/bin:/bin" FAKE_GRAPHIFY_LOG="$home/graphify.log" \
    "$ROOT/scripts/tools.sh" graphify "$@"
}

tool_dir() { printf '%s/data/dev-agent-config/tools/graphify/0.9.88\n' "$1"; }

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
