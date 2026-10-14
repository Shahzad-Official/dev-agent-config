# Shared Engineering Instructions

## Implementation
- Prefer the smallest complete, correct, and maintainable solution.
- Inspect relevant code and reuse existing components and dependencies before creating new ones.
- Preserve established architecture, interfaces, conventions, and intentional learning exercises.
- Avoid speculative features and unnecessary wrappers, abstractions, and dependencies.
- Consider callers, tests, fixtures, migrations, error handling, and edge cases.
- Never weaken security, validation, accessibility, or data integrity for brevity.

## Validation
- Do not launch applications, emulators, physical device debug sessions, or servers unless explicitly asked.
- Use focused static checks and tests when appropriate and allowed by project instructions.
- Explain practical manual verification steps and disclose anything not checked.

## Git
- Follow Conventional Commits: type(scope): description, with optional scope.
- Use a lowercase, imperative subject, ideally under 50 characters and never over 72.
- Base proposed commit messages only on staged changes.
- For complex changes, explain why in a short commit body.

## Skills and precedence
- Shared skills are installed in ~/.agents/skills/ when supported.
- When structural codebase exploration would help, read `~/.agents/instructions/code-intelligence.md`; otherwise skip it.
- Consider the ponytail skill for implementation, refactoring, and review, without forcing it into every prompt.
- More specific project instructions take precedence over these defaults unless they conflict with higher-priority safety requirements.
- Follow each agent's native skill discovery behavior; a file link alone does not prove skill activation.
