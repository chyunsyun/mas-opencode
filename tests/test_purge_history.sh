#!/usr/bin/env bash
# scripts/purge_history.sh の削除範囲とモデル初期化を検証する。
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d /tmp/opencode/purge-history.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

new_root() {
    local root="$1"
    mkdir -p "$root"
    local item
    for item in first_setup.sh start.sh lib scripts instructions config templates memory AGENTS.md; do
        cp -a "$SRC/$item" "$root/"
    done
    rm -f "$root/config/settings.yaml"
    rm -rf "$root/scripts/__pycache__" "$root/tests"
    mkdir -p "$root/testbin"
    cat > "$root/testbin/opencode" <<'EOF'
#!/usr/bin/env bash
[[ -n "${CALL_LOG:-}" ]] && printf '%s\n' "$*" >> "$CALL_LOG"
if [[ "${1:-}" == "models" && "${2:-}" == "--refresh" ]]; then
    exit 0
fi
if [[ "${1:-}" == "models" && "${2:-}" == "--verbose" ]]; then
    cat "${MODELS_FILE:?MODELS_FILE is required}"
    exit 0
fi
exit 0
EOF
    cat > "$root/testbin/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    cat > "$root/testbin/tmux" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    has-session|list-panes|list-windows) exit 1 ;;
esac
exit 0
EOF
    chmod +x "$root/testbin/opencode" "$root/testbin/pgrep" "$root/testbin/tmux"

    mkdir -p \
        "$root/queue/tasks" \
        "$root/queue/reports" \
        "$root/queue/inbox" \
        "$root/logs" \
        "$root/run" \
        "$root/status" \
        "$root/reports" \
        "$root/memory"
    : > "$root/logs/.gitkeep"
    : > "$root/run/.gitkeep"
    : > "$root/status/.gitkeep"
    : > "$root/reports/.gitkeep"

    printf 'task_id: OLD_TASK\nstatus: assigned\n' > "$root/queue/tasks/engineer1.yaml"
    printf '# OLD_DASHBOARD\n' > "$root/dashboard.md"
    printf '# OLD_MEMORY\n' > "$root/memory/MEMORY.md"
    printf '# OLD_CONTEXT\n' > "$root/memory/global_context.md"
    printf 'old watcher log\n' > "$root/logs/watcher.engineer1.log"
    printf 'old report\n' > "$root/reports/old_report.md"
    printf 'old status\n' > "$root/status/old_status.yaml"
    printf 'old session\n' > "$root/run/session.env"
    mkdir -p "$root/run/opencode-state/engineer1/opencode"
    printf '{}\n' > "$root/run/opencode-state/engineer1/opencode/prompt-history.jsonl"

    cat > "$root/config/settings.yaml" <<'EOF'
language: ja
cli:
  default: opencode
  agents:
    director:
      type: opencode-go
      model: opencode-go/old-model
      variant: max
      thinking: true
    chief:
      type: opencode-go
      model: opencode-go/old-model
      variant: max
      thinking: true
    engineer1:
      type: opencode-go
      model: opencode-go/old-model
      variant: high
      thinking: true
    engineer2:
      type: opencode-go
      model: opencode-go/old-model
      variant: high
      thinking: true
    engineer3:
      type: opencode-go
      model: opencode-go/old-model
      variant: low
      thinking: true
      max_bloom: 3
    auditor:
      type: opencode-go
      model: opencode-go/old-model
      variant: max
      thinking: true
capability_tiers:
  opencode-go/old-model:
    max_bloom: 4
model_selection:
  source: old
EOF
}

write_catalog() {
    local root="$1"
    local include_free="${2:-1}"
    python3 - "$root/models.txt" "$include_free" <<'PY'
import json
import sys

path = sys.argv[1]
include_free = sys.argv[2] == "1"

def block(provider, model_id, cost=0, context=200000, toolcall=True, status="active"):
    payload = {
        "id": model_id,
        "providerID": provider,
        "name": model_id,
        "status": status,
        "cost": {
            "input": cost,
            "output": cost,
            "cache": {"read": cost, "write": cost},
        },
        "limit": {"context": context, "output": 32000},
        "capabilities": {"toolcall": toolcall, "reasoning": True},
        "release_date": "2026-10-01",
    }
    return f"{provider}/{model_id}\n{json.dumps(payload, indent=2)}\n"

blocks = [block("opencode", "paid-model", cost=1)]
if include_free:
    blocks.extend([
        block("opencode", "nemotron-3-ultra-free", context=1000000),
        block("opencode", "deepseek-v4.1-flash-free"),
    ])
with open(path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(blocks))
PY
}

run_purge() {
    local root="$1"
    shift
    (
        cd "$root"
        PATH="$root/testbin:$PATH" \
        MAS_ROOT="$root" \
        MAS_SESSION="mas-purge-test-$$" \
        MODELS_FILE="$root/models.txt" \
        CALL_LOG="$root/opencode-calls.log" \
        bash "$root/scripts/purge_history.sh" "$@"
    ) >"$root/purge.out" 2>"$root/purge.err"
}

settings_python() {
    local root="$1"
    shift
    python3 - "$root/config/settings.yaml" "$@" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}
agents = ((data.get("cli") or {}).get("agents") or {})
args = sys.argv[2:]

if args and args[0] == "models":
    for role in ("director", "chief", "engineer1", "engineer2", "engineer3", "auditor"):
        print(f"{role}={agents.get(role, {}).get('model', '')}")
elif args and args[0] == "variant-count":
    print(sum(1 for cfg in agents.values() if isinstance(cfg, dict) and "variant" in cfg))
