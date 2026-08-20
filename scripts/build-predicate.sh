#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Shapes the pull-request-merge collector raw JSON into the "github-pull-request"
# predicate and its subject file. The predicate carries the merge body under the
# root section `pull_request_merge`; the subject is a compact merge-commit identity.
# Writes predicate.json and subject.json (paths overridable via
# PREDICATE_OUT / SUBJECT_OUT).
#
# Required env: PR_RAW_SNAPSHOT_FILE.
# Optional env: PREDICATE_TYPE (default pull-request-merge/v1), PREDICATE_OUT,
#   SUBJECT_OUT.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

: "${PR_RAW_SNAPSHOT_FILE:?PR_RAW_SNAPSHOT_FILE must be set}"
PREDICATE_OUT="${PREDICATE_OUT:-predicate.json}"
SUBJECT_OUT="${SUBJECT_OUT:-subject.json}"

PREDICATE_TYPE="${PREDICATE_TYPE:-https://jfrog.com/evidence/pull-request-merge/v1}"

# Guard against a missing/empty/null snapshot up front: --slurpfile would happily
# bind $x[0] to null and emit an all-null section instead of failing.
if ! jq -e 'if . == null then false else true end' "$PR_RAW_SNAPSHOT_FILE" >/dev/null 2>&1; then
  echo "::error::snapshot file ${PR_RAW_SNAPSHOT_FILE} is missing, empty, or not valid JSON" >&2
  exit 1
fi

jq -n \
  --arg schema_version "1.0.0" \
  --arg subject_type "GithubPullRequest" \
  --arg predicate_type "$PREDICATE_TYPE" \
  --slurpfile pr "$PR_RAW_SNAPSHOT_FILE" \
  '
  $pr[0] as $p
  | {
      schema_version: $schema_version,
      subject_type: $subject_type,
      predicate_type: $predicate_type,
      pull_request_merge: {
        merge: {
          merge_commit_sha: $p.pr.merge_commit_sha,
          merged_at: $p.pr.merged_at,
          merged_by: $p.pr.merged_by,
          target_branch: $p.pr.target_branch,
          target_base_sha: $p.pr.target_base_sha
        },
        approvers: $p.approvers,
        commits_on_target_branch: $p.commits_on_target_branch,
        code_committers: $p.code_committers,
        commit_signatures: $p.commit_signatures,
        all_commits_verified: $p.all_commits_verified,
        collection: {
          collected_at: $p.collected_at,
          workflow_run_url: $p.workflow_run_url
        }
      }
    }
  ' > "$PREDICATE_OUT"

# The subject is a compact merge-commit identity built from the PR snapshot.
jq -n \
  --slurpfile pr "$PR_RAW_SNAPSHOT_FILE" \
  '$pr[0] as $p
   | {
       merge_commit_sha: $p.pr.merge_commit_sha,
       head_sha: $p.pr.head_sha,
       pr_number: $p.pr.pr_number,
       head_ref: $p.pr.head_ref,
       repo_url: $p.pr.repo_url,
       created_at: $p.collected_at
     }' > "$SUBJECT_OUT"

echo "Wrote ${PREDICATE_OUT} and ${SUBJECT_OUT}" >&2
