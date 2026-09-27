---
name: agent-preset
description: Add an agent CLI preset, or change how an existing one is invoked, sandboxed, given an image, or timed out. Covers the preset table, resolution, the hardening flags, vision support, the settings card's description of each restriction, and proving the exact argv with dev/parity. Use for any change to cli/src/config.c presets or to harden() in cli/src/enrich.c. Do not use for what the prompt asks for or how a reply is validated, which is the enrichment reference plus cli-command.
---

# Agent preset

Read [enrichment](../../docs/reference/enrichment.md) first. Capture content can carry text written to steer whatever reads it, and every preset is a coding agent with a shell, so the sandbox is the security boundary and the prompt is not.

## Rules

- **Stricter needs no approval; looser always does.** Removing a flag, widening a permission, adding a writable directory, or giving a preset tools it did not have is a security change for every user who picked it.
- **Use the agent's own flag,** from its current documentation or `--help`, not a flag remembered from another CLI. If it has none, the preset runs as a plain model and the settings card says so.
- **The prompt stays on stdin.** Never pass it in argv, where it shows in `ps`.
- **Vision is a claim about the CLI.** Add a provider to `provider_takes_image` in `cli/src/config.c` only when its CLI attaches a local image with an option you have run. That predicate, and `provider_is_plain_model` beside it, are the one place the rest of the CLI asks.

## Steps

1. Add or change the entry in the preset table in `cli/src/config.c`.
2. Add its hardening, and its image option if any, in `harden()` in `cli/src/enrich.c`.
3. Describe the restriction in the text `ai-config` returns for the settings card, in `cli/src/cmd_setup.c`.
4. Load `parity-case`. Add the agent to `STUBBED` if it is new, and add a `commit-<preset>` case, plus one with vision on if it takes images. The recorded call is the evidence: the case shows the exact argv, working directory, environment and stdin the agent received.
5. Run it once by hand against the real CLI with a harmless capture, and confirm from its own output that tools were off. Parity's stubs accept any flag in any order, so this is the only check that the flags work. Say in the handoff that you did it, or that you could not.
6. `dev/check`.
