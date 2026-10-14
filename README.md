# dev-agent-config

A small, portable configuration manager for shared coding-agent instructions and
Agent Skills on macOS and Linux. `AGENTS.md` is the canonical instruction source.

## Install

Always preview first:

```bash
./scripts/install.sh --dry-run
./scripts/install.sh --mode=merge
```

`merge` is the default. It replaces only this project's marked instruction block,
preserves all other instructions, and preserves a conflicting same-name skill.

To replace agent instruction files and the Ponytail skill:

```bash
./scripts/install.sh --mode=replace --dry-run
./scripts/install.sh --mode=replace
```

Replace mode affects only documented instruction files and the `ponytail` skill
entry. It does not edit credentials, authentication, model choices, MCP settings,
session history, JSON/TOML settings, or project-level instructions.

Only agents whose configuration directory already exists are configured. The
shared `~/AGENTS.md` and `~/.agents/skills/ponytail` entries are always installed.
Unexpected instruction symlinks and symlinked parent directories are refused.

## Command-line interface

From a checkout, use the executable at the repository root:

```bash
./dev-agent-config --help
./dev-agent-config verify
./dev-agent-config graphify --help
./dev-agent-config cbm --help
```

To make `dev-agent-config` available without the checkout's full path, create a
user-local symlink (no sudo and no shell-profile edits):

```bash
./dev-agent-config cli install --dry-run
./dev-agent-config cli install
```

The link defaults to `~/.local/bin/dev-agent-config`. If that directory is not
already in `PATH`, add `export PATH="$HOME/.local/bin:$PATH"` to your shell
profile yourself. Remove only this checkout's link with
`./dev-agent-config cli uninstall`. The command resolves the checkout through
the link, so the repository must stay in its current location.

## Compatibility

| Agent | Global instructions | Portable skill location | Status |
| --- | --- | --- | --- |
| Codex | `~/.codex/AGENTS.md` | `~/.agents/skills/ponytail` | Supported |
| Claude Code | `~/.claude/CLAUDE.md` | `~/.claude/skills/ponytail` | Supported |
| Gemini CLI | `~/.gemini/GEMINI.md` | `~/.gemini/skills/ponytail` | Supported |
| OpenCode | `~/.config/opencode/AGENTS.md` | `~/.config/opencode/skills/ponytail` | Supported |
| Cursor, Cline, Antigravity | — | — | Not implemented in this prototype |

Project instruction files are never changed. Agent precedence remains native:
more specific project instructions can supplement or override these global defaults.

The conditional shared code-intelligence guidance has one canonical source at
`instructions/code-intelligence.md`. Installation links it to
`~/.agents/instructions/code-intelligence.md`, and the shared `AGENTS.md` asks
agents to read that stable path only when structural code exploration is useful.
The same reference is delivered through each supported agent's existing global
instruction mechanism; it is not copied into agent-specific files or project
repositories. A Markdown reference is not treated as automatic loading: the
instruction explicitly tells the agent to open the shared file when relevant.
Project-specific `AGENTS.md` precedence remains unchanged; project extensions
are opt-in and are never created by this installer.

## Backups and rollback

Every changing install creates a timestamped backup and TSV manifest under:

```text
~/.agents/dev-agent-config/backups/
```

The installer prints its exact rollback command. Restore the latest transaction or
a selected transaction with:

```bash
./scripts/rollback.sh --dry-run
./scripts/rollback.sh
./scripts/rollback.sh ~/.agents/dev-agent-config/backups/TIMESTAMP-PID
```

Rollback restores original files, directories, and symbolic links, or removes paths
that did not exist before the transaction. Keep the repository at the same location
while installed because skill links point into it.

## Verify and uninstall

```bash
./scripts/verify.sh
./scripts/verify.sh --json       # machine-readable discovery and health report
./scripts/uninstall.sh            # preview
./scripts/uninstall.sh --apply
```

Verification reports the operating system, CLI installation and safe `--version`
result, VS Code extension discovery, configuration presence, instruction and skill
health, and unsupported adapters. CLI, VS Code extension, and configuration presence
are independent. When a VS Code CLI is available, verification uses its read-only
extension list; known extension directories are a presence-only fallback and never
proof that an extension is active. The fallback covers local VS Code, Insiders,
VSCodium, Flatpak/XDG data, VS Code Server and Server Insiders used by Remote SSH,
WSL, and Dev Containers, plus an explicitly configured `VSCODE_AGENT_FOLDER`.
Symlinked, invalid, and unreadable extension roots are ignored. Filesystem
verification does not prove that an agent activated Ponytail, so runtime activation
remains `unverified`.

