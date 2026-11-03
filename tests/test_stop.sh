#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export MAS_ROOT="$ROOT"
export MAS_SESSION="mas-stop-test-$$"
export MAS_RUN_DIR="${ROOT}/.work/stop-run-$$"
export MAS_START_INTERVAL=0
mkdir -p "$MAS_RUN_DIR"

mock="${MAS_RUN_DIR}/opencode"
cat > "$mock" <<'EOF'
#!/usr/bin/env bash
trap 'exit 0' TERM INT
echo "mock opencode: $*"
while true; do sleep 1; done
EOF
chmod +x "$mock"
export OPENCODE_BIN="$mock"

cleanup() {
    MAS_SESSION="$MAS_SESSION" MAS_RUN_DIR="$MAS_RUN_DIR" bash "${ROOT}/stop.sh" --quiet >/dev/null 2>&1 || true
    rm -rf "$MAS_RUN_DIR"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

bash "${ROOT}/start.sh" >/dev/null
sleep 1

[[ "$(tmux list-panes -t "${MAS_SESSION}:team" -F '#{pane_id}' | wc -l | tr -d ' ')" == "6" ]] || fail "6 panes not created"
[[ "$(find "$MAS_RUN_DIR" -maxdepth 1 -name 'watcher.*.pid' | wc -l | tr -d ' ')" == "6" ]] || fail "6 watcher pid files not created"
pgrep -f -- "$mock" >/dev/null || fail "mock opencode is not running"
pgrep -f -- "${ROOT}/scripts/inbox_watcher.sh" >/dev/null || fail "watchers are not running"

bash "${ROOT}/stop.sh" --quiet >/dev/null

tmux has-session -t "$MAS_SESSION" 2>/dev/null && fail "tmux session remains"
pgrep -f -- "$mock" >/dev/null && fail "mock opencode remains"
pgrep -f -- "${ROOT}/scripts/inbox_watcher.sh" >/dev/null && fail "watcher remains"

echo "stop test passed"
