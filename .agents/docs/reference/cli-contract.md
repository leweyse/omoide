---
type: Reference
title: CLI contract
description: What every subcommand accepts, touches and returns, the exit codes, and what enforces each promise.
source_digest: 'sha256:b22b7b3a3cf07592bc602e020164c8478ebdc4c9c212ebf4bc675a39198ebfbb'
sources:
  - id: dispatch
    resource: ../../../cli/src/main.c
    title: Subcommand table and top-level options
  - id: header
    resource: ../../../cli/src/omoide.h
    title: Exit codes, SCHEMA_VERSION, INDEX_VERSION
  - id: args
    resource: ../../../cli/src/args.c
    title: Option parsing and its exit codes
  - id: parity
    resource: ../../../dev/parity
    title: The cases that pin every behavior below
generated:
  by: anthropic/claude-opus-5-5
  at: '2026-09-26T00:00:00Z'
---

# CLI contract

Read this before changing what a subcommand accepts or prints, or before QML starts depending on something new from one. Every row is a promise to a caller, either a QML file in this repository or a user's own script, so a change to one is breaking unless it only adds.

`dev/parity` enforces this page. Each case runs one invocation with a fixed clock, fixed ids and every external program stubbed, with nothing but the stubs on `PATH`, and compares exit code, stdout, the index `omoide index` returns afterwards, `config.json`, every database row, the log, the files left behind and every program the CLI ran, against its recorded fixture in `dev/parity-cases/`. A behavior this page describes without a case is not a promise; add the case with the `parity-case` skill.

## Global rules

- **One JSON object on stdout**, plain and on one line, for every subcommand except `keybind` without `--json`, which prints the snippet itself. Keys are camelCase.
- **Errors go to stderr** as `omoide: <message>`. Their wording is not part of the contract, and parity does not compare it.
- **Arguments are bytes.** String options are read as filenames and repaired to valid UTF-8, so no locale can make a title unreadable. The process never calls `setlocale`.
- **Adding is compatible, and still approved.** A new optional flag or a new output key is additive, so it breaks no caller. Removing either, renaming either, changing a type, or changing a default is breaking. Either kind needs the owner's approval before it is written: `dev/cli-surface.lock` records the surface, and `dev/check` fails until a change to it is written there.

## Exit codes

| Code | Meaning |
| ---- | ------- |
| 0 | success, including an agent run that failed; the failure is recorded on the memory |
| 1 | a runtime error: a missing record, an unreadable date, a missing program, a refused path |
| 2 | nothing to do (a cancelled picker, an empty commit, a draft already gone), and also a malformed command line |
| 3 | the database is newer than this binary understands; nothing is read or written |

Exit 3 applies to every subcommand that opens the database, reads included, so an older binary left running after an update never misreads a newer schema.

## Subcommands

`omoide --help` lists them, in the order of the table in `cli/src/main.c`. The files are grouped by what a command does, not one per command:

| File | Holds |
| ---- | ----- |
| `cli/src/cmd_read.c` | reads: nothing is written and nothing migrates |
| `cli/src/capture.c` | capture, the draft lifecycle, and enrichment by the agent |
| `cli/src/cmd_write.c` | writes that change memories, items, reminders, collections and links |
| `cli/src/cmd_maint.c` | maintenance the shell or a person runs: rebuilding, sweeping, discarding |
| `cli/src/cmd_migrate.c` | the explicit migration |
| `cli/src/cmd_setup.c` | agent settings, the keybind, `install` and `uninstall` |

Which command lives where is `grep -n cmd_ cli/src/main.c`; this table only says where a new one goes.

What each group promises beyond its output shape:

- **Reads** never migrate and write no rows. They still open the database read-write, which creates it and its directories when absent and sets WAL mode, and they exit 3 on a newer schema.
- **`index`** prints the snapshot the shell renders: counts, today's digest, the collections and every live alarm. It carries no list a view scrolls through, and every count is taken over all the items. It is the only way the shell learns what changed.
- **`archive --group`** and **`events`** page the same way as `list`: `archive --group <open|upcoming|past|completed|suggested>` answers under `items`, `events` under `events`, each with a `pageInfo`, resuming from `--after <endCursor>`. `open` is soonest due first; the other groups are newest first. `archive` without `--group` prints every group in full, as it always has, and takes no `--after`.
- **`list`** and **`search`** return one page of cards and a `pageInfo` of `total`, `startCursor`, `endCursor` and `hasNextPage`. The next page is `--after <endCursor>`. A cursor is opaque to callers: `list` resumes from a card, so a memory saved between two pages neither repeats nor skips one, and `search` resumes from a position in the ranking. `--facet <group>:<value>` narrows either to one chip, for the groups `kind`, `source` and `tag`. A malformed cursor or facet exits 2. `--limit` keeps its meaning and default, and a negative limit still means no limit.
- **`facets`** returns the chips a view offers. Which chips exist is decided over the whole library; each count is taken within the view's scope (`--collection`, `--q`), and a chip with nothing in the scope is left out.
- **Writes** end by calling `omarchy-shell -q omoide refresh` exactly once, which makes the shell pull `index`. `commit` and `enrich` signal twice, once before the agent runs and once after. A write that adds or changes a dated item sweeps reminders first, so an alarm already due fires in the same run.
- **`capture`** creates a draft and opens the compose overlay over IPC; it writes no index, because a draft is not yet a memory. A second capture while a picker is open exits 2 rather than stack pickers.
- **`commit`** finishes a draft, runs OCR, signals `refresh` before the agent starts so the memory appears at once, runs the agent, and signals again. It exits 0 when the agent fails.
- **`enrich`** replaces the agent's unedited blocks and their items, and leaves every block a user edited.
- **`sweep`** discards drafts older than its cutoff, marks an enrichment whose process died as failed, fires due reminders, and signals `refresh`. The shell runs it once shortly after load.
- **`install`** and **`uninstall`** are run by a person, not by QML. `uninstall` deletes only what [storage](storage.md) says it may.

`list` answers under `memories` and `search` under `results`, and both build each card with `memory_card` in `cli/src/index.c`, so a grid renders either without a second code path. `show` returns a whole memory with its blocks, and `archive` returns items, not cards.

## Versions the CLI carries

- **`SCHEMA_VERSION`** in `cli/src/omoide.h` is the number of migrations compiled in; a static assertion holds them equal. See the `schema-migration` skill.
- **`INDEX_VERSION`** in the same header is the shape of what `index` prints. `indexVersion` in `Service.qml` must match it, and both change in one commit.
- **`--version`** prints the manifest version, embedded at build time, and the source id `Service.qml` built it from, or `local`.

## Environment

The CLI reads the `XDG_*_HOME` variables, only when absolute, and `HOME`. Tests and parity pin time and ids with `OMOIDE_NOW` and `OMOIDE_TEST_IDS`, which no user sets. `OMOIDE_SHELL_JSON` points at a different `shell.json` for the same reason. `grep -n getenv cli/src/*.c` is the full list.