## Ponytail provenance

Ponytail is a reviewed local adaptation, version `1.0.0-dev-agent-config`, of the
MIT-licensed [Ponytail project](https://github.com/dietrichgebert/ponytail). Full
provenance is recorded in `skills/ponytail/SOURCE.md`. Nothing is downloaded or
executed during installation.

## Optional tools: Graphify

Graphify is separate from instructions and skills. Managing it never runs
`graphify install`, edits `AGENTS.md`, registers hooks or MCP, or starts a service.
Preview and install the latest stable compatible release in a private virtual
environment:

```bash
./scripts/tools.sh graphify install --dry-run
./scripts/tools.sh graphify install
./scripts/tools.sh graphify verify
```

Add `--verbose` to a fresh `install` command to stream pip's download and
installation details.

Fresh installation resolves the latest non-prerelease release and universal wheel
from the authoritative PyPI JSON API. If metadata lookup is unavailable, it falls
back safely to the retained `graphifyy==0.9.88` pin under
`${XDG_DATA_HOME:-$HOME/.local/share}/dev-agent-config/tools/graphify/VERSION`.
It downloads the selected official wheel and verifies its PyPI SHA-256 before
installation. The retained 0.9.88 wheel SHA-256 is
`04e5a44c0ff94554315e03d39d8eccfddb2850b77837ede23d75f0f63dc4e66d`
and remains the trusted fallback. Package source and license metadata live in
`tools/graphify/tool.conf`.

Installation preflight requires Python 3.10+ and tests `venv` before any download
or target change. System pip is not required: the new environment's pip is used,
and `ensurepip` is attempted inside that environment when necessary. If the OS
Python lacks venv/ensurepip, the manager detects common macOS/Linux package
managers and prints an appropriate prerequisite command. It never runs `sudo`,
`apt`, `dnf`, `apk`, `pacman`, or Homebrew itself.

The environment's resolved versions are recorded in `dependencies.txt` after
installation. The Graphify wheel is exactly pinned and hash-verified, but its
transitive dependencies are resolved from Graphify's declared constraints and
are not fully hash-locked. Review `dependencies.txt` when reproducibility or
supply-chain policy requires a complete dependency lock.

Routine install and verify operations never upgrade a healthy installation.
Local operations use the version in validated manager metadata and do not
contact PyPI. A healthy install is unchanged by routine install. Successful
install output is concise; failures point to a retained log under the Graphify
manager state directory, and `--verbose` streams pip details.
Update checking is read-only, and upgrades must be explicit:

```bash
./scripts/tools.sh graphify check-update
./scripts/tools.sh graphify upgrade --dry-run
./scripts/tools.sh graphify upgrade
```

The manager reports current and latest stable versions, rejects prereleases and
yanked/unsupported wheel artifacts, verifies the selected wheel, and records its
release URL, digest, and resolved dependencies. A new release is staged and
verified before it becomes current. Failed upgrades leave the working version
selected, while successful upgrades can be rolled back with the printed command.

The verified wheel and download helper use a temporary staging directory, but the
Graphify virtual environment is created directly at its permanent versioned path.
Python console scripts embed the environment's absolute interpreter path in their
shebang, so verification checks that the installed `graphify` interpreter exists.
For an older install with a stale staging-path shebang, verify and explicitly
repair it with:

```bash
./scripts/tools.sh graphify verify
./scripts/tools.sh graphify repair --dry-run
./scripts/tools.sh graphify repair
./scripts/tools.sh graphify verify
```

Repair is limited to a directory with valid manager ownership metadata. It backs
up that exact version before rebuilding it; the printed rollback command can
restore the prior directory. Unexpected files and symlinks are not overwritten.

Indexing is explicit and code-only:

```bash
./scripts/tools.sh graphify index --project /absolute/path/to/project --dry-run
./scripts/tools.sh graphify index --project /absolute/path/to/project
./scripts/tools.sh graphify index \
  --project /absolute/path/to/project \
  --output /absolute/path/to/output-root
```

Graphify interprets `--out OUTPUT_ROOT` as a parent and writes the graph
to `OUTPUT_ROOT/graphify-out/`. The manager treats extraction as successful when
`graph.json` contains node-link `nodes` and `links` arrays. If extraction does not
create `GRAPH_REPORT.md`, it separately attempts `cluster-only --no-label --no-viz`
to generate a report without AI labeling or visualization; report failure is
reported as a warning and does not invalidate the graph. The default output root
is an XDG data path derived from the canonical project path and is outside the
source tree. Outputs inside the selected project are refused. Project paths
(including a symlinked project directory) are resolved to their physical
directory before mapping; this keeps the same project associated with the same
isolated index.
For rollback and symlink safety, a custom output root must remain beneath `HOME`,
`XDG_DATA_HOME`, or `XDG_STATE_HOME`.

Every run forces `graphify extract PROJECT --out OUTPUT_ROOT --code-only`, removes
known AI-provider credentials from the child environment, disables query logging
and cloud tips, and does not enable document/media extraction. It does not scan
projects automatically. The selected project's canonical physical directory is
used so symlink aliases resolve to one project index.

Project operations use the same default project-specific location, so there is no
need to locate `graph.json` yourself. `--project` is optional; from inside a
repository, the commands below use that current working directory:

```bash
cd ~/retail-pos-api
dev-agent-config graphify index
dev-agent-config graphify query "CreateUserHandler dependencies" --budget 1200
dev-agent-config graphify report
dev-agent-config graphify visualize
dev-agent-config graphify serve --port 8080
dev-agent-config graphify clean --dry-run
```

An explicit project always takes precedence, including when the CLI is invoked
from another directory:

```bash
./scripts/tools.sh graphify query --project /path/to/project "where is auth configured?" --budget 1200
./scripts/tools.sh graphify report --project /path/to/project
./scripts/tools.sh graphify visualize --project /path/to/project
./scripts/tools.sh graphify visualize --project /path/to/project --open
./scripts/tools.sh graphify serve --project /path/to/project --port 8080
./scripts/tools.sh graphify clean --project /path/to/project --dry-run
./scripts/tools.sh graphify clean --project /path/to/project
```

For a graph created with a custom `index --output /path/to/output-root`, pass that
same output root with `--output` to `query`, `report`, `visualize`, `serve`, or
`clean`.

For `index`, `query`, `report`, `visualize`, `serve`, `clean`, and `run`, the calling
shell's current working directory is used when `--project` is omitted. The CLI
does not switch to the dev-agent-config installation directory. Paths containing
spaces and symlinked project directories are normalized before lookup. An
explicit invalid project path is an error and never falls back to the caller's
directory.

These commands require a prior successful index and never re-index. Query uses
Graphify's native traversal against the existing graph; report runs native
`cluster-only --no-label --no-viz`; visualization uses native `export html` and
does not recluster or modify source files. Query logging is disabled and known
provider credentials are removed from each Graphify process. `--open` is opt-in;
headless Linux and SSH/VS Code Remote sessions print the HTML path without trying
to launch a remote browser. In VS Code Remote SSH, open the printed absolute path
from the remote workspace's File > Open File dialog (or the Remote Explorer); the
HTML is stored under the remote user's XDG data directory, not inside the source
repository. Supply `--output` when the graph was indexed to a custom output root.

`serve` requires an existing graph and generated `graph.html`; it never indexes
or generates HTML automatically. It serves that directory in the foreground on
`127.0.0.1` (default port 8080), with Python's standard-library HTTP server, and
stops with Ctrl+C. For Remote SSH, forward the printed port from VS Code's Ports
panel and open `http://localhost:8080/graph.html` on your local Mac. No public
interface or background service is started.

For the complete local workflow, run this from any project directory:

```bash
cd ~/retail-pos-api
dev-agent-config graphify run
```

`run` reuses a healthy managed Graphify installation (installing the latest
verified stable release only when missing), indexes code-only when the graph is
missing or stale, generates a local architecture report and native HTML, then
serves it on `127.0.0.1:8080` in the foreground. Use `--project PATH` to select
another project, `--output PATH` for an index created with a custom output root,
`--port 9090` to select a port, `--no-serve` to stop after generating artifacts,
`--force` to rebuild, or `--dry-run` to preview the plan. Dry-run does not install,
index, generate files, or start a server. It may perform the installer's
temporary prerequisite probe when Graphify is absent; the probe is cleaned up.
The manager does not repair a corrupted installation automatically; run the
explicit `graphify repair` command after reviewing its dry-run.

For Git projects, unchanged detection uses the checked-out commit plus tracked
and untracked Git status; for non-Git folders it uses file-content checksums.
The non-Git check skips common dependency/build directories (`node_modules`,
virtual environments, `build`, and `dist`), so changes limited to those ignored
trees do not trigger a rebuild. The first `run` against an existing index with
no saved run fingerprint rebuilds it once to establish a baseline. Failed
rebuilds preserve the prior manager-owned graph and retain failed output for
inspection. Successful run fingerprints are stored outside the project beneath
`XDG_STATE_HOME` (or `~/.local/state`). No project app, scripts, tests, hooks,
MCP servers, or cloud/AI processing are started.

`clean` removes only recognized Graphify-generated files from the selected
project's `graphify-out` tree (or the explicitly supplied custom output's
generated index). This includes the standard graph/report/dashboard files,
Graphify's named `*-callflow.html` visualization, known manifest/cost and
`.graphify_*` metadata, and hash-named cache files in Graphify's known cache
namespaces. It validates the complete tree before
deletion; symlinks, unknown files/directories, and changed ownership metadata
make the operation fail without starting cleanup. Cleanup removes files
individually rather than recursively deleting arbitrary content, and can resume
if interrupted while the manager ownership marker remains. Dry-run prints the
resolved project and exact index target. If a dashboard server is active for
that index, clean refuses and asks you to stop it with Ctrl+C. Clean does not
remove Graphify itself; `remove` does not clean indexes.

