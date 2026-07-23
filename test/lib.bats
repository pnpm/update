#!/usr/bin/env bats
# Unit tests for scripts/lib.sh. Run with `bats test`.

setup() {
  load '../scripts/lib.sh'
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

# --- validate_update_deps -------------------------------------------------

@test "validate_update_deps accepts latest, ranges, and false" {
  for value in latest ranges false; do
    run validate_update_deps "$value"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "validate_update_deps rejects an unknown value with an error annotation" {
  run validate_update_deps latests
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"* ]]
  [[ "$output" == *"latests"* ]]
}

# --- pnpm_update_args -----------------------------------------------------

@test "pnpm_update_args: latest adds --recursive and --latest" {
  run pnpm_update_args latest false ''
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = '--recursive' ]
  [ "${lines[1]}" = '--latest' ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "pnpm_update_args: ranges omits --latest" {
  run pnpm_update_args ranges false ''
  [ "${lines[0]}" = '--recursive' ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "pnpm_update_args: include-github-actions adds the flag" {
  run pnpm_update_args latest true ''
  [[ "$output" == *'--include-github-actions'* ]]
}

@test "pnpm_update_args: exclude patterns become negation selectors" {
  set -f
  run pnpm_update_args latest false 'webpack @types/*'
  [ "${lines[2]}" = '!webpack' ]
  [ "${lines[3]}" = '!@types/*' ]
}

@test "pnpm_update_args: glob patterns are not expanded against the tree" {
  # A path that "@types/*" would match if globbing were active.
  mkdir -p "$TMP/@types/node" && touch "$TMP/@types/node/x"
  cd "$TMP"
  set -f
  run pnpm_update_args ranges false '@types/*'
  # ranges => no --latest, so the pattern is the only arg after --recursive,
  # and it stays literal (a glob would have produced !@types/node instead).
  [ "${lines[1]}" = '!@types/*' ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "pnpm_update_args: changeset arg is appended when set" {
  run pnpm_update_args latest false '' '--changeset'
  [ "${lines[2]}" = '--changeset' ]
}

@test "pnpm_update_args: --no-changeset is passed through" {
  run pnpm_update_args ranges false '' '--no-changeset'
  [ "${lines[1]}" = '--no-changeset' ]
}

@test "pnpm_update_args: no changeset arg when empty" {
  run pnpm_update_args latest true 'webpack' ''
  [[ "$output" != *changeset* ]]
}

# --- node_major_from_manifest ---------------------------------------------

@test "node_major_from_manifest: object form" {
  printf '%s' '{"devEngines":{"runtime":{"name":"node","version":"^24.4.0"}}}' > "$TMP/package.json"
  run node_major_from_manifest "$TMP/package.json"
  [ "$output" = '24' ]
}

@test "node_major_from_manifest: array form picks the node entry" {
  printf '%s' '{"devEngines":{"runtime":[{"name":"bun","version":"1.2"},{"name":"node","version":"26.5.0"}]}}' > "$TMP/package.json"
  run node_major_from_manifest "$TMP/package.json"
  [ "$output" = '26' ]
}

@test "node_major_from_manifest: no runtime pinned prints nothing" {
  printf '%s' '{"name":"x"}' > "$TMP/package.json"
  run node_major_from_manifest "$TMP/package.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "node_major_from_manifest: missing file prints nothing and succeeds" {
  run node_major_from_manifest "$TMP/does-not-exist.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
