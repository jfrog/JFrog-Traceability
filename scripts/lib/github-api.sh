#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
# One GitHub REST API client for the whole action, organized in layers so a
# reader sees a single design rather than two parallel implementations.
#
#   transport   gh_http_get                 one GET -> a {status, ok, body}
#                                            envelope. Owns the single copy of
#                                            the token-hygiene + curl pattern.
#   pagination  gh_api_get_paginated        total_count / wrapper list endpoints
#               gh_get_paginated_array      Link-header list endpoints
#   settings    gh_section_get[_paginated]  never-fail: non-2xx degrades to an
#               gh_section_from_result      "unavailable"/"error" section record
#               gh_redact_json              (admin-gated fields must not look
#               gh_api_error_message        like empty configuration).
#   strict      gh_get_required             required data: exit 1 on any non-2xx
#
# The two error models are intentional: repository *settings* may be admin-gated
# and must degrade gracefully, while *pull-request* data is required and should
# fail the run loudly if it cannot be read.
#
# Requires: curl, jq. Expects GITHUB_TOKEN in the environment. All requests go
# to the public GitHub REST API.

GH_API_BASE_URL="https://api.github.com"
GH_API_VERSION="2022-11-28"

# ---------------------------------------------------------------------------
# transport
# ---------------------------------------------------------------------------

# Write the bearer token to a chmod-600 curl --config file and print its path.
# Passing the token via --config (rather than -H) keeps it out of the process
# argument list, where ps/proc would expose it on shared or self-hosted runners.
# The caller owns removing the file (each does so right after curl reads it).
_gh_auth_config() {
  local cfg
  cfg="$(mktemp)"
  chmod 600 "$cfg"
  printf 'header = "Authorization: Bearer %s"\n' \
    "${GITHUB_TOKEN:?GITHUB_TOKEN is required}" > "$cfg"
  printf '%s' "$cfg"
}

