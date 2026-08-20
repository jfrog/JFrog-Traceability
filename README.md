# JFrog Traceability

A GitHub Action that records signed **JFrog evidence** for every pull request merged into a configured target branch. Evidence is keyed by the merge commit sha and travels with your software through Artifactory and AppTrust.

The action uses the JFrog CLI to record evidence — you only supply your JFrog OIDC provider and signing key.

## Why

Review and merge controls (required reviews, signed commits) live in GitHub. By the time an artifact is promoted, there's no tamper-evident proof it was actually reviewed. This action captures that context as signed evidence on the merge commit so **AppTrust lifecycle policies** can gate releases on it.

## What it records

One `github-pull-request` evidence per merge, containing:

- **Merge metadata** — e.g. target branch, merge sha
- **Approvers** — e.g. reviewers, approved shas
- **Commits** — e.g. code committers, per-commit signature verification

Full schema: [`predicates/github-pull-request.json`](predicates/github-pull-request.json).

## How to use

Add the action to a workflow that runs when a pull request is merged into your target branch:

```yaml
name: JFrog Traceability
on:
  pull_request:
    types: [closed]
    branches: [main]
permissions:
  contents: read
  pull-requests: read
  id-token: write
jobs:
  git-evidence:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    steps:
      - uses: jfrog/github-evidence@v1
        with:
          jf_url: ${{ vars.JF_URL }}
          oidc_provider_name: ${{ vars.JF_OIDC_PROVIDER }}
          evidence_signing_key: ${{ secrets.EVIDENCE_KEY }}
          evidence_key_alias: ${{ vars.EVIDENCE_KEY_ALIAS }}
```

On each merge, the action records one signed `github-pull-request` evidence on the merge commit. A runnable copy lives in [`examples/git-evidence.yml`](examples/git-evidence.yml).

## Inputs

| Input | Required | Description |
|---|---|---|
| `jf_url` | yes | JFrog platform host (bare host or URL). |
| `oidc_provider_name` | yes | OIDC integration name in the JFrog platform. The identity mapping typically follows `{org}/{repo}@github`. |
| `evidence_signing_key` | yes | Private signing key (raw PEM contents). |
| `evidence_key_alias` | yes | Public-key alias registered in the platform. |

## Prerequisites

One-time platform setup:

1. **Evidence signing key** — generate a key pair and upload the public key under an alias, for example with the JFrog CLI:

```bash
jf evd generate-key-pair --key-alias my-key-alias
```
Store the resulting private PEM as the `EVIDENCE_KEY` secret.

2. **OIDC integration** under **Administration → OIDC** with an identity mapping for this repository. The identity the token maps to needs at least **Read** and **Annotate** permissions on the target repository to upload evidence.
3. **GitHub config**: secret `EVIDENCE_KEY`; variables `JF_URL`, `JF_OIDC_PROVIDER`, `EVIDENCE_KEY_ALIAS`.

## On the JFrog platform

When the merged artifact is bundled into an **AppTrust application version** and promoted, AppTrust consumes this evidence automatically and lifecycle policies can gate the promotion. See [AppTrust lifecycle policies](https://jfrog.com/help/r/jfrog-apptrust-documentation/lifecycle-policy-management).
