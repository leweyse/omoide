---
type: Reference
title: Enrichment
description: How a capture reaches an agent, how each agent CLI is sandboxed, and how its reply is trusted.
sources:
  - id: enrich
    resource: ../../../cli/src/enrich.c
    title: The agent run, the sandbox flags, and reply validation
  - id: config
    resource: ../../../cli/src/config.c
    title: Provider presets and resolution
  - id: proc
    resource: ../../../cli/src/proc.c
    title: Running an agent in its own process group, capped
  - id: prompt
    resource: ../../../cli/prompts/enrich.txt
    title: The prompt and the reply shape it asks for
generated:
  by: anthropic/claude-opus-5-5
  at: '2026-09-26T00:00:00Z'
---

# Enrichment

Read this before changing a provider preset, a sandbox flag, the prompt, or how a reply is parsed. The agent sees content the user did not write, such as a web page on screen, and the presets are coding agents with a shell, so every rule here is a security rule first.

## The threat

A capture is a transcription of whatever was on screen. That can include a paragraph written to be read by whatever processes it next. The plugin assumes it will, and therefore:

- the prompt tells the model that OCR text and the image are data, not instructions;
- every preset runs with its tools off or read-only, in an empty working directory;
- the reply is parsed as data, bounded, and validated before anything is stored;
- no model-written text reaches a notification or a shell command unescaped.

The prompt is not the defense. It helps a well-behaved model; the sandbox and the validator are what hold against one that is not.

## Providers

`config.c` holds the presets and `resolve_provider` picks the configured one, only if its binary is on `PATH`. It never guesses a provider. `harden()` in `cli/src/enrich.c` adds each preset's own flag for no tools, a read-only sandbox, or deny-all permissions, and attaches the image with that CLI's own option when vision is on.

Some presets have no such flag and run as plain models. A `custom` command is stored as `sh -c` with the user's text and run exactly as written; the settings card tells the user to add their agent's own read-only flag. Adding a preset, or changing a flag, is a change to what an untrusted page can make a user's agent do. The `agent-preset` skill covers it, and a flag may only become stricter without approval.

## The run

- **Input.** The prompt goes on stdin, never in argv, so it stays out of `ps`. It carries the note, the OCR text or the image path, and the current time and zone.
- **OCR or vision.** By default the agent gets OCR text and the image stays on the machine. With vision on and a provider that accepts images, it gets the image instead.
- **Bounds.** The agent runs in its own process group with a timeout and a cap on output. Crossing either kills the whole group, since a wedged or flooding agent is a malfunction, not an answer.
- **The log gets names and lengths.** It records the program, the exit code and how much it printed, never the prompt, the reply, or a custom command line (D-016).
- **Failure is recorded, not raised.** A spawn error, a timeout, the cap, a non-zero exit, or a reply with no JSON sets `ai_status` to `failed` with a one-line reason. `commit` and `enrich` still exit 0, and the capture is kept.

## The reply

`extract_json` accepts one JSON object, directly, inside a common envelope key, or embedded in prose. `validate_blocks` then drops unknown and forbidden block types, bounds every text field and every list, keeps only `http` and `https` URLs, and blanks list headings that duplicate a block's own label. The limits are the constants at the top of `cli/src/enrich.c`.

When the agent creates no to-do, because there is none, it failed, or it replied with only events, a note that starts "remind me" still becomes a dated to-do through `parse_when` in `cli/src/dates.c`, which returns nothing rather than guess at a date it cannot read.

## What proves it

`dev/fuzz` runs the reply parser, the validator and the date parser under sanitizers. Parity has a `commit-ai-*` case per reply shape and per provider, and records the exact argv and stdin each agent was given, so a changed flag shows up as a diff.
