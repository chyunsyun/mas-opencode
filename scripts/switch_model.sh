#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAS_ROOT="${MAS_ROOT:-$SCRIPT_DIR}"
source "${MAS_ROOT}/lib/cli_adapter.sh"
source "${MAS_ROOT}/lib/tmux_layout.sh"
source "${MAS_ROOT}/lib/agent_status.sh"

AGENT_ID="${1:-}"
shift || true
if [[ -z "$AGENT_ID" ]] || ! get_agent_ids | grep -qx "$AGENT_ID"; then
    echo "Usage: switch_model.sh <agent_id> [--model MODEL] [--variant VARIANT] [--max-bloom N] [--force]" >&2
    exit 1
fi

MODEL=""
VARIANT=""
MAX_BLOOM=""
FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model) MODEL="${2:-}"; shift 2 ;;
        --variant) VARIANT="${2:-}"; shift 2 ;;
        --max-bloom) MAX_BLOOM="${2:-}"; shift 2 ;;
        --force) FORCE=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

SESSION_ROOT=$(tmux show-environment -t "$(mas_session_name)" MAS_ROOT 2>/dev/null | sed -n 's/^MAS_ROOT=//p' || true)
PANE=""
if [[ -n "$SESSION_ROOT" && "${SESSION_ROOT%/}" != "${MAS_ROOT%/}" ]]; then
    echo "WARN: tmux session $(mas_session_name) は ${SESSION_ROOT} のものです。${MAS_ROOT} のペイン再起動は行いません。" >&2
else
    PANE=$(mas_pane_for_agent "$AGENT_ID" || true)
fi

if [[ -n "$PANE" ]] && agent_is_busy_check "$PANE"; then
    if [[ "$FORCE" != "1" ]]; then
        echo "ERROR: ${AGENT_ID} は稼働中です。作業完了後に再実行するか、強制再起動する場合は --force を指定してください。" >&2
        exit 2
    fi
    echo "WARN: ${AGENT_ID} は稼働中です。--force により再起動します。" >&2
fi

MAS_ROOT="$MAS_ROOT" AGENT_ID="$AGENT_ID" MODEL="$MODEL" VARIANT="$VARIANT" MAX_BLOOM="$MAX_BLOOM" \
python3 - <<'PY'
import os
import yaml

root = os.environ["MAS_ROOT"]
agent = os.environ["AGENT_ID"]
model = os.environ["MODEL"]
variant = os.environ["VARIANT"]
max_bloom = os.environ["MAX_BLOOM"]
path = os.path.join(root, "config", "settings.yaml")
with open(path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
agents = data.setdefault("cli", {}).setdefault("agents", {})
cfg = agents.setdefault(agent, {})
if not isinstance(cfg, dict):
    cfg = {"type": str(cfg)}
    agents[agent] = cfg
cfg["type"] = "opencode"
if model:
    cfg["model"] = model
if variant:
    cfg["variant"] = variant
elif "variant" in cfg and variant == "" and os.environ.get("MODEL"):
    cfg.pop("variant", None)
if max_bloom:
    cfg["max_bloom"] = int(max_bloom)
with open(path, "w", encoding="utf-8") as fh:
    yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)
PY

bash "${MAS_ROOT}/scripts/build_instructions.sh" >/dev/null

if [[ -n "$PANE" ]]; then
    tmux respawn-pane -k -t "$PANE" 2>/dev/null || true
    sleep 0.3
    COMMAND=$(build_cli_command "$AGENT_ID" 1)
    tmux send-keys -t "$PANE" "cd $(printf '%q' "$MAS_ROOT") && clear && $COMMAND" 2>/dev/null || true
    tmux send-keys -t "$PANE" Enter 2>/dev/null || true
    mas_set_pane_metadata "$PANE" "$AGENT_ID" "$(get_agent_label "$AGENT_ID")" "$(get_model_display_name "$AGENT_ID")"
fi

echo "${AGENT_ID}: model=$(get_model_display_name "$AGENT_ID") max_bloom=$(get_agent_max_bloom "$AGENT_ID")"
