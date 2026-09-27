# dev

Read this before changing a check, or before trusting one as evidence. Each script here proves a specific thing and nothing more, and a green run of the wrong one is not evidence for the claim at hand.

| Script | Proves | Does not prove |
| ------ | ------ | -------------- |
| `check` | every check below that applies passed, plus `clang-format` and both compiler builds under `-Werror` | anything a skipped step covers; it prints what it skipped |
| `parity` | with only the stubs and `REAL` on `PATH`, each case's exit code, stdout, the index `omoide index` returns afterwards, `config.json`, rows, log, files and every program call match its recorded fixture in `parity-cases/` | stderr wording, `XDG_*` overrides, the cache and `~/.local/bin`, or how a real agent CLI treats its flags |
| `parity --sanitize` | the same cases run clean under ASan and UBSan | paths no case exercises |
| `fuzz` | the untrusted-text parsers do not crash or trip a sanitizer on mutated input | that their output is correct, or anything past the fuzz input size |
| `check-types` | every QML type name resolves against its file's own imports | properties, signals, or behavior |
| `check-docs` | the knowledge bundle is well formed, its links and paths resolve, mirrored skills match the lock, every `AGENTS.md` has its `CLAUDE.md` | that a claim in a document is true |
| `sync-docs --check` | every reference concept's `source_digest` matches the files its `sources` name | that the document still describes those files; only a reader can tell |
| `changeset` | every pending changeset has a `type(scope): what changed` title and a bump that suits its type, and `--since <ref>` finds a changeset added wherever a user-facing file changed since the merge base; `selftest` runs both in throwaway repositories | that the bump is the right one or the title true; writing and applying changesets is the changesets CLI's |
| `sync-version` | `manifest.json`'s version equals `package.json`'s (`--check`), or makes it so | that the version is the one the changesets justify |
| `cli-surface` | the CLI's subcommands, aliases, flags (hidden ones too), the verbs parity runs, their output keys and exit codes match `cli-surface.lock` | that a change to the surface was approved; the lock diff is what the owner reviews |
| `capabilities` | every call in `cli/src` that deletes, runs a program, writes outside the database or reaches the network matches `capabilities.lock`, by file and function | a harmful call through a wrapper whose name the tool does not list, or what the call does with its arguments |
| `check-comments` | no code comment uses the phrasing of history or port rationale | that a comment is needed, or right |

## Invariants

- **The changesets CLI is the one Node dependency.** It lives in `package.json`'s devDependencies, installed with `pnpm install`, and only writes and applies changesets; every check here stays Python.
- **Python here, and nowhere a user runs.** These scripts use only the standard library; a new import from outside it is a new development dependency and needs approval.
- **A check fails loudly.** A check that cannot run, because a tool or the shell is missing, reports failure or states that it skipped. It never passes by doing nothing.
- **A fixture changes only with the code that changes it.** `parity --record` rewrites fixtures from whatever the CLI does, so a re-recorded fixture is reviewed line by line in the same change. A fixture with no case, or a case with no fixture, fails the run.
- **`comment-allowlist` entries carry their reason.** An entry that no longer matches anything fails `check-comments`, so the list cannot rot.
- **A check is a script, not a recipe.** A verification worth repeating becomes a script here, run from `check` if it is fast enough.
