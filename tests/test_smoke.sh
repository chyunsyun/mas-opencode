#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export MAS_ROOT="$ROOT"
export MAS_SETTINGS_FILE="$ROOT/config/settings.yaml.sample"
source "${ROOT}/lib/agent_registry.sh"
source "${ROOT}/lib/cli_adapter.sh"

failures=0
pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
check_eq() { if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi; }

agents=$(agent_registry_agents | tr '\n' ' ')
check_eq "$agents" "director chief engineer1 engineer2 engineer3 auditor " "6名の固定編成"

engineers=$(agent_registry_engineers | tr '\n' ' ')
check_eq "$engineers" "engineer1 engineer2 engineer3 " "エンジニアは3名"

check_eq "$(get_agent_label director)" "部長" "director の表示名"
check_eq "$(get_agent_label chief)" "係長" "chief の表示名"
check_eq "$(get_agent_label engineer3)" "エンジニア3" "engineer3 の表示名"
check_eq "$(get_agent_label auditor)" "監査役" "auditor の表示名"

check_eq "$(get_agent_max_bloom engineer3)" "3" "engineer3 の max_bloom"
check_eq "$(needs_model_switch engineer3 4)" "yes" "engineer3 は bloom 4 以上で切替対象"
check_eq "$(needs_model_switch engineer3 3)" "no" "engineer3 は bloom 3 まで担当可"

if [[ "$(get_task_status engineer3)" == "idle" || "$(get_task_status engineer3)" == "done" ]]; then
    check_eq "$(find_engineer_for_bloom 1)" "engineer3" "bloom 1 は engineer3 を優先"
fi
if [[ "$(find_engineer_for_bloom 4 2>/dev/null || true)" == "engineer3" ]]; then
    fail "bloom 4 を engineer3 に割り当ててはいけない"
else
    pass "bloom 4 は engineer3 以外"
fi

bash "${ROOT}/scripts/build_instructions.sh" >/dev/null
count=$(find "${ROOT}/.opencode/agents" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
check_eq "$count" "6" ".opencode/agents は6ファイル"

for id in $(agent_registry_agents); do
    if [[ -f "${ROOT}/.opencode/agents/${id}.md" ]]; then
        pass "agent file: ${id}.md"
    else
        fail "agent file missing: ${id}.md"
    fi
done

if grep -RInE 'shogun|karo|ashigaru|gunshi|将軍|家老|足軽|軍師|ござる|拙者' \
    lib scripts instructions config .opencode/agents start.sh stop.sh first_setup.sh mas Makefile AGENTS.md >/dev/null 2>&1; then
    fail "旧役割名・戦国表現が残っている"
else
    pass "旧役割名・戦国表現なし"
fi

if grep -RInE 'CLI_ADAPTER_ALLOWED_CLIS|switch_cli|session_start_hook|stop_hook_inbox|mcp_health_check' \
    lib scripts start.sh stop.sh first_setup.sh mas >/dev/null 2>&1; then
    fail "旧CLI専用機能の参照が残っている"
else
    pass "旧CLI専用機能の参照なし"
fi

python3 - "$ROOT/config/settings.yaml.sample" <<'PY'
import sys
import yaml
with open(sys.argv[1], encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
agents = ((data.get("cli") or {}).get("agents") or {})
assert set(agents) == {"director", "chief", "engineer1", "engineer2", "engineer3", "auditor"}, agents
assert int(agents["engineer3"]["max_bloom"]) == 3
PY
pass "settings sample の6名と max_bloom"

export MAS_SESSION="mas-test-$$"
export MAS_RUN_DIR="${ROOT}/.work/test-run-$$"
cleanup() {
    MAS_SESSION="$MAS_SESSION" MAS_RUN_DIR="$MAS_RUN_DIR" bash "${ROOT}/stop.sh" --quiet >/dev/null 2>&1 || true
    rm -rf "$MAS_RUN_DIR"
}
trap cleanup EXIT

bash "${ROOT}/start.sh" --setup-only >/dev/null
pane_count=$(tmux list-panes -t "${MAS_SESSION}:team" -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')
check_eq "$pane_count" "6" "tmux 6ペイン"

labels=$(tmux list-panes -t "${MAS_SESSION}:team" -F '#{@agent_id}' 2>/dev/null | sort | tr '\n' ' ')
check_eq "$labels" "auditor chief director engineer1 engineer2 engineer3 " "tmux の6名ラベル"

bash "${ROOT}/stop.sh" --quiet >/dev/null
if tmux has-session -t "$MAS_SESSION" 2>/dev/null; then
    fail "stop 後も tmux セッションが残っている"
else
    pass "stop で tmux セッションを削除"
fi

if [[ "$failures" -eq 0 ]]; then
    echo "all smoke tests passed"
    exit 0
fi
echo "${failures} failure(s)" >&2
exit 1