Removal is limited to an installation carrying unchanged manager ownership
metadata:

```bash
./scripts/tools.sh graphify remove --dry-run
./scripts/tools.sh graphify remove
./scripts/tools.sh graphify rollback --dry-run
./scripts/tools.sh graphify rollback
```

Tool backups are stored under
`${XDG_STATE_HOME:-$HOME/.local/state}/dev-agent-config/tools/graphify/backups`.
Rollback refuses mismatched manifests, changed install ownership, symlinked paths,
or an occupied restore destination. Tool rollback is intentionally separate from
the instruction installer's rollback.

On Debian and Ubuntu, the distribution's `python3-venv` package may be needed.
The dry run performs the same preflight and reports whether installation can
proceed; if not, it prints the suggested command for the user to review and run.

## Simple benchmark procedure

Prepare three isolated copies of a disposable test repository:

```bash
./scripts/benchmark.sh /path/to/test-repository /tmp/agent-benchmark
```

The command creates `default`, `rules`, and `rules-ponytail` variants with separate
HOME and workspace directories. It never copies credentials. For a fair comparison:

1. Use the same agent release, exact model version, prompt, permissions, repository
   snapshot, and test command in every variant.
2. Explicitly request Ponytail in the `rules-ponytail` run so activation is observable.
3. Record elapsed duration, final diff, and test result.
4. Record tokens, cost, and tool calls only when the agent exposes them; otherwise
   mark those fields unavailable.
