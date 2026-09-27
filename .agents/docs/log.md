# Omoide knowledge log

## 2026-09-26

- **Established the knowledge bundle** — A root `AGENTS.md` router, directory contracts for `cli/`, `sql/`, `common/` and `dev/`, an engineering standard, eight reference concepts, a decision register and an open-questions register. Skills load from `.agents/skills` through a committed `.claude/skills` symlink. `evidence-first`, `diataxis-docs` and `open-knowledge-format` are vendored from pmndrs/glyph and `unslop` from the Claude Code user skill, each hash-locked in `skills-lock.json`.

- **Made the knowledge enforceable** — `dev/check` runs every gate and is what a change must pass. `dev/check-docs` validates the bundle and fails on warnings under `--strict`, and `dev/check-comments` flags comments that narrate history. CI runs the C half in `.github/workflows/cli.yml` and the docs, comment and format half in `.github/workflows/check.yml`; the QML checks run only locally (D-015).

- **Recorded the C port** — The CLI moved from Python to C, built on the user's machine. The alternatives that lost and the four intentional behavior changes are D-001 and D-002.

- **Pinned CLI behavior with recorded fixtures** — `dev/parity` compares each case against `dev/parity-cases/<name>.json`, recorded from the C CLI at the point where it matched the Python CLI case for case. A behavior change re-records the cases it touches, and its fixture diff is the evidence. The schema is stored as a digest, since it is the same in nearly every case (D-014).

- **Formatted the C sources with `clang-format`** — The configuration in `.clang-format` was tuned against the hand-formatted code to change the fewest lines, and the binaries built before and after were byte-identical under both gcc and clang (D-008).

- **Brought qmllint to zero** — Pointed at the shell's `qs` modules it resolves every import. What remained was thirteen unused imports and a `blockId` property `SummaryBlock.qml` redeclared from `BlockCard.qml`, all removed. Four categories stay off because QML cannot answer them statically here (D-009).

- **Moved rationale out of the comments** — Every code comment now states a constraint that holds; history, incidents and port rationale were cut or moved here and into the registers, and no code changed with them. Comments that were wrong about the code were corrected on the way, among them a capture said to be cancelled with `pkill slurp` when the CLI refuses it with a lock, node unit tests that do not exist, and an event said to get no alarm when every dated event gets a default one.

- **Made the log keep its own policy** — `omoide.log` records names, ids, counts and lengths, never captured text, an agent's output, or a command line the user typed. What a failing agent said reaches the user through `ai_error` on the memory (D-016).

- **Fixed four behaviors that contradicted their own description** — `install` no longer claims a rollback it does not do. The "remind me" fallback runs whenever the agent creates no to-do, so an event-only reply no longer swallows the reminder; `commit-ai-event-only-reminder` pins it. `memoryCount` counts every ready memory rather than the capped card list. A stalled enrichment carries a reason on the memory.

- **Gave one rule one home** — The providers that take an image and the plain models are one pair of predicates in `cli/src/config.c`. `MAX_TITLE` and `MAX_REMINDERS` live once in `cli/src/omoide.h`, beside a named tag cap, and the commit pidfile has one builder. In QML, every page scrolls through `common/PageWheel.qml`; the collection page had lacked the handler the others copied, which is why its scroll felt slower. `Service.qml` derives its paths with the same absolute-only rule as the CLI.

- **Confirmed codex honors its sandbox flag after the positional** — `codex exec --skip-git-repo-check - -s bogus` fails on the invalid sandbox mode in codex-cli 0.156.1, so flags placed after `-` are parsed and the preset's `-s read-only` takes effect.

- **Recorded why the index version is checked once** — Reindexing on every `index.json` version mismatch loops when the QML does not know the CLI's version: reindex, the watcher fires, mismatch, reindex. `applyIndex` reindexes once and then renders the stale file, which is why `INDEX_VERSION` and `indexVersion` change together.

- **Recorded why a capture is detached** — A capture run as a tracked `Process` died when a plugin reload destroyed its QML object, which killed the region picker mid-selection and left the screen frozen. Captures run through `Quickshell.execDetached`, and the CLI reports back over IPC.

- **Recorded why agent settings are their own surface** — Running `setup-ai` through gum in a terminal opened an empty window, because xdg-terminal-exec's `-e` kept the binary and dropped the subcommand. `surfaces/SettingsDialog.qml` is owned by the service rather than the Space window, so it opens without Space.

- **Recorded the binding-order trap the Space pages share** — Reading a binding such as `regionName` or `orderedBlocks` inside the change handler of the property it depends on can return the previous value, because Qt does not order a binding's update against that property's own handler. Every page resolves through an explicit function of the new value instead, and the horizontal rows compute their scroll bounds from `originX` in a function for the same reason.

- **Recorded why focus borders ignore the kit's focus style** — `Border.controlSpec("focus")` applies the shell-wide `focusBorderAlpha`, which makes a focused control hard to tell from an unfocused one. Every focusable primitive in `common/` draws its focus border with `Border.flat` at full accent strength; `common/AGENTS.md` holds the rule.

- **Recorded why a surface handles Enter once** — The host's `PanelKeyCatcher` emits both `returnRequested` and `activateRequested` for one Enter, so `dialogs/ActionMenu.qml` handles only the second, or every entry would run twice.