# GET a single resource. Accepts either an absolute URL or a path relative to
# GH_API_BASE_URL. Prints an envelope on stdout and never fails the shell:
#   {"status": <http status|000>, "ok": <2xx bool>, "body": <json|string|null>}
gh_http_get() {
  local path="$1"
  local accept_header="${2:-application/vnd.github+json}"
  local url
  if [[ "$path" == http*://* ]]; then
    url="$path"
  else
    url="${GH_API_BASE_URL}${path}"
  fi

  local response_file auth_config status_code
  response_file="$(mktemp)"
  auth_config="$(_gh_auth_config)"

  status_code=$(curl -sS -o "$response_file" -w '%{http_code}' \
    --config "$auth_config" \
    -H "Accept: ${accept_header}" \
    -H "X-GitHub-Api-Version: ${GH_API_VERSION}" \
    "$url" 2>/dev/null) || status_code="000"
  # Remove the token config file immediately after curl reads it, so it never
  # lingers on disk regardless of how the rest of the function exits.
  rm -f "$auth_config"

  local body
  body="$(cat "$response_file" 2>/dev/null || true)"
  rm -f "$response_file"

  if [[ -z "$body" ]]; then
    jq -n --argjson status "$status_code" \
      '{status: $status, ok: ($status >= 200 and $status < 300), body: null}'
  elif printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
    jq -n --argjson status "$status_code" --argjson body "$(printf '%s' "$body" | jq -c .)" \
      '{status: $status, ok: ($status >= 200 and $status < 300), body: $body}'
  else
    jq -n --argjson status "$status_code" --arg body "$body" \
      '{status: $status, ok: ($status >= 200 and $status < 300), body: $body}'
  fi
}

# ---------------------------------------------------------------------------
# pagination
# ---------------------------------------------------------------------------

# GET all pages of a list endpoint, accumulating items across pages. Stops
# early (marking the result partial) if a later page fails after the first
# page succeeded, so already-collected data is not discarded.
#
# Handles both GitHub list conventions:
#   - a bare JSON array (e.g. collaborators, teams, hooks, branches, rulesets)
#   - a {"total_count": N, "<name>": [...]} wrapper (e.g. environments,
#     Actions variables/secrets, deployment branch policies)
# For wrapped responses, pagination continues until the accumulated item
# count reaches total_count rather than relying on page size, since some of
# these endpoints cap per_page below the 100 we request.
gh_api_get_paginated() {
  local path="$1"
  local accept_header="${2:-application/vnd.github+json}"
  local per_page=100
  local page=1
  local separator="?"
  [[ "$path" == *"?"* ]] && separator="&"

  local all_items="[]"
  local wrapper_key=""
  local wrapper_template="{}"
  local use_total_count="false"

  while true; do
    local result status ok body items count
    result="$(gh_http_get "${path}${separator}per_page=${per_page}&page=${page}" "$accept_header")"
    status="$(printf '%s' "$result" | jq -r '.status')"
    ok="$(printf '%s' "$result" | jq -r '.ok')"

    if [[ "$ok" != "true" ]]; then
      if [[ "$page" -eq 1 ]]; then
        printf '%s' "$result"
        return 0
      fi
      if [[ -n "$wrapper_key" ]]; then
        jq -n --argjson status "$status" --arg key "$wrapper_key" --argjson tmpl "$wrapper_template" --argjson items "$all_items" \
          '{status: $status, ok: false, partial: true, body: ($tmpl + {($key): $items, total_count: ($items | length)})}'
      else
        jq -n --argjson status "$status" --argjson items "$all_items" \
          '{status: $status, ok: false, partial: true, body: $items}'
      fi
      return 0
    fi

    body="$(printf '%s' "$result" | jq -c '.body')"

    if [[ "$page" -eq 1 ]]; then
      if [[ "$(printf '%s' "$body" | jq -r 'type')" == "array" ]]; then
        wrapper_key=""
      else
        wrapper_key="$(printf '%s' "$body" | jq -r '
          if type == "object" then
            ([to_entries[] | select(.value | type == "array") | .key] | .[0]) // ""
          else "" end
        ')"
        if [[ -z "$wrapper_key" ]]; then
          # Not a list endpoint at all (single object) - return as-is.
          printf '%s' "$result"
          return 0
        fi
        wrapper_template="$(printf '%s' "$body" | jq -c --arg k "$wrapper_key" 'del(.[$k])')"
        if printf '%s' "$body" | jq -e 'has("total_count")' >/dev/null 2>&1; then
          use_total_count="true"
        fi
      fi
    fi

    if [[ -n "$wrapper_key" ]]; then
      items="$(printf '%s' "$body" | jq -c --arg k "$wrapper_key" '.[$k]')"
    else
      items="$body"
    fi

    count="$(printf '%s' "$items" | jq 'length')"
    all_items="$(jq -c -n --argjson a "$all_items" --argjson b "$items" '$a + $b')"

    if [[ "$use_total_count" == "true" ]]; then
      local total_count accumulated
      total_count="$(printf '%s' "$body" | jq -r '.total_count')"
      accumulated="$(printf '%s' "$all_items" | jq 'length')"
      if [[ "$count" -eq 0 || "$accumulated" -ge "$total_count" ]]; then
        break
      fi
    else
      if [[ "$count" -lt "$per_page" ]]; then
        break
      fi
    fi
    page=$((page + 1))
  done

  if [[ -n "$wrapper_key" ]]; then
    jq -n --argjson status 200 --arg key "$wrapper_key" --argjson tmpl "$wrapper_template" --argjson items "$all_items" \
      '{status: $status, ok: true, body: ($tmpl + {($key): $items, total_count: ($items | length)})}'
  else
    jq -n --argjson status 200 --argjson items "$all_items" '{status: $status, ok: true, body: $items}'
  fi
}

# GET one page for the Link-header paginator, capturing response headers so the
# caller can follow rel="next". Hard-fails (exit 1) on any non-2xx, matching the
# strict layer: these are required pull-request endpoints.
gh_get_page() {
  local url="$1"
  local headers_file="$2"
  local body_file="$3"
  local http_code auth_config
  auth_config="$(_gh_auth_config)"

  http_code=$(curl -sS -D "$headers_file" -o "$body_file" -w "%{http_code}" \
    --config "$auth_config" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: ${GH_API_VERSION}" \
    "$url")
  rm -f "$auth_config"

  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "::error::GET ${url} returned HTTP ${http_code}" >&2
    cat "$body_file" >&2
    rm -f "$headers_file" "$body_file"
    exit 1
  fi
}

# GET every page of a Link-paginated array endpoint and print the concatenated
# JSON array. Used for PR commits and reviews, where GitHub advertises the next
# page via the Link header rather than a total_count wrapper.
gh_get_paginated_array() {
  local url="$1"
  local result="[]"

  while :; do
    local headers_file body_file
    headers_file="$(mktemp)"
    body_file="$(mktemp)"

    gh_get_page "$url" "$headers_file" "$body_file"

    result=$(jq -n --argjson a "$result" --argjson b "$(jq '.' "$body_file")" '$a + $b')

    local next_url
    next_url=$(
      grep -i '^link:' "$headers_file" \
        | tr ',' '\n' \
        | sed -n 's/.*<\([^>]*\)>; rel="next".*/\1/p' \
        | sed -n '1p' \
        || true
    )

    rm -f "$headers_file" "$body_file"

    [[ -z "$next_url" ]] && break
    url="$next_url"
  done

  echo "$result"
}

# ---------------------------------------------------------------------------
# settings layer (never-fail)
# ---------------------------------------------------------------------------

# Recursively strip keys that could carry credential/secret material out of a
# JSON value. This is a defensive net: none of the endpoints we call are
# expected to return secret values, but we never want to accidentally print
# one if GitHub's response shape changes.
gh_redact_json() {
  # Exact key-name match only (case-insensitive) - deliberately narrower than
  # a substring match so that safe plural/container field names GitHub itself
  # uses (e.g. "secrets" listing metadata, "actions_secrets") are not swept up
  # alongside genuinely sensitive singular fields (e.g. "secret", "token").
  #
  # The list also covers credential-bearing singular fields that specific
  # endpoints in the raw snapshot can return: deploy-key material ("key",
  # "pem") from /keys and encrypted Actions secret payloads ("encrypted_value").
  # "config.url" on webhooks is intentionally NOT redacted here - it is not a
  # credential and blanket-redacting every "url" would strip legitimate data.
  jq 'def redact:
        if type == "object" then
          with_entries(
            if (.key | ascii_downcase) as $k
               | ($k | test("^(secret|token|password|private_key|client_secret|authorization|access_token|api_key|refresh_token|key|pem|encrypted_value)$")) then
              .value = "***REDACTED***"
            else
              .value |= redact
            end
          )
        elif type == "array" then
          map(redact)
        else
          .
        end;
      redact'
}

# Extract a short, safe diagnostic message from a failed envelope.
gh_api_error_message() {
  local result="$1"
  local body_type
  body_type="$(printf '%s' "$result" | jq -r '.body | type')"
  if [[ "$body_type" == "object" ]]; then
    printf '%s' "$result" | jq -r '.body.message // "Request did not succeed."'
  elif [[ "$body_type" == "string" ]]; then
    printf '%s' "$result" | jq -r '.body // "Request did not succeed."' | head -c 300
  else
    echo "Request did not succeed."
  fi
}

# Normalize a gh_http_get/gh_api_get_paginated envelope into a section record:
#   {status: "collected"|"unavailable"|"error", http_status, data?, message?, reason?}
# 401/403/404/410 are reported as "unavailable" (token lacks access, or the
# resource does not exist) rather than treated as empty data. Anything else
# unsuccessful is "error". Non-collected records carry a machine-readable
# "reason":
#   401/403 -> "permission_denied"
#   404/410 -> "not_found" (or the caller's override, e.g. "not_supported" for an
#              endpoint that simply does not exist on this GitHub instance)
#   other   -> "error"
#
# The optional 2nd argument overrides the 404/410 reason. It lets a specific
# endpoint distinguish "this GitHub instance does not offer this feature"
# (not_supported) from "this resource was not found" (not_found).
gh_section_from_result() {
  local result="$1"
  local not_found_reason="${2:-not_found}"
  local status ok partial
  status="$(printf '%s' "$result" | jq -r '.status')"
  ok="$(printf '%s' "$result" | jq -r '.ok')"
  partial="$(printf '%s' "$result" | jq -r '.partial // false')"

  if [[ "$partial" == "true" ]]; then
    local data
    data="$(printf '%s' "$result" | jq -c '.body' | gh_redact_json)"
    jq -n --argjson http_status "$status" --argjson data "$data" \
      '{status: "collected", partial: true, http_status: $http_status, data: $data,
        message: "Pagination stopped early after a non-success response; data may be incomplete."}'
    return 0
  fi

  if [[ "$ok" == "true" ]]; then
    local data
    data="$(printf '%s' "$result" | jq -c '.body' | gh_redact_json)"
    jq -n --argjson http_status "$status" --argjson data "$data" \
      '{status: "collected", http_status: $http_status, data: $data}'
    return 0
  fi

  local message
  message="$(gh_api_error_message "$result")"
  case "$status" in
    401|403)
      jq -n --argjson http_status "$status" --arg message "$message" \
        '{status: "unavailable", http_status: $http_status, message: $message, reason: "permission_denied"}'
      ;;
    404|410)
      jq -n --argjson http_status "$status" --arg message "$message" --arg reason "$not_found_reason" \
        '{status: "unavailable", http_status: $http_status, message: $message, reason: $reason}'
      ;;
    *)
      jq -n --argjson http_status "$status" --arg message "$message" \
        '{status: "error", http_status: $http_status, message: $message, reason: "error"}'
      ;;
  esac
}