elif args and args[0] == "selection":
    print(((data.get("model_selection") or {}).get("source") or ""))
elif args and args[0] == "tiers":
    print(",".join(sorted((data.get("capability_tiers") or {}).keys())))
PY
}

# 1. --yes なしでは何も削除しない
ROOT0="$TMP/root0"
new_root "$ROOT0"
write_catalog "$ROOT0" 1
set +e
run_purge "$ROOT0"
RC=$?
set -e
[[ "$RC" -ne 0 ]] && pass "--yes なしは失敗する" || fail "--yes なしで成功した"
[[ -f "$ROOT0/dashboard.md" ]] && pass "--yes なしでは削除しない" || fail "--yes なしで削除された"

# 2. 無料モデルが選べる場合は履歴削除とモデル初期化を行う
ROOT1="$TMP/root1"
new_root "$ROOT1"
write_catalog "$ROOT1" 1
run_purge "$ROOT1" --yes

[[ ! -e "$ROOT1/logs/watcher.engineer1.log" ]] && pass "watcher ログを削除" || fail "watcher ログが残る"
[[ -f "$ROOT1/logs/.gitkeep" ]] && pass "logs/.gitkeep を保持" || fail "logs/.gitkeep が消えた"
[[ ! -e "$ROOT1/reports/old_report.md" ]] && pass "reports 配下を削除" || fail "reports 配下が残る"
[[ -f "$ROOT1/reports/.gitkeep" ]] && pass "reports/.gitkeep を保持" || fail "reports/.gitkeep が消えた"
[[ ! -e "$ROOT1/status/old_status.yaml" ]] && pass "status 配下を削除" || fail "status 配下が残る"
[[ -f "$ROOT1/status/.gitkeep" ]] && pass "status/.gitkeep を保持" || fail "status/.gitkeep が消えた"
[[ ! -e "$ROOT1/run/opencode-state" ]] && pass "run/opencode-state を削除" || fail "run/opencode-state が残る"
[[ ! -e "$ROOT1/run/session.env" ]] && pass "run/session.env を削除" || fail "run/session.env が残る"
[[ -f "$ROOT1/run/.gitkeep" ]] && pass "run/.gitkeep を保持" || fail "run/.gitkeep が消えた"
if grep -q 'OLD_TASK' "$ROOT1/queue/tasks/engineer1.yaml" 2>/dev/null; then
    fail "旧 queue が残る"
else
    pass "旧 queue を削除"
fi
if compgen -G "$ROOT1/logs/backup_*" >/dev/null; then
    fail "バックアップが作成された"
else
    pass "バックアップを作らない"
fi
if compgen -G "$ROOT1/config/settings.yaml.bak.*" >/dev/null; then
    fail "settings バックアップが残る"
else
    pass "settings バックアップを残さない"
fi
[[ -f "$ROOT1/queue/tasks/engineer1.yaml" ]] && pass "queue を再生成" || fail "queue が再生成されない"
grep -q 'mas_oc ダッシュボード' "$ROOT1/dashboard.md" && pass "dashboard を再生成" || fail "dashboard が再生成されない"
if grep -q 'OLD_DASHBOARD' "$ROOT1/dashboard.md"; then
    fail "旧 dashboard が残る"
else
    pass "旧 dashboard を削除"
fi
grep -q 'OLD_MEMORY' "$ROOT1/memory/MEMORY.md" && fail "memory が初期化されない" || pass "memory を初期化"

MODELS="$(settings_python "$ROOT1" models)"
[[ "$MODELS" == "director=opencode/nemotron-3-ultra-free"* ]] && pass "director を無料モデルに変更" || fail "director model: $MODELS"
grep -q 'engineer3=opencode/deepseek-v4.1-flash-free' <<< "$MODELS" && pass "engineer3 を高速無料モデルに変更" || fail "engineer3 model: $MODELS"
[[ "$(settings_python "$ROOT1" variant-count)" == "0" ]] && pass "variant を削除" || fail "variant が残る"
[[ "$(settings_python "$ROOT1" selection)" == "opencode-free" ]] && pass "model_selection を更新" || fail "model_selection が更新されない"
TIERS="$(settings_python "$ROOT1" tiers)"
[[ "$TIERS" == "opencode/deepseek-v4.1-flash-free,opencode/nemotron-3-ultra-free" ]] && pass "capability_tiers を再作成" || fail "capability_tiers: $TIERS"
if grep -q '^session' "$ROOT1/opencode-calls.log" 2>/dev/null; then
    fail "OpenCode セッションを削除した"
else
    pass "OpenCode セッションを削除しない"
fi

# 3. 無料モデルがない場合は openrouter/free にフォールバックする
ROOT2="$TMP/root2"
new_root "$ROOT2"
write_catalog "$ROOT2" 0
run_purge "$ROOT2" --yes
grep -q 'openrouter/free' "$ROOT2/purge.err" && pass "フォールバック警告を表示" || fail "フォールバック警告がない"
MODELS2="$(settings_python "$ROOT2" models)"
if grep -q '=openrouter/free' <<< "$MODELS2" && ! grep -qv '=openrouter/free' <<< "$MODELS2"; then
    pass "全エージェントを openrouter/free に設定"
else
    fail "フォールバック model: $MODELS2"
fi
grep -q 'openrouter/free' "$ROOT2/.opencode/agents/director.md" \
    && pass "フォールバック後にエージェント定義を再生成" \
    || fail "エージェント定義が openrouter/free で再生成されない"

if [[ "$failures" -eq 0 ]]; then
    echo "all purge history tests passed"
    exit 0
fi
echo "${failures} failure(s)" >&2
exit 1
