#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Minimal bash test harness shared by all tests/test_*.sh files.

TESTS_RUN=0
TESTS_FAILED=0

assert_equal() {
  local expected="$1" actual="$2" message="${3:-values should be equal}"
  if [[ "$expected" != "$actual" ]]; then
    echo "  FAIL: $message" >&2
    echo "    expected: $expected" >&2
    echo "    actual:   $actual" >&2
    return 1
  fi
}

assert_json_equal() {
  local expected="$1" actual="$2" message="${3:-json values should be equal}"
  local norm_expected norm_actual
  norm_expected="$(printf '%s' "$expected" | jq -S -c .)"
  norm_actual="$(printf '%s' "$actual" | jq -S -c .)"
  if [[ "$norm_expected" != "$norm_actual" ]]; then
    echo "  FAIL: $message" >&2
    echo "    expected: $norm_expected" >&2
    echo "    actual:   $norm_actual" >&2
    return 1
  fi
}

assert_true() {
  local condition="$1" message="${2:-condition should be true}"
  if [[ "$condition" != "true" ]]; then
    echo "  FAIL: $message (got: $condition)" >&2
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" message="${3:-output should contain substring}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  FAIL: $message" >&2
    echo "    expected to contain: $needle" >&2
    echo "    actual:              $haystack" >&2
    return 1
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" message="${3:-output should not contain substring}"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  FAIL: $message" >&2
    echo "    expected to NOT contain: $needle" >&2
    echo "    actual:                  $haystack" >&2
    return 1
  fi
}

assert_valid_json() {
  local value="$1" message="${2:-value should be valid JSON}"
  if ! printf '%s' "$value" | jq -e . >/dev/null 2>&1; then
    echo "  FAIL: $message" >&2
    echo "    value: $value" >&2
    return 1
  fi
}

run_test() {
  local test_name="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  if "$test_name"; then
    echo "PASS: $test_name"
  else
    echo "FAIL: $test_name"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

report_results() {
  echo ""
  echo "Ran $TESTS_RUN test(s), $TESTS_FAILED failed."
  [[ "$TESTS_FAILED" -eq 0 ]]
}
