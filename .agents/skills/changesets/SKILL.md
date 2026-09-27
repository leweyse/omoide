---
name: changesets
description: Write and place a changeset for a change users will run. Covers when one is required, the three-word filename, the `type(scope): what changed` title, the plain-language body, choosing the bump, and splitting one changeset per logical change. Use before committing a change under `ui/`, `cli/` or `sql/` or to `manifest.json`, when asked for a changelog entry, or when the changeset gate in CI fails. Do not use for release mechanics, the version pull request, or commit messages, which are `release`.
---

# Changesets

A changeset is read by people who never saw the diff: someone deciding whether to update the plugin, or reading what an update changed. Its title and body land verbatim in `CHANGELOG.md`. Say what changed for someone using Omoide; the pull request carries the mechanics.

This skill owns the file: its name, its bump, its title and its body. `release` owns what happens to it afterwards, and the root `AGENTS.md` owns what needs approval. **The bump follows the title's type:** a `feat` is `minor`, and every other type is `patch`, or `none` when a user notices nothing. `major` is never an agent's call: a change that would break an existing install needs the user's decision first, and the bump comes with it.

## When one is required

Every change to a file under `ui/`, `cli/` or `sql/`, or to `manifest.json`, carries a changeset in the same change. The usage text of `dev/changeset` lists what does not count, and the gate in `check.yml` fails a pull request that changed a counted file without adding one. A change a user would not notice, such as a refactor or a test, carries an empty changeset, `pnpm changeset --empty`, which is how the gate knows it was considered.

## Before writing

1. Read one or two files in `.changeset/`, or the latest section of `CHANGELOG.md`, to match the current voice.
2. Decide how many changesets the branch needs. See the last section.

## Write it with the changesets CLI

```sh
pnpm changeset            # asks for the bump and the summary, and names the file
pnpm changeset --empty    # a change users will not notice
dev/changeset status      # holds every pending changeset to the rules below
```

The changesets CLI writes the frontmatter, `"omoide": <bump>`, and a random three-word name; the summary it asks for is the title below, and a body can follow it in the file. It knows nothing of this repository's rules, so `dev/changeset status` checks the title and that the bump suits its type, and CI runs it on every pull request. A file written by hand in the same shape is just as good.

## Name the file with three words

<!-- check-docs: examples -->

`.changeset/<adjective>-<noun>-<verb>.md`, such as `bright-waves-flow.md` or `happy-lions-jump.md`. `add` picks one.

Never a descriptive slug. `fix-badge-count.md` looks helpful and is not: the filename is deleted at release time, and a descriptive name invites a second changeset for "the same" topic instead of one per logical change.

## Title

`<type>(<scope>): <what changed>`, with a type from `TYPES` in `dev/changeset`, which also refuses any other. Never drop the type. The scope names the part of the product a user would recognise, comma-separated when there is more than one: `fix(tasks,bar): …`. Use the scopes `git log --format=%s` already shows, such as `library`, `space`, `tasks`, `bar`, `capture` and `cli`. Leave the scope out only for a change that reaches every part of the plugin.

- A `fix` title states the problem that was happening, not the repair: "the open to-do count stops at 200", not "count to-dos in SQL".
- A `feat` title states what a user can now do: "tasks load as you scroll, however many there are".

Present tense, lowercase after the colon, no trailing period.

Most changesets are the title and nothing else:

```markdown
---
"omoide": patch
---

fix(space): a library saved by a newer Omoide opens as an empty page
```

## Bump

The type decides it, and `dev/changeset` refuses a pair that does not match:

| Type | Bump |
| ---- | ---- |
| `feat` | `minor`: something new a user can do or see |
| `fix` | `patch`: a problem that was happening no longer does |
| `refactor`, `docs`, `chore` | `patch` when a user sees the same thing working better; an empty changeset when they notice nothing, whose title is optional and never reaches the changelog |
| any, with the user's decision | `major`: an existing install breaks or loses something, such as a renamed IPC function, a removed `barWidget.schema` key, a CLI flag or JSON key gone, or a migration that drops data. Each is a guardrail in the root `AGENTS.md` |

A title that fits `feat` but reads like a fix is a sign the type is wrong, not the bump: pick the type from what changed for the user, and the bump follows.

## Body

Add one only when something is left to say. If the title carries it, stop at the title.

```markdown
---
"omoide": minor
---

feat(tasks): tasks and events load as you scroll, however many there are

The badge on the bar and the tab counts now count every open to-do.
```

A body is short but names the surface it affects, so a reader can tell whether it touches them. Several changes in one changeset go in bullets, one per change:

```markdown
---
"omoide": patch
---

fix(space): polish after the paging change

- Library: cards stay in place while the next page loads
- Tasks: the tab count matches the list
- For you: the events row keeps its borders while it scrolls
```

## Keep out of the body

File paths, function and property names, error strings, SQL, and how the fix works. They belong in the pull request description; in a changelog they read as noise to everyone who was not reviewing the diff.

## One changeset per logical change

Unrelated changes get separate files. Two bug fixes that happen to ship together are two changesets.

A branch that fixes several things in the same part of the product is one logical change and takes one changeset, with a bullet per fix. Split it only where a split says something the merged note cannot: a different bump, or a `feat` that a `fix` title would have to swallow. Ten notes naming ten symptoms of one body of work are the same noise as one note bundling ten unrelated changes.
