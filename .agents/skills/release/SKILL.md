---
name: release
description: Prepare a change for users: bump the plugin version, write the commit message, and check what an update does to an existing install. Covers manifest.json's version, Conventional Commit messages with this repository's scopes, INDEX_VERSION and SCHEMA_VERSION consequences, and the README's update notes. Use when asked to bump the version, write a commit message, or prepare a merge to main. Do not commit, amend or push unless that exact action was asked for.
---

# Release

Users get a change through `omarchy plugin update leweyse.omoide`, a fast-forward pull, and see it after the next shell restart, which also rebuilds the CLI. Nothing else runs.

## Before a merge

1. `dev/check` passes, and the CI workflows would pass: `cli.yml` for anything under `cli/`, `sql/` or `cli/prompts/`, and `check.yml` for the rest.
2. Walk the update from the last release's state. A new migration upgrades the user's database on its first write. A changed `INDEX_VERSION` triggers one reindex. A new program the plugin runs has to be installed already, or the feature says so.
3. If the change needs anything from the user beyond a restart, update the README's install or update section. The README is written for someone installing the plugin, so it says what to do, not how the code works.

## The version

`version` in `manifest.json` is the only version, and the CLI embeds it for `--version`. Bump it in its own commit, `chore: bump version`, as the history does. Bumping it is a user-visible release and needs the user to ask for it.

## The commit message

One Conventional Commit per coherent change: `type(scope): summary`, lowercase, no trailing period. Types are `feat`, `fix`, `refactor`, `docs` and `chore`. Scopes name the part of the product, and `git log --format=%s` shows the ones in use, such as `cli`, `space`, `library`, `ui`, `security`. The summary says what is true after the change, not what was done.

Write the message and hand it over as text. Committing, amending and pushing each need their own explicit request, and before an authorized amend or history rewrite, run `git log` first, because the repository is also edited outside the session.
