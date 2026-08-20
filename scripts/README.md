# Local entity evidence smoke test
[`smoke-entity-evidence.sh`](smoke-entity-evidence.sh) creates signed evidence
on a `gitCommit` entity (keyed by the merge commit sha) by invoking
`jf evd create --entity-type gitCommit --entity-id <sha>`.
It uses the **default** entity repository `gitCommit-entity` (no `project_key` /
`application-key` / `repo` scope).
Default sample data is [`fixtures/unified-github-pull-request-predicate.json`](fixtures/unified-github-pull-request-predicate.json)
(unified github-pull-request predicate). Markdown is rendered from that predicate with
[`build-markdown.sh`](build-markdown.sh). The entity id defaults to
`.pull_request_merge.merge.merge_commit_sha` read from the fixture.
Requires a platform Evidence build that supports entity evidence APIs (i.e.
attaching evidence to entity subjects such as `gitCommit`).
## Prerequisites
- `curl`, `jq`, `node`, `openssl`
- Artifactory repository named **`gitCommit-entity`**
- Access token that can **annotate** that repository
- Evidence signing key (private PEM) whose public key is registered under the
  alias you pass as `EVIDENCE_KEY_ALIAS`
## Run
From the repository root:
```bash
JF_URL=http://localhost:8082 \
EVIDENCE_SIGNING_KEY_FILE=./private.pem \
EVIDENCE_KEY_ALIAS=<key-alias> \
bash scripts/smoke-entity-evidence.sh
```
Or with the PEM contents in the environment:
```bash
JF_URL=http://localhost:8082 \
EVIDENCE_SIGNING_KEY="$(cat ./private.pem)" \
EVIDENCE_KEY_ALIAS=<key-alias> \
bash scripts/smoke-entity-evidence.sh
```
## Environment
| Variable | Required | Description |
| `JF_URL` | yes | Platform base URL (e.g. `http://localhost:8082`) |
| `JF_ACCESS_TOKEN` | yes | Bearer token |
| `EVIDENCE_SIGNING_KEY_FILE` | one of | Path to private PEM file |
| `EVIDENCE_SIGNING_KEY` | one of | Private PEM contents |
| `EVIDENCE_KEY_ALIAS` | yes | Signing key alias in Artifactory |
| `ENTITY_TYPE` | no | Entity type (default: `gitCommit`) |
| `ENTITY_ID` | no | Entity id (default: `.pull_request_merge.merge.merge_commit_sha` from the fixture) |
| `PREDICATE_FILE` | no | Predicate JSON (default: unified fixture) |
| `MARKDOWN_FILE` | no | Markdown override (default: rendered from predicate) |
| `PROVIDER_ID` | no | Default `github-actions` |
| `SKIP_LIST` | no | If set, skip the final list GET |
## What it does
1. Loads the unified predicate fixture (or `PREDICATE_FILE`)
2. Renders markdown via `build-markdown.sh` (or uses `MARKDOWN_FILE`)
3. Configures a transient JFrog CLI server context from `JF_URL` +
   `JF_ACCESS_TOKEN`
4. Runs `jf evd create --entity-type gitCommit --entity-id <sha>` with the
   predicate, markdown, key, and key alias
5. `GET /evidence/api/v1/entity/gitCommit/<gitSha>` to list evidence (unless
   `SKIP_LIST` is set)
On success, `jf evd create` prints the created evidence details and, when
listing is enabled, stdout shows the list response.
