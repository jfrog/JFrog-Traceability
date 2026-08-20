#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Tests for scripts/generate-evidence.sh: that main() runs one
# collect->build->create pass with a gitCommit entity whose id is the merge
# commit sha sourced from the unified predicate JSON. Collaborators are stubbed
# so no collectors or JFrog API calls run.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${TESTS_DIR}/.." &>/dev/null && pwd)"

# shellcheck source=./lib/test_helpers.sh
source "${TESTS_DIR}/lib/test_helpers.sh"

export GITHUB_REPOSITORY="acme/widget"
export PR_NUMBER="123"
export EVIDENCE_SIGNING_KEY="unused-in-stub"
export EVIDENCE_KEY_ALIAS="unused-in-stub"

# Set up a fake scripts/ tree that mirrors the real layout so generate-evidence.sh
# resolves ${SCRIPT_DIR}/... to our stubs while still sourcing the real lib/.
setup_fake_scripts_dir() {
  local target="$1" sha="$2"
  mkdir -p "${target}/pull-request-merge"
  ln -s "${REPO_ROOT}/scripts/lib" "${target}/lib"
  cat > "${target}/pull-request-merge/collect-pr-merge.sh" <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
  cat > "${target}/build-predicate.sh" <<EOF
#!/usr/bin/env bash
cat > predicate.json <<'PJSON'
{"pull_request_merge":{"merge":{"merge_commit_sha":"${sha}"}}}
PJSON
echo '{}' > subject.json
EOF
  cat > "${target}/build-markdown.sh" <<'EOF'
#!/usr/bin/env bash
echo '# report' > report.md
EOF
  cat > "${target}/create-entity-evidence.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$ENTITY_TYPE" > entity_type.txt
printf '%s\n' "$ENTITY_ID" > entity_id.txt
printf '%s\n' "$PREDICATE_TYPE" > predicate_type.txt
EOF
  cp "${REPO_ROOT}/scripts/generate-evidence.sh" "${target}/generate-evidence.sh"
  chmod +x "${target}"/*.sh "${target}/pull-request-merge"/*.sh
}

test_main_emits_gitcommit_entity_with_merge_sha_id() {
  local tmp sha saw_entity_type saw_entity_id
  tmp="$(mktemp -d)"
  sha="0123456789abcdef0123456789abcdef01234567"
  (
    cd "$tmp" || exit 1
    setup_fake_scripts_dir "${tmp}/fake_scripts" "$sha"
    bash "${tmp}/fake_scripts/generate-evidence.sh"
  )

  saw_entity_type="$(< "${tmp}/entity_type.txt")"
  saw_entity_id="$(< "${tmp}/entity_id.txt")"
  assert_equal "gitCommit" "$saw_entity_type" "entity type is gitCommit" || return 1
  assert_equal "$sha" "$saw_entity_id" "entity id is the merge commit sha" || return 1
  rm -rf "$tmp"
}

test_main_fails_when_merge_sha_missing_from_predicate() {
  local tmp rc
  tmp="$(mktemp -d)"
  (
    cd "$tmp" || exit 1
    mkdir -p fake_scripts/pull-request-merge
    ln -s "${REPO_ROOT}/scripts/lib" fake_scripts/lib
    cat > fake_scripts/pull-request-merge/collect-pr-merge.sh <<'EOF'
#!/usr/bin/env bash
echo '{"ok":true}'
EOF
    # Predicate is present but has no merge_commit_sha field.
    cat > fake_scripts/build-predicate.sh <<'EOF'
#!/usr/bin/env bash
echo '{"pull_request_merge":{"merge":{}}}' > predicate.json
echo '{}' > subject.json
EOF
    cat > fake_scripts/build-markdown.sh <<'EOF'
#!/usr/bin/env bash
echo '# report' > report.md
EOF
    cat > fake_scripts/create-entity-evidence.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$ENTITY_TYPE" > entity_type.txt
printf '%s\n' "$ENTITY_ID" > entity_id.txt
EOF
    cp "${REPO_ROOT}/scripts/generate-evidence.sh" fake_scripts/generate-evidence.sh
    chmod +x fake_scripts/*.sh fake_scripts/pull-request-merge/*.sh
  )

  set +e
  ( cd "$tmp" && bash "${tmp}/fake_scripts/generate-evidence.sh" ) >/dev/null 2>&1
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "  FAIL: expected non-zero exit when predicate lacks merge_commit_sha" >&2
    rm -rf "$tmp"
    return 1
  fi
  if [[ -f "${tmp}/fake_scripts/entity_id.txt" || -f "${tmp}/entity_id.txt" ]]; then
    echo "  FAIL: create-entity-evidence.sh should not run when the sha is missing" >&2
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"
}

run_test test_main_emits_gitcommit_entity_with_merge_sha_id
run_test test_main_fails_when_merge_sha_missing_from_predicate

report_results
