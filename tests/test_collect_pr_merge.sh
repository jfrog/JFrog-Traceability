#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Tests for scripts/pull-request-merge/collect-pr-merge.sh against fixture-driven mock responses.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

export PATH="${TESTS_DIR}/lib:${PATH}"
export GITHUB_TOKEN="test-token"
export GITHUB_REPOSITORY="acme/widget"
export GITHUB_SERVER_URL="https://github.com"
export GITHUB_RUN_ID="999"
export PR_NUMBER="7"
export MOCK_CURL_FIXTURE="${TESTS_DIR}/fixtures/pr-merge/pr-merge-success.json"

collect_pr_merge() {
  "${REPO_ROOT}/scripts/pull-request-merge/collect-pr-merge.sh"
}

test_collects_merged_pr_fields() {
  local out
  out="$(collect_pr_merge)" || return 1
  assert_valid_json "$out" "collector must print valid JSON" || return 1
  assert_equal "mergesha" "$(printf '%s' "$out" | jq -r '.pr.merge_commit_sha')" "merge commit sha" || return 1
  assert_equal "parentsha" "$(printf '%s' "$out" | jq -r '.pr.target_base_sha')" "target base sha should become the merge commit's first parent" || return 1
  assert_equal "headsha" "$(printf '%s' "$out" | jq -r '.pr.head_sha')" "head sha" || return 1
  assert_equal "main" "$(printf '%s' "$out" | jq -r '.pr.target_branch')" "target branch"
}

test_approvers_are_deduped_latest_per_login() {
  local out approvers
  out="$(collect_pr_merge)" || return 1
  approvers="$(printf '%s' "$out" | jq -c '.approvers')"
  assert_equal "2" "$(printf '%s' "$approvers" | jq 'length')" "only the two APPROVED reviewers, not the commenter" || return 1
  assert_equal "true" "$(printf '%s' "$approvers" | jq -r '.[] | select(.login=="alice") | .is_pr_head_approval')" "alice approved the head sha" || return 1
  assert_equal "false" "$(printf '%s' "$approvers" | jq -r '.[] | select(.login=="bob") | .is_pr_head_approval')" "bob approved an older sha"
}

test_commits_and_committers() {
  local out
  out="$(collect_pr_merge)" || return 1
  assert_json_equal '["c1","c2"]' "$(printf '%s' "$out" | jq -c '.commits_on_target_branch')" "commits on target branch from compare" || return 1
  assert_equal "2" "$(printf '%s' "$out" | jq '.code_committers | length')" "two code committers" || return 1
  assert_equal "alice@example.com" "$(printf '%s' "$out" | jq -r '.code_committers[] | select(.login=="alice") | .email')" "committer email lowercased"
}

test_committer_login_filled_from_noreply_email() {
  # c2 has no resolved GitHub author (author: null) but its commit email is a
  # GitHub no-reply address, which encodes the login. Enrichment must recover it.
  local out
  out="$(collect_pr_merge)" || return 1
  assert_equal "bobby" "$(printf '%s' "$out" | jq -r '.code_committers[] | select(.email | test("noreply")) | .login')" "login parsed from no-reply commit email"
}

test_approver_email_enriched_from_public_profile() {
  # Approver emails come from the public profile email; a user without a public
  # email stays null.
  local out approvers
  out="$(collect_pr_merge)" || return 1
  approvers="$(printf '%s' "$out" | jq -c '.approvers')"
  assert_equal "alice.public@example.com" "$(printf '%s' "$approvers" | jq -r '.[] | select(.login=="alice") | .email')" "alice email from public profile, lowercased" || return 1
  assert_equal "null" "$(printf '%s' "$approvers" | jq -r '.[] | select(.login=="bob") | .email')" "bob has no public email -> null"
}

test_commit_signatures_and_verification_summary() {
  local out sigs
  out="$(collect_pr_merge)" || return 1
  sigs="$(printf '%s' "$out" | jq -c '.commit_signatures')"
  assert_equal "2" "$(printf '%s' "$sigs" | jq 'length')" "one signature entry per PR commit" || return 1
  assert_equal "true" "$(printf '%s' "$sigs" | jq -r '.[] | select(.sha=="c1") | .verified')" "c1 is verified" || return 1
  assert_equal "valid" "$(printf '%s' "$sigs" | jq -r '.[] | select(.sha=="c1") | .reason')" "c1 reason is valid" || return 1
  assert_equal "false" "$(printf '%s' "$sigs" | jq -r '.[] | select(.sha=="c2") | .verified')" "c2 has no verification -> false" || return 1
  assert_equal "unsigned" "$(printf '%s' "$sigs" | jq -r '.[] | select(.sha=="c2") | .reason')" "c2 defaults to unsigned" || return 1
  assert_equal "false" "$(printf '%s' "$out" | jq -r '.all_commits_verified')" "not all commits verified"
}

test_unmerged_pr_fails() {
  local rc
  MOCK_CURL_FIXTURE="${TESTS_DIR}/fixtures/pr-merge/pr-merge-not-merged.json" collect_pr_merge >/dev/null 2>&1
  rc=$?
  assert_equal "1" "$rc" "an unmerged PR must fail the collector"
}

test_approvers_span_multiple_review_pages() {
  # Reviews are Link-paginated: alice approves on page 1, carol on page 2. Both
  # must appear, proving the collector follows rel="next" instead of truncating
  # the approver list at the first page.
  local out approvers
  out="$(MOCK_CURL_FIXTURE="${TESTS_DIR}/fixtures/pr-merge/pr-merge-reviews-paginated.json" collect_pr_merge)" || return 1
  approvers="$(printf '%s' "$out" | jq -c '.approvers')"
  assert_equal "2" "$(printf '%s' "$approvers" | jq 'length')" "approvers from both review pages are collected" || return 1
  assert_equal "true" "$(printf '%s' "$approvers" | jq '[.[].login] | contains(["alice"])')" "page-1 approver alice present" || return 1
  assert_equal "true" "$(printf '%s' "$approvers" | jq '[.[].login] | contains(["carol"])')" "page-2 approver carol present"
}

run_test test_collects_merged_pr_fields
run_test test_approvers_are_deduped_latest_per_login
run_test test_commits_and_committers
run_test test_committer_login_filled_from_noreply_email
run_test test_approver_email_enriched_from_public_profile
run_test test_commit_signatures_and_verification_summary
run_test test_unmerged_pr_fails
run_test test_approvers_span_multiple_review_pages

report_results
