---
type: Question Register
title: Open questions
description: What is unresolved, what it affects, and what would settle it.
tags: [questions, governance]
sources:
  - id: dispatch
    resource: ../../../cli/src/main.c
    title: The subcommands the CLI offers
generated:
  by: anthropic/claude-opus-5-5
  at: '2026-09-26T00:00:00Z'
---

# Open questions

What is still unresolved. Settle one by fixing it with a parity case, or by recording why it stays in [the decision register](decision-register.md), then delete it here; [the log](../log.md) records how it was settled.

## Unused surface

- [ ] No QML file calls `block delete`, `collection new` or `collection remove`, `reminder add --offset`, `item --notes`, or `memory --lede`. Are they kept for scripts, or unused? Removing one is a breaking change to the CLI contract.
