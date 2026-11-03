#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAS_ROOT="${MAS_ROOT:-$SCRIPT_DIR}"
cd "$MAS_ROOT"

source "${MAS_ROOT}/lib/agent_registry.sh"
source "${MAS_ROOT}/lib/cli_adapter.sh"
source "${MAS_ROOT}/lib/tmux_layout.sh"
source "${MAS_ROOT}/lib/run_state.sh"

AUTO=1
CLEAN=0
PURGE=0
PURGE_YES=0
SETUP_ONLY=0
LAYOUT="3x2"
START_INTERVAL="${MAS_START_INTERVAL:-15}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--clean) CLEAN=1; shift ;;
        --purge) PURGE=1; CLEAN=1; shift ;;
        --yes) PURGE_YES=1; shift ;;
        -s|--setup-only) SETUP_ONLY=1; shift ;;
        --no-auto) AUTO=0; shift ;;
        --layout) LAYOUT="${2:-3x2}"; shift 2 ;;
        --start-interval) START_INTERVAL="${2:-15}"; shift 2 ;;
        -h|--help)
            cat <<'EOF'
Usage: ./start.sh [-c|--clean] [--purge --yes] [-s|--setup-only] [--no-auto] [--layout 3x2|2x3] [--start-interval SEC]
  -c, --clean       キューをバックアップして初期化する
  --purge           使用履歴を完全に削除して起動する（--yes が必須、バックアップなし）
  --yes             --purge の実行を確認する
  -s, --setup-only  tmux とエージェント設定だけを作り、CLI は起動しない
  --no-auto         OpenCode の --auto を付けない
  --layout          3x2（既定）または 2x3
  --start-interval  エージェント起動間隔（秒、既定15）
EOF
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ "$PURGE" == "1" && "$PURGE_YES" != "1" ]]; then
    echo "ERROR: --purge には --yes が必要です（使用履歴を完全に削除します）。" >&2
    exit 1
fi

case "$LAYOUT" in 3x2|2x3) ;; *) echo "layout must be 3x2 or 2x3" >&2; exit 1 ;; esac
if ! [[ "$START_INTERVAL" =~ ^[0-9]+$ ]]; then
    echo "ERROR: start interval must be a non-negative integer (seconds)." >&2
    exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
    echo "ERROR: tmux が見つかりません。" >&2
    exit 1
fi
if [[ "$SETUP_ONLY" == "0" ]] && ! validate_cli_availability; then
    echo "ERROR: opencode が見つかりません。" >&2
    exit 1
fi
if [[ ! -f "${MAS_ROOT}/config/settings.yaml" ]]; then
    # start.sh はこの直後に既存セッションを停止して起動し直すため、稼働中でも設定を許可する。
    bash "${MAS_ROOT}/first_setup.sh" --non-interactive --allow-running
fi

bash "${MAS_ROOT}/stop.sh" --quiet

if [[ "$PURGE" == "1" ]]; then
    bash "${MAS_ROOT}/scripts/purge_history.sh" --yes
elif [[ "$CLEAN" == "1" ]]; then
    bash "${MAS_ROOT}/first_setup.sh" --reset-queue --non-interactive
fi

mkdir -p "${MAS_ROOT}/run" "${MAS_ROOT}/logs" "${MAS_ROOT}/status"

if [[ ! -f "${MAS_ROOT}/.opencode/agents/director.md" ]]; then
    bash "${MAS_ROOT}/scripts/build_instructions.sh" >/dev/null
fi

cleanup_on_error() {
    local rc=$?
    if (( rc != 0 )); then
        echo "起動に失敗しました。関連プロセスを停止します。" >&2
        bash "${MAS_ROOT}/stop.sh" --quiet || true
    fi
    exit "$rc"
}
trap cleanup_on_error EXIT

tmux new-session -d -s "$(mas_session_name)" -n "$(mas_window_name)" \
    -e "MAS_ROOT=$MAS_ROOT" \
    -x "${MAS_TMUX_COLS:-240}" -y "${MAS_TMUX_LINES:-50}" -c "$MAS_ROOT"
tmux set-environment -t "$(mas_session_name)" MAS_ROOT "$MAS_ROOT"
tmux set-option -t "$(mas_session_name)" window-size largest
tmux set-option -t "$(mas_session_name)" aggressive-resize on
tmux set-option -t "$(mas_session_name)" -w pane-border-status top
tmux set-option -t "$(mas_session_name)" -w pane-border-format \
    '#{?pane_active,#[reverse],}#[bold]#{@agent_label}#[default] #{@current_task}'
tmux set-option -t "$(mas_session_name)" status-left '[mas_oc] '
tmux set-option -t "$(mas_session_name)" status-right '#{session_name}:#{window_name}'

