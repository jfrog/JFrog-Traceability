#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Local smoke test: create signed evidence on a gitCommit entity via
# `jf evd create`. Targets the default entity repo `gitCommit-entity` (no
# project/application scope). Default predicate + markdown come from
# fixtures/unified-github-pull-request-predicate.json.
#
# Required env:
#   JF_URL              Platform base URL, e.g. http://localhost:8082
#   JF_ACCESS_TOKEN     Bearer token with annotate on gitCommit-entity
#   EVIDENCE_SIGNING_KEY  Private PEM contents, or set EVIDENCE_SIGNING_KEY_FILE
#   EVIDENCE_KEY_ALIAS  Key alias registered in Artifactory
#
# Optional env:
#   ENTITY_TYPE         Default: gitCommit
#   ENTITY_ID           Default: merge commit sha from the fixture
#                       (.pull_request_merge.merge.merge_commit_sha)
#   PREDICATE_FILE      Default: fixtures/unified-github-pull-request-predicate.json
#   MARKDOWN_FILE       Default: rendered from the predicate via build-markdown.sh
#   PROVIDER_ID         Default: github-actions
#   SKIP_LIST           If set, skip the final GET
#
# Example:
#   JF_URL=http://localhost:8082 \
#   JF_ACCESS_TOKEN=... \
#   EVIDENCE_SIGNING_KEY_FILE=./private.pem \
#   bash scripts/smoke-entity-evidence.sh
set -euo pipefail
set +x

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
DEFAULT_PREDICATE="${SCRIPT_DIR}/fixtures/unified-github-pull-request-predicate.json"

: "${JF_URL:?JF_URL must be set}"
: "${JF_ACCESS_TOKEN:?JF_ACCESS_TOKEN must be set}"
: "${EVIDENCE_KEY_ALIAS:?EVIDENCE_KEY_ALIAS must be set}"

if [[ -n "${EVIDENCE_SIGNING_KEY_FILE:-}" ]]; then
  EVIDENCE_SIGNING_KEY="$(< "$EVIDENCE_SIGNING_KEY_FILE")"
fi
: "${EVIDENCE_SIGNING_KEY:?EVIDENCE_SIGNING_KEY or EVIDENCE_SIGNING_KEY_FILE must be set}"

JF_URL="${JF_URL%/}"
ENTITY_TYPE="${ENTITY_TYPE:-gitCommit}"
PROVIDER_ID="${PROVIDER_ID:-github-actions}"
PREDICATE_FILE="${PREDICATE_FILE:-$DEFAULT_PREDICATE}"

if [[ ! -f "$PREDICATE_FILE" ]]; then
  echo "::error::PREDICATE_FILE not found: ${PREDICATE_FILE}" >&2
  exit 1
fi

PREDICATE_TYPE="${PREDICATE_TYPE:-$(jq -r '.predicate_type // "https://jfrog.com/evidence/pull-request-merge/v1"' "$PREDICATE_FILE")}"
if [[ -z "${ENTITY_ID:-}" ]]; then
  ENTITY_ID="$(jq -r '.pull_request_merge.merge.merge_commit_sha // empty' "$PREDICATE_FILE")"
  if [[ -z "$ENTITY_ID" ]]; then
    echo "::error::merge_commit_sha not found in ${PREDICATE_FILE}; set ENTITY_ID explicitly" >&2
    exit 1
  fi
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/smoke-entity-evidence.XXXXXX")"
cleanup() {
  rm -rf "$WORKDIR"
  # Best-effort: remove any transient CLI server config created below.
  jf c rm smoke-entity-evidence --quiet >/dev/null 2>&1 || true
}
trap cleanup EXIT

KEY_FILE="${WORKDIR}/key.pem"
PREDICATE_PATH="${WORKDIR}/predicate.json"
MARKDOWN_PATH="${WORKDIR}/report.md"

( umask 077; printf '%s\n' "$EVIDENCE_SIGNING_KEY" > "$KEY_FILE" )
chmod 600 "$KEY_FILE"

# Drop any top-level predicate_type from the fixture so `jf evd create`
# receives just the predicate object.
jq 'del(.predicate_type)' "$PREDICATE_FILE" > "$PREDICATE_PATH"

if [[ -n "${MARKDOWN_FILE:-}" ]]; then
  if [[ ! -f "$MARKDOWN_FILE" ]]; then
    echo "::error::MARKDOWN_FILE not found: ${MARKDOWN_FILE}" >&2
    exit 1
  fi
  cp "$MARKDOWN_FILE" "$MARKDOWN_PATH"
else
  PREDICATE_FILE="$PREDICATE_PATH" MARKDOWN_OUT="$MARKDOWN_PATH" \
    "${SCRIPT_DIR}/build-markdown.sh"
fi

# Configure a transient CLI server context using the provided access token so
# `jf evd create` can talk to the platform without relying on the caller's
# global `jf c` state.
jf c add smoke-entity-evidence \
  --url "$JF_URL" \
  --access-token "$JF_ACCESS_TOKEN" \
  --interactive=false \
  --overwrite >/dev/null
jf c use smoke-entity-evidence >/dev/null

echo "→ create  entity=${ENTITY_TYPE}/${ENTITY_ID}  (repo gitCommit-entity)" >&2
jf evd create \
  --entity-type "$ENTITY_TYPE" \
  --entity-id "$ENTITY_ID" \
  --predicate "$PREDICATE_PATH" \
  --predicate-type "$PREDICATE_TYPE" \
  --markdown "$MARKDOWN_PATH" \
  --key "$KEY_FILE" \
  --key-alias "$EVIDENCE_KEY_ALIAS" \
  --provider-id "$PROVIDER_ID"

if [[ -z "${SKIP_LIST:-}" ]]; then
  echo "→ list" >&2
  curl -sS \
    "${JF_URL}/evidence/api/v1/entity/${ENTITY_TYPE}/${ENTITY_ID}" \
    -H "Authorization: Bearer ${JF_ACCESS_TOKEN}" \
    | jq .
fi

echo "OK  entity=${ENTITY_TYPE}/${ENTITY_ID}" >&2
