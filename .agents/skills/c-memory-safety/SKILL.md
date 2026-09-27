---
name: c-memory-safety
description: Keep the C CLI memory-safe and bounded. Covers ownership with g_autoptr and json-c references, running dev/parity under ASan and UBSan, adding a fuzz entry point and seeds for a new untrusted-text path, and responding to a sanitizer, fuzzer or gcc -fanalyzer finding. Use before changing ownership, parsing, or anything that reads another program's output, and whenever one of those tools reports something. Do not use for a behavior change with no memory aspect, which is cli-command.
---

# C memory safety

The ownership rules are in [the engineering standard](../../docs/engineering/code-style.md#c). This skill is the procedure for proving them.

## Before changing ownership or parsing

- Trace every allocation in the function to its release: `g_autofree` or `g_autoptr` in scope, `g_steal_pointer` on the way out, or an explicit handoff that `cli/src/omoide.h` documents.
- For json-c, remember that adding an object to another transfers the reference. A value kept in two places needs `json_object_get`.
- Every read of outside data has a bound: a byte cap on process output, a character cap on text, a count cap on lists. Find the named constant, or add one beside the code.

## Prove it

1. `dev/parity --sanitize` and `dev/parity --sanitize --cc gcc`. Every case runs under ASan and UBSan, and a leak or undefined operation fails the case.
2. `dev/fuzz` for a minute, or `dev/fuzz 600` after a parser change. It exercises the reply parser, the block validator, the date parser and the text cleaners.
3. `gcc @build.rsp -Werror -fanalyzer -o /dev/null` from `cli/`, which CI also runs.

## A new path for untrusted text

Add a call to it in `cli/fuzz/fuzz_text.c`, with the input repaired to UTF-8 first as the real caller does it, and add a seed to the corpus in `dev/fuzz` that reaches the new code. A path the fuzzer cannot reach is unproven.

## A finding

Reproduce it first: the fuzzer writes a crash file, and a sanitizer names the case. Fix the cause, not the report. Silencing an analyzer warning with a cast or an assertion that cannot fail in production hides the next real one. Add the reproducer as a parity case or a fuzz seed so it stays fixed, and record anything the fix taught in [the log](../../docs/log.md).
