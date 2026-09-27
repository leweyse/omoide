# cli

Read this before changing anything under `cli/`. This code is compiled on every user's machine by `Service.qml` from `build.rsp`, so a change here ships as source to a compiler you do not control. The C rules are in [the engineering standard](../.agents/docs/engineering/code-style.md#c); this file holds what binds an edit in this directory.

## Invariants

- **Every behavior change updates `dev/parity` in the same change.** That means what a subcommand prints, exits with, writes, logs, or runs. The affected fixtures are re-recorded and their diff reviewed, so the diff shows exactly what changed. Load the `parity-case` skill. A change that parity does not notice is either a pure refactor or a missing case.
- **`build.rsp` is the build.** A new source file is added there. A new library or flag in it is a new requirement on every user's machine and needs approval. `-Werror` never goes in it.
- **`INDEX_VERSION` and `indexVersion` in `Service.qml` change together.** Bump both, in one commit, whenever `build_index` changes the shape of what `index` prints. On a mismatch QML logs a warning and renders what it got, so a bump on only one side degrades silently.
- **A write ends by signalling `refresh`.** `shell_ipc(IPC_TARGET, "refresh", NULL)` is how the shell learns anything changed: it then pulls `index`. A write that skips it is invisible until the next unrelated change. Signal once per state worth showing, as the contract lists; `commit` and `enrich` signal before the agent runs as well as after.
- **`SCHEMA_VERSION` equals the number of embedded migrations**, which a static assertion enforces. Change it only through the `schema-migration` skill.
- **Embedded files count toward the build id.** The migrations, `prompts/enrich.txt` and `manifest.json` are compiled in with `#embed`. Embedding a file from any other path means adding that path to `cliSources` in `Service.qml`.
- **Untrusted text is bounded where it enters.** Capture content, agent replies and other programs' output are cleaned and capped once, in this directory, before storage. A new path for such text gets a fuzz entry point in `fuzz/fuzz_text.c`. Load the `c-memory-safety` skill.
- **Loose JSON readings land in stored rows.** `truthy`, `as_text`, `as_int`, `py_float` and `json_round4` shape values that reach the database and the log, and parity pins their exact output. Change one only with a parity case.
- **Nothing is written into the plugin directory at runtime.** Paths come from `paths()`; see [storage](../.agents/docs/reference/storage.md).

## Approval required

A subcommand, flag, output key or exit code that is removed or changes meaning; a path; a sandbox flag; a new program the CLI runs. See [the CLI contract](../.agents/docs/reference/cli-contract.md) and [enrichment](../.agents/docs/reference/enrichment.md).

## Verify

`dev/check` builds with gcc and clang under `-Werror` and runs parity. Before handing off a change to ownership or parsing, also run `dev/parity --sanitize` and `dev/fuzz`. CI adds `-fanalyzer` and a fresh-clone build.
