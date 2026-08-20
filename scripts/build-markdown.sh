#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# Renders a human-readable, per-run markdown report from the github-pull-request
# predicate document. The report is attached to the evidence via
# `jf evd create --markdown` so it is legible in the JFrog UI.
#
# The JFrog Evidence markdown viewer HTML-escapes and then literally displays
# the characters " < > (as &#34; &lt; &gt;). Everything emitted here therefore
# avoids those characters: no JSON/quotes/angle-brackets, only headings, bold
# bullet lists, backtick code spans, tables, and markdown links. A `safe`
# helper strips any stray " < > that sneaks in from collected data.
#
# Required env: PREDICATE_FILE.
# Optional env: SUBJECT_FILE (pull-request-merge identity), MARKDOWN_OUT
#               (default markdown.md).
set -euo pipefail

: "${PREDICATE_FILE:?PREDICATE_FILE must be set}"
MARKDOWN_OUT="${MARKDOWN_OUT:-markdown.md}"

# Shared jq helpers, defined once and prepended to the report filter:
#   safe  strip the " < > characters the JFrog markdown viewer escapes, and
#         escape pipe so collected values can't break out of a table cell.
#   dash  render an em dash for empty/null instead of a blank cell.
MD_HELPERS='
  def safe: if . == null then "" else (tostring | gsub("[<>\"]"; "") | gsub("\\|"; "\\|")) end;
  def dash: if . == null or . == "" then "—" else (. | safe) end;
'

subject_json='{}'
if [ -n "${SUBJECT_FILE:-}" ] && [ -f "$SUBJECT_FILE" ]; then
  subject_json="$(< "$SUBJECT_FILE")"
fi

jq -r --argjson subj "$subject_json" "$MD_HELPERS"'
  def repo_slug: ($subj.repo_url // "") | safe | (split("/") | if length >= 2 then .[-2:] | join("/") else (. | join("/")) end);

  .pull_request_merge as $pm

  | "# Github Pull Request Evidence Report\n"

  + "\n## Summary\n"
  + "- **Repository:** " + (repo_slug | if . == "" then "—" else . end) + "\n"
  + "- **Pull request:** #" + (($subj.pr_number // "—") | safe) + "\n"
  + "- **Target branch:** " + ($pm.merge.target_branch | dash) + "\n"
  + "- **Merged by:** " + ($pm.merge.merged_by | dash) + "\n"
  + "- **Merged at:** " + ($pm.merge.merged_at | dash) + "\n"
  + "\n## Merge Details\n"
  + "- **Merge commit:** `" + ($pm.merge.merge_commit_sha | dash) + "`\n"
  + "- **Target base SHA:** `" + ($pm.merge.target_base_sha | dash) + "`\n"
  + "- **Head branch:** " + (($subj.head_ref // null) | dash) + "\n"
  + "- **Head SHA:** `" + (($subj.head_sha // null) | dash) + "`\n"
  + "- **Collected at:** " + ($pm.collection.collected_at | dash) + "\n"
  + "- **Workflow run:** " + ($pm.collection.workflow_run_url | dash) + "\n"
  + "\n## Approvers (" + (($pm.approvers // []) | length | tostring) + ")\n\n"
  + (if (($pm.approvers // []) | length) == 0 then "_None_\n"
     else "| Login | Email | Submitted At | Approved PR Head |\n|---|---|---|---|\n"
       + (($pm.approvers // []) | map(
           "| " + (.login | dash) + " | "
           + ((.email // "") | safe | if . == "" then "—" else "[" + . + "](mailto:" + . + ")" end) + " | "
           + (.submitted_at | dash) + " | "
           + (if .is_pr_head_approval then "yes" else "no" end) + " |"
         ) | join("\n")) + "\n" end)
  + "\n## Commits on Target Branch (" + (($pm.commits_on_target_branch // []) | length | tostring) + ")\n\n"
  + (if (($pm.commits_on_target_branch // []) | length) == 0 then "_None_\n"
     else (($pm.commits_on_target_branch // []) | map("- `" + (. | safe) + "`") | join("\n")) + "\n" end)
  + "\n## Code Committers (" + (($pm.code_committers // []) | length | tostring) + ")\n\n"
  + (if (($pm.code_committers // []) | length) == 0 then "_None_\n"
     else "| Login | Email |\n|---|---|\n"
       + (($pm.code_committers // []) | map(
           "| " + (.login | dash) + " | "
           + ((.email // "") | safe | if . == "" then "—" else "[" + . + "](mailto:" + . + ")" end) + " |"
         ) | join("\n")) + "\n" end)
  + "\n## Commit Signatures (" + (($pm.commit_signatures // []) | length | tostring) + ")\n\n"
  + "- **All commits verified:** " + (if $pm.all_commits_verified then "yes" else "no" end) + "\n\n"
  + (if (($pm.commit_signatures // []) | length) == 0 then "_None_\n"
     else "| Commit | Verified | Reason | Signer |\n|---|---|---|---|\n"
       + (($pm.commit_signatures // []) | map(
           "| `" + (.sha | safe) + "` | "
           + (if .verified then "yes" else "no" end) + " | "
           + (.reason | dash) + " | "
           + (.signer_login | dash) + " |"
         ) | join("\n")) + "\n" end)
' "$PREDICATE_FILE" > "$MARKDOWN_OUT"

echo "Wrote ${MARKDOWN_OUT}" >&2
