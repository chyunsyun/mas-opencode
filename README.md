# mas_oc

mas_oc is an OpenCode-only multi-agent development environment for local repositories. It can use free AI models for OpenCode, so you can run a multi-agent setup without additional cost. Six fixed agents run in six panes of a single tmux window, so the whole team fits on one screen. They coordinate through YAML commands, tasks, and reports, and the queue is the source of truth, so work can resume after a context reset.

This is an unofficial fork of [multi-agent-shogun](https://github.com/yohey-w/multi-agent-shogun), redesigned around OpenCode and a compact six-person team.

## Highlights

- OpenCode only. The runtime starts OpenCode in every pane and does not manage other CLIs.
- Free AI models for OpenCode, so multi-agent operation needs no additional cost. Free-model availability and rate limits can change.
- One-screen operation. All six panes live in a single tmux window, so the whole team fits on one screen.
- Six fixed roles with a clear chain of command.
- Event-driven coordination through inbox messages, tasks, and reports.
- YAML-based state that survives restarts and context resets.
- Role-specific OpenCode permissions generated from one matrix.
- Small, bounded model for lightweight work through `max_bloom`.
- Runtime data stays inside the repository.

## Team

| agent_id | Label | Responsibility |
|---|---|---|
| `director` | 部長 | Human interface, command authoring, final decisions |
| `chief` | 係長 | Breakdown, assignment, progress, QC coordination |
| `engineer1` | エンジニア1 | Implementation, tests, reports |
| `engineer2` | エンジニア2 | Implementation, tests, reports |
| `engineer3` | エンジニア3 | Lightweight tasks only, Bloom L1-L3, `max_bloom: 3` |
| `auditor` | 監査役 | Independent quality review, evidence-based verdicts, RCA |

The command chain is:

```
Human <-> director <-> chief <-> engineer1 / engineer2 / engineer3
                          <-> auditor
```

`director` does not instruct engineers directly. `chief` creates tasks and assigns them. `engineer1`-`engineer3` and `auditor` report to `chief`.

## Requirements

- Linux, macOS, or WSL2
- bash
- tmux
- python3 with PyYAML
- OpenCode (`opencode`)
- `inotifywait` is optional; watchers fall back to polling

Use `OPENCODE_BIN` to point at a non-standard OpenCode binary. A terminal around 240x50 is recommended for the default layout.

## Quick start

```bash
cd mas_oc
./mas setup
# Only for paid providers
opencode auth login
# Change the model only if needed
$EDITOR config/settings.yaml
./mas build
./mas start
```

`./mas setup` creates `config/settings.yaml` from `config/settings.yaml.sample`, initializes the queue, and generates agent definitions. On first setup it selects free models from `opencode models --verbose`, preferring `opencode/*-free`; `opencode-go/*-free` is used only as a fallback. director / chief / auditor / engineer1 / engineer2 use a high-capability model, while engineer3 uses a speed-oriented model. `capability_tiers` is set to 4 for the high-capability model and 3 for engineer3. Existing `model` values are not overwritten.

Re-select with `./mas setup --select-free-model`, set a model explicitly with `./mas setup --free-model provider/model`, or disable automatic selection with `./mas setup --no-select-free-model`. The model list is refreshed with `opencode models --refresh` by default; if that fails, the cached list is used. Use `--no-refresh-free-models` to use only the cache. If no free model is available, `model` stays empty and setup continues.

`./mas setup` refuses to run while the same `mas_oc` instance is running, because running agents would keep their old settings. Stop it first, or pass `--allow-running` to force the change (running agents are not updated until they restart).

`./mas start` starts the six agents at a 15-second interval by default; a full start takes about 75 seconds. It runs a build automatically only when `.opencode/agents/director.md` is missing. Run `./mas build` after editing settings or instruction sources.

## Commands

| Command | Behavior |
|---|---|
| `./mas setup` | Initial setup, free-model selection, and agent generation |
| `./mas setup --select-free-model` | Re-select free models even when models are already configured |
| `./mas setup --no-select-free-model` | Disable automatic free-model selection |
| `./mas setup --free-model provider/model` | Set the specified free model for all agents |
| `./mas setup --no-refresh-free-models` | Use the cached model list |
| `./mas setup --allow-running` | Change settings while running (running agents are not updated) |
| `./mas start` | Start all six agents in one tmux window |
| `./mas start --clean` | Back up and reset the queue, then start |
| `./mas start --purge --yes` | Delete usage history without backup, reset models to free models, then start |
| `./mas start --setup-only` | Create tmux panes and configuration without starting OpenCode or watchers |
| `./mas start --no-auto` | Start without passing `--auto` to OpenCode |
| `./mas start --layout 2x3` | Use two columns and three rows for tall screens |
| `./mas start --start-interval SEC` | Set the OpenCode startup interval (default 15 seconds) |
| `./mas status` | Show pane state, task status, and unread inbox counts |
| `./mas stop` | Stop scoped processes, panes, session, and managed cron block |
| `./mas stop --verify` | Check for leftovers without stopping anything |
| `./mas build` | Regenerate `.opencode/agents/*.md` and `AGENTS.md` |
| `./mas switch-model <agent> --model <provider/model> [--force]` | Change a model, rebuild, and respawn the pane; busy agents require `--force` |
| `./mas dashboard` | Serve `dashboard.md` at `http://127.0.0.1:8787` |
| `./mas version` | Print the version |

`./mas start --purge --yes` is irreversible. It deletes `queue/`, `dashboard.md`, `memory/MEMORY.md`, `memory/global_context.md`, `logs/`, `reports/`, `status/`, and `run/` history, then re-selects free models for all six agents. No backup is created. If no free model can be selected, every agent is set to `openrouter/free`. OpenCode session history under `~/.local/share/opencode` is not deleted.

`./mas stop` is idempotent and safe to rerun. It is scoped to this repository and the `mas` tmux session; it does not run a global `pkill`.

## Layout

The default layout is three columns by two rows:

```
+-----------+-----------+-----------+
| director  | chief     | auditor   |
+-----------+-----------+-----------+
| engineer1 | engineer2 | engineer3 |
+-----------+-----------+-----------+
```

The tmux session is `mas` and the window is `team`. For a tall terminal, use `./mas start --layout 2x3`.

## Model routing

Models are configured per agent:

```yaml
cli:
  default: opencode
  agents:
    engineer1:
      type: opencode
      model: "provider/model"
    engineer3:
      type: opencode
      model: "provider/model"
      max_bloom: 3

capability_tiers:
  "provider/model":
    max_bloom: 3
```

`engineer3` must only receive Bloom level 1-3 work. Tasks at level 4 or higher exclude `engineer3` and require another engineer, a model switch, or escalation. `find_engineer_for_bloom` implements the allocation rule. The effective `max_bloom` is the lower of the model tier and the agent override.

On first setup, models with `cost` 0 are selected from `opencode models --verbose`, preferring `opencode/*-free`; `opencode-go/*-free` is used only as a fallback. director / chief / auditor / engineer1 / engineer2 use a high-capability model, while engineer3 uses a speed-oriented model (`flash` / `lightning` families first). The selection is recorded in `model_selection`, and capability limits are recorded in `capability_tiers`.

The automatic tiers are `max_bloom: 4` for the high-capability model and `max_bloom: 3` for engineer3's speed-oriented model. Bloom L5/L6 exceed the high model's tier 4, so use `./mas switch-model` for a stronger model or adjust `capability_tiers` manually. The engineer3 `max_bloom: 3` override is preserved.

Existing `model` values are not overwritten. Re-select with `./mas setup --select-free-model`, set an explicit model with `./mas setup --free-model provider/model`, or disable automatic selection with `./mas setup --no-select-free-model`. If `opencode models --refresh` fails, the cached model list is used. If no free model is available, `model` stays empty. Free-model availability and rate limits change; check `opencode models --verbose` periodically.

`./mas switch-model` updates `config/settings.yaml`, rebuilds generated agents, and respawns the agent pane. If the target agent is busy, it refuses and exits without changing settings; use `--force` only with explicit approval.

## Queue and runtime

| Path | Purpose |
|---|---|
| `queue/inbox/<id>.yaml` | Agent messages |
| `queue/tasks/<id>.yaml` | Active task per agent |
| `queue/reports/<id>_report.yaml` | Reports from engineers and auditor |
| `queue/commands.yaml` | Open commands |
| `queue/pending.yaml` | Deferred work |
| `dashboard.md` | Human-facing summary |

Inbox messages contain `id`, `from`, `timestamp`, `type`, `content`, and `read`. Write messages with:

```bash
bash scripts/inbox_write.sh <target> "<message>" <type> <from>
```

Mark processed messages as read with the `mark-as-read` OpenCode tool (`.opencode/tools/mark-as-read.ts`). Do not edit inbox YAML directly.

Runtime data stays under `mas_oc` in `run/`, `logs/`, `status/`, and `queue/`. The environment does not write to `~/.tmux.conf` or `~/.claude`. OpenCode authentication is the only external state.

## Security

By default, `./mas start` passes `--auto` to OpenCode, which auto-approves permission requests. Use `./mas start --no-auto` when you want manual approval. Role permissions are defined in `config/opencode-permissions.yaml` and generated into `.opencode/agents/*.md`. Do not put secrets or credentials in the queue, logs, or reports.

## Documentation

- [Quick start](docs/quickstart.md)
- [Manual](docs/manual.md)
- [Attribution](docs/attribution.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)

## Attribution

- Original project: multi-agent-shogun by yohey-w, https://github.com/yohey-w/multi-agent-shogun
- License: MIT, Copyright (c) 2026 yohey-w
- Based on Claude-Code-Communication by Akira-Papa
- mas_oc is an unofficial fork with modifications; not affiliated with the original author.

See [docs/attribution.md](docs/attribution.md) and [NOTICE](NOTICE) for details.

## License

MIT. See [LICENSE](LICENSE).