if [[ "$LAYOUT" == "3x2" ]]; then
    tmux split-window -h -t "$(mas_session_name):$(mas_window_name)" -c "$MAS_ROOT"
    tmux split-window -h -t "$(mas_session_name):$(mas_window_name)" -c "$MAS_ROOT"
    tmux select-layout -t "$(mas_session_name):$(mas_window_name)" even-horizontal
    while IFS= read -r pane; do
        tmux split-window -v -t "$pane" -c "$MAS_ROOT"
    done < <(tmux list-panes -t "$(mas_session_name):$(mas_window_name)" -F '#{pane_id}')
    sort_args=(-k2,2n -k3,3n)
else
    tmux split-window -h -t "$(mas_session_name):$(mas_window_name)" -c "$MAS_ROOT"
    tmux select-layout -t "$(mas_session_name):$(mas_window_name)" even-horizontal
    pane_a=$(tmux list-panes -t "$(mas_session_name):$(mas_window_name)" -F '#{pane_id}' | sed -n '1p')
    pane_b=$(tmux list-panes -t "$(mas_session_name):$(mas_window_name)" -F '#{pane_id}' | sed -n '2p')
    tmux split-window -v -t "$pane_a" -c "$MAS_ROOT"
    tmux split-window -v -t "$pane_a" -c "$MAS_ROOT"
    tmux split-window -v -t "$pane_b" -c "$MAS_ROOT"
    tmux split-window -v -t "$pane_b" -c "$MAS_ROOT"
    sort_args=(-k3,3n -k2,2n)
fi

mapfile -t panes < <(
    tmux list-panes -t "$(mas_session_name):$(mas_window_name)" -F '#{pane_id} #{pane_top} #{pane_left}' \
        | sort "${sort_args[@]}"
)
if (( ${#panes[@]} != 6 )); then
    echo "ERROR: 6ペインを作成できませんでした（${#panes[@]}ペイン）。端末サイズを確認してください。" >&2
    exit 1
fi

agents=(director chief auditor engineer1 engineer2 engineer3)
for i in "${!agents[@]}"; do
    agent_id="${agents[$i]}"
    read -r pane _top _left <<< "${panes[$i]}"
    label=$(agent_registry_label "$agent_id")
    model=$(get_model_display_name "$agent_id")
    mas_set_pane_metadata "$pane" "$agent_id" "$label" "$model"
    if [[ "$agent_id" == "director" ]]; then
        tmux select-pane -t "$pane" -P 'bg=#002b36' 2>/dev/null || true
    fi
    if [[ "$SETUP_ONLY" == "0" ]]; then
        command=$(build_cli_command "$agent_id" "$AUTO")
        tmux send-keys -t "$pane" "cd $(printf '%q' "$MAS_ROOT") && clear && $command" 2>/dev/null || true
        tmux send-keys -t "$pane" Enter 2>/dev/null || true
    else
        tmux send-keys -t "$pane" "cd $(printf '%q' "$MAS_ROOT") && clear" Enter 2>/dev/null || true
    fi

    if [[ "$SETUP_ONLY" == "0" ]] && (( i + 1 < ${#agents[@]} )); then
        echo "${label}を起動しました。次の起動まで ${START_INTERVAL} 秒待機します。"
        sleep "$START_INTERVAL"
    fi
done

if [[ "$SETUP_ONLY" == "0" ]]; then
    for _ in {1..20}; do
        ready=1
        while IFS= read -r pane; do
            if ! tmux capture-pane -t "$pane" -p 2>/dev/null | grep -qiE 'opencode|esc.*interrupt|Tip'; then
                ready=0
                break
            fi
        done < <(mas_all_panes)
        [[ "$ready" == "1" ]] && break
        sleep 0.3
    done
    start_daemon() {
        local name="$1"
        shift
        local log="${MAS_ROOT}/logs/${name}.log"
        if command -v setsid >/dev/null 2>&1; then
            setsid "$@" >>"$log" 2>&1 </dev/null &
        else
            python3 -c 'import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])'                 "$@" >>"$log" 2>&1 </dev/null &
        fi
        local pid=$!
        mas_write_pid "$name" "$pid"
    }

    while IFS= read -r agent_id; do
        pane=$(mas_pane_for_agent "$agent_id" || true)
        [[ -n "$pane" ]] || continue
        state_home=$(ensure_agent_state_home "$agent_id")
        start_daemon "watcher.${agent_id}" env XDG_STATE_HOME="$state_home" bash "${MAS_ROOT}/scripts/inbox_watcher.sh" "$agent_id" "$pane"
    done < <(agent_registry_agents)
fi

printf 'MAS_SESSION=%s\nMAS_ROOT=%s\nSTARTED_AT=%s\n' \
    "$(mas_session_name)" "$MAS_ROOT" "$(date '+%Y-%m-%dT%H:%M:%S%z')" > "${MAS_ROOT}/run/session.env"

trap - EXIT
echo "起動しました。6名: 部長 / 係長 / エンジニア1-3 / 監査役"
echo "接続: $(mas_attach_hint)"
echo "状態: ./mas status"
echo "停止: ./mas stop"
