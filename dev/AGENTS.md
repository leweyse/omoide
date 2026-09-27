# dev

Read this before changing a check, or before trusting one as evidence. Each script here proves a specific thing and nothing more, and a green run of the wrong one is not evidence for the claim at hand.

| Script | Proves | Does not prove |
| ------ | ------ | -------------- |
| `check` | every check below that applies passed, plus `clang-format` and both compiler builds under `-Werror` | anything a skipped step covers; it prints what it skipped |
| `parity` | each case's exit code, stdout, the index `omoide index` returns afterwards, `config.json`, rows, log, files and every program call match its recorded fixture in `parity-cases/` | stderr wording, `XDG_*` overrides, the cache and `~/.local/bin`, or how a real agent CLI treats its flags |
| `parity --sanitize` | the same cases run clean under ASan and UBSan | paths no case exercises |
| `fuzz` | the untrusted-text parsers do not crash or trip a sanitizer on mutated input | that their output is correct, or anything past the fuzz input size |
| `check-types` | every QML type name resolves against its file's own imports | properties, signals, or behavior |
| `check-docs` | the knowledge bundle is well formed, its links and paths resolve, vendored skills match the lock, every `AGENTS.md` has its `CLAUDE.md` | that a claim in a document is true |
| `check-comments` | no code comment uses the phrasing of history or port rationale | that a comment is needed, or right |

## Invariants

- **Python here, and nowhere a user runs.** These scripts use only the standard library; a new import from outside it is a new development dependency and needs approval.
- **A check fails loudly.** A check that cannot run, because a tool or the shell is missing, reports failure or states that it skipped. It never passes by doing nothing.
- **A fixture changes only with the code that changes it.** `parity --record` rewrites fixtures from whatever the CLI does, so a re-recorded fixture is reviewed line by line in the same change. A fixture with no case, or a case with no fixture, fails the run.
- **`comment-allowlist` entries carry their reason.** An entry that no longer matches anything fails `check-comments`, so the list cannot rot.
- **A check is a script, not a recipe.** A verification worth repeating becomes a script here, run from `check` if it is fast enough.