5. Repeat runs to reduce one-off model variation, and never use a production project.

The helper prepares environments only. It deliberately does not launch agents,
authenticate them, execute paid requests, or claim unsupported telemetry.

## Optional Codebase Memory MCP

CBM remains optional and independent of Graphify. Binary files installed by this
manager live under
`${XDG_DATA_HOME:-$HOME/.local/share}/dev-agent-config/tools/codebase-memory-mcp/versions/`;
the active version is exposed through `~/.local/bin/codebase-memory-mcp`.
Fresh installation is pinned to the v0.11.0 release in
`tools/codebase-memory-mcp/tool.conf`. Each install downloads the official
platform archive (macOS canonical assets; Linux portable assets) and its release
`checksums.txt` over HTTPS, verifies SHA-256, streams only the exact executable
member without extracting arbitrary archive paths, checks its version in staging
and at the final destination, then activates it. Installation shows live archive
download progress and names each verification/activation stage. The selected
archive hash and platform are recorded in local manager metadata. New
Codex/OpenCode integrations use the stable manager executable link so explicit
upgrades continue using the active version. `curl` or `wget`, `tar`, a SHA-256 utility
(`sha256sum` or macOS `shasum`), and Python 3 for JSON/OpenCode and project
mapping features are used; no privileged package manager is called.

