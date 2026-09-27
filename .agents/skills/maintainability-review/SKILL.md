---
name: maintainability-review
description: Run a deliberate, evidence-led review of changed or existing code for clarity, local reasoning, safe duplication, explicit state, bounded untrusted input, and comment discipline, then implement only the accepted findings. Use for a cleanup pass, a pre-merge review, or a request to simplify code that already works. Do not use to hunt correctness bugs in isolation, or to justify refactoring code outside the change's scope.
---

# Maintainability review

Preserve behavior and user-facing contracts unless correctness or a seriously misleading name gives strong evidence otherwise. [The engineering standard](../../docs/engineering/code-style.md) owns the rules; this skill owns the procedure. Do not restate the standard in a finding.

## 1. Establish the baseline

1. Read the root `AGENTS.md`, the contract of each directory in scope, and recent entries in [the log](../../docs/log.md).
2. Inspect the worktree and preserve unrelated changes.
3. Run `dev/check` and record what passed before anything changed. A review that cannot show its baseline cannot show it made nothing worse.

## 2. Audit

Read the whole file around every hunk, not the hunk alone. For each finding record the concrete failure mode, the exact file and symbol, the evidence, the smallest credible correction, and the parity case or check that would tell the correction from the current behavior.

Look first for what goes wrong most here:

- an abstraction with one caller, or scope grown past the change's purpose;
- a limit, list or version kept in two places;
- untrusted text reaching storage, a toast or an argv without passing its bound;
- a comment that narrates history instead of stating a constraint;
- a QML file that runs a process, formats a date, or renders model text as markup.

"More abstraction", "split the file" and "deduplicate" are not findings without a demonstrated reasoning, safety or maintenance benefit.

## 3. Reconcile

Classify each finding against the standard's trust-boundary table before accepting it; confirm a real caller can produce the value a check rejects. Then mark it **accept** (a correctness, safety or material clarity problem), **defer** (valid but out of scope, recorded in [open questions](../../docs/planning/open-questions.md)), or **reject** (taste, speculative generality, or a change to a user-facing contract).

## 4. Implement, narrow to broad

Change one accepted finding at a time. A behavior change starts with the parity case that distinguishes it. Verify in order: `clang-format`, both builds, the focused parity cases, `dev/parity --sanitize`, `dev/check`, and the shell with `verify-in-shell` if QML changed.

## 5. Report

Lead with outcomes: accepted changes, deliberate non-changes, deferred findings and where they were recorded, what was verified and what was not. Move any rationale a fix produced into the knowledge bundle, not into a comment.
