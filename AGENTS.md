# Repository guidance

Omoide is an Omarchy shell plugin. It has two halves, and every change belongs to one side of the seam between them:

- **QML** (`ui/`): the bar widget, the Space window, the dialogs. It never opens the database. It renders the index it pulls from `omoide index`, and it changes state only by running the CLI.
- **The CLI** (`cli/`): a C program that owns everything touching disk, including SQLite, blobs, the agent and its prompt, reminders and the index. `Service.qml` compiles it on the user's machine from `cli/build.rsp`, so no binary is committed and nothing is built into the plugin directory.

[`.agents/docs/index.md`](.agents/docs/index.md) is the map, and [the architecture reference](.agents/docs/reference/architecture.md) is where to start. A directory with its own `AGENTS.md` (`cli/`, `sql/`, `ui/common/`, `dev/`) holds the invariants for any edit there, and it loads when files there are read.

`.agents/` ships with the plugin, because `omarchy plugin add` is a plain clone. Nothing written under it names a machine, a user, or a secret.

## Guardrails

Prefer the simplest change that satisfies the requirement, and stop there. Three similar lines beat the wrong abstraction, a helper with one caller is premature, and adjacent code is not refactored inside a fix. When two designs look equally reasonable or the requirement is ambiguous, ask before writing code.

These are user-facing contracts. Changing one needs explicit human approval, and an agent cannot grant it to itself:

- the IPC functions on target `omoide`, which users bind in `bindings.lua`;
- `manifest.json`'s `id`, `entryPoints`, and `barWidget.schema` keys, which live in users' `shell.json`;
- a CLI subcommand, flag, JSON key, or exit code, added as much as changed or removed, which `dev/cli-surface.lock` records (see [the CLI contract](.agents/docs/reference/cli-contract.md));
- a new call that deletes, runs a program, or writes outside the plugin's own directories, which `dev/capabilities.lock` records;
- the database schema, `SCHEMA_VERSION`, `INDEX_VERSION`, or the shape of the index `omoide index` prints;
- any path the plugin reads, writes, or deletes, and the `uninstall` guard;
- an agent preset's sandbox flags, which only ever get stricter;
- the reply shape `cli/prompts/enrich.txt` asks for;
- a library, flag, or source layout in `cli/build.rsp`, and any new program the plugin runs.

`.claude/settings.json` makes Claude Code ask before it edits the CLI, the schema, the manifest, `ui/Service.qml`, CI, the checks that guard them, or itself, and before `git commit` or `git push`. Another harness does not read that file, so for it the locks and the owner's review are the gate.

Never add a dependency, runtime or development, without asking. If a change turns out to be breaking partway through, stop, summarize the impact, and wait.

Never create, amend, or push a commit unless asked for that exact action. Asking for a commit message is asking for text. A commit is one Conventional Commit per coherent change, `type(scope): summary` in lowercase, with the scopes `git log` already uses. A change to what users run also carries a changeset in `.changeset/`, titled `type(scope): what changed` and written by the `changesets` skill; the version is bumped only by the release pull request, which `release` owns.

## Skills

Load the skill that matches the task before starting it:

- `cli-command` to add or change a subcommand, and `parity-case` for the `dev/parity` case every CLI behavior change needs.
- `schema-migration` for any change under `sql/`.
- `agent-preset` for a change to how an agent CLI is run.
- `c-memory-safety` for sanitizer, fuzzer, or `-fanalyzer` findings, and before touching ownership in `cli/src`.
- `qml-component` to add, move, or restyle anything in the QML tree.
- `verify-in-shell` to see a change running in the live shell. Read it before restarting anything.
- `changesets` to write the changeset every change under `ui/`, `cli/`, `sql/` or to `manifest.json` carries, and `release` to bump the version or prepare a merge to `main`.
- `maintainability-review` for a deliberate cleanup or pre-merge pass.
- `agent-knowledge` to decide where rationale goes instead of a comment, and before adding or editing an `AGENTS.md` or anything under `.agents/`. `open-knowledge-format` owns the bundle's format rules.
- `diataxis-docs` for what kind of document something is, `evidence-first` for how work is reported to a human, and `unslop` for every piece of prose, comments and commit messages included.

## Standards

[The engineering standard](.agents/docs/engineering/code-style.md) owns the rules for C, QML, trust boundaries, comments and evidence. A directory contract never restates it.

Comments state a constraint at the line that needs it. History, rationale, and incidents go where the `agent-knowledge` skill says, and `dev/check-comments` flags the phrasing that gives them away.

## Working

`dev/check` is the gate, and a change is not done until it passes. It runs the docs check, the digest check, the comment check, the changeset check and self-test, `clang-format`, the QML type and lint checks, both compiler builds under `-Werror`, and `dev/parity`. `--no-cli` skips the C half for a QML or docs change, `--no-shell` the QML checks, and `--no-docs` the docs and digest checks. CI runs the C half through `.github/workflows/cli.yml`, adding `-fanalyzer`, parity under the sanitizers with both compilers, and a fuzz run whose length follows the trigger (short on a pull request, longer on `main`, longest in the weekly run), and the rest through `.github/workflows/check.yml`, which also fails a pull request that changes a user-facing file without a changeset; the QML checks need the Omarchy shell installed, so they run only locally.

A change to a file a reference concept under `.agents/docs/reference` lists in its `sources` fails the digest check until that concept is revisited. Read it, fix what the change made untrue, then run `dev/sync-docs`; the `agent-knowledge` skill owns the rule.

Format C with `clang-format -i`, never by hand. `-Werror` belongs in CI and `dev/check` only; a user's build must never fail over a warning a newer compiler learned to give.

A QML change is verified by running it in the shell, and the plugin watcher does not reload everything. Read `verify-in-shell` first. Type checks verify code, not behavior, so say which of the two a change had.

The subcommand list is `omoide --help`, the build is `cli/build.rsp`, and the schema is `sql/migrations/`. Point at these instead of copying them into prose.
