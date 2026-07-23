#!/usr/bin/env bats
# Integration tests for scripts/update.sh: drive the whole "Update dependencies"
# step against a fixture directory with `pnpm` stubbed, and assert on the
# commands it invokes (recorded in $PNPM_LOG).

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/update.sh"

setup() {
  TMP="$(mktemp -d)"
  # Put the pnpm stub first on PATH.
  mkdir -p "$TMP/bin"
  cp "${BATS_TEST_DIRNAME}/stubs/pnpm" "$TMP/bin/pnpm"
  chmod +x "$TMP/bin/pnpm"
  PATH="$TMP/bin:$PATH"
  export PNPM_LOG="$TMP/pnpm.log"
  : > "$PNPM_LOG"
  cd "$TMP"

  # Defaults matching the action's inputs; individual tests override via `export`.
  export UPDATE_DEPS=latest
  export REFRESH_LOCKFILE=false
  export EXCLUDE=''
  export INCLUDE_GITHUB_ACTIONS=false
  export CHANGESETS=true
  export UPDATE_PNPM=false
  export NODE=''
  printf '%s' '{"name":"fixture","devEngines":{"runtime":{"name":"node","version":"^24.4.0"}}}' > package.json
}

teardown() {
  rm -rf "$TMP"
}

@test "latest update: pins the runtime major, updates recursively with changeset" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -Fqx 'runtime set node 24' "$PNPM_LOG"
  grep -Fqx 'update --recursive --latest --changeset' "$PNPM_LOG"
}

@test "invalid update-deps fails" {
  export UPDATE_DEPS=bogus
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"* ]]
}

@test "update-deps=false runs a plain install, not update" {
  export UPDATE_DEPS=false
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -Fqx 'install' "$PNPM_LOG"
  ! grep -Fq -- '--recursive' "$PNPM_LOG"
}

@test "update-deps=false with github-actions warns that it is skipped" {
  export UPDATE_DEPS=false INCLUDE_GITHUB_ACTIONS=true
  run bash "$SCRIPT"
  [[ "$output" == *"::notice::"* ]]
  [[ "$output" == *"github-actions updates are skipped"* ]]
}

@test "changesets=false passes --no-changeset" {
  export CHANGESETS=false
  run bash "$SCRIPT"
  grep -Fq -- '--no-changeset' "$PNPM_LOG"
}

@test "unsupported pnpm skips the changeset flag with a notice" {
  export STUB_SUPPORTS_CHANGESET=0
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -Fq -- '--changeset' "$PNPM_LOG"
  ! grep -Fq -- '--no-changeset' "$PNPM_LOG"
  [[ "$output" == *"has no --changeset flag"* ]]
}

@test "github-actions=true adds --include-github-actions" {
  export INCLUDE_GITHUB_ACTIONS=true
  run bash "$SCRIPT"
  grep -Fq -- '--include-github-actions' "$PNPM_LOG"
}

@test "exclude patterns become negation selectors" {
  export EXCLUDE='webpack @types/*'
  run bash "$SCRIPT"
  grep -Fqx 'update --recursive --latest --changeset !webpack !@types/*' "$PNPM_LOG"
}

@test "explicit node version is used verbatim" {
  export NODE=22
  run bash "$SCRIPT"
  grep -Fqx 'runtime set node 22' "$PNPM_LOG"
}

@test "node=false skips the runtime update" {
  export NODE=false
  run bash "$SCRIPT"
  ! grep -Fq 'runtime set node' "$PNPM_LOG"
}

@test "no pinned runtime skips the runtime update with a message" {
  printf '%s' '{"name":"fixture"}' > package.json
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -Fq 'runtime set node' "$PNPM_LOG"
  [[ "$output" == *"No Node.js version pinned"* ]]
}

@test "refresh-lockfile removes the lockfile and node_modules" {
  export REFRESH_LOCKFILE=true
  touch pnpm-lock.yaml
  mkdir -p node_modules/.pnpm
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e pnpm-lock.yaml ]
  [ ! -e node_modules ]
}

@test "update-pnpm default stays on the pinned major from pnpm --version" {
  export STUB_PNPM_VERSION=11.5.0
  export UPDATE_PNPM=''
  run bash "$SCRIPT"
  grep -Fqx 'self-update 11' "$PNPM_LOG"
}

@test "update-pnpm explicit dist-tag is passed through" {
  export UPDATE_PNPM=next-12
  run bash "$SCRIPT"
  grep -Fqx 'self-update next-12' "$PNPM_LOG"
}

@test "update-pnpm=false skips self-update" {
  export UPDATE_PNPM=false
  run bash "$SCRIPT"
  ! grep -Fq 'self-update' "$PNPM_LOG"
}