# Convenience: run gh_http_get then immediately normalize into a section record.
# Optional 3rd arg overrides the 404/410 reason (e.g. "not_supported").
gh_section_get() {
  gh_section_from_result "$(gh_http_get "$1" "${2:-application/vnd.github+json}")" "${3:-not_found}"
}

# Convenience: run gh_api_get_paginated then immediately normalize into a section record.
# Optional 3rd arg overrides the 404/410 reason (e.g. "not_supported").
gh_section_get_paginated() {
  gh_section_from_result "$(gh_api_get_paginated "$1" "${2:-application/vnd.github+json}")" "${3:-not_found}"
}

# ---------------------------------------------------------------------------
# strict layer (fail-fast)
# ---------------------------------------------------------------------------

# GET a required resource and print its body. Exits 1 with an ::error:: log on
# any non-2xx status, so a missing PR / commit / compare aborts the run rather
# than producing partial evidence. Accepts an absolute URL or a base-relative
# path, like gh_http_get.
gh_get_required() {
  local url="$1"
  local result status
  result="$(gh_http_get "$url")"
  status="$(printf '%s' "$result" | jq -r '.status')"

  if [[ "$(printf '%s' "$result" | jq -r '.ok')" != "true" ]]; then
    echo "::error::GET ${url} returned HTTP ${status}" >&2
    printf '%s' "$result" | jq -r '.body | if type == "string" then . else tojson end' >&2
    exit 1
  fi

  printf '%s' "$result" | jq -c '.body'
}

