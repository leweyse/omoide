---
okf_version: '0.2'
---

# Omoide knowledge bundle

Navigation for everything under `.agents/docs`. Every document appears here once, with the clause that says when to read it. The `open-knowledge-format` skill owns the format of these files and the `agent-knowledge` skill owns where knowledge goes; no document here restates either.

## Start here

- [Repository guidance](../../AGENTS.md) — the router every session loads: guardrails, skills, and the gate.
- [Architecture](reference/architecture.md) — the two halves and the three channels between them. Every reference below assumes it.

## Engineering

- [Engineering house style](engineering/code-style.md) — the rules for C, QML, trust boundaries, comments and evidence, and the non-rules that stop each being over-applied.

## Reference

How the system works. Each page owns its subject; the directory contracts (`cli/AGENTS.md`, `sql/AGENTS.md`, `ui/common/AGENTS.md`, `dev/AGENTS.md`) hold the invariants and point here for the mechanism.

- [Omarchy host](reference/shell-host.md) — loading, reloading, surfaces, and the IPC functions users bind.
- [CLI contract](reference/cli-contract.md) — what each subcommand accepts, touches and returns, and the exit codes. `dev/parity` enforces it.
- [CLI build](reference/cli-build.md) — how `Service.qml` compiles the CLI on the user's machine, and what keeps QML and CLI from one checkout.
- [Storage](reference/storage.md) — every path, and what `uninstall` may delete.
- [Memory model](reference/memory-model.md) — memories, blocks, items, reminders, tags, collections and links.
- [Enrichment](reference/enrichment.md) — the agent run, each preset's sandbox, and how a reply is trusted.
- [Reminders](reference/reminders.md) — armed in the shell, fired once by the CLI.
- [Keyboard model](reference/qml-keyboard.md) — how the Space window routes keys, and the contract every page implements.

## Planning

- [Decision register](planning/decision-register.md) — what was settled and what each decision rules out. The source of truth for why the CLI is C, built locally.
- [Open questions](planning/open-questions.md) — what is still unresolved, and what would settle it.
- [Knowledge log](log.md) — newest-first record of what changed in this bundle and what was learned about the code.

## Outside the bundle

- [README](../../README.md) — for someone installing the plugin. Nothing here restates it.
