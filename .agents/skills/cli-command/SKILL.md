---
name: cli-command
description: Add a subcommand to the C CLI, or change what an existing one accepts, prints, writes or runs, end to end from the dispatch table to the QML that calls it. Covers placing the code, option parsing, output, exit codes, rebuilding the index, the IPC refresh, the parity case, and the contract document. Use for any change under cli/src that a caller could observe. Do not use for a schema change, which is schema-migration, or for how an agent CLI is invoked, which is agent-preset.
---

# CLI command

Read [the CLI contract](../../docs/reference/cli-contract.md) and `cli/AGENTS.md` first. Every change to the CLI's surface needs approval before any code is written: a new subcommand, flag or output key as much as a removed or changed one. A new one is additive, so it breaks no caller; removing, renaming, retyping or changing the default of one is breaking. After approval, `dev/cli-surface --write` records the new surface in `dev/cli-surface.lock`, and a new call that deletes, runs a program or writes outside `paths()` goes into `dev/capabilities.lock` with `dev/capabilities --write`.

## Steps

1. **Place it.** Add the command to the table in `cli/src/main.c`, in the position `omoide --help` should list it, and write its `cmd_` function in the file that holds its kind of command: reads in `cmd_read.c`, writes in `cmd_write.c`, maintenance in `cmd_maint.c`, setup in `cmd_setup.c`. Declare it in `cli/src/omoide.h`. A new source file is justified only by a new kind of command, and it goes into `cli/build.rsp`.
2. **Parse.** Declare the options in a `GOptionEntry` table and call `parse_options`. Use `require_option`, `require_choice` and `positional` so a malformed command line exits 2 the way every other command does.
3. **Open the database** with `db_open(false)` for a read or `db_open(true)` for a write. A write migrates; a read never does. Both exit 3 on a newer schema.
4. **Do the work** with bound parameters through `db_query`, and bound any text from outside by the rules in [the engineering standard](../../docs/engineering/code-style.md#trust-boundaries).
5. **Finish a write** the way its siblings do. Sweep reminders if a dated item changed, then call `shell_ipc(IPC_TARGET, "refresh", NULL)` once, which makes the shell pull `omoide index`. A command that skips a step differs from its neighbors on purpose, and the contract says why.
6. **Print once** with `emit()`: one JSON object, camelCase keys. Report failure with `die()` and the right code from the contract.
7. **Pin it.** Load `parity-case` and add cases for the success path and each failure path. Record each fixture and read it before trusting it; for a changed command, review the diff of every fixture it re-records.
8. **Call it from QML**, when the shell needs it, through `service.call` or `service.detach`, never a new `Process`. A command only a person or a script runs has no QML caller; that is fine. If the index `omoide index` prints changed shape, bump `INDEX_VERSION` and `indexVersion` in `Service.qml` together.
9. **Document it.** Update the contract page if a rule changed, and nothing else: the output shape lives in the code and the parity case.
10. **Verify** with `dev/check`, then `dev/parity --sanitize`. A stale digest names each concept that describes a file you changed: read it, fix what is now untrue, then run `dev/sync-docs`. If QML changed, load `verify-in-shell`.
