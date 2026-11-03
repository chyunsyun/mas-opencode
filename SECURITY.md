# Security Policy

mas_oc is an unofficial OpenCode-only fork of multi-agent-shogun. This policy applies to mas_oc, not to the original project.

## Supported versions

Security fixes are provided for the current 1.x line. Older snapshots and unmodified upstream copies are not supported by this fork.

## Reporting a vulnerability

Report fork-specific issues privately to the maintainer of this repository. Use the repository's private security advisory feature if it is available. If it is not available, contact the maintainer through the repository's private contact channel.

Do not open a public issue containing exploit details, credentials, or a working proof of concept.

Include:

- The affected commit or version
- The operating system and OpenCode version
- Reproduction steps
- The expected and actual behavior
- The impact you believe is possible
- Any suggested mitigation

Do not send fork-specific reports to the original multi-agent-shogun project. The original project's security page is provided only as a reference for upstream code:

https://github.com/yohey-w/multi-agent-shogun/security

## Scope

In scope:

- The `mas` launcher, `start.sh`, `stop.sh`, and `first_setup.sh`
- `lib/` shell libraries
- `scripts/` helpers, including watchers, inbox writes, model switching, dashboard, and cron setup
- Generated OpenCode agent permissions
- Queue, inbox, task, and report handling
- Documentation that could cause unsafe operation

Out of scope:

- Vulnerabilities in OpenCode itself
- Vulnerabilities in tmux, Python, PyYAML, or the operating system
- Vulnerabilities in upstream multi-agent-shogun code that are unrelated to this fork
- Issues caused by running the environment as root or with an overly privileged account
- Social engineering or physical access

Report OpenCode issues to the OpenCode project. Report upstream issues to the original project.

## Threat model

mas_oc is a local development environment. It runs OpenCode in tmux panes and coordinates work through YAML files. It is not a sandbox and does not provide isolation between the repository, the executing user, and the host.

The main risks are:

- Automatic approval of tool permissions
- Prompt injection from repository content or task text
- Untrusted shell commands executed with the user's privileges
- Secrets or personal data written to the queue, logs, or reports
- Local processes left running after an interrupted session
- Optional external integrations such as ntfy
- Optional cron entries installed by a helper script

## Permission model

Role permissions are defined in `config/opencode-permissions.yaml` and generated into `.opencode/agents/*.md` by `scripts/build_instructions.sh`. OpenCode enforces these permissions for file operations.

This is not an OS-level sandbox. Shell commands, child processes, and files outside the configured permission patterns still run with the operating user's privileges. Review the permission matrix before relying on it for isolation.

`config/settings.yaml` and `config/opencode-permissions.yaml` are protected by the generated permissions, but a local user can still edit them directly.

## Automatic approval

By default, `./mas start` passes `--auto` to OpenCode. This auto-approves permission requests and is convenient for trusted repositories, but it removes the manual confirmation step.

Use manual approval when working with untrusted code:

```bash
./mas start --no-auto
```

`./mas switch-model` restarts the target pane with `--auto`. If you need manual approval, restart the whole environment with `--no-auto` instead of relying on a mid-session model switch.

## Recommended operation

- Run mas_oc as a normal user, not as root.
- Use `--no-auto` for untrusted repositories and unfamiliar tasks.
- Keep the repository and task scope small.
- Do not place API keys, tokens, passwords, or personal data in the queue, logs, reports, or `dashboard.md`.
- Use OpenCode's authentication mechanism for provider credentials.
- Review generated agent definitions after changing permissions.
- Verify that `OPENCODE_BIN` points to a trusted binary.
- Run `./mas stop --verify` after an interrupted session.
- Keep the dashboard viewer on `127.0.0.1`; it does not provide authentication.

## Data handling

Runtime data is stored under the repository in `run/`, `logs/`, `status/`, and `queue/`. These files may contain task descriptions, code excerpts, and test output. Protect them according to the sensitivity of the work.

The environment does not write to `~/.tmux.conf` or `~/.claude`. OpenCode authentication is the only external state used by normal startup and shutdown. Optional helpers may use the user's crontab or an external notification service when explicitly configured.

## Disclosure

Please allow reasonable time for investigation and a fix before public disclosure. The maintainer will coordinate the disclosure timeline with the reporter when possible.
