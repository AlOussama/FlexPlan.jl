# Codex and GitHub Copilot Roles

## 1. Principle

Codex and GitHub Copilot may write code, but all code must be reviewed.

No generated code is merged unless:

1. it is traceable to a documented equation;
2. every new function has a docstring;
3. it is covered by tests;
4. it passes CI;
5. it passes human mathematical review.

## 2. Codex role

Codex is the repo-level implementation agent.

Use Codex for:

- scoped implementation branches;
- parser/reference extensions;
- variables and constraints;
- test additions;
- documentation updates;
- running tests.

Codex must not invent new mathematical assumptions.

If ambiguous, Codex must stop and write the ambiguity to:

```text
docs/uc_gscr_block/open_questions.md
```

## 3. GitHub Copilot role

Copilot is the IDE-level assistant and PR review assistant.

Use Copilot for:

- local completions;
- docstrings;
- small refactors;
- test boilerplate;
- PR review suggestions.

Copilot must not change mathematical intent.

## 4. Combined workflow

```text
Human updates docs
  ↓
Codex implements one scoped task
  ↓
Codex writes/updates docstrings
  ↓
Codex runs tests
  ↓
Copilot assists local cleanup
  ↓
Open PR
  ↓
CI
  ↓
Copilot PR review
  ↓
Human mathematical review
  ↓
Merge
```

## 5. Branch strategy

Use one branch per task:

```text
feature/uc-gscr-ref-extension
feature/block-variables
feature/block-dispatch-constraints
feature/gscr-gershgorin
feature/storage-block-constraints
feature/global-gscr-lmi
```

## 6. PR gate

Every PR must answer:

- Which equation is implemented?
- Which functions were added?
- Do all new functions have docstrings?
- Which files changed?
- Which tests were added?
- Which tests were run?
- Was any assumption added?
- Did Copilot review it?
- Did a human review the mathematical formulation?
