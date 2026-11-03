#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAS_ROOT="${MAS_ROOT:-$SCRIPT_DIR}"
source "${MAS_ROOT}/lib/agent_registry.sh"
source "${MAS_ROOT}/lib/runtime_guard.sh"

NON_INTERACTIVE=0
RESET_QUEUE=0
SELECT_FREE_MODE="auto"
REFRESH_FREE_MODELS=1
FREE_MODEL=""
ALLOW_RUNNING=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --non-interactive) NON_INTERACTIVE=1; shift ;;
        --reset-queue) RESET_QUEUE=1; shift ;;
        --select-free-model) SELECT_FREE_MODE="force"; shift ;;
        --no-select-free-model) SELECT_FREE_MODE="off"; shift ;;
        --free-model)
            FREE_MODEL="${2:-}"
            if [[ -z "$FREE_MODEL" ]]; then
                echo "--free-model requires a provider/model id" >&2
                exit 1
            fi
            SELECT_FREE_MODE="force"
            shift 2
            ;;
        --refresh-free-models) REFRESH_FREE_MODELS=1; shift ;;
        --no-refresh-free-models) REFRESH_FREE_MODELS=0; shift ;;
        --allow-running) ALLOW_RUNNING=1; shift ;;
        -h|--help)
            cat <<'EOF'
Usage: ./first_setup.sh [options]
  --non-interactive          対話せず既定値で初期化する
  --reset-queue              queue をバックアップして初期化する
  --select-free-model        既存設定でも無料モデルを再選択する
  --no-select-free-model     無料モデルの自動選択を無効化する
  --free-model MODEL         指定した無料モデルを全エージェントに設定する
  --refresh-free-models      opencode models --refresh を実行する（既定）
  --no-refresh-free-models   キャッシュされたモデル一覧を使う
  --allow-running            稼働中でも設定を変更する（実行中エージェントには未反映）
EOF
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

log() { echo "[setup] $*"; }

if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import yaml' >/dev/null 2>&1; then
    echo "ERROR: python3 と PyYAML が必要です。" >&2
    echo "  Ubuntu/Debian: sudo apt-get install python3 python3-yaml" >&2
    exit 1
fi
if ! command -v tmux >/dev/null 2>&1; then
    echo "ERROR: tmux が必要です。" >&2
    exit 1
fi
if ! command -v opencode >/dev/null 2>&1; then
    echo "WARN: opencode が見つかりません。インストール後に ./mas start を実行してください。"
fi
if ! command -v inotifywait >/dev/null 2>&1; then
    echo "WARN: inotifywait が見つかりません。watcher はポーリングで動作します。"
fi

if mas_root_is_running "$MAS_ROOT"; then
    if [[ "$ALLOW_RUNNING" != "1" ]]; then
        echo "ERROR: mas_oc が稼働中です。設定を変更する前に ./mas stop で停止してください。" >&2
        echo "  稼働中に変更する場合は --allow-running を指定してください（実行中エージェントには反映されません）。" >&2
        exit 1
    fi
    echo "WARN: --allow-running: 稼働中に設定を変更します。実行中エージェントには次回起動/再起動まで反映されません。" >&2
fi

mkdir -p \
    "${MAS_ROOT}/config" \
    "${MAS_ROOT}/queue/tasks" \
    "${MAS_ROOT}/queue/reports" \
    "${MAS_ROOT}/queue/inbox" \
    "${MAS_ROOT}/queue/metrics" \
    "${MAS_ROOT}/logs" \
    "${MAS_ROOT}/run" \
    "${MAS_ROOT}/status" \
    "${MAS_ROOT}/memory" \
    "${MAS_ROOT}/context" \
    "${MAS_ROOT}/projects" \
    "${MAS_ROOT}/reports"

if [[ "$RESET_QUEUE" == "1" ]]; then
    backup="${MAS_ROOT}/logs/backup_$(date '+%Y%m%d_%H%M%S')"
    mkdir -p "$backup"
    if [[ -d "${MAS_ROOT}/queue" ]]; then
        cp -a "${MAS_ROOT}/queue/." "$backup/" 2>/dev/null || true
    fi
    [[ -f "${MAS_ROOT}/dashboard.md" ]] && cp -a "${MAS_ROOT}/dashboard.md" "$backup/" 2>/dev/null || true
    rm -rf "${MAS_ROOT}/queue"
    mkdir -p "${MAS_ROOT}/queue/tasks" "${MAS_ROOT}/queue/reports" "${MAS_ROOT}/queue/inbox" "${MAS_ROOT}/queue/metrics"
    log "queue を ${backup} にバックアップして初期化しました。"
fi

if [[ ! -f "${MAS_ROOT}/config/settings.yaml" ]]; then
    cp "${MAS_ROOT}/config/settings.yaml.sample" "${MAS_ROOT}/config/settings.yaml"
    log "config/settings.yaml を作成しました。"
fi

MAS_ROOT="$MAS_ROOT" python3 - <<'PY'
import os
import yaml

