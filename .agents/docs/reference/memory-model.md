---
type: Reference
title: Memory model
description: Memories, blocks, items, reminders, tags, collections and links, as stored and as rendered.
sources:
  - id: schema
    resource: ../../../sql/migrations/001-initial.sql
    title: The initial schema
  - id: items
    resource: ../../../cli/src/items.c
    title: Creating items and their reminders
  - id: index
    resource: ../../../cli/src/index.c
    title: How the model is projected into the index
  - id: renderer
    resource: ../../../blocks/BlockRenderer.qml
    title: Which QML renders which block type
generated:
  by: anthropic/claude-opus-5-5
  at: '2026-09-26T00:00:00Z'
---

# Memory model

Read this before adding a block type, an item field, or anything that decides what an agent may create on its own. `sql/migrations/` is the schema; this page explains the rules the schema cannot express.

## A memory

A memory is one capture: a title, a lede, the OCR text of its image if it has one, and an ordered list of blocks. It moves through `draft`, created by `capture`, to `ready`, set by `commit`. A draft the user abandons is removed by `discard`, or by `sweep` once it is old enough. `ai_status` records the agent run separately (`none`, `pending`, `ok`, `failed`), so a failed run never loses the capture.

## Blocks

A block has a type, a JSON payload, a position, an origin and an `edited` flag.

- **Origin says who wrote it.** `capture` blocks are the image, `user` blocks are the note, and `ai` blocks came from the agent.
- **`edited` protects a correction.** Editing a block sets it, and `enrich` replaces only AI blocks that are unedited. A user's fix survives a re-run.
- **The agent may write only the types it is asked for.** The list is in `prompts/enrich.txt`, and `validate_blocks` in `cli/src/enrich.c` drops anything else. The `note` and `image` types belong to the capture and are never accepted from an agent.
- **Every type needs a renderer.** `blocks/BlockRenderer.qml` maps a type to its QML, and `KNOWN_BLOCKS` in `MemoryModel.js` decides what is renderable. A type the CLI can store and QML cannot render is invisible, not an error.

Adding a block type touches the prompt, the validator, the renderer and a parity case, and changes what an agent writes into users' databases. It needs approval.

## Items

Items are the to-dos and events a memory holds, referenced from a `todos` or `event` block.

- **Inferred is not told.** An item the agent inferred rather than read as an instruction arrives with status `suggested` and no alarm. It becomes `active` only when the user accepts it with `item promote`. An event is always active.
- **Titles are cleaned and bounded** when created, whoever wrote them.
- A dated event with no requested alarm gets a default one before it starts. An inferred to-do gets none until promoted, and an explicit dated to-do gets one at its due time.
- A to-do is completed, reopened or cancelled through `item`; a cancelled item is hidden from every view but kept.

## Reminders

A reminder belongs to an item. It is either absolute, at a fixed time, or relative, an offset from the item's time that is recomputed when the item is rescheduled. An item carries a bounded number of reminders, and so does a memory. How one fires is in [reminders](reminders.md).

## Tags, collections and links

- **Tags** come from the agent and filter the library.
- **Collections** and **links** are the user's own. Nothing infers them. `collection add` creates the collection if needed; a link is stored once per pair and read in both directions.

## What QML sees

The index `omoide index` prints carries counts, open to-dos, suggestions, upcoming events, collections, today's digest, and the live alarms. It carries no memory cards: the library and a collection page load theirs a page at a time with `list` or `search`, through `components/PagedMemories.qml`, and their chips come from `facets`. A detail page asks for links and block bodies with `show` and `related`. Each list in the index is capped in `build_index`, so a view must not treat the length of one as the total; `memoryCount` and a page's `pageInfo.total` are totals.
