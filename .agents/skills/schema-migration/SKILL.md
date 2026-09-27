---
name: schema-migration
description: Change the SQLite schema by adding a migration under sql/migrations, embedding it in the CLI, bumping SCHEMA_VERSION, and proving the upgrade from every earlier version with dev/parity. Use for any new table, column, index or constraint, and before touching anything under sql/. Do not use for changes to the index `omoide index` prints, which is derived and versioned by INDEX_VERSION.
---

# Schema migration

A schema change needs approval before it is written. It changes what every user stores, and the only backup is the one the CLI takes on each user's own machine as it migrates. Read `sql/AGENTS.md` first.

## Steps

1. **Write the next file**, `sql/migrations/NNN-<subject>.sql`, numbered one past the highest. Plain statements only: the CLI wraps each migration in its own transaction and sets `user_version`. Never edit a migration that has shipped.
2. **Embed it.** Add its entry to the `MIGRATIONS` table in `cli/src/db.c`, and raise `SCHEMA_VERSION` in `cli/src/omoide.h` to match. The build fails on a mismatch.
3. **Use it in the code**, including `refresh_fts` in `cli/src/index.c` if the new column should be searchable.
4. **Prove the upgrade.** Load `parity-case`. At minimum, cover a fresh database, and a database seeded at each earlier version and then migrated, modeled on `migrate-from-v1`. Add a `seed_v<N>` alongside `seed_v1` for the version you are leaving. Every case whose rows or schema digest change is re-recorded, and its diff shows the new column and nothing else.
5. **Keep refusal working.** `migrate-schema-newer` must still exit 3 with the database untouched.
6. **Verify** with `dev/check` and `dev/parity --sanitize`, then `verify-in-shell` against a copy of a real database. Never test a migration on the user's own data directory.

A new column that QML shows usually also changes what `omoide index`, `list` or `show` prints; when the index changes shape, bump `INDEX_VERSION` and `indexVersion` in `Service.qml` together.
