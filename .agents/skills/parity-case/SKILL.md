---
name: parity-case
description: Add or change a dev/parity case, the harness that pins every CLI behavior by running each invocation with a fixed clock, fixed ids and every external program stubbed, and comparing everything it did against a recorded fixture in dev/parity-cases. Covers choosing seeds, stubbing a program, recording a fixture, reviewing a fixture diff as the evidence for a behavior change, reading --dump, and running under sanitizers. Use for every change to what a subcommand prints, exits with, writes, logs or runs. Do not use for QML changes, which parity cannot see.
---

# Parity case

`dev/parity` is the CLI's behavioral contract. [The CLI contract](../../docs/reference/cli-contract.md) says what is promised, and the fixtures in `dev/parity-cases/` hold it, one JSON file per case. `dev/AGENTS.md` lists what is compared and what is not.

## How a case runs

Each entry in `CASES` is `(name, seeds, argv)`. The harness builds a fresh home, runs the seeds (CLI argv lists, or functions on the home such as `seed_library` or `write_config(...)`), runs `argv` once, and compares exit code, stdout, the index `omoide index` prints afterwards, `config.json`, every row, the log, the files left behind and every call to a stubbed program against `dev/parity-cases/<name>.json`. A case without a fixture fails, and so does a fixture without a case.

Every program the CLI might run is a stub from `STUBBED` that records its argv, stdin, working directory and environment. Add a program the CLI newly runs to `STUBBED`; an unstubbed program runs for real and makes the case depend on the machine.

## Add a case

1. Name it `<subcommand>-<situation>`, next to that subcommand's other cases. The name selects it: `dev/parity <filter>`.
2. Seed the smallest state that exercises the behavior, reusing an existing seed where one fits.
3. Run `dev/parity <name> --dump` and read what the CLI did. A case whose dump shows nothing interesting tests nothing.
4. Record it with `dev/parity --record <name>`, then read the new fixture. Recording writes down whatever the code does, correct or not, so the fixture is only as good as that reading.
5. Cover the failure path too: a missing record, a bad flag, a refused state. Exit codes are part of the contract.

## Change behavior

1. Change the code, then run `dev/parity` and read which cases fail. They are every case the change reaches; a case that fails and should not have is a bug, not a fixture to re-record.
2. Re-record exactly those with `dev/parity --record <filter>`.
3. Review the fixture diff with `git diff dev/parity-cases`. Every changed line must be one the change intended. That diff is the evidence for the change and belongs in the same commit.

Never re-record everything to make a run pass. A broad `--record` with no filter is for a deliberate, reviewed sweep, such as a change to the harness itself.

## Verify

`dev/parity` for the default compiler, `dev/parity --cc gcc` for the other, and `dev/parity --sanitize` before handing off anything that touches memory. CI runs all four combinations against the same fixtures.
