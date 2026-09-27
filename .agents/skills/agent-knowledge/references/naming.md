# Naming and placement

The bundle-relative path without `.md` is a document's identity. Moving a file renames the concept and breaks every link to it, so a path is chosen once and then left alone.

## Filenames

<!-- check-docs: examples -->

Lowercase kebab-case, `.md`, naming the subject rather than the genre: `cli-contract.md`, not `cli-contract-reference.md`. The type lives in frontmatter; the folder is the scope. A genre suffix appears only to separate two documents about the same subject.

| Kind | Pattern | Example |
| ---- | ------- | ------- |
| Concept | `<subject>.md` | `reference/storage.md` |
| Concept about one part | `<part>-<subject>.md` | `reference/cli-contract.md` |
| Decision record | a row in `planning/decision-register.md`; `NNNN-<subject>.md` zero-padded only when one needs its own argument | `planning/0001-c-cli.md` |
| Skill | `<name>/SKILL.md`, directory equal to frontmatter `name` | `skills/parity-case/SKILL.md` |
| Skill reference | `references/<subject>.md` | `skills/agent-knowledge/references/register.md` |
| Directory contract | exactly `AGENTS.md`, with a sibling `CLAUDE.md` | `cli/AGENTS.md` |
| Reserved | `index.md`, `log.md` | never concepts |

The part prefixes in use are `cli-`, `qml-`, and `shell-` for the Omarchy host. A document that belongs to no single part takes no prefix and names every part it spans in `sources`.

## Directories

The directory says what kind of reading a document is. It never encodes maturity: a design that ships does not move from `planning/` to `reference/`, it loses `status: draft` and stays put.

| Directory | Holds |
| --------- | ----- |
| `engineering/` | rules that constrain how code here is written |
| `reference/` | how the system works: contracts, data flow, the seams between QML, the CLI and the host |
| `planning/` | the working record: decisions, open questions, findings, and disposable plans |

Do not create a directory before its first occupant exists. A task-shaped walkthrough, when the first one is written, starts `guides` this way.

## Lifecycle

| State | Marker | Moves? |
| ----- | ------ | ------ |
| Current | no `status`, or `status: stable` | no |
| In progress | `status: draft` | no |
| Superseded | `status: deprecated` plus an index line naming the replacement | no |
| Disposable | an `Implementation Plan` stating its own deletion condition | deleted when the condition is met |

A finding records an observation and the date it held. A perishable one carries `stale_after`, and past that date it is asking to be re-verified rather than trusted.
