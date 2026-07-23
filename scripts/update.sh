#!/usr/bin/env bash
# The "Update dependencies" step: bump the pinned runtime, optionally refresh
# the lockfile, run the update (or a plain install), generate a changeset, and
# self-update pnpm. Inputs arrive as environment variables (set by action.yml).
# Pure decision logic lives in lib.sh; this file is the orchestration, driven in
# tests against a stubbed `pnpm` (see test/update.bats).
#
# shellcheck disable=SC2153 # the UPPER_CASE vars are inputs from the environment
set -euo pipefail
# Keep patterns like "@types/*" from glob-expanding against the repo.
set -f
# shellcheck source=scripts/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

validate_update_deps "$UPDATE_DEPS" || exit 1

# Update the runtime pin first, so the installs below run with it in place and
# sync anything derived from it.
if [ "$NODE" != "false" ]; then
  if [ -n "$NODE" ]; then
    pnpm runtime set node "$NODE"
  else
    # Stay on the pinned major and only refresh within it: crossing toolchain
    # majors usually needs coordinated changes (Dockerfiles, CI matrices,
    # @types/node) that this job cannot make.
    NODE_MAJOR="$(node_major_from_manifest package.json)"
    if [ -n "$NODE_MAJOR" ]; then
      pnpm runtime set node "$NODE_MAJOR"
    else
      echo "No Node.js version pinned in devEngines.runtime; skipping the runtime update."
    fi
  fi
fi

if [ "$REFRESH_LOCKFILE" = "true" ]; then
  # Remove node_modules too so pnpm cannot reuse the hidden lockfile in
  # node_modules/.pnpm as the missing wanted lockfile and skip resolution.
  rm -rf node_modules pnpm-lock.yaml
fi

if [ "$UPDATE_DEPS" = "false" ]; then
  pnpm install
  if [ "$INCLUDE_GITHUB_ACTIONS" = "true" ]; then
    # `--include-github-actions` is a `pnpm update` flag; the install path above
    # never reaches it, so there's nothing to update here.
    echo "::notice::github-actions updates are skipped because update-deps is \"false\" (they need a dependency update pass)."
  fi
else
  # Let `pnpm update` generate the changeset natively (it also covers catalog
  # consumers and peer-dep majors, which a git diff can't). `--no-changeset`
  # overrides a repo-level `update.changeset: true`.
  CHANGESET_ARG=''
  if pnpm update --help 2>/dev/null | grep -q -- '--changeset'; then
    if [ "$CHANGESETS" = "true" ]; then
      CHANGESET_ARG=--changeset
    else
      CHANGESET_ARG=--no-changeset
    fi
  elif [ "$CHANGESETS" = "true" ]; then
    echo "::notice::Skipping changeset generation: this pnpm version has no --changeset flag. Upgrade pnpm to enable it."
  fi
  # A while-read loop rather than `mapfile` so this runs on bash 3.2 too.
  args=()
  while IFS= read -r arg; do
    args+=("$arg")
  done < <(pnpm_update_args "$UPDATE_DEPS" "$INCLUDE_GITHUB_ACTIONS" "$EXCLUDE" "$CHANGESET_ARG")
  pnpm update "${args[@]}"
fi

# Last, so every earlier step runs on the pnpm the workflow installed.
if [ "$UPDATE_PNPM" != "false" ]; then
  if [ -n "$UPDATE_PNPM" ]; then
    pnpm self-update "$UPDATE_PNPM"
  else
    # A major bump of pnpm can rewrite the whole lockfile; keep that out of
    # routine update PRs by staying on the pinned major.
    pnpm self-update "$(pnpm --version | cut -d . -f 1)"
  fi
fi