```bash
dev-agent-config tools codebase-memory-mcp status
dev-agent-config tools codebase-memory-mcp verify
dev-agent-config tools codebase-memory-mcp install --dry-run
dev-agent-config tools codebase-memory-mcp install
dev-agent-config tools codebase-memory-mcp check-update
dev-agent-config tools codebase-memory-mcp upgrade --dry-run
dev-agent-config tools codebase-memory-mcp upgrade
dev-agent-config tools codebase-memory-mcp rollback --dry-run
dev-agent-config tools codebase-memory-mcp rollback
dev-agent-config tools codebase-memory-mcp remove --dry-run
dev-agent-config tools codebase-memory-mcp remove
```

Routine `install` keeps a healthy active manager-owned version; it never
downgrades or checks for updates. Only `check-update` and explicit `upgrade`
query GitHub for the latest stable release. Previous manager-owned versions are
retained for rollback. Removal affects only versions with intact ownership
metadata and matching binary hashes, plus this manager's executable symlink.
It preserves external binaries, CBM caches, indexes, MCP configuration, and
dashboard settings. An external binary is never overwritten or removed.
`adopt` only records an existing executable as external and does not transfer
ownership; use it to make the existing installation available to the adapter:

```bash
dev-agent-config tools codebase-memory-mcp adopt --dry-run
dev-agent-config tools codebase-memory-mcp adopt
```

### One-command project bootstrap

From any Git repository, bootstrap its CBM setup with:

```bash
cd /path/to/your-git-project
dev-agent-config cbm run --dry-run
dev-agent-config cbm run
```

The run command verifies an existing binary (including an external one), or
installs the verified pinned release if no binary exists. It merges the global
shared instructions without touching the project's `AGENTS.md`; configures MCP
only for detected Codex/OpenCode installations, preserving any external CBM
entry; indexes only when the project is missing; and refreshes only when CBM
reports a stale state or `--refresh` is explicitly passed. Repeated runs do not
reinstall or re-index a healthy project. `--agent codex` or `--agent opencode`
limits MCP setup to that available agent; unsupported/missing agents are never
configured. Use `--no-mcp` or `--no-dashboard` to skip either action, and
`--port 8080` to choose a dashboard port.

```bash
dev-agent-config cbm run --dry-run --no-mcp --no-dashboard
dev-agent-config cbm run --agent codex --refresh
dev-agent-config cbm run --no-dashboard
```

Dry-run plans installation and global configuration changes but does not
download files, call CBM project/status commands, alter indexes, or start a
dashboard. It therefore reports index state as unchecked. A real run reports
watcher settings separately from CBM's project registration strategy; neither
is proof that future file changes are detected and reindexed. An occupied port
is never taken over: use `--no-dashboard`, choose another port, or inspect the
existing listener. Incompatible CBM runtime/cache conflicts are left to CBM's
admission checks; the manager does not stop or kill daemons and directs you to
`codebase-memory-mcp daemon status` for diagnosis.

Codex MCP management respects `CODEX_HOME` (default `~/.codex`). When the
Codex CLI is present, the manager uses its documented MCP commands; without the
CLI it can add a marked TOML block so the Codex VS Code extension can use the
same config. OpenCode uses its global JSON config (or `OPENCODE_CONFIG`).
Both adapters back up the config before writing, preserve unrelated settings,
and report pre-existing CBM entries as externally managed. Disable removes
only an unchanged, manager-owned entry. OpenCode JSONC/commented configs are
left untouched because this small prototype does not parse JSONC.

```bash
dev-agent-config tools codebase-memory-mcp mcp status codex
dev-agent-config tools codebase-memory-mcp mcp enable codex --dry-run
dev-agent-config tools codebase-memory-mcp mcp enable codex
dev-agent-config tools codebase-memory-mcp mcp disable codex --dry-run
dev-agent-config tools codebase-memory-mcp mcp disable codex
dev-agent-config tools codebase-memory-mcp mcp status opencode
dev-agent-config tools codebase-memory-mcp mcp enable opencode --dry-run
dev-agent-config tools codebase-memory-mcp mcp enable opencode
dev-agent-config tools codebase-memory-mcp mcp disable opencode --dry-run
dev-agent-config tools codebase-memory-mcp mcp disable opencode
```

