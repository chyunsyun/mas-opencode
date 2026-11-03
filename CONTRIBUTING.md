# Contributing to mas_oc

mas_oc is an OpenCode-only multi-agent environment. This fork does not include the upstream Android application and does not use bats helper submodules. Use the Makefile targets described below.

## Scope

Contributions are welcome for:

- OpenCode runtime behavior
- Agent instructions and role contracts
- Queue, inbox, and reporting workflows
- Permission generation
- Shell scripts, Python helpers, and documentation
- Tests and reproducible bug reports

Do not add support for other CLIs. `cli.default` is fixed to `opencode`.

## Development setup

Requirements:

- bash
- tmux
- python3 with PyYAML
- OpenCode
- `inotifywait` (optional)

Initialize the local environment:

```bash
make setup
opencode auth login
opencode models
```

Edit `config/settings.yaml` for local model selection. Do not commit that file; it is generated from `config/settings.yaml.sample` and is ignored by Git.

## Build

Generated files are not edited by hand.

```bash
make build
```

This regenerates:

- `AGENTS.md`
- `.opencode/agents/*.md`

The sources are:

- `instructions/AGENTS.md`
- `instructions/roles/*.md`
- `instructions/common/*.md`
- `instructions/opencode_tools.md`
- `config/opencode-permissions.yaml`
- `config/settings.yaml`

If you change a role, a permission rule, or a shared protocol, update the source and run `make build`. Commit the source change and the regenerated output together.

## Lint, test, and consistency checks

```bash
make lint
make test
make check
```

- `make lint` checks shell syntax, compiles Python files, and runs shellcheck when available.
- `make test` is the test entry point for this fork.
- `make check` rebuilds and verifies that generated files are idempotent.

Run all three before opening a pull request. If a check cannot run in your environment, state the reason in the pull request.

Do not add Android build steps, bats submodules, or upstream test helpers that require submodule initialization.

## Generated files

Do not edit these directly:

- `AGENTS.md`
- `.opencode/agents/*.md`

Edit the source files and rebuild.

Protected configuration:

- `config/settings.yaml`
- `config/opencode-permissions.yaml`

`config/settings.yaml` is local and ignored. `config/opencode-permissions.yaml` is the source of truth for role permissions.

## Queue and runtime files

Runtime data is not part of a contribution unless the change explicitly concerns initialization or recovery:

- `queue/`
- `run/`
- `logs/`
- `status/`
- `dashboard.md`

Do not commit runtime data, local model settings, credentials, or logs.

## Documentation

Documentation changes should match the actual scripts and commands. Check every command name against the repository before adding it. Keep Japanese documentation in natural technical Japanese without decorative role-play. Update both `README.md` and `README_ja.md` when the change affects the landing page.

Relative links must point to files that exist in the repository.

## Pull requests

Before opening a pull request:

1. Keep the change focused.
2. Run `make build`, `make lint`, `make test`, and `make check`.
3. Verify that generated files are committed if they changed.
4. Update documentation for user-visible behavior.
5. Confirm that no secrets, credentials, or personal data are included.
6. Preserve the attribution and license notices.

Describe the problem, the change, and the verification you performed. Include the exact commands and results for behavior changes.

## Security

Do not report fork-specific security issues to the original project. See [SECURITY.md](SECURITY.md) for the reporting policy.

## Attribution and license

mas_oc is an unofficial fork of multi-agent-shogun by yohey-w and is based on Claude-Code-Communication by Akira-Papa. Keep the attribution in [docs/attribution.md](docs/attribution.md) and [NOTICE](NOTICE) intact. Contributions are accepted under the MIT License in [LICENSE](LICENSE).
