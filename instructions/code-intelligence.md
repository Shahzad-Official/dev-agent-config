# Code Intelligence

For explicit architecture investigations, cross-module tracing, call/dependency
analysis, or security reviews that require understanding how code paths connect,
start with one or two targeted Codebase Memory MCP (CBM) graph queries when the
selected project has a current index and CBM is available. Use the results to
identify relevant symbols and files, then verify conclusions in source. Do not
request a whole-graph dump.

For a simple, local change or question whose answer is clear from a small number
of files, use direct source navigation without invoking CBM. If CBM is unavailable,
the project is not indexed, or graph results are inconclusive, fall back to targeted
source search and reads; do not silently create or refresh an index.

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
