---
type: Engineering Standard
title: Engineering house style
description: The durable C, QML, boundary, evidence and comment conventions for Omoide. Applies to new work and evidence-backed cleanup, not to churning stable code.
documentation_type: reference
tags: [engineering, c, qml, boundaries, evidence]
sources:
  - id: build
    resource: ../../../cli/build.rsp
    title: The one build argv, shared by users, CI and dev/check
  - id: format
    resource: ../../../.clang-format
    title: C formatting
  - id: header
    resource: ../../../cli/src/omoide.h
    title: The CLI's only shared header
  - id: enrich
    resource: ../../../cli/src/enrich.c
    title: Where agent output is bounded and validated
  - id: model
    resource: ../../../ui/MemoryModel.js
    title: Pure QML helpers
  - id: review
    resource: ../../skills/maintainability-review/SKILL.md
    title: The review procedure that applies this standard
generated:
  by: anthropic/claude-opus-5-5
  at: '2026-09-26T00:00:00Z'
---

# Engineering house style

This standard is the code-quality policy for Omoide. It supports code a reader can understand from the file in front of them, change without discovering hidden coupling, and verify without a desktop. Apply it to new work and to evidence-backed cleanup; do not churn stable code or a user-facing contract to make syntax uniform.

It owns rules that hold across the repository. A directory's `AGENTS.md` owns that directory's invariants and does not restate a rule from here. A procedure with a trigger belongs to its skill. A contradiction between any two of them is a defect in one: report it instead of picking a winner.

## Design for local reasoning

- Prefer explicit data flow, domain vocabulary, and invariants visible in the current file. A reader should not have to open three files to learn what a value can be.
- Model a closed set of states as one field with named values, as `status` and `ai_status` are, rather than as booleans that can combine into a state the product cannot be in.
- Keep a function total over the inputs its callers can produce, and make expected failure explicit in its return value. `die()` is for a failure the process cannot continue past.
- Retain semantic state until the presentation edge. Never recover state by parsing a label, a toast, a log line, or any other display string; derive the label from the value at the render site.
- Name a limit once, as a constant beside the code it bounds, and never repeat its value in prose.

## Share durable knowledge, not coincidental mechanics

- Pick the most direct implementation that satisfies the requirement and stop there. Do not add a feature, a fallback, or a check for a case the requirement does not contain.
- Three similar lines beat the wrong abstraction. A helper with one caller is premature; the second caller shows what the shared part actually is.
- Deduplicate a rule that is dangerous to let drift: a limit, a persisted shape, a sandbox flag, a security boundary. Two lists of which providers accept images are one list waiting to disagree.
- Keep one owner for each contract that crosses the seam. `INDEX_VERSION` and `indexVersion` are the one pair that must be kept equal by hand; everything else QML needs comes from a subcommand's output, the index included, not from a copy of a CLI constant.
- When two designs look equally reasonable, or the requirement is ambiguous, ask.

## Trust boundaries

Classify a value by who can author it, not by which file it crossed. Validate what an outsider authors once, where it enters, and trust what this code produced after that.

| Where the value comes from | Treatment | What proves it |
| -------------------------- | --------- | -------------- |
| Capture content: a screenshot, its OCR text, a note, a transcript | Untrusted instructions as well as untrusted data. Bounded and cleaned in the CLI before storage; never interpreted by QML | Fuzzing and parity cases with hostile text |
| An agent's reply | Untrusted. Parsed, bounded and validated once in `cli/src/enrich.c`; unknown block types dropped; only `http` and `https` URLs kept | `dev/fuzz` over the reply path, parity `commit-ai-*` cases |
| Another program's output: `hyprctl`, `tesseract`, `ffprobe`, the picker | Repaired to UTF-8 and parsed defensively; a missing field reads as absent | Parity cases with the program stubbed |
| A user-editable file: `config.json`, `shell.json` | Read defensively; a malformed file behaves as unset, never as a crash | Parity `state-bad-config` |
| Command-line arguments, from QML or a person | Repaired to UTF-8 and checked by the option parser; a title a person typed is stored as typed | Parity cases per flag |
| The database | Written by this CLI at some schema version. Trusted after the version check; a newer schema exits 3 | Parity `migrate-*` cases |
| The index, as pulled by QML | Printed by `omoide index` from the same checkout; trust its shape, and render an empty default until the first pull answers | `INDEX_VERSION` equality |
| The Omarchy host's API | Outside this repository, and changes on Omarchy's schedule. Verify against the installed shell's source, not against memory | Running it, with `verify-in-shell` |

Keep every memory-safety check: lengths, caps on output read from a process, arithmetic on sizes. Those are not trust decisions. Validating the same value twice is not caution; it is a second place to be wrong, and it hides which check is the contract.

## C