Project indexes remain in CBM's own cache, outside the source tree. The manager
records project mappings only when it can confirm that the index did not exist
before its explicit `index` command and CBM subsequently reports the exact
canonical repository path. `clean` refuses external/unmapped projects, changed
names, unparseable project lists, symlinks, and active dashboards for that
project; it calls CBM's documented `delete_project` command and verifies the
result. Project commands default to the current directory only when it is a Git
repository; otherwise pass `--project PATH`. Explicit paths always win.

```bash
cd ~/retail-pos-api
dev-agent-config tools codebase-memory-mcp index
dev-agent-config tools codebase-memory-mcp status --project "$PWD"
dev-agent-config tools codebase-memory-mcp refresh --project "$PWD" --dry-run
dev-agent-config tools codebase-memory-mcp refresh --project "$PWD"
dev-agent-config tools codebase-memory-mcp clean --project "$PWD" --dry-run
dev-agent-config tools codebase-memory-mcp clean --project "$PWD"
dev-agent-config tools codebase-memory-mcp dashboard start --project "$PWD" --port 9749
dev-agent-config tools codebase-memory-mcp dashboard status
dev-agent-config tools codebase-memory-mcp dashboard stop --dry-run
dev-agent-config tools codebase-memory-mcp dashboard stop
dev-agent-config tools codebase-memory-mcp watcher status
dev-agent-config tools codebase-memory-mcp watcher set disabled --dry-run
dev-agent-config tools codebase-memory-mcp watcher set disabled
```

The dashboard binds to loopback and prints a project-specific URL. Its managed
runner keeps CBM's stdio open and runs in the background on macOS and Linux.
`dashboard stop` stops only that manager-owned runner. CBM shares its UI through
its coordination daemon, so the UI can remain available while another CBM/MCP
session is connected; the manager will report this and will not kill a shared
daemon. After indexing, a short-lived CBM daemon can briefly own the port before
its UI is ready or the port is released. When the listener is confirmed as the
selected CBM binary's internal daemon but HTTP is not ready, the manager starts
its persistent `--ui=true` CBM session so it can join or establish the shared
daemon; it does not wait for or terminate the short-lived CLI process. Startup
succeeds only after a healthy HTTP HTML response from a verified CBM listener,
with a 30-second bound. An unrelated or unverifiable listener is refused.
Failed startup reports both the manager runner log and CBM's daemon log path.
Stop the runner before cleaning that project's index or removing the binary.

Persistent dashboard services are optional and require explicit actions. The
manager creates only its own service definition and refuses pre-existing or
modified content:

```bash
dev-agent-config tools codebase-memory-mcp service install --port 9749 --dry-run
dev-agent-config tools codebase-memory-mcp service install --port 9749
dev-agent-config tools codebase-memory-mcp service verify
dev-agent-config tools codebase-memory-mcp service enable --dry-run
dev-agent-config tools codebase-memory-mcp service enable
dev-agent-config tools codebase-memory-mcp service disable --dry-run
dev-agent-config tools codebase-memory-mcp service disable
dev-agent-config tools codebase-memory-mcp service remove --dry-run
dev-agent-config tools codebase-memory-mcp service remove
```

Linux uses a user systemd unit. `service verify` reports whether lingering is
enabled; surviving logout requires the explicit host-admin action
`loginctl enable-linger`, which this manager never performs. macOS uses a
user LaunchAgent, active in the logged-in GUI session and stopped at logout.
Services bind through CBM's documented loopback UI. Service management requires
a manager-owned CBM binary and available `systemctl --user` or `launchctl`;
other operating systems and unavailable user service managers are unsupported.
The generated service references this checkout's dashboard runner, so keep the
checkout at the same path while the service definition is installed.

