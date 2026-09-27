---
name: release
description: Prepare a change for users: write the commit message, check what an update does to an existing install, and cut a release. Covers `dev/changeset status` and `version`, the version pull request that bumps manifest.json's version and writes CHANGELOG.md, Conventional Commit messages with this repository's scopes, INDEX_VERSION and SCHEMA_VERSION consequences, and the README's update notes. Use when asked to bump the version, cut a release, write a commit message, or prepare a merge to main; the changeset file itself is `changesets`. Do not commit, amend, push or merge unless that exact action was asked for.
---

# Release

Users get a change through `omarchy plugin update leweyse.omoide`, a fast-forward pull, and see it after the next shell restart, which also rebuilds the CLI. Nothing else runs.

## Before a merge

1. `dev/check` passes, and the CI workflows would pass: `cli.yml` for anything under `cli/`, `sql/` or `cli/prompts/`, and `check.yml` for the rest, including its changeset gate.
2. Walk the update from the last release's state. A new migration upgrades the user's database on its first write. A changed `INDEX_VERSION` triggers one reindex. A new program the plugin runs has to be installed already, or the feature says so.
3. If the change needs anything from the user beyond a restart, update the README's install or update section. The README is written for someone installing the plugin, so it says what to do, not how the code works.

## The changeset

A branch that changes what users run carries a changeset in the same change. The `changesets` skill owns the file: when one is required, its name, its title and body, and the bump. Check what is pending with `dev/changeset status`, and what the gate will say with `dev/changeset status --since origin/main`.

Do not raise the version by hand in a feature branch. Two branches that each edit `version` conflict, and the one merged second releases the wrong number.

## How a release happens

`version` in `manifest.json` is the only version, and the CLI embeds it for `--version`, so a release also changes the CLI build. Nothing but `dev/changeset version` changes it.

On every push to `main`, `.github/workflows/release.yml` runs `dev/changeset version` on a branch named changeset-release/main, force-pushes it, and opens or updates one pull request titled `chore: bump version`. That command takes the highest pending bump, rewrites the `version` line of `manifest.json` and nothing else, prepends a dated section to `CHANGELOG.md` grouped by Major, Minor and Patch, and deletes the changesets it consumed. With only `none` changesets pending it changes nothing, so no pull request opens.

Merging that pull request is the release, and every user gets it on their next update. It needs the user's say-so, like any user-visible release, so hand over the pull request and wait; never merge it on an agent's own judgment. Before asking, read its diff: the new version should be the one the changesets justify, and each changelog line should read well to someone who has never seen the code.

Two repository facts the workflow depends on:

- The setting "Allow GitHub Actions to create and approve pull requests", under the repository's Actions settings, must be on, or `gh pr create` is refused.
- A pull request opened with `GITHUB_TOKEN` starts no other workflow, so `check.yml` and `cli.yml` do not run on the version pull request. Its diff is only the version line, the changelog and deleted changesets, all of which ran through CI on the pull requests that added them. To see CI on it anyway, close and reopen it.

To preview a release locally, run `dev/changeset status`. Running `dev/changeset version` on a working branch rewrites files the workflow owns; discard those changes afterwards.

## The commit message

One Conventional Commit per coherent change: `type(scope): summary`, lowercase, no trailing period. The types are the ones `TYPES` in `dev/changeset` accepts, so a commit and its changeset share a vocabulary. Scopes name the part of the product, and `git log --format=%s` shows the ones in use, such as `cli`, `space`, `library`, `ui`, `security`. The summary says what is true after the change, not what was done. The changeset and the commit message describe the same change for two readers: the commit for whoever reads the history, the changeset for whoever updates the plugin.

Write the message and hand it over as text. Committing, amending and pushing each need their own explicit request, and before an authorized amend or history rewrite, run `git log` first, because the repository is also edited outside the session.
