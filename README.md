# pnpm/update

Updates the dependencies of your project with `pnpm update`, optionally bumps
the pinned pnpm (`packageManager` / `devEngines.packageManager`) and Node.js
(`devEngines.runtime`) versions, and opens a pull request with the result.

Unlike external dependency bots, this action runs pnpm itself, so it supports
every feature of your workspace: catalogs, patched dependencies, config
dependencies, overrides, and anything pnpm learns in the future.

The action expects pnpm (and a runtime, if your project needs one for
verification) to already be set up — pair it with [`pnpm/setup`].

## Usage

```yaml
name: Update Dependencies

on:
  schedule:
    - cron: '0 0 * * 1' # Every Monday at midnight UTC
  workflow_dispatch: {}

permissions:
  contents: write
  pull-requests: write

concurrency:
  group: update-dependencies
  cancel-in-progress: false

jobs:
  update-dependencies:
    if: github.repository == 'your-org/your-repo' # Don't run on forks
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v6
      # Installs the pnpm version from `packageManager` and the runtime
      # from `devEngines.runtime`.
      - uses: pnpm/setup@v1
      - uses: pnpm/update@v0
        with:
          node: 24
          verify: |
            pnpm build
            pnpm test
```

[`pnpm/setup`]: https://github.com/pnpm/setup

## Inputs

| Input | Default | Description |
|---|---|---|
| `token` | `github.token` | Token used to push the branch and create the PR. PRs created with the default `GITHUB_TOKEN` don't trigger other workflows; pass a GitHub App token or PAT if you want CI to run on the PR. |
| `branch` | `chore/update-dependencies` | Branch the updates are pushed to (force-pushed on every run, so at most one update PR stays open). |
| `base` | repository default branch | Base branch of the pull request. |
| `latest` | `true` | Update to the latest versions, ignoring `package.json` ranges. Set to `false` to update within ranges. |
| `exclude` | — | Whitespace-separated package name patterns that should not be updated, e.g. `typescript @types/*`. |
| `update-pnpm` | `latest` | Bump pnpm itself via `pnpm self-update`. A dist-tag or exact version, or `false` to skip. |
| `node` | — | Bump the Node.js version pinned in `devEngines.runtime` to the latest release of this major, e.g. `24`. Empty to skip. |
| `verify` | — | Shell commands run after updating (build, tests). If they fail, no PR is created. |
| `commit-message` | `chore: update dependencies` | Message of the update commit. |
| `pr-title` | `chore: update dependencies` | Title of the pull request. |
| `pr-body` | Automated dependency updates… | Body of the pull request. |