Watcher controls only read or set CBM's global `watcher_enabled` setting.
Current upstream documentation distinguishes this from `auto_watch`: an open
MCP session registers its own project with the background watcher. The manager's
CLI `index`/`refresh` operation does not prove that registration. Project
`status` reports CBM's `watch.strategy` when the installed version exposes it;
this is registration evidence, not proof the poller is healthy. Source-change
detection and successful reindex after changes remain unverified unless checked
against live CBM state. The watcher subsystem master setting is read when the
daemon starts; this manager does not stop or restart CBM's shared daemon.

### Debian clean-room test procedure (documentation only)

This procedure is for a later, separately approved Debian Remote SSH run. It
first inventories the manually installed executable, Codex registration, and
service files without printing credentials. Do not reset or remove any of these
external resources as part of this test. Use a temporary HOME, cache, Codex
config, and disposable Git repository; never point the test at a real project.
Do not run it with `HOME`, `CODEX_HOME`, or cache variables pointing at a real
user home.

```bash
cd /path/to/dev-agent-config
REAL_HOME="$HOME"
REAL_CODEX_HOME="${CODEX_HOME:-$REAL_HOME/.codex}"
REAL_CBMCACHE_DIR="${CBM_CACHE_DIR:-$REAL_HOME/.cache/codebase-memory-mcp}"
REAL_XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$REAL_HOME/.config}"
# Read-only inventory: capture paths and ownership/state, not config contents.
command -v codebase-memory-mcp || true
codebase-memory-mcp --version 2>/dev/null || true
dev-agent-config tools codebase-memory-mcp status
dev-agent-config tools codebase-memory-mcp mcp status codex
systemctl --user list-unit-files 'dev-agent-config-cbm-dashboard.service' 2>/dev/null || true
ls -ld "$HOME/.local/bin/codebase-memory-mcp" "$HOME/.local/share/codebase-memory-mcp" 2>/dev/null || true

CBM_TEST_HOME="$(mktemp -d /tmp/dev-agent-config-cbm.XXXXXX)"
export HOME="$CBM_TEST_HOME"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CONFIG_HOME="$HOME/.config"
export CBM_CACHE_DIR="$HOME/.cache/codebase-memory-mcp"
export CODEX_HOME="$HOME/.codex"
mkdir -p "$CODEX_HOME" "$HOME/.config/opencode"
HOME="$HOME" ./scripts/install.sh --dry-run
HOME="$HOME" ./scripts/install.sh
HOME="$HOME" ./scripts/verify.sh
mkdir -p "$HOME/cbm-fixture"
git -C "$HOME/cbm-fixture" init
printf 'export function demo() { return 1; }\n' > "$HOME/cbm-fixture/demo.ts"

./dev-agent-config tools codebase-memory-mcp install --dry-run
./dev-agent-config tools codebase-memory-mcp install
./dev-agent-config tools codebase-memory-mcp verify
./dev-agent-config tools codebase-memory-mcp index --project "$HOME/cbm-fixture"
./dev-agent-config tools codebase-memory-mcp status --project "$HOME/cbm-fixture"
CBM_PROJECT_NAME="$(./dev-agent-config tools codebase-memory-mcp status --project "$HOME/cbm-fixture" | sed -n 's/^CBM project: //p')"
"$HOME/.local/bin/codebase-memory-mcp" cli search_graph --project "$CBM_PROJECT_NAME" --label Function --name-pattern demo --limit 5
./dev-agent-config tools codebase-memory-mcp mcp enable codex --dry-run
./dev-agent-config tools codebase-memory-mcp mcp enable codex
# If an isolated Codex CLI/client is available, connect using this CODEX_HOME
# and test MCP; do not borrow the real user's credentials or config.
./dev-agent-config tools codebase-memory-mcp mcp disable codex
./dev-agent-config tools codebase-memory-mcp dashboard start --project "$HOME/cbm-fixture" --port 19749
# Open the printed loopback URL or forward port 19749 in VS Code Remote SSH.
# In a separate terminal, verify the HTTP endpoint:
curl --fail --silent --show-error http://127.0.0.1:19749/ >/dev/null
./dev-agent-config tools codebase-memory-mcp dashboard stop
./dev-agent-config tools codebase-memory-mcp clean --project "$HOME/cbm-fixture" --dry-run
./dev-agent-config tools codebase-memory-mcp clean --project "$HOME/cbm-fixture"
./dev-agent-config tools codebase-memory-mcp remove --dry-run
./dev-agent-config tools codebase-memory-mcp remove
```

