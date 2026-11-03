#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAS_ROOT="${MAS_ROOT:-$SCRIPT_DIR}"
source "${MAS_ROOT}/lib/agent_registry.sh"
source "${MAS_ROOT}/lib/agent_status.sh"
source "${MAS_ROOT}/lib/tmux_layout.sh"

task_info() {
    local agent_id="$1"
    python3 - "$MAS_ROOT/queue/tasks/${agent_id}.yaml" <<'PY'
import sys
import yaml
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    print(f"{data.get('task_id') or '-'}\t{data.get('status') or 'idle'}")
except Exception:
    print("-\tidle")
PY
}

unread_count() {
    local agent_id="$1"
    python3 - "$MAS_ROOT/queue/inbox/${agent_id}.yaml" <<'PY'
import sys
import yaml
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    print(sum(1 for m in (data.get("messages") or []) if not m.get("read", False)))
except Exception:
    print(0)
PY
}

printf '%-12s %-8s %-8s %-16s %-12s %-6s\n' "Agent" "表示名" "Pane" "Task" "Status" "Inbox"
printf '%s\n' "----------------------------------------------------------------------------"
while IFS= read -r agent; do
    pane=$(mas_pane_for_agent "$agent" || true)
    if [[ -n "$pane" ]]; then
        state=$(get_pane_state_label "$pane")
    else
        state="不在"
    fi
    info=$(task_info "$agent")
    task_id="${info%%$'\t'*}"
    task_status="${info#*$'\t'}"
    unread=$(unread_count "$agent")
    printf '%-12s %-8s %-8s %-16s %-12s %-6s\n' \
        "$agent" "$(agent_registry_label "$agent")" "$state" "$task_id" "$task_status" "$unread"
done < <(agent_registry_agents)
