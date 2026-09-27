---
type: Reference
title: CLI build
description: How Service.qml compiles the CLI on the user's machine, where the binary lives, and what keeps QML and CLI from the same checkout.
source_digest: 'sha256:6d782f32d45bb52d712d909c375f02b08704d37b818323555c0f1ff87dec950c'
sources:
  - id: service
    resource: ../../../ui/Service.qml
    title: buildCli, linkCli and the call queue
  - id: rsp
    resource: ../../../cli/build.rsp
    title: Compiler flags, sources and libraries
  - id: ci
    resource: ../../../.github/workflows/cli.yml
    title: The fresh-clone build CI runs on every change
generated:
  by: anthropic/claude-opus-5-5
  at: '2026-09-26T00:00:00Z'
---

# CLI build

Read this before changing `cli/build.rsp`, the build section of `Service.qml`, or anything the binary embeds. A mistake here does not fail a test; it leaves every fresh install with a plugin that runs nothing.

## Why it builds on the user's machine

`omarchy plugin add` is a plain `git clone`, and `omarchy plugin update` a fast-forward pull, with no install hook. Committing a binary would tie it to one architecture and one set of library versions, and a build step outside the shell would be a setup task the user has to remember. Omarchy already ships clang and the headers of every library the CLI links, so the first shell load after an add or an update compiles it. [The decision register](../planning/decision-register.md) records the alternatives that lost.

## What happens on load

`Service.qml` runs every step as an argv, never a shell string:

1. **Identify the source.** `git rev-parse` of the tree ids of `cli` (its prompt included), `sql` and `manifest.json`, which is everything the binary compiles or embeds, hashed into a short id. If `git` fails, or `git status` shows local changes under those paths, the id is `local`, and the plugin rebuilds on every load. That is the development loop.
2. **Reuse or compile.** If a build for that id already exists in the user's cache directory, it is used as it is. Otherwise the first compiler found among clang, gcc and cc runs `@build.rsp` from `cli/`, with the id passed in as `OMOIDE_SRC_ID`, into a temporary file that is then moved into place. A failed build removes its temporary file.
3. **Link.** A stable `omoide` symlink in the same directory is pointed at that build, and every other build there is deleted. `Service.binPath` is the symlink.
4. **Drain the queue.** Calls QML made before the build finished waited in `cliQueue`, and now run.

When there is no compiler, or the build fails, the plugin sends one critical notification with the first line of the error and answers every queued call with a failure, so no view waits forever.

## Invariants

- **Build output never goes into the plugin directory.** A file there triggers the shell's plugin watcher and makes the next `omarchy plugin update` refuse to fast-forward.
- **QML and CLI come from one checkout.** After an update, the running QML keeps its old id, and so its old binary, until the shell restarts. A newer QML never talks to an older CLI.
- **`-Werror` is for CI and `dev/check`, never the user's build.** A newer compiler adding a warning must not break an install.
- **The build needs no network and no tool beyond the compiler.** It links against system libraries only. A new library in `build.rsp` is a new requirement on every user's machine, and needs approval.
- **Everything the binary embeds counts toward the id.** The migrations, the enrichment prompt under `cli/prompts/` and the manifest are compiled in with `#embed`. A new embedded file outside those paths must be added to `cliSources` in `Service.qml`, or an update that changes only that file will keep running the old build. A local edit to such a file does not make the id `local` either, because the `git status` check is scoped to `cliSources`.

## What proves it

CI's "Fresh clone builds and runs" step clones the repository, runs `cc @build.rsp`, the argv `Service.qml` uses less the `-DOMOIDE_SRC_ID` it adds, and starts the result. The `verify-in-shell` skill covers checking a real load.
