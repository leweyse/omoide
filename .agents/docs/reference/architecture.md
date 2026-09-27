---
type: Reference
title: Architecture
description: The two halves of the plugin, what each may do, and the four channels between them.
source_digest: 'sha256:e8ca9806b7e61550bd8d8969cb9fca2aa7c05542883d7c68179264dc33c3bf50'
sources:
  - id: service
    resource: ../../../ui/Service.qml
    title: The singleton that builds the CLI, reads the index, and owns IPC
  - id: cli-runner
    resource: ../../../ui/Cli.qml
    title: The one Process wrapper QML uses to run the CLI
  - id: dispatch
    resource: ../../../cli/src/main.c
    title: CLI dispatch table
  - id: index
    resource: ../../../cli/src/index.c
    title: What `omoide index` prints for the shell
generated:
  by: anthropic/claude-opus-5-5
  at: '2026-09-26T00:00:00Z'
---

# Architecture

Read this before a change that crosses from QML into the CLI or back. Every other reference document assumes the split described here.

## Two halves

| Half | Owns | Never does |
| ---- | ---- | ---------- |
| QML in `ui/`, loaded by the Omarchy shell | rendering, focus and keyboard, the IPC target, arming reminder timers, building the CLI | open the database, write a file under the plugin's data or state directories, parse capture content |
| The CLI, `cli/src` compiled to one binary | SQLite, blobs, thumbnails, OCR, the agent run, reminder firing, notifications, the index the shell renders | keep state between runs, render anything, assume the shell is running |

## Where things live

| Path | Holds |
| ---- | ----- |
| `ui/` | every QML file and `MemoryModel.js`; the manifest's entry points are here |
| `cli/` | the C sources in `cli/src/`, the build argv in `cli/build.rsp`, the agent prompt in `cli/prompts/`, the fuzzer in `cli/fuzz/` |
| `sql/migrations/` | the schema, one file per version, embedded into the CLI |
| `dev/` | the checks, the parity harness and its fixtures in `dev/parity-cases/` |
| `.agents/` | this bundle and the skills; `.claude/skills` links to them |
| `.github/workflows/` | CI |
| `assets/` | the README's images |

`manifest.json` sits at the root, where Omarchy looks for it.

The split is what lets the CLI be tested without a desktop: `dev/parity` runs every subcommand with every external program stubbed. It is also what keeps untrusted content out of QML's reach. A capture's text and an agent's reply are parsed and bounded by C code before any of it reaches the index.

## Four channels

**QML to the CLI: argv.** `Service.call(args, callback)` runs the binary through `Cli.qml` and hands back the exit code and the parsed stdout JSON. `Service.detach(args)` runs it with `Quickshell.execDetached` for work that must outlive a shell reload: capture, commit, enrich, `reminder fire`, delete. Views, dialogs and components reach both through the `service` property they are given; only `Service.qml` and `Cli.qml` create a `Process`.

**The CLI to QML: the index, pulled.** Nothing is written for the shell to read. Every write ends by signalling `refresh`, and `Service.refresh()` then runs `omoide index` and renders its stdout; it runs at load too, once the CLI is built. One pull runs at a time, and a refresh that arrives during one queues exactly one more. There is no polling and no watched file. The index carries a `version` that must equal `indexVersion` in `Service.qml`; a mismatch is logged and rendered anyway. When `index` exits 3, the library was written by a newer build: `libraryTooNew` is set, the Space window covers its pages with a notice to update the plugin, and the bar icon shows its failure state until a pull succeeds. Its shape is defined by `build_index` in `cli/src/index.c`. `Service.qml` exposes the counts the surfaces show, such as `openTodoCount` (the upcoming and past counts in `todoCounts`), `dueTodayCount` (the digest's), `enrichingCount` and `failedCount`; look there before adding an index field for one. The alarm tick pulls again when the local day changes, so the day's counts roll over at midnight. A page with queries of its own (the library's `facets`, a memory's `show` and `related`, every paged list) re-runs them when the index changes.

**Lists: pulled a page at a time.** The index carries counts, never a list a view scrolls through. `ui/components/PagedList.qml` fetches memory cards from `list` or `search`, to-dos from `archive --group` and events from `events`, sized to fill the view about twice over, and asks for the next page while a viewport of rows is still below; the events carousel asks while less than a row of cards is left to its right. A new query or chip restarts it once its bindings settle, and only the latest request is applied. After a `refresh` it re-fetches what is already on screen, from the top, so the view keeps its place.

**The CLI to the running shell: IPC.** The CLI calls back with `omarchy-shell -q omoide refresh` after a write and `compose` after a capture, and a notification's click action runs `openSpace`. Those IPC functions are the same ones a user binds, so they carry the same compatibility promise; see [the host reference](shell-host.md).

## Where each part is described

- [Omarchy host](shell-host.md) — how the shell loads, reloads and talks to the plugin.
- [CLI contract](cli-contract.md) — what each subcommand accepts, does and returns.
- [CLI build](cli-build.md) — how `Service.qml` turns `cli/` into a binary on the user's machine.
- [Storage](storage.md) — every path, and what `uninstall` may delete.
- [Memory model](memory-model.md) — memories, blocks, items, reminders, collections and links.
- [Enrichment](enrichment.md) — the agent run, its sandbox, and how its reply is trusted.
- [Reminders](reminders.md) — how an alarm is armed in the shell and fired by the CLI.
- [Keyboard model](qml-keyboard.md) — how the Space window routes keys, and the contract every page implements.