- **Toolchain.** `cli/build.rsp` is the build: flags, sources and libraries in one argv that `Service.qml`, CI and `dev/check` all use. The code must compile warning-free under both gcc and clang with `-Werror`, and under `-fanalyzer`. The runtime libraries are glibc, GLib and GIO, json-c and SQLite, nothing else.
- **Formatting.** `.clang-format` is the authority. Run `clang-format -i` on the files you touched; never align by hand.
- **Layout.** `cli/src/omoide.h` is the only shared header; no source file includes another's. Command files are grouped by what the commands do (`cmd_read.c`, `cmd_write.c`, and the rest), and the dispatch table in `cli/src/main.c` is the list.
- **Ownership.** Every allocation that leaves scope is `g_autofree` or `g_autoptr`, and a value handed back to the caller leaves through `g_steal_pointer`. A json-c object added to another is owned by it; take an extra reference with `json_object_get` when both keep it. A function that takes ownership of an argument says so in `omoide.h`. Process-lifetime caches are the only deliberate leaks.
- **Errors.** `die(code, ...)` prints `omoide: <message>` and exits with a code from [the CLI contract](../reference/cli-contract.md). A soft failure returns `NULL` or `false`, or fills a reason for the caller. `GError` stays local to the GLib call that produced it.
- **SQL.** Every statement goes through `db_query` with bound parameters; never format a value into SQL text. A statement that fails to prepare is a bug and dies.
- **Processes.** Run a program with an argv, never a shell string, and bound both its time and its output. The one `sh -c` is the user's own custom agent command, stored and run exactly as they wrote it.
- **Behavior is pinned by parity.** A change to what a subcommand prints, writes, logs, or runs re-records the affected `dev/parity` fixtures in the same change, and their diff is the evidence.

## QML

- **Placement.** A file's directory says what it is, and its imports follow from that:

  | Directory | Holds | May import |
  | --------- | ----- | ---------- |
  | root | `Service.qml`, `BarWidget.qml`, `Cli.qml`, `MemoryModel.js` | anything |
  | `ui/common/` | design primitives with no knowledge of memories | `qs.*` only |
  | `ui/components/` | domain cards and rows reused across pages | `ui/common/`, `MemoryModel.js` |
  | `ui/blocks/` | one renderer per memory block type, each extending `BlockCard` | `ui/common/`, `ui/components/`, `MemoryModel.js` |
  | `ui/views/` | the pages of the Space window, plus the cards only they use | `ui/common/`, `ui/components/`, `ui/blocks/`, `MemoryModel.js` |
  | `ui/dialogs/` | sheets that open over the Space window, and the bar's action menu | `ui/common/`, `ui/components/`, `MemoryModel.js` |
  | `ui/surfaces/` | top-level layer windows, loaded by `Service.qml` | any directory above |

- **Imports.** A QML directory is imported unqualified, as `import "../common"`; a JavaScript file takes an alias, as `import "../MemoryModel.js" as Model`. `dev/check-types` resolves every type against these imports, and qmllint rejects an unused one.
- **Only the service runs things.** `Service.qml` and `Cli.qml` are the only files that create a `Process`. Everything else calls `service.call` or `service.detach`, or opens a URL with `Quickshell.execDetached`.
- **Text a user or an agent wrote renders as `Text.PlainText`.** Markup is allowed only where the label is ours and the value passes through `Model.escapeMarkup`.
- **Sizes come from `Style`.** Use `Style.space()`, `Style.font` and the `Color` tokens from `qs.Commons`; a literal pixel value will not scale with the user's settings.
- **Resolve from the new value in a change handler.** A binding read inside the handler of the property it depends on can still hold the previous value; compute from the handler's argument instead, as every page does.
- **Pure logic lives in `MemoryModel.js`**, which holds no Qt types so it stays testable outside the shell. It is the only place that formats a date or time.
- **Keyboard first.** Every page implements [the page contract](../reference/qml-keyboard.md), and Esc steps back one level at a time. A new interactive element is reachable without a mouse and shows focus with `FocusRing`.

## Determinism, tests, and evidence

- `dev/check` is the gate, and a change is not done until it passes. Say which parts ran.
- CLI behavior is proved by `dev/parity`: fixed clock, fixed ids, every external program stubbed, and exit code, output, rows, files and calls all compared against recorded fixtures. Memory safety is proved by the same cases under ASan and UBSan, and by `dev/fuzz` over the untrusted-text paths.
- QML has no test runner. A QML change is verified by `dev/check-types`, qmllint, and by running it in the shell with the `verify-in-shell` skill. A type check verifies code, not behavior; state which one a change had.
- Encode a repeatable check as a `dev/` script rather than leaving it as a shell recipe in a message. A command nobody can run again is not evidence.
- Never use a sleep, a retry, or a timer cushion as a correctness mechanism. Wait for the signal that the thing happened.

## Generated code, comments, and documentation

- Prefer names and types that make ordinary code self-explanatory. Add a comment for a non-obvious constraint at the line it governs: an ownership rule, a protocol requirement, a bound, a workaround for a named defect. Match the surrounding comment density.
- A comment states what holds now. How the code got here, which release changed it, and which bug prompted it belong in [the log](../log.md) or [the decision register](../planning/decision-register.md); the `agent-knowledge` skill says which. `dev/check-comments` flags the phrasing.
- A rule for a whole directory goes in its `AGENTS.md`, and how a part of the system works goes in a reference concept. Update the affected document in the same change as the code.
- Do not hand-edit generated output. The build cache is written by `Service.qml`.

## Deliberate non-rules

This standard does not require a named constant for every literal, an abstraction for every repeated expression, a check for every value, a comment for every non-obvious line, or zero comments. It does require the author to name the invariant being protected, choose a proportionate way to express it, and show evidence when a change affects correctness, a persisted shape, or a user-facing contract.
