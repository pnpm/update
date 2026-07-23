# pnpm/update

Updates the dependencies of your project with pnpm, keeps the pinned
pnpm (`packageManager` / `devEngines.packageManager`) and Node.js
(`devEngines.runtime`) versions fresh — by default within their current major
versions — and opens a pull request with the result. It can optionally update
the GitHub Actions pinned in your workflow files too. By default the lockfile
is regenerated from scratch, so transitive dependencies of unchanged packages
are refreshed too.

The default setup needs no secrets: the built-in `GITHUB_TOKEN` is enough to
update dependencies, pnpm, and Node.js, validate them with your own `verify`
commands, and open a pull request.

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
          verify: |
            pnpm build
            pnpm test
```

[`pnpm/setup`]: https://github.com/pnpm/setup

## Updating GitHub Actions

The action can also bump the GitHub Actions pinned in `.github/workflows/*.yml`
and `action.yml` (via `pnpm update --include-github-actions`). This is **opt-in**
(`github-actions: true`) because GitHub does not let the default `GITHUB_TOKEN`
push changes to workflow files — you must pass a `token` that carries the
`workflow` scope (a PAT) or `workflows: write` (a GitHub App). Without such a
token the push fails as soon as an action needs updating.

```yaml
      - uses: pnpm/update@v0
        with:
          github-actions: true
          token: ${{ secrets.UPDATE_TOKEN }} # PAT with `repo` + `workflow`
```

GitHub Actions updates ride along with the dependency update, so they only
happen when `update-deps` is `latest` or `ranges` (not `false`).

## Refreshing the lockfile only

To refresh the lockfile to the latest versions matching your `package.json`
ranges without touching any manifests (and, in this example, follow pnpm's
prereleases while propagating updated versions into other files):

```yaml
      - uses: pnpm/update@v0
        with:
          update-deps: false
          update-pnpm: next-12
          post-update: pnpm update-manifests
          token: ${{ secrets.UPDATE_TOKEN }}
```

## Development

The action's pure logic (update-argument construction, `update-deps`
validation, and the Node.js-major extraction) lives in `scripts/lib.sh`, which
the action sources at runtime and which is unit-tested with
[bats](https://github.com/bats-core/bats-core):

```sh
shellcheck scripts/*.sh
bats test/
```

CI runs both on every push and pull request.

## Inputs

| Input | Default | Description |
|---|---|---|
| `token` | `github.token` | Token used to push the branch and create the PR. PRs created with the default `GITHUB_TOKEN` don't trigger other workflows; pass a GitHub App token or PAT if you want CI to run on the PR. With `github-actions` enabled, the token must also carry the `workflow` scope (PAT) or `workflows: write` (App) to push workflow-file changes. |
| `branch` | `chore/update-dependencies` | Branch the updates are pushed to (force-pushed on every run, so at most one update PR stays open). |
| `base` | repository default branch | Branch the updates are based on and the pull request targets. |
| `update-deps` | `latest` | How to update dependencies: `latest` ignores `package.json` ranges, `ranges` stays within them, `false` skips manifest updates entirely. |
| `refresh-lockfile` | `true` | Delete `pnpm-lock.yaml` and `node_modules` before updating, so the whole graph — including transitive dependencies — is freshly resolved. Set to `false` to keep existing resolutions where possible. |
| `exclude` | — | Whitespace-separated package name patterns whose ranges should not be updated, e.g. `typescript @types/*`. With `refresh-lockfile`, excluded packages are still re-resolved within their kept ranges. |
| `github-actions` | `false` | Set to `true` to also update the GitHub Actions pinned in `.github/workflows/*.yml` and `action.yml`. Only applies when `update-deps` is `latest` or `ranges`. Requires a `token` with the `workflow` scope (see above). |
| `post-update` | — | Shell commands run after the updates, before verification; their changes are included in the PR. |
| `changesets` | `true` | In repositories that use changesets: generate a changeset for the updated dependencies via `pnpm update --changeset` (patch for production deps, major for peer deps, and the same for packages consuming a changed `catalog:` entry). Private, ignored, and dev-only changes are skipped. Only applies in `latest`/`ranges` mode and when the installed pnpm supports `--changeset`. Set to `false` to disable. |
| `update-pnpm` | pinned major | Bump pnpm itself via `pnpm self-update`. Defaults to the latest release of the currently pinned major; set a version, range, or dist-tag (`latest`, `12`, `next-12`) to move onto it, or `false` to skip. |
| `node` | pinned major | Bump the Node.js version pinned in `devEngines.runtime`. Defaults to the latest release of the currently pinned major (skipped when nothing is pinned); set `24`, `lts`, or `latest` to move onto it, or `false` to skip. |
| `verify` | — | Shell commands run after updating (build, tests). If they fail, no PR is created. |
| `commit-message` | `chore: update dependencies` | Message of the update commit. |
| `pr-title` | `chore: update dependencies` | Title of the pull request. |
| `pr-body` | Automated dependency updates… | Body of the pull request. |
