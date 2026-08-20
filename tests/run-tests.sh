#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Runs every tests/test_*.sh suite and exits non-zero if any suite failed.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

suites_failed=0
for suite in "${TESTS_DIR}"/test_*.sh; do
  echo "=== $(basename "$suite") ==="
  if ! bash "$suite"; then
    suites_failed=$((suites_failed + 1))
  fi
  echo ""
done

if [[ "$suites_failed" -gt 0 ]]; then
  echo "FAILED: $suites_failed suite(s) had failing tests."
  exit 1
fi

echo "All test suites passed."
