#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Small cross-cutting helpers shared by the collector and builder scripts.
#
# Sourced, not executed: no `set` here — the file inherits the caller's shell
# options (every entry script sets `set -euo pipefail` itself).
#
# Standard runner-provided environment used below: GITHUB_REPOSITORY,
# GITHUB_SERVER_URL, GITHUB_RUN_ID.

# Split GITHUB_REPOSITORY ("owner/name") into the canonical GH_OWNER / GH_REPO
# globals every script uses. Honors pre-set values so a caller can override.
resolve_owner_repo() {
  : "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set (automatically provided by the runner)}"
  GH_OWNER="${GH_OWNER:-${GITHUB_REPOSITORY%%/*}}"
  GH_REPO="${GH_REPO:-${GITHUB_REPOSITORY##*/}}"
}

# One RFC 3339 / ISO 8601 UTC timestamp format for the whole suite, with
# millisecond precision (…T…:…:…​.000Z), so collected documents are consistent.
rfc3339_now() {
  date -u +%Y-%m-%dT%H:%M:%S.000Z
}

# Build the URL of the current workflow run for provenance links. Falls back to
# github.com and an empty run id when those are not in the environment.
workflow_run_url() {
  local server_url="${GITHUB_SERVER_URL:-https://github.com}"
  printf '%s/%s/actions/runs/%s' \
    "$server_url" "${GITHUB_REPOSITORY:-}" "${GITHUB_RUN_ID:-}"
}
