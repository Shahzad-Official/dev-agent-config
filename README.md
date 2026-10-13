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
proof that an extension is active. Filesystem verification does not prove that an
agent activated Ponytail, so runtime activation remains `unverified`.

## Ponytail provenance

Ponytail is a reviewed local adaptation, version `1.0.0-dev-agent-config`, of the
MIT-licensed [Ponytail project](https://github.com/dietrichgebert/ponytail). Full
provenance is recorded in `skills/ponytail/SOURCE.md`. Nothing is downloaded or
executed during installation.

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
./tests/smoke.sh
```

Tests use temporary HOME directories and remove them afterward. They cover fresh
installation, merge, replace, adapters, repeated installation, symlink conflicts,
rollback, uninstall, and benchmark isolation.
