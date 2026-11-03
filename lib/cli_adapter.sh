#!/usr/bin/env bash

CLI_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAS_ROOT="${MAS_ROOT:-$(cd "${CLI_ADAPTER_DIR}/.." && pwd)}"
MAS_SETTINGS="${MAS_SETTINGS_FILE:-${MAS_ROOT}/config/settings.yaml}"

source "${MAS_ROOT}/lib/agent_registry.sh"

_mas_python() {
    local candidate
    for candidate in "${MAS_ROOT}/.venv/bin/python3" "$(command -v python3 2>/dev/null || true)"; do
        [[ -n "$candidate" && -x "$candidate" ]] || continue
        if "$candidate" -c 'import yaml' 2>/dev/null; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

normalize_opencode_model() {
    local model="${1:-}"
    [[ -z "$model" ]] && return 0
    [[ "$model" == */* ]] && { echo "$model"; return 0; }
    case "$model" in
        gpt-5*|gpt-5.4*) echo "openai/${model}" ;;
        claude-opus-4-8) echo "anthropic/claude-opus-4-8" ;;
        claude-opus-4-7) echo "anthropic/claude-opus-4-7" ;;
        claude-opus-4-6|opus) echo "anthropic/claude-opus-4-6" ;;
        claude-sonnet-4-6|sonnet) echo "anthropic/claude-sonnet-4-6" ;;
        claude-haiku-4-5-20251001|haiku) echo "anthropic/claude-haiku-4-5-20251001" ;;
        moonshot-k2.5|k2.5) echo "moonshot/kimi-k2.5" ;;
        kimi-*) echo "moonshot/kimi-${model#kimi-}" ;;
        *) echo "$model" ;;
    esac
}

get_cli_type() {
    echo "opencode"
}

get_agent_ids() {
    agent_registry_agents
}

get_engineer_ids() {
    agent_registry_engineers
}

get_agent_role() {
    agent_registry_role "${1:-}"
}

get_agent_label() {
    agent_registry_label "${1:-}"
}

get_agent_model() {
    local agent_id="${1:-}"
    [[ -z "$agent_id" ]] && return 0
    local py
    py="$(_mas_python)" || return 0
    local model
    model=$("$py" - "$MAS_SETTINGS" "$agent_id" <<'PY'
import sys
import yaml
settings, agent = sys.argv[1], sys.argv[2]
try:
    with open(settings, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
except Exception:
    data = {}
cfg = ((data.get("cli") or {}).get("agents") or {}).get(agent)
model = ""
if isinstance(cfg, dict):
    model = cfg.get("model") or ""
if not model:
    model = (data.get("models") or {}).get(agent) or ""
print(model)
PY
)
    normalize_opencode_model "$model"
}

get_agent_variant() {
    local agent_id="${1:-}"
    [[ -z "$agent_id" ]] && return 0
    local py
    py="$(_mas_python)" || return 0
    "$py" - "$MAS_SETTINGS" "$agent_id" <<'PY'
import sys
import yaml
settings, agent = sys.argv[1], sys.argv[2]
try:
    with open(settings, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
except Exception:
    data = {}
cfg = ((data.get("cli") or {}).get("agents") or {}).get(agent)
print((cfg or {}).get("variant", "") if isinstance(cfg, dict) else "")
PY
}

get_capability_tier() {
    local model="${1:-}"
    [[ -z "$model" ]] && { echo 6; return 0; }
    local py
    py="$(_mas_python)" || { echo 6; return 0; }
    "$py" - "$MAS_SETTINGS" "$model" <<'PY'
import sys
import yaml
settings, model = sys.argv[1], sys.argv[2]
try:
    with open(settings, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
except Exception:
    data = {}
tiers = data.get("capability_tiers") or {}
cfg = tiers.get(model) or {}
try:
    print(int(cfg.get("max_bloom", 6)))
except Exception:
    print(6)
PY
}

get_agent_max_bloom() {
    local agent_id="${1:-}"
    local py
    py="$(_mas_python)" || { echo 6; return 0; }
    local model
    model=$(get_agent_model "$agent_id")
    "$py" - "$MAS_SETTINGS" "$agent_id" "$model" <<'PY'
import sys
import yaml
settings, agent, model = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(settings, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
except Exception:
    data = {}
cfg = ((data.get("cli") or {}).get("agents") or {}).get(agent)
agent_cap = None
if isinstance(cfg, dict) and cfg.get("max_bloom") is not None:
    try:
        agent_cap = int(cfg["max_bloom"])
    except Exception:
        agent_cap = None
tier = ((data.get("capability_tiers") or {}).get(model) or {})
try:
    model_cap = int(tier.get("max_bloom", 6))
except Exception:
    model_cap = 6
print(min(agent_cap, model_cap) if agent_cap is not None else model_cap)
PY
}

get_recommended_model() {
    local bloom="${1:-1}"
    local py
    py="$(_mas_python)" || return 0
    "$py" - "$MAS_SETTINGS" "$bloom" <<'PY'
import sys
import yaml
settings, bloom = sys.argv[1], int(sys.argv[2])
try:
    with open(settings, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
except Exception:
    data = {}
candidates = []
for model, cfg in (data.get("capability_tiers") or {}).items():
    try:
        cap = int((cfg or {}).get("max_bloom", 6))
    except Exception:
        cap = 6
    if cap >= bloom:
        candidates.append((cap, model))
if candidates:
    print(sorted(candidates)[0][1])
PY
}

needs_model_switch() {
    local agent_id="${1:-}"
    local bloom="${2:-1}"
    local cap
    cap=$(get_agent_max_bloom "$agent_id")
    [[ "$bloom" =~ ^[0-9]+$ ]] || bloom=1
    [[ "$cap" =~ ^[0-9]+$ ]] || cap=6
    if (( bloom > cap )); then
        echo "yes"
    else
        echo "no"
    fi
}

get_task_status() {
    local agent_id="${1:-}"
    local py
    py="$(_mas_python)" || { echo "idle"; return 0; }
    "$py" - "${MAS_ROOT}/queue/tasks/${agent_id}.yaml" <<'PY'
import sys
import yaml
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    print(data.get("status") or "idle")
except Exception:
    print("idle")
PY
}

find_engineer_for_bloom() {
    local bloom="${1:-1}"
    [[ "$bloom" =~ ^[0-9]+$ ]] || bloom=1
    local order
    if (( bloom <= 3 )); then
        order=(engineer3 engineer1 engineer2)
    else
        order=(engineer1 engineer2 engineer3)
    fi
    local agent cap status
    for agent in "${order[@]}"; do
        cap=$(get_agent_max_bloom "$agent")
        (( bloom > cap )) && continue
        status=$(get_task_status "$agent")
        case "$status" in
            assigned|blocked) continue ;;
        esac
        echo "$agent"
        return 0
    done
    return 1
}

get_model_display_name() {
    local agent_id="${1:-}"
    local model variant
    model=$(get_agent_model "$agent_id")
    variant=$(get_agent_variant "$agent_id")
    if [[ -z "$model" ]]; then
        echo "default"
        return 0
    fi
    model="${model##*/}"
    if [[ -n "$variant" ]]; then
        echo "${model}+${variant}"
    else
        echo "$model"
    fi
}

get_agent_state_home() {
    local agent_id="${1:-}"
    local run_dir
    [[ -z "$agent_id" ]] && return 0
    run_dir="${MAS_RUN_DIR:-${MAS_ROOT}/run}"
    run_dir="${run_dir%/}"
    printf '%s/opencode-state/%s\n' "$run_dir" "$agent_id"
}

ensure_agent_state_home() {
    local agent_id="${1:-}"
    local state_home
    state_home=$(get_agent_state_home "$agent_id") || return 0
    [[ -n "$state_home" ]] || return 0
    mkdir -p "$state_home" || return 1
    printf '%s\n' "$state_home"
}

build_cli_command() {
    local agent_id="${1:-}"
    local auto="${2:-1}"
    local model command state_home
    model=$(get_agent_model "$agent_id")
    local opencode_bin="${OPENCODE_BIN:-opencode}"
    command=""
    if [[ -n "$agent_id" ]]; then
        state_home=$(ensure_agent_state_home "$agent_id") || return 1
        command+="XDG_STATE_HOME=$(printf '%q' "$state_home") "
    fi
    command+="OPENCODE_AGENT_ID=$(printf '%q' "$agent_id") OPENCODE_TUI_CONFIG=$(printf '%q' "${MAS_ROOT}/config/opencode-tui.json") $(printf '%q' "$opencode_bin")"
    if [[ -n "$model" ]]; then
        command+=" --model $(printf '%q' "$model")"
    fi
    command+=" --agent $(printf '%q' "$agent_id")"
    if [[ "$auto" == "1" ]]; then
        command+=" --auto"
    fi
    echo "$command"
}

validate_cli_availability() {
    local bin="${OPENCODE_BIN:-opencode}"
    [[ -x "$bin" ]] || command -v "$bin" >/dev/null 2>&1
}

can_model_switch() {
    echo "yes"
}
