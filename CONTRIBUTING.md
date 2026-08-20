# Contributing

Thanks for your interest in contributing to JFrog Traceability! Contributions of
all kinds are welcome — bug reports, feature requests, documentation, and code.

## Contributor License Agreement (CLA)

Before we can accept your contribution, you must sign the JFrog Contributor
License Agreement. This is a one-time process handled automatically on your first
pull request by a bot that will comment with a signing link.

- JFrog CLA: https://jfrog.com/cla/

Pull requests cannot be merged until the CLA check passes.

## Development

This project is a composite GitHub Action written in Bash.

- **Lint:** `shellcheck` and `actionlint` run in CI on every push and pull
  request. Run `shellcheck` locally on any script you change.
- **Test:** the fixture-driven suites live under `tests/`. Run them with:

  ```bash
  bash tests/run-tests.sh
  ```

Please make sure lint and tests pass before opening a pull request.

## Copyright headers

Every source file must begin with a JFrog copyright header. For shell scripts,
place it immediately after the shebang:

```bash
#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
```

## Pull requests

1. Fork the repository and create a topic branch.
2. Make your change, keeping commits focused and messages descriptive.
3. Ensure `shellcheck`, `actionlint`, and `tests/run-tests.sh` pass.
4. Open a pull request describing the change and the motivation behind it.
5. Sign the CLA when prompted.

## Reporting issues

Please open a GitHub issue with a clear description, reproduction steps where
applicable, and the expected versus actual behavior.
