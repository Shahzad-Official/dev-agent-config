# dev-agent-config

Portable, public-safe engineering instructions and reusable coding skills for macOS and Linux.

**Status:** Filesystem installation is supported and tested. Skill discovery and automatic invocation must be verified separately for each agent and version. No coding agent or paid API subscription is required to install.

## Quick start

```bash
./scripts/install.sh --dry-run
./scripts/install.sh
./scripts/verify.sh
```

The installer copies one **managed section** from `AGENTS.md` into `~/AGENTS.md` and supported existing agent instruction entry points, and links the portable Ponytail skill to relevant skills directories. Existing instructions outside the managed section are retained. It deliberately does not create unused agent configurations.

To preview removal: `./scripts/uninstall.sh`. To remove the managed sections and links: `./scripts/uninstall.sh --apply`.

## Supported operating systems and adapters

POSIX-style Bash on macOS and Linux. Confirmed filesystem targets include:

| Agent | Instructions | Skills |
| --- | --- | --- |
| Root/home compatible agents | `~/AGENTS.md` | `~/.agents/skills` |
| Codex | `~/.codex/AGENTS.md` | `~/.codex/skills` |
| Claude Code | `~/.claude/CLAUDE.md` | `~/.claude/skills` |
| Gemini CLI | `~/.gemini/GEMINI.md` | `~/.gemini/skills` (check version) |
| Cursor | Use agent-native rules for global policies | `~/.cursor/skills` (check version) |
| Cline | Use agent-native rules for global policies | `~/.cline/skills` (check version) |
| OpenCode | Use native instruction configuration | `~/.config/opencode/skills` (check version) |

Integration paths are best-effort, not a universal discovery standard. Check your installed agent's documentation before relying on a path. The installer never edits JSON, TOML, authentication, plugin, or MCP configuration files.

## Project boundary

Keep architecture decisions, language-specific conventions, and business requirements inside each project. Global instructions are short defaults, not a replacement for project rules.

## Reproducibility and updates

Clone this repository to a stable location (e.g. `~/dev-agent-config`) because symlinks point into the clone. `git pull` updates linked skills immediately. Rerun `./scripts/install.sh` after edits to `AGENTS.md` to refresh managed instruction sections. Consider pinning a Git commit or tag for deployments on multiple machines.

The bundled Ponytail-inspired skill is an MIT-licensed adaptation of [Ponytail](https://github.com/dietrichgebert/ponytail), not an exact mirrored upstream version. You can replace it with a reviewed upstream copy if desired.

## Testing

```bash
./tests/test_install.sh
```

Use a fresh agent session to confirm that global instructions were auto-loaded and that a skills tool can explicitly invoke Ponytail. A correct or short answer alone does not prove invocation.

## Security

Do not commit API keys, credentials, `.env` contents, chat logs, or private project details. Before pushing a public repository, run `git status` and review `git diff --cached`.
