# Register

How prose in this bundle, and in a code comment, is written. These documents are read by an agent deciding what to do next, so they are written as instructions rather than as description. The examples are real text from this repository, before and after.

## R1 — Open with the trigger, not the identity

A reader arriving at a document needs to know whether to keep reading before they need to know what the thing is. A contract opens with "Read this before changing anything under `cli/src`", not with "The CLI is written in C".

## R2 — Attach the boundary to the rule, in the same sentence

A prohibition with no stated exception is over-applied until someone decides the whole rule is wrong. "Run programs through GSubprocess with an argv; the one `sh -c` is the user's own custom agent command, which is stored and run as written" is a rule an agent can apply. "Never use a shell" is not.

## R3 — Name the tempting wrong move

Most rules here exist because something went wrong first. Write the sentence that would have stopped it, including the loophole.

> Bumping `INDEX_VERSION` without touching this line was enough to trigger it.

is the loophole, stated at the only place it bites. The rule it implies is a contract item: `INDEX_VERSION` in `cli/src/omoide.h` and `indexVersion` in `Service.qml` change together, in one change.

## R4 — Keep the constraint, drop the history

A comment that tells the story of how the code arrived imposes nothing on the next edit.

> The bar mark used to light on openTodoCount > 0, which counts what exists rather than what is owed -- a single to-do due in October kept it lit through August and September, so it never changed and never told anyone anything.

becomes, at the line,

> Lit by what is owed today, not by what exists: open to-dos due before local midnight, overdue included.

and the October story becomes a log entry, if it is still worth telling. If the code has changed so that no reader could reintroduce the old behavior by accident, the story is deleted outright.

## R5 — Replace conflict resolution with ownership

A rule for picking a winner guarantees the same rule is written twice. "The standard owns the rules; a directory contract owns that directory's invariants and does not restate a standard. A contradiction between the two is a defect in one of them: report it instead of picking a winner."

## R6 — Link by title, never by section number

`AGENTS.md §5` breaks silently the first time a section is added. Link to a named heading, or to the skill that owns the subject.

## R7 — Retire emoji as prose syntax

Write the constraint into the verb. Past four related rules, use a table with a column saying why each holds. A marker is fine where it labels rather than argues, such as the two halves of a contrasting code example.

## R8 — Bold at most once per section

Four bolded phrases in six lines is no emphasis at all.

## R9 — A derivable artifact becomes the command that derives it

The subcommand list is `omoide --help`. The build argv is `cli/build.rsp`. The schema is `sql/migrations/`. Point at these rather than pasting them, because a pasted copy is stale on the next change.

## R10 — Mark superseded, never orphan

A document left looking current is worse than a deleted one. `status: deprecated` plus an index line naming what replaced it.

## R11 — Draft the frontmatter `description` first

For a skill it is the only thing deciding whether the skill loads: trigger nouns first, then explicit negative scope.

## R12 — An em dash that joins two clauses becomes two sentences

Keep the dash where it labels: after a bolded term in a bullet (`- **Name** — what it is`), in a table cell, as a heading qualifier. Keep it out of running prose. The same holds for the `--` a code comment uses as a dash. `dev/check-docs` counts the prose case.

## R13 — Sentence case in every heading

`## Build on the user's machine`, not `## Build On The User's Machine`.

## R14 — Name the actor

"`Service.qml` builds the CLI on load", not "the CLI is built on load". Passive is for the case where the actor is genuinely unknown or does not matter.

## R15 — Instructions address no one

"Add the source file to `cli/build.rsp`", not "you should add the file". Write the imperative, or name the thing that acts.

## R16 — A vendored file keeps its author's register

`skills-lock.json` records the hash of every file copied from another repository, so a rewrite shows up as a divergence rather than an improvement. `dev/check-docs` skips their prose.

## R17 — A domain's own word is not a tell

Quickshell calls a Wayland layer a `PanelWindow` and Omarchy calls a plugin's bar part a widget. Check what the domain already calls the thing before replacing the word.