root = os.environ["MAS_ROOT"]
path = os.path.join(root, "config", "settings.yaml")
agents = ["director", "chief", "engineer1", "engineer2", "engineer3", "auditor"]
with open(path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
data.setdefault("language", "ja")
data.setdefault("shell", "bash")
cli = data.setdefault("cli", {})
cli["default"] = "opencode"
agent_cfg = cli.setdefault("agents", {})
for agent in agents:
    cfg = agent_cfg.get(agent)
    if isinstance(cfg, str):
        cfg = {"type": cfg}
    if not isinstance(cfg, dict):
        cfg = {}
    cfg["type"] = "opencode"
    cfg.setdefault("model", "")
    if agent == "engineer3":
        cfg["max_bloom"] = 3
    agent_cfg[agent] = cfg
data.setdefault("capability_tiers", {})
data.setdefault("bloom_routing", {}).setdefault("enabled", True)
with open(path, "w", encoding="utf-8") as fh:
    yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)
PY

if [[ "$SELECT_FREE_MODE" != "off" ]]; then
    selector_args=(--settings "${MAS_ROOT}/config/settings.yaml")
    if [[ "$SELECT_FREE_MODE" == "force" ]]; then
        selector_args+=(--force)
    fi
    if [[ "$REFRESH_FREE_MODELS" == "1" ]]; then
        selector_args+=(--refresh)
    fi
    if [[ -n "$FREE_MODEL" ]]; then
        selector_args+=(--free-model "$FREE_MODEL")
    fi
    if [[ "$ALLOW_RUNNING" == "1" ]]; then
        selector_args+=(--allow-running)
    fi
    if ! python3 "${MAS_ROOT}/scripts/select_free_model.py" "${selector_args[@]}"; then
        log "WARN: 無料モデルの自動選択に失敗しました。model は空欄のままにします。"
    fi
fi

for agent in $(agent_registry_agents); do
    inbox="${MAS_ROOT}/queue/inbox/${agent}.yaml"
    [[ -f "$inbox" ]] || printf 'messages: []\n' > "$inbox"
done

while IFS= read -r agent; do
    task="${MAS_ROOT}/queue/tasks/${agent}.yaml"
    if [[ ! -f "$task" ]]; then
        cat > "$task" <<EOF
task_id: null
status: idle
assigned_by: null
assigned_at: null
summary: ""
EOF
    fi
    report="${MAS_ROOT}/queue/reports/${agent}_report.yaml"
    if [[ ! -f "$report" ]]; then
        cat > "$report" <<EOF
task_id: null
status: idle
summary: ""
evidence: []
EOF
    fi
done < <(agent_registry_engineers; agent_registry_agents | grep -x auditor || true)
[[ -f "${MAS_ROOT}/queue/tasks/auditor.yaml" ]] || printf 'task_id: null\nstatus: idle\n' > "${MAS_ROOT}/queue/tasks/auditor.yaml"

[[ -f "${MAS_ROOT}/queue/commands.yaml" ]] || printf 'commands: []\n' > "${MAS_ROOT}/queue/commands.yaml"
[[ -f "${MAS_ROOT}/queue/commands_archive.yaml" ]] || printf 'commands: []\n' > "${MAS_ROOT}/queue/commands_archive.yaml"
[[ -f "${MAS_ROOT}/queue/pending.yaml" ]] || printf 'tasks: []\n' > "${MAS_ROOT}/queue/pending.yaml"
[[ -f "${MAS_ROOT}/config/projects.yaml" ]] || printf 'projects: []\n' > "${MAS_ROOT}/config/projects.yaml"
[[ -f "${MAS_ROOT}/dashboard.md" ]] || cat > "${MAS_ROOT}/dashboard.md" <<'EOF'
# mas_oc ダッシュボード

## 現在の状況

- 起動待ち

## 判断待ち

- なし

## 最近の完了

- なし
EOF

if [[ -f "${MAS_ROOT}/memory/MEMORY.md.sample" && ! -f "${MAS_ROOT}/memory/MEMORY.md" ]]; then
    cp "${MAS_ROOT}/memory/MEMORY.md.sample" "${MAS_ROOT}/memory/MEMORY.md"
fi
if [[ ! -f "${MAS_ROOT}/memory/MEMORY.md" ]]; then
    printf '# MEMORY\n\nプロジェクトの長期記憶をここに書く。\n' > "${MAS_ROOT}/memory/MEMORY.md"
fi
if [[ ! -f "${MAS_ROOT}/memory/global_context.md" ]]; then
    printf '# グローバルコンテキスト\n\n- プロジェクト: mas_oc\n' > "${MAS_ROOT}/memory/global_context.md"
fi

bash "${MAS_ROOT}/scripts/build_instructions.sh"

count=$(find "${MAS_ROOT}/.opencode/agents" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
if [[ "$count" != "6" ]]; then
    echo "ERROR: .opencode/agents の生成数が 6 ではありません（${count}）。" >&2
    exit 1
fi

log "完了しました。"

if python3 - "${MAS_ROOT}/config/settings.yaml" <<'PY'
import sys

import yaml

with open(sys.argv[1], encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

agent = ((data.get("cli") or {}).get("agents") or {}).get("director")
if isinstance(agent, str):
    model = agent
elif isinstance(agent, dict):
    model = agent.get("model")
else:
    model = ""
raise SystemExit(0 if str(model or "").strip() else 1)
PY
then
    log "config/settings.yaml の model は設定済みです。"
    log "再選択: ./first_setup.sh --select-free-model"
else
    log "config/settings.yaml の model を設定してください（空欄なら OpenCode の既定モデル）。"
    log "モデル確認: opencode models --verbose"
fi
log "起動: ./mas start"
log "停止: ./mas stop"
