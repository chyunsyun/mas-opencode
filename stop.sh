#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAS_ROOT="${MAS_ROOT:-$SCRIPT_DIR}"
source "${MAS_ROOT}/lib/tmux_layout.sh"
source "${MAS_ROOT}/lib/run_state.sh"

QUIET=0
VERIFY_ONLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quiet) QUIET=1; shift ;;
        --verify) VERIFY_ONLY=1; shift ;;
        -h|--help)
            cat <<'EOF'
Usage: ./stop.sh [--quiet] [--verify]
  --quiet   通常メッセージを抑制する
  --verify  停止せず、残存プロセスだけを検査する
EOF
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

log() { [[ "$QUIET" == "1" ]] || echo "$@"; }

verify_clean() {
    local leftovers=()
    if tmux has-session -t "$(mas_session_name)" 2>/dev/null; then
        leftovers+=("tmux session $(mas_session_name)")
    fi
    local pattern
    for pattern in \
        "${MAS_ROOT}/scripts/inbox_watcher.sh" \
        "${MAS_ROOT}/scripts/ntfy_listener.sh" \
        "${MAS_ROOT}/scripts/watcher_supervisor.sh" \
        "${MAS_ROOT}/scripts/dashboard-viewer.py" \
        "inotifywait.*${MAS_ROOT}/queue/inbox"; do
        if pgrep -f -- "$pattern" >/dev/null 2>&1; then
            leftovers+=("process: $pattern")
        fi
    done
    local ss_bin
    ss_bin="/usr/bin/ss"
    [[ -x "$ss_bin" ]] || ss_bin="$(command -v ss || true)"
    if [[ -n "$ss_bin" ]] && "$ss_bin" -ltn 2>/dev/null | grep -qE ':8787[[:space:]]'; then
        leftovers+=("port 8787 is still listening")
    fi
    if [[ ${#leftovers[@]} -gt 0 ]]; then
        echo "残存プロセス/セッション:" >&2
        printf '  - %s\n' "${leftovers[@]}" >&2
        return 1
    fi
    return 0
}

if [[ "$VERIFY_ONLY" == "1" ]]; then
    verify_clean
    exit $?
fi

for pid_file in "${MAS_ROOT}/run"/watcher.*.pid; do
    [[ -f "$pid_file" ]] || continue
    name=$(basename "$pid_file" .pid)
    mas_stop_pid "$name" "inbox_watcher.sh" || true
done
mas_stop_pid ntfy_listener "ntfy_listener.sh" 2>/dev/null || true
mas_stop_pid watcher_supervisor "watcher_supervisor.sh" 2>/dev/null || true
mas_stop_pid dashboard "dashboard-viewer.py" 2>/dev/null || true

mas_stop_pattern "${MAS_ROOT}/scripts/watcher_supervisor.sh" || true
mas_stop_pattern "${MAS_ROOT}/scripts/inbox_watcher.sh" || true
mas_stop_pattern "${MAS_ROOT}/scripts/ntfy_listener.sh" || true
mas_stop_pattern "${MAS_ROOT}/scripts/dashboard-viewer.py" || true
mas_stop_pattern "inotifywait.*${MAS_ROOT}/queue/inbox" || true

if [[ -x "${MAS_ROOT}/scripts/setup_cron.sh" ]]; then
    bash "${MAS_ROOT}/scripts/setup_cron.sh" --uninstall --quiet >/dev/null 2>&1 || true
fi

if tmux has-session -t "$(mas_session_name)" 2>/dev/null; then
    while IFS= read -r pane; do
        pane_pid=$(tmux display-message -t "$pane" -p '#{pane_pid}' 2>/dev/null || true)
        [[ -n "$pane_pid" ]] && mas_kill_tree "$pane_pid" TERM
    done < <(tmux list-panes -t "$(mas_session_name):$(mas_window_name)" -F '#{pane_id}' 2>/dev/null || true)
    sleep 0.5
    while IFS= read -r pane; do
        pane_pid=$(tmux display-message -t "$pane" -p '#{pane_pid}' 2>/dev/null || true)
        [[ -n "$pane_pid" ]] && mas_kill_tree "$pane_pid" KILL
    done < <(tmux list-panes -t "$(mas_session_name):$(mas_window_name)" -F '#{pane_id}' 2>/dev/null || true)
    tmux kill-session -t "$(mas_session_name)" 2>/dev/null || true
fi

if [[ -d /proc ]]; then
    for envfile in /proc/[0-9]*/environ; do
        [[ -r "$envfile" ]] || continue
        pid=${envfile#/proc/}
        pid=${pid%/environ}
        [[ "$pid" == "$$" ]] && continue
        mas_is_ancestor_of_self "$pid" && continue
        if tr '\0' '\n' < "$envfile" 2>/dev/null | grep -qE '^OPENCODE_AGENT_ID=(director|chief|engineer1|engineer2|engineer3|auditor)$'; then
            cwd=$(readlink "/proc/${pid}/cwd" 2>/dev/null || true)
            mas_root_prefix="${MAS_ROOT%/}"
            if [[ "$cwd" == "$mas_root_prefix" || "$cwd" == "${mas_root_prefix}/"* ]]; then
                mas_kill_tree "$pid" TERM
            fi
        fi
    done
fi

find "${MAS_ROOT}/queue" -type d -name '*.lock.d' -prune -exec rm -rf {} + 2>/dev/null || true
find "${MAS_ROOT}/queue" -type f -name '*.lock' -delete 2>/dev/null || true
find "${MAS_ROOT}/run" -maxdepth 1 -type f \( -name '*.lock' -o -name '*.pid' -o -name 'session.env' \) -delete 2>/dev/null || true
find "${MAS_ROOT}/run" -maxdepth 1 -type f -name 'idle_*' -delete 2>/dev/null || true

log "停止しました。"
if ! verify_clean; then
    exit 1
fi
