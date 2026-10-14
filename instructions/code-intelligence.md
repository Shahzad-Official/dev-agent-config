# Code Intelligence

Use Codebase Memory MCP (CBM) when a task benefits from structural exploration
of a repository: locating symbols, understanding call/dependency relationships,
or tracing a feature across modules. Start with one or two targeted queries for
the relevant symbols or relationships; do not request a whole-graph dump.

Keep retrieval proportional to the task. Avoid repeating equivalent queries,
pulling large neighborhoods without a concrete question, or reading broad
reports when a focused symbol/dependency result is enough. Follow returned file
paths to the source and read only the relevant ranges.

Treat graph results as navigation hints, not authoritative source. Verify
framework-mediated relationships, security-sensitive behavior, and ambiguous or
high-impact conclusions in the actual implementation, configuration, and tests.

Before relying on a result, confirm that CBM has an index for the selected
project and that its reported status is current enough for the task. If the
project is missing or the index appears stale, do not silently index or refresh
it; ask before changing index state when needed. Fall back to direct source
navigation and targeted search when CBM is unavailable or inconclusive.

Graphify remains an optional alternative only when explicitly requested. Do not
run both indexing systems automatically or treat either graph as a replacement
for project documentation or source code.

Project-specific `AGENTS.md` instructions retain their normal precedence. A
project may add an intelligence note when its owner chooses to; never create or
modify project files for this guidance automatically.
