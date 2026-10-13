---
name: ponytail
description: >
  Prefer the smallest complete code change for implementation, refactoring,
  debugging, and code reviews. Use when the task benefits from avoiding
  unnecessary dependencies or abstractions. Modes: lite, full, ultra.
argument-hint: "[lite|full|ultra]"
license: MIT
---

# Ponytail

Adapted from https://github.com/dietrichgebert/ponytail (MIT licensed).

Solve the complete task with the least new code that is easy to maintain.
Inspect the relevant code before changing it and identify affected callers,
tests, configuration, exports, and any data or security consequences.

1. Skip unrequested speculative features.
2. Reuse existing project patterns and components first.
3. Prefer built-in platform features or already installed dependencies.
4. Introduce an abstraction only when it solves a demonstrated need.
5. Finish the entire necessary change, including affected tests and fixtures.
6. Preserve intentional architectural boundaries, validation, security, and accessibility.
7. For nontrivial logic, include a focused test or equivalent check where appropriate.
8. In the final reply, state any skipped verification and material risks concisely.

Modes: lite (give the minimal viable approach and a smaller alternative),
full (apply all rules), ultra (also question unnecessary requirements).