# Resolve PR_NUMBER from GITHUB_SHA when the caller did not supply one. The
# action fires on both pull_request (where the event payload carries the PR
# number) and push (where it does not); on a merge-to-main push we still need
# to identify which pull request produced the merge commit. Queries
# /repos/{owner}/{repo}/commits/{sha}/pulls and takes the first merged entry.
# Exits 1 when no merged PR is associated with the commit.
resolve_pr_number() {
  if [[ -n "${PR_NUMBER:-}" ]]; then
    return
  fi
  : "${GITHUB_SHA:?GITHUB_SHA must be set to resolve PR_NUMBER from the merge commit}"
  : "${GH_OWNER:?GH_OWNER must be set (call resolve_owner_repo first)}"
  : "${GH_REPO:?GH_REPO must be set (call resolve_owner_repo first)}"

  local body
  body="$(gh_get_required "/repos/${GH_OWNER}/${GH_REPO}/commits/${GITHUB_SHA}/pulls")"
  PR_NUMBER="$(printf '%s' "$body" | jq -r 'map(select(.merged_at != null)) | .[0].number // empty')"

  if [[ -z "$PR_NUMBER" ]]; then
    echo "::error::No merged pull request found for commit ${GITHUB_SHA}" >&2
    exit 1
  fi
  export PR_NUMBER
}
