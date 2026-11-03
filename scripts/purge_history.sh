#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAS_ROOT="${MAS_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
MAS_ROOT="$(cd "$MAS_ROOT" && pwd)"

source "${MAS_ROOT}/lib/runtime_guard.sh"

YES=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes) YES=1; shift ;;
        -h|--help)
            cat <<'EOF'
Usage: scripts/purge_history.sh --yes
  使用履歴を完全に削除し、設定を無料モデルへ初期化する。
  --yes  確認なしで実行する（必須）
EOF
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ "$YES" != "1" ]]; then
    echo "ERROR: purge_history.sh は --yes が必要です。" >&2
    exit 1
fi

if [[ -z "$MAS_ROOT" || "$MAS_ROOT" == "/" || "$MAS_ROOT" == "${HOME:-/nonexistent}" ]]; then
    echo "ERROR: 安全でない MAS_ROOT です: ${MAS_ROOT}" >&2
    exit 1
fi
if [[ ! -f "${MAS_ROOT}/start.sh" || ! -f "${MAS_ROOT}/first_setup.sh" || ! -f "${MAS_ROOT}/lib/agent_registry.sh" ]]; then
    echo "ERROR: mas_oc のルートではありません: ${MAS_ROOT}" >&2
    exit 1
fi
if mas_root_is_running "$MAS_ROOT"; then
    echo "ERROR: mas_oc が稼働中です。先に ./mas stop を実行してください。" >&2
    exit 1
fi

log() { echo "[purge] $*"; }

remove_all_except_gitkeep() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    local entry base
    while IFS= read -r -d '' entry; do
        base=$(basename "$entry")
        [[ "$base" == ".gitkeep" ]] && continue
        rm -rf -- "$entry"
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0)
}

log "使用履歴を削除します: ${MAS_ROOT}"
rm -rf -- "${MAS_ROOT}/queue"
rm -f -- "${MAS_ROOT}/dashboard.md"
rm -f -- "${MAS_ROOT}/memory/MEMORY.md" "${MAS_ROOT}/memory/global_context.md"
remove_all_except_gitkeep "${MAS_ROOT}/logs"
remove_all_except_gitkeep "${MAS_ROOT}/status"
remove_all_except_gitkeep "${MAS_ROOT}/reports"
remove_all_except_gitkeep "${MAS_ROOT}/run"
rm -f -- "${MAS_ROOT}"/config/settings.yaml.bak.*
log "使用履歴を削除しました。"

if [[ -f "${MAS_ROOT}/config/settings.yaml" ]]; then
    MAS_ROOT="$MAS_ROOT" python3 - <<'PY'
import os
from pathlib import Path

import yaml

root = Path(os.environ["MAS_ROOT"])
path = root / "config" / "settings.yaml"
data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
if not isinstance(data, dict):
    data = {}
cli = data.setdefault("cli", {})
if not isinstance(cli, dict):
    cli = {}
    data["cli"] = cli
agents = cli.setdefault("agents", {})
if not isinstance(agents, dict):
    agents = {}
    cli["agents"] = agents

for role in ("director", "chief", "engineer1", "engineer2", "engineer3", "auditor"):
    config = agents.get(role)
    if isinstance(config, str):
        config = {"type": config}
    if not isinstance(config, dict):
        config = {}
    config["type"] = "opencode"
    config.pop("variant", None)
    if role == "engineer3":
        config["max_bloom"] = 3
    agents[role] = config

data["capability_tiers"] = {}
data.pop("model_selection", None)
path.write_text(
    yaml.safe_dump(data, allow_unicode=True, sort_keys=False),
    encoding="utf-8",
)
PY
fi

log "無料モデルを選択します。"
bash "${MAS_ROOT}/first_setup.sh" --non-interactive --select-free-model

set +e
MAS_ROOT="$MAS_ROOT" python3 - <<'PY'
import os
import sys
from pathlib import Path

import yaml

root = Path(os.environ["MAS_ROOT"])
path = root / "config" / "settings.yaml"
data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
if not isinstance(data, dict):
    data = {}

cli = data.setdefault("cli", {})
if not isinstance(cli, dict):
    cli = {}
    data["cli"] = cli
agents = cli.setdefault("agents", {})
if not isinstance(agents, dict):
    agents = {}
    cli["agents"] = agents

selection = data.get("model_selection")
roles = ("director", "chief", "engineer1", "engineer2", "engineer3", "auditor")
needs_fallback = not isinstance(selection, dict) or selection.get("source") != "opencode-free"
for role in roles:
    config = agents.get(role)
    if isinstance(config, str):
        config = {"type": config}
    if not isinstance(config, dict):
        config = {}
    if not str(config.get("model") or "").strip():
        needs_fallback = True
    agents[role] = config

if needs_fallback:
    for role in roles:
        config = agents[role]
        config["type"] = "opencode"
        config["model"] = "openrouter/free"
        config.pop("variant", None)
        if role == "engineer3":
            config["max_bloom"] = 3
    print(
        "WARN: 無料モデルを選択できなかったため、全エージェントを openrouter/free に設定しました。",
        file=sys.stderr,
    )

path.write_text(
    yaml.safe_dump(data, allow_unicode=True, sort_keys=False),
    encoding="utf-8",
)
if needs_fallback:
    sys.exit(3)
PY
fallback_rc=$?
set -e
if [[ "$fallback_rc" -eq 3 ]]; then
    bash "${MAS_ROOT}/scripts/build_instructions.sh" >/dev/null
elif [[ "$fallback_rc" -ne 0 ]]; then
    exit "$fallback_rc"
fi

rm -f -- "${MAS_ROOT}"/config/settings.yaml.bak.*
log "完了しました。"
