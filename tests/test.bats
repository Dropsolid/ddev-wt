#!/usr/bin/env bats

# Basic install smoke test, following the standard ddev add-on template
# pattern (https://github.com/ddev/ddev-addon-template). Verify this against
# the current template before relying on it in CI - the add-on tooling
# conventions do move over time.

setup() {
  set -eu -o pipefail
  export DDEV_NONINTERACTIVE=true
  export PROJNAME=ddev-worktree-test
  export TESTDIR=$(mktemp -d)
  export DIR="${TESTDIR}/${PROJNAME}"
  mkdir -p "$DIR"
  cd "$DIR" || exit 1
  git init -q
  ddev config --project-name="${PROJNAME}" --project-type=php --docroot=web
  ddev start -y >/dev/null
}

teardown() {
  cd "$TESTDIR" || exit 1
  ddev delete -Oy "$PROJNAME" >/dev/null 2>&1 || true
  rm -rf "$TESTDIR"
}

@test "install add-on and expect wt-* commands to be available" {
  cd "$DIR" || exit 1
  ddev add-on get "${GITHUB_WORKSPACE:-$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)}"
  ddev restart >/dev/null

  run ddev wt-list
  [ "$status" -eq 0 ]

  run ddev wt-status
  [ "$status" -eq 0 ]
}
