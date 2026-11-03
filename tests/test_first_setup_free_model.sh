#!/usr/bin/env bash
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/first-setup.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

new_root() {
    local root="$1"
    mkdir -p "$root"
    local item
    for item in first_setup.sh scripts lib instructions config templates memory AGENTS.md; do
        cp -a "$SRC/$item" "$root/"
    done
    rm -f "$root/config/settings.yaml"
    mkdir -p "$root/testbin"
    cat > "$root/testbin/opencode" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "models" && "${2:-}" == "--refresh" ]]; then
    if [[ "${MOCK_REFRESH_FAIL:-0}" == "1" ]]; then
        echo "mock refresh failure" >&2
        exit 1
    fi
    exit 0
fi
if [[ "${1:-}" == "models" && "${2:-}" == "--verbose" ]]; then
    cat "${MODELS_FILE:?MODELS_FILE is required}"
    exit 0
fi
exit 0
EOF
    chmod +x "$root/testbin/opencode"
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

blocks = [
    block("opencode", "paid-model", cost=1),
    block("lmstudio", "local-model"),
]
if include_free:
    blocks.extend([
        block("opencode", "nemotron-3-ultra-free", context=1000000),
        block("opencode", "deepseek-v4.1-flash-free"),
        block("opencode", "glm-5.3-flash-free"),
    ])
with open(path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(blocks))
PY
}

run_setup() {
    local root="$1"
    shift
    (
        cd "$root"
        PATH="$root/testbin:$PATH" \
        MAS_ROOT="$root" \
        MODELS_FILE="$root/models.txt" \
        bash "$root/first_setup.sh" --non-interactive "$@"
    ) >"$root/setup.log" 2>&1
}

model_of() {
    local root="$1"
    local role="$2"
    python3 - "$root/config/settings.yaml" "$role" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}
agent = ((data.get("cli") or {}).get("agents") or {}).get(sys.argv[2])
if isinstance(agent, str):
    print(agent)
elif isinstance(agent, dict):
    print(agent.get("model") or "")
PY
}

assert_model() {
    local root="$1"
    local role="$2"
    local expected="$3"
    local actual
    actual="$(model_of "$root" "$role")"
    [[ "$actual" == "$expected" ]] || fail "$role model: expected '$expected', got '$actual'"
}

# 1. first run selects high/fast free models
ROOT1="$TMP/root1"
new_root "$ROOT1"
write_catalog "$ROOT1" 1
run_setup "$ROOT1"
assert_model "$ROOT1" director "opencode/nemotron-3-ultra-free"
assert_model "$ROOT1" engineer2 "opencode/nemotron-3-ultra-free"
assert_model "$ROOT1" engineer3 "opencode/deepseek-v4.1-flash-free"
grep -q "model: opencode/deepseek-v4.1-flash-free" "$ROOT1/.opencode/agents/engineer3.md" \
    || fail "engineer3 agent markdown does not contain selected fast model"
python3 - "$ROOT1/config/settings.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}
agents = data["cli"]["agents"]
assert agents["engineer3"]["max_bloom"] == 3
assert data["capability_tiers"]["opencode/nemotron-3-ultra-free"]["max_bloom"] == 4
assert data["capability_tiers"]["opencode/deepseek-v4.1-flash-free"]["max_bloom"] == 3
assert data["model_selection"]["high_model"] == "opencode/nemotron-3-ultra-free"
assert data["model_selection"]["fast_model"] == "opencode/deepseek-v4.1-flash-free"
PY

# 2. second run leaves existing models unchanged
BEFORE="$(model_of "$ROOT1" director)"
run_setup "$ROOT1" --no-refresh-free-models
AFTER="$(model_of "$ROOT1" director)"
[[ "$BEFORE" == "$AFTER" ]] || fail "existing model changed on second run"

# 3. force re-selection creates a backup
run_setup "$ROOT1" --no-refresh-free-models --select-free-model
ls "$ROOT1"/config/settings.yaml.bak.* >/dev/null 2>&1 \
    || fail "settings backup not created by --select-free-model"

# 4. --no-select-free-model leaves a new settings file empty
ROOT2="$TMP/root2"
new_root "$ROOT2"
write_catalog "$ROOT2" 1
run_setup "$ROOT2" --no-select-free-model --no-refresh-free-models
assert_model "$ROOT2" director ""

# 5. --free-model applies the requested free model
ROOT3="$TMP/root3"
new_root "$ROOT3"
write_catalog "$ROOT3" 1
run_setup "$ROOT3" --free-model opencode/glm-5.3-flash-free --no-refresh-free-models
assert_model "$ROOT3" director "opencode/glm-5.3-flash-free"
assert_model "$ROOT3" engineer3 "opencode/glm-5.3-flash-free"
python3 - "$ROOT3/config/settings.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}
assert data["capability_tiers"]["opencode/glm-5.3-flash-free"]["max_bloom"] == 4
assert data["cli"]["agents"]["engineer3"]["max_bloom"] == 3
PY

# 6. no free model leaves the settings empty and setup still succeeds
ROOT4="$TMP/root4"
new_root "$ROOT4"
write_catalog "$ROOT4" 0
run_setup "$ROOT4" --no-refresh-free-models
assert_model "$ROOT4" director ""

echo "first setup free model test passed"