For synchronization, keep an isolated Codex MCP session open for the fixture
project and inspect `status --project` before and after a harmless fixture-only
source edit. Record separately the `watch.strategy` registration evidence,
whether CBM reports source changes, and whether index status changes afterward.
Do not infer these outcomes from `watcher_enabled` alone.

Only after the clean-room test is reviewed should a separate, explicitly
approved stage consider the existing installation. Run this backup block in a
new shell with the normal HOME (not the isolated HOME exported above). It copies
only configuration files, never project indexes or the full cache:

```bash
umask 077
REAL_HOME="$HOME"
REAL_CODEX_HOME="${CODEX_HOME:-$REAL_HOME/.codex}"
REAL_CBMCACHE_DIR="${CBM_CACHE_DIR:-$REAL_HOME/.cache/codebase-memory-mcp}"
REAL_XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$REAL_HOME/.config}"
PARENT="$REAL_HOME/.local/state/dev-agent-config"
[ ! -L "$REAL_HOME" ] && [ ! -L "$REAL_HOME/.local" ] && [ ! -L "$REAL_HOME/.local/state" ] && [ ! -L "$PARENT" ]
mkdir -p "$PARENT"
BACKUP="$(mktemp -d "$PARENT/cbm-preflight.XXXXXX")"
chmod 700 "$BACKUP"
for file in "$REAL_CODEX_HOME/config.toml" \
  "$REAL_CBMCACHE_DIR/_config.db" \
  "$REAL_CBMCACHE_DIR/config.json" \
  "$REAL_XDG_CONFIG_HOME/systemd/user/dev-agent-config-cbm-dashboard.service" \
  "$REAL_HOME/Library/LaunchAgents/org.dev-agent-config.cbm-dashboard.plist"; do
  if [ -f "$file" ] && [ ! -L "$file" ]; then
    relative="${file#"$REAL_HOME"/}"
    case "$relative" in /*) relative="external/${file#/}" ;; esac
    mkdir -p "$BACKUP/$(dirname "$relative")"
    cp -p "$file" "$BACKUP/$relative"
    printf '%s\t%s\n' "$file" "$BACKUP/$relative" >> "$BACKUP/manifest.tsv"
  fi
done
```

Record which binary, MCP entry, cache/index, and service definition is external
versus manager-owned. Do not use this prototype's `remove` or `clean` on any
external resource. Roll back only by disabling an unchanged manager-owned MCP
entry or service, removing the disposable test index, and removing
manager-owned test binaries; restore user-owned files only from the matching
backup. A real reset of the prior installation requires separate explicit
approval.

After verifying that `CBM_TEST_HOME` still names the temporary directory
created above, delete only that directory to discard its isolated cache and
configs. Do not run the cleanup against your normal HOME:

```bash
case "$CBM_TEST_HOME" in
  /tmp/dev-agent-config-cbm.*) [ -d "$CBM_TEST_HOME" ] && [ ! -L "$CBM_TEST_HOME" ] && rm -rf -- "$CBM_TEST_HOME" ;;
  *) echo "Refusing unexpected test path: $CBM_TEST_HOME" >&2; exit 1 ;;
esac
```

## Development and tests

```bash
bash -n dev-agent-config scripts/*.sh scripts/lib/*.sh scripts/tools/*.sh tests/*.sh
bash tests/test_cli.sh
bash tests/test_install.sh
bash tests/test_code_intelligence.sh
bash tests/test_verify.sh
bash tests/test_tools.sh
bash tests/test_cbm.sh
bash tests/test_cbm_projects.sh
bash tests/test_cbm_service.sh
bash tests/test_cbm_run.sh
bash tests/smoke.sh
```

Tests use temporary HOME directories and remove them afterward. They cover fresh
installation, merge, replace, adapters, repeated installation, symlink conflicts,
rollback, uninstall, benchmark isolation, conditional code-intelligence links,
CBM install/MCP fixtures, project mapping and cleanup, dashboard ownership and
port-conflict fixtures, watcher evidence reporting, one-command CBM bootstrap
and isolated cache fixtures, and isolated Graphify tool management.
Service-definition tests use fake service-manager commands and do not install
systemd units, launch agents, or persistent services.
