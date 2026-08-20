#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Creates signed JFrog evidence on a gitCommit (or other non-artifact) entity
# by invoking `jf evd create`. Assumes the JFrog CLI is already configured
# (setup-jfrog-cli / jf c) so `jf evd create` can authenticate against the
# platform.
#
# Required env: PREDICATE_FILE, PREDICATE_TYPE, ENTITY_TYPE, ENTITY_ID,
#               EVIDENCE_SIGNING_KEY, EVIDENCE_KEY_ALIAS.
# Optional env: MARKDOWN_FILE (human-readable report attached to the evidence),
#               PROVIDER_ID (default github-actions).
set -euo pipefail
# This script writes the private signing key to disk. Force xtrace off so an
# inherited `set -x` or RUNNER_DEBUG=1 can never echo the PEM into the run log.
set +x

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

: "${PREDICATE_FILE:?PREDICATE_FILE must be set}"
: "${PREDICATE_TYPE:?PREDICATE_TYPE must be set}"
: "${ENTITY_TYPE:?ENTITY_TYPE must be set}"
: "${ENTITY_ID:?ENTITY_ID must be set}"
: "${EVIDENCE_SIGNING_KEY:?EVIDENCE_SIGNING_KEY must be set}"
: "${EVIDENCE_KEY_ALIAS:?EVIDENCE_KEY_ALIAS must be set}"

PROVIDER_ID="${PROVIDER_ID:-github-actions}"

if [[ ! -f "$PREDICATE_FILE" ]]; then
  echo "::error::PREDICATE_FILE not found: ${PREDICATE_FILE}" >&2
  exit 1
fi

# Register cleanup before creating the key file, and create it with a
# restrictive umask, so the private key is never briefly world-readable and is
# always removed on exit (including if a signal arrives mid-write).
cleanup() {
  rm -f evidence-signing-key.pem
}
trap cleanup EXIT
( umask 077; printf '%s\n' "$EVIDENCE_SIGNING_KEY" > evidence-signing-key.pem )
chmod 600 evidence-signing-key.pem

cli_args=(
  evd create
  --entity-type "$ENTITY_TYPE"
  --entity-id "$ENTITY_ID"
  --predicate "$PREDICATE_FILE"
  --predicate-type "$PREDICATE_TYPE"
  --key ./evidence-signing-key.pem
  --key-alias "$EVIDENCE_KEY_ALIAS"
  --provider-id "$PROVIDER_ID"
)

if [[ -n "${MARKDOWN_FILE:-}" ]]; then
  if [[ -f "$MARKDOWN_FILE" ]]; then
    echo "Including markdown report ${MARKDOWN_FILE}" >&2
    cli_args+=(--markdown "$MARKDOWN_FILE")
  else
    echo "::warning::MARKDOWN_FILE set but not found: ${MARKDOWN_FILE}; skipping markdown" >&2
  fi
fi

echo "Creating evidence for entity ${ENTITY_TYPE}/${ENTITY_ID}" >&2
if ! jf "${cli_args[@]}"; then
  echo "::error::evidence create failed" >&2
  exit 1
fi

echo "Evidence uploaded successfully" >&2
