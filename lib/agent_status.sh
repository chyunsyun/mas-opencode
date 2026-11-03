#!/usr/bin/env bash

agent_is_busy_check() {
    local pane_target="${1:-}"
    [[ -z "$pane_target" ]] && return 2
    if ! tmux display-message -t "$pane_target" -p '#{pane_id}' >/dev/null 2>&1; then
        return 2
    fi

    local capture tail_text last_line
    capture=$(tmux capture-pane -t "$pane_target" -p 2>/dev/null || true)
    [[ -z "$capture" ]] && return 1

    tail_text=$(printf '%s\n' "$capture" | grep -v '^[[:space:]]*$' | tail -8)
    last_line=$(printf '%s\n' "$tail_text" | tail -1)

    if printf '%s\n' "$last_line" | grep -qiE 'esc([[:space:]]+to)?[[:space:]]+interrupt|interrupt[[:space:]]+esc'; then
        return 0
    fi
    if printf '%s\n' "$tail_text" | grep -qiE 'thinking|working|processing|running tool|実行中|処理中|考え中'; then
        return 0
    fi
    if printf '%s\n' "$capture" | grep -qE '([■⬝].*){8}'; then
        return 0
    fi
    return 1
}

get_pane_state_label() {
    local pane_target="${1:-}"
    agent_is_busy_check "$pane_target"
    local rc=$?
    case "$rc" in
        0) echo "稼働中" ;;
        1) echo "待機中" ;;
        *) echo "不在" ;;
    esac
}
