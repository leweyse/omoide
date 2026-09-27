---
name: release
description: Prepare a change for users: write the commit message, check what an update does to an existing install, and cut a release. Covers `pnpm version-packages` and `pnpm release`, the version pull request the changesets GitHub Action opens to bump package.json's and manifest.json's version and write CHANGELOG.md, Conventional Commit messages with this repository's scopes, INDEX_VERSION and SCHEMA_VERSION consequences, and the README's update notes. Use when asked to bump the version, cut a release, write a commit message, or prepare a merge to main; the changeset file itself is `changesets`. Do not commit, amend, push or merge unless that exact action was asked for.
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

`version` in `manifest.json` is what Omarchy shows and the CLI embeds for `--version`, so a release also changes the CLI build. `package.json` carries the same version for the changesets CLI, and only a release changes either: `pnpm version-packages` runs `changeset version`, which bumps `package.json` and writes the changelog, then `pnpm release`, which copies that version into `manifest.json`, changing that one line. `dev/sync-version --check`, in `dev/check`, fails when the two disagree.

On every push to `main`, `.github/workflows/release.yml` runs the changesets GitHub Action, which runs `pnpm version-packages` on the branch changeset-release/main and opens or updates one pull request titled `chore: bump version`. The version it picks is the highest pending bump; the changelog groups the changesets under Major, Minor and Patch Changes, each with a link to its commit and pull request; the consumed changesets are deleted. With nothing pending, no pull request opens. It never publishes a package.

Merging that pull request is the release, and every user gets it on their next update. It needs the user's say-so, like any user-visible release, so hand over the pull request and wait; never merge it on an agent's own judgment. Before asking, read its diff: the new version should be the one the changesets justify, and each changelog line should read well to someone who has never seen the code.

Two repository facts the workflow depends on:

- The setting "Allow GitHub Actions to create and approve pull requests", under the repository's Actions settings, must be on, or opening the pull request is refused.
- A pull request opened with `GITHUB_TOKEN` starts no other workflow, so `check.yml` and `cli.yml` do not run on the version pull request. Its diff is only the two versions, the changelog and deleted changesets, all of which ran through CI on the pull requests that added them. To see CI on it anyway, close and reopen it.

To preview a release locally, `pnpm changeset status` names the next version. `pnpm version-packages` does the real thing, and the changelog it writes looks each changeset up on GitHub, so it needs `GITHUB_TOKEN` set; on a working branch it rewrites files the workflow owns, so discard those changes afterwards.

## The commit message

One Conventional Commit per coherent change: `type(scope): summary`, lowercase, no trailing period. The types are the ones `TYPES` in `dev/changeset` accepts, so a commit and its changeset share a vocabulary. Scopes name the part of the product, and `git log --format=%s` shows the ones in use, such as `cli`, `space`, `library`, `ui`, `security`. The summary says what is true after the change, not what was done. The changeset and the commit message describe the same change for two readers: the commit for whoever reads the history, the changeset for whoever updates the plugin.

Write the message and hand it over as text. Committing, amending and pushing each need their own explicit request, and before an authorized amend or history rewrite, run `git log` first, because the repository is also edited outside the session.
