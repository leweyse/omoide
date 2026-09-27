---
name: agent-knowledge
description: Decide where a piece of knowledge lives in this repository and write it there, instead of in a code comment. Covers moving rationale and history out of comments, directory contracts (`AGENTS.md`), the decision register, open questions, the log, placement and filenames under `.agents/`, the register these documents are written in, and vendoring a skill into `skills-lock.json`. Do not use for the bundle's format rules (frontmatter, reserved files, provenance), which are `open-knowledge-format`, for what kind of document something is, which is `diataxis-docs`, or for how a result is reported to a human, which is `evidence-first`.
---

# Agent knowledge

`open-knowledge-format` owns how a document declares itself: frontmatter, `generated`, `sources`, reserved `index.md` and `log.md`, lifecycle fields, and the three severity tiers. This skill owns what is specific to this repository: where each kind of knowledge goes, how it is named, how it reads, and how a borrowed skill is tracked. `dev/check-docs --strict` enforces both, and CI fails on its warnings as well as its errors.

The bundle ships with the plugin. `omarchy plugin add` is a plain clone, so every file under `.agents/` lands on every user's machine. Never write a machine-specific path, a username, a token, or anything about a person into it; `dev/check-docs` rejects absolute home and runtime paths.

## Where knowledge goes instead of a comment

A code comment is for what a reader needs at that line. Everything else has a home:

| What it is | Where it goes |
| ---------- | ------------- |
| A constraint on one line or block that still holds | A one-line comment at that line, stating the constraint, not its history |
| A rule that binds every edit in a directory | That directory's `AGENTS.md` |
| How a part of the system works, across files | A concept under `.agents/docs/reference/` |
| A rule about how code is written | A standard under `.agents/docs/engineering/` |
| Why one design won over another | A row in [the decision register](../../docs/planning/decision-register.md) |
| Something that broke, and what it taught | A dated entry in [the log](../../docs/log.md) |
| Behavior the CLI must keep | A `dev/parity` case, and [the CLI contract](../../docs/reference/cli-contract.md) |
| Something unresolved | A row in [open questions](../../docs/planning/open-questions.md) |

A comment that says what the code used to do, which release changed it, or which bug prompted it is a log entry in the wrong file. Move it, and leave behind only the constraint it still imposes, or nothing. `dev/check-comments --strict` flags the phrasing. When a match states a constraint that genuinely needs its history to make sense, allowlist it in `dev/comment-allowlist` with the reason, rather than rewording it to slip past the pattern.

## Whether a document should exist

The default is not to create a file. A fact belongs in the concept that already owns its subject, updated in the same change as the code it describes. A decision is a register row. Something learned is a log entry. A procedure with a recognisable trigger is a skill. Never write a second document that restates a canonical one; both then drift.

Read [references/naming.md](references/naming.md) before adding, renaming, or moving a file, because a path is a concept's identity.

## Directory contracts

A directory's `AGENTS.md` holds the invariants that bind any edit in that directory, and nothing else. It opens with its trigger, names what may not change without approval, and points at the reference concept for how things work there. A sibling `CLAUDE.md` containing only `@AGENTS.md` makes Claude Code load it when files in that directory are read; `dev/check-docs` requires the pair.

## Skills

A skill lives at `.agents/skills/<name>/SKILL.md` and reaches Claude Code through the committed `.claude/skills` symlink. Its `description` decides whether it loads, so draft that first: trigger nouns, then explicit negative scope. Add `agents/openai.yaml` with a display name, a short description and a default prompt, so Codex lists it too. The root `AGENTS.md` routes to every skill; `dev/check-docs` fails on one it never names.

A skill owns a procedure. It points at the standard or contract that owns the rules it applies instead of restating them.

A skill copied from elsewhere is recorded in `skills-lock.json`: its source, the hash of the source `SKILL.md`, the hash of every file as it stands here, and each local adaptation. Its prose keeps its author's register, and `dev/check-docs` skips it. Changing a vendored file means recording the adaptation and updating its hash in the same change; the check fails on a hash that does not match, and on a file in the skill that the lock does not list.

## Register

Read [references/register.md](references/register.md) before writing or rewriting prose here. These documents are read by an agent deciding what to do next, so they are written as instructions: trigger first, the rule and its boundary in one sentence, and the tempting wrong move named out loud.

Two rules matter enough to repeat:

- **Say what owns what.** A sentence naming which document owns which half is what stops two documents drifting into the same territory.
- **Never state a value a file already defines.** A version, a count, a limit, a flag list: point at the source. A number written into prose is a promise to keep updating prose, and it is always broken.
