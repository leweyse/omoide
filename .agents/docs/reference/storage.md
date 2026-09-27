---
type: Reference
title: Storage
description: Every path the plugin reads, writes or deletes, how each is derived, and what uninstall may remove.
sources:
  - id: paths
    resource: ../../../cli/src/paths.c
    title: Path derivation and guard_paths
  - id: setup
    resource: ../../../cli/src/cmd_setup.c
    title: install and uninstall
  - id: tree
    resource: ../../../cli/src/memories.c
    title: remove_tree and the blob directory of a memory
  - id: service
    resource: ../../../ui/Service.qml
    title: The paths QML derives for itself
generated:
  by: anthropic/claude-opus-5-5
  at: '2026-09-26T00:00:00Z'
---

# Storage

Read this before adding a file, moving one, or changing anything that deletes. Every path here is a promise to users who already have data at it, and the deletion rules are what keep `uninstall` from ever removing something the plugin did not make.

## Where things live

| Directory | Holds | Owned by |
| --------- | ----- | -------- |
| `$XDG_DATA_HOME/omoide` | `memories.db`, and `blobs/<memory id>/` with each capture and its thumbnail | the CLI |
| `$XDG_STATE_HOME/omoide` | the log, lock and pid files, the agent's empty working directory, a backup taken during a migration | the CLI; everything here is rebuildable |
| `$XDG_CONFIG_HOME/omoide/config.json` | the agent settings | the CLI writes only the `ai` key and keeps any other key it finds |
| `$XDG_CACHE_HOME/omoide/bin` | the compiled CLI and its stable symlink | `Service.qml` |
| `~/.local/bin/omoide` | a symlink to the cached CLI, created by `install` | the CLI, only when the path is absent or already its own link |

The plugin also reads the user's `shell.json` for the bar widget's settings and writes nothing else. `paths()` in `cli/src/paths.c` derives every CLI path; `Service.qml` derives its own copies of the data, state and cache roots.

## Rules that keep deletion safe

- **The last component is always the literal `omoide`.** An `XDG_*` variable moves the base directory, and only when it is absolute, but no variable can rename the leaf. That is what makes it safe for `uninstall` to delete the directory: it can only be one the plugin made.
- **Nothing under the Omarchy package tree.** `guard_paths` refuses to run if the data, state or config directory resolves under `/usr/`, which is where `~/.local/share/omarchy` points. It runs before opening the database, before writing config, and before `uninstall` deletes anything.
- **Deletion does not follow links.** `remove_tree` refuses a root that is not a real directory, and unlinks symlinks inside rather than following them.
- **A memory's blob directory is derived from its id** and refused if the id could climb out of `blobs/`.

## What uninstall removes

Always the state directory, the cache directory, and `~/.local/bin/omoide` if it is still the plugin's own link. With `--purge`, also the data directory and `config.json`. It never touches the user's `bindings.lua`, their `shell.json`, or the plugin checkout.

## Adding a path

A new file goes under one of the four roots above, in the one whose lifetime matches: data for what the user would lose, state for what can be rebuilt, config for what they chose, cache for what can be recompiled. A new root, a path outside them, or a change to what `uninstall` removes needs approval.
