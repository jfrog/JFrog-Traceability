#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/github-api.sh
source "${SCRIPT_DIR}/../lib/github-api.sh"

github_get_pr_commits_json() {
  local api_url="$1"
  local owner="$2"
  local repo="$3"
  local pr_number="$4"

  gh_get_paginated_array \
    "${api_url}/repos/${owner}/${repo}/pulls/${pr_number}/commits?per_page=100&page=1"
}

github_get_pr_code_committers_json() {
  local api_url="$1"
  local owner="$2"
  local repo="$3"
  local pr_number="$4"
  local commits_json

  commits_json=$(github_get_pr_commits_json "$api_url" "$owner" "$repo" "$pr_number")

  echo "$commits_json" | jq '
    [
      .[]
      | {
          login: (.author.login // null),
          email: ((.commit.author.email // "") | ascii_downcase)
        }
      | select((.login != null and .login != "") or .email != "")
      | . + {key: (if .login != null and .login != "" then "login:" + .login else "email:" + .email end)}
    ]
    | sort_by(.key)
    | group_by(.key)
    | map({
        login: .[0].login,
        email: ([.[].email | select(. != "")] | first // "")
      })
  '
}

github_get_pr_commit_signatures_json() {
  local api_url="$1"
  local owner="$2"
  local repo="$3"
  local pr_number="$4"
  local commits_json

  commits_json=$(github_get_pr_commits_json "$api_url" "$owner" "$repo" "$pr_number")

  echo "$commits_json" | jq '
    [
      .[]
      | {
          sha: (.sha // ""),
          verified: (.commit.verification.verified // false),
          reason: (.commit.verification.reason // "unsigned"),
          signer_login: (.author.login // null)
        }
    ]
  '
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ "$#" -ne 5 ]]; then
    echo "usage: $0 <commits|committers|signatures> <api-url> <owner> <repo> <pr-number>" >&2
    exit 2
  fi

  mode="$1"
  shift

  case "$mode" in
    commits)
      github_get_pr_commits_json "$@"
      ;;
    committers)
      github_get_pr_code_committers_json "$@"
      ;;
    signatures)
      github_get_pr_commit_signatures_json "$@"
      ;;
    *)
      echo "usage: $0 <commits|committers|signatures> <api-url> <owner> <repo> <pr-number>" >&2
      exit 2
      ;;
  esac
fi
