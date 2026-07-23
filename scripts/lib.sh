#!/usr/bin/env bash
# Pure helpers for the pnpm/update action, kept in a sourceable library so they
# can be unit-tested (see test/lib.bats) without running the whole action.
# Nothing here has side effects or calls pnpm/git — the action wires these into
# its steps.

# Validate the `update-deps` input. Prints a GitHub error annotation and returns
# non-zero on an unknown value.
validate_update_deps() {
  case "$1" in
    latest | ranges | false) return 0 ;;
    *)
      echo "::error::Invalid value for the update-deps input: ${1}. Expected latest, ranges, or false."
      return 1
      ;;
  esac
}

# Print the arguments for `pnpm update`, one per line, given:
#   $1  update-deps           (latest|ranges — the caller handles "false")
#   $2  include-github-actions (true|false)
#   $3  exclude               (whitespace-separated name patterns)
# The exclude string is deliberately word-split; the caller runs with `set -f`
# so patterns like "@types/*" reach pnpm as negation selectors rather than
# globbing against the working tree.
pnpm_update_args() {
  local update_deps="$1" include_actions="$2" exclude="$3" pattern
  printf '%s\n' --recursive
  [ "$update_deps" = latest ] && printf '%s\n' --latest
  [ "$include_actions" = true ] && printf '%s\n' --include-github-actions
  # shellcheck disable=SC2086 # intentional word splitting; caller sets -f
  for pattern in $exclude; do
    printf '!%s\n' "$pattern"
  done
  return 0
}

# Print the pinned Node.js major from a package.json's `devEngines.runtime`,
# handling both the single-object and array forms. Prints nothing (and returns
# 0) when no Node.js runtime is pinned or the file is unreadable.
node_major_from_manifest() {
  local file="${1:-package.json}" pinned
  pinned="$(jq -r '
    .devEngines.runtime // empty
    | if type == "array" then .[] else . end
    | select(.name == "node") | .version // empty
  ' "$file" 2>/dev/null | head -n 1)"
  [ -n "$pinned" ] || return 0
  printf '%s' "$pinned" | grep -oE '[0-9]+' | head -n 1
}
