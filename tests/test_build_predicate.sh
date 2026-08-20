#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Tests for scripts/build-predicate.sh: shapes the collector output into the
# github-pull-request predicate and its merge-commit-identity subject file.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

export PATH="${TESTS_DIR}/lib:${PATH}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

test_git_pull_request_predicate_and_subject() {
  local pr_raw pred subj
  pr_raw="${WORK}/raw-pr.json"
  pred="${WORK}/pred.json"; subj="${WORK}/subj.json"

  GITHUB_TOKEN="t" GITHUB_REPOSITORY="acme/widget" GITHUB_SERVER_URL="https://github.com" \
    GITHUB_RUN_ID="5" PR_NUMBER="7" \
    MOCK_CURL_FIXTURE="${TESTS_DIR}/fixtures/pr-merge/pr-merge-success.json" \
    "${REPO_ROOT}/scripts/pull-request-merge/collect-pr-merge.sh" > "$pr_raw" || return 1

  PR_RAW_SNAPSHOT_FILE="$pr_raw" \
    PREDICATE_OUT="$pred" SUBJECT_OUT="$subj" \
    "${REPO_ROOT}/scripts/build-predicate.sh" || return 1

  assert_valid_json "$(cat "$pred")" "predicate must be valid JSON" || return 1

  # Top-level envelope
  assert_equal "1.0.0" "$(jq -r '.schema_version' "$pred")" "top-level schema_version" || return 1
  assert_equal "GithubPullRequest" "$(jq -r '.subject_type' "$pred")" "top-level subject_type" || return 1
  assert_equal "https://jfrog.com/evidence/pull-request-merge/v1" "$(jq -r '.predicate_type' "$pred")" "top-level predicate_type" || return 1

  # Inner envelope is stripped from the PR section.
  assert_equal "null" "$(jq -r '.pull_request_merge.schema_version // "null"' "$pred")" "no inner PR schema_version" || return 1

  # No branch_protection root key
  assert_equal "null" "$(jq -r '.branch_protection // "null"' "$pred")" "no branch_protection root key" || return 1

  # pull_request_merge section
  assert_equal "mergesha" "$(jq -r '.pull_request_merge.merge.merge_commit_sha' "$pred")" "merge commit carried through" || return 1
  assert_equal "2" "$(jq '.pull_request_merge.approvers | length' "$pred")" "approvers carried through" || return 1
  assert_equal "2" "$(jq '.pull_request_merge.commit_signatures | length' "$pred")" "commit_signatures carried through" || return 1
  assert_equal "false" "$(jq -r '.pull_request_merge.all_commits_verified' "$pred")" "all_commits_verified carried through" || return 1

  # Merge-commit identity subject
  assert_equal "mergesha" "$(jq -r '.merge_commit_sha' "$subj")" "subject merge_commit_sha" || return 1
  assert_equal "headsha" "$(jq -r '.head_sha' "$subj")" "subject head_sha" || return 1
  assert_equal "7" "$(jq -r '.pr_number' "$subj")" "subject pr_number"
}

run_test test_git_pull_request_predicate_and_subject

report_results
