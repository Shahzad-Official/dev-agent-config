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

Graphify 0.9.88 interprets `--out OUTPUT_ROOT` as a parent and writes the graph
to `OUTPUT_ROOT/graphify-out/`. The manager verifies `graph.json`,
`GRAPH_REPORT.md`, and `graph.html` there. The default output root is an XDG data
path derived from the canonical project path and is outside the source tree.
Outputs inside the selected project are refused.
For rollback and symlink safety, a custom output root must remain beneath `HOME`,
`XDG_DATA_HOME`, or `XDG_STATE_HOME`.

Every run forces `graphify extract PROJECT --out OUTPUT_ROOT --code-only`, removes
known AI-provider credentials from the child environment, disables query logging
and cloud tips, and does not enable document/media extraction. It does not scan
projects automatically. A project symlink is refused so the selected source is
unambiguous.

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

## Development and tests

```bash
bash -n scripts/*.sh scripts/lib/*.sh tests/*.sh
./tests/test_install.sh
./tests/test_verify.sh
./tests/test_tools.sh
./tests/smoke.sh
```

Tests use temporary HOME directories and remove them afterward. They cover fresh
installation, merge, replace, adapters, repeated installation, symlink conflicts,
rollback, uninstall, benchmark isolation, and isolated Graphify tool management.
