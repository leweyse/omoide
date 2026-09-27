# sql

Read this before adding or editing a file under `sql/migrations/`. Every user's database is at some version of this schema, and the CLI will migrate it the next time it opens it for writing. Load the `schema-migration` skill for the procedure.

## Invariants

- **A shipped migration is never edited.** Users whose database already ran it will not run it again, so an edit forks the schema between old and new installs. Change the schema with a new migration. That includes its comments: migrations are compiled into the CLI with `#embed`, so any byte changed alters the binary and its build id.
- **Migrations are numbered `NNN-<subject>.sql`, contiguous from `001`**, and each one is embedded in `cli/src/db.c` and counted by `SCHEMA_VERSION` in `cli/src/omoide.h`. The build fails if the count and the version disagree.
- **A migration runs inside the transaction the CLI opens for it.** It does not begin or commit its own, and it does not set `user_version`.
- **The search index is rebuilt by code, not by triggers.** A column that should be searchable is added to `refresh_fts` in `cli/src/index.c`, not to a trigger.
- **A newer database is refused, never downgraded.** A binary older than the schema exits 3 and touches nothing, so a migration needs no down script.

## Approval required

Every schema change. It changes what users store, and a backup is taken only on the machine that runs it.
