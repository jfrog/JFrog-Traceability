#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Tests for scripts/build-markdown.sh: renders a single render-safe markdown
# report from the github-pull-request predicate (plus subject for PR identity).
# The report is attached via `jf evd create --markdown`.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

assert_contains() {
  local haystack="$1" needle="$2" message="${3:-output should contain substring}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  FAIL: $message" >&2
    echo "    missing: $needle" >&2
    return 1
  fi
}

# The JFrog viewer mangles " < > — the report must never emit them.
assert_render_safe() {
  local haystack="$1" message="${2:-output must not contain \" < or >}"
  if [[ "$haystack" == *'"'* || "$haystack" == *'<'* || "$haystack" == *'>'* ]]; then
    echo "  FAIL: $message" >&2
    return 1
  fi
}

test_git_pull_request_markdown_renders_merge_section() {
  local pred subj md
  pred="${WORK}/pred.json"; subj="${WORK}/subj.json"; md="${WORK}/report.md"

  cat > "$pred" <<'JSON'
{
  "schema_version": "1.0.0",
  "subject_type": "GithubPullRequest",
  "predicate_type": "https://jfrog.com/evidence/pull-request-merge/v1",
  "pull_request_merge": {
    "merge": {
      "merge_commit_sha": "ed0be7a1",
      "merged_at": "2026-07-23T11:28:03Z",
      "merged_by": "octocat",
      "target_branch": "main",
      "target_base_sha": "ed6de7af"
    },
    "approvers": [
      { "login": "hubot", "submitted_at": "2026-07-23T11:27:58Z", "is_pr_head_approval": true }
    ],
    "commits_on_target_branch": ["55bf3c3a", "0b2b9eec"],
    "code_committers": [
      { "login": null, "email": "octocat@example.com" }
    ],
    "commit_signatures": [
      { "sha": "55bf3c3a", "verified": true, "reason": "valid", "signer_login": "octocat" },
      { "sha": "0b2b9eec", "verified": false, "reason": "unsigned", "signer_login": null }
    ],
    "all_commits_verified": false,
    "collection": {
      "collected_at": "2026-07-23T11:28:30.000Z",
      "workflow_run_url": "https://github.com/acme/widget/actions/runs/30003234739"
    }
  }
}
JSON

  cat > "$subj" <<'JSON'
{ "merge_commit_sha": "ed0be7a1", "head_sha": "0b2b9eec", "pr_number": "7", "head_ref": "feature-x", "repo_url": "https://github.com/acme/widget", "created_at": "2026-07-23T11:28:30.000Z" }
JSON

  PREDICATE_FILE="$pred" SUBJECT_FILE="$subj" MARKDOWN_OUT="$md" \
    "${REPO_ROOT}/scripts/build-markdown.sh" || return 1

  local out; out="$(cat "$md")"
  assert_contains "$out" "# Github Pull Request Evidence Report" "top-level title" || return 1
  assert_contains "$out" "**Repository:** acme/widget" "repository slug from subject" || return 1
  assert_contains "$out" "**Pull request:** #7" "pr number" || return 1
  assert_contains "$out" "**Merged by:** octocat" "merged_by" || return 1
  assert_contains "$out" "ed0be7a1" "merge commit sha" || return 1
  assert_contains "$out" "Approvers (1)" "approver count" || return 1
  assert_contains "$out" "hubot" "approver login" || return 1
  assert_contains "$out" "Commits on Target Branch (2)" "commit count" || return 1
  assert_contains "$out" "55bf3c3a" "commit sha listed" || return 1
  assert_contains "$out" "Code Committers (1)" "committer count" || return 1
  assert_contains "$out" "mailto:octocat@example.com" "committer email as mailto link" || return 1
  assert_contains "$out" "Commit Signatures (2)" "commit signature count" || return 1
  assert_contains "$out" "**All commits verified:** no" "verification summary rendered" || return 1
  assert_contains "$out" "unsigned" "unverified reason rendered" || return 1

  if [[ "$out" == *"# Branch Protection"* ]]; then
    echo "  FAIL: report must not include a Branch Protection section" >&2
    return 1
  fi

  assert_render_safe "$out" "report must be render-safe"
}

run_test test_git_pull_request_markdown_renders_merge_section

report_results
