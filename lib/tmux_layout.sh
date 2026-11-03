#!/usr/bin/env bash

MAS_SESSION="${MAS_SESSION:-mas}"
MAS_WINDOW="${MAS_WINDOW:-team}"

mas_session_name() {
    echo "$MAS_SESSION"
}

mas_window_name() {
    echo "$MAS_WINDOW"
}

mas_pane_for_agent() {
    local agent_id="${1:-}"
    [[ -z "$agent_id" ]] && return 1
    tmux list-panes -t "${MAS_SESSION}:${MAS_WINDOW}" -F '#{pane_id} #{@agent_id}' 2>/dev/null \
        | awk -v id="$agent_id" '$2 == id { print $1; exit }'
}

mas_pane_exists() {
    local pane_target="${1:-}"
    [[ -n "$pane_target" ]] || return 1
    tmux display-message -t "$pane_target" -p '#{pane_id}' >/dev/null 2>&1
}

mas_agent_for_pane() {
    local pane_target="${1:-}"
    tmux display-message -t "$pane_target" -p '#{@agent_id}' 2>/dev/null || true
}

mas_all_panes() {
    tmux list-panes -t "${MAS_SESSION}:${MAS_WINDOW}" -F '#{pane_id}' 2>/dev/null
}

mas_set_pane_metadata() {
    local pane_target="$1"
    local agent_id="$2"
    local label="$3"
    local model="$4"
    tmux set-option -p -t "$pane_target" @agent_id "$agent_id" 2>/dev/null || true
    tmux set-option -p -t "$pane_target" @agent_label "$label" 2>/dev/null || true
    tmux set-option -p -t "$pane_target" @model_name "$model" 2>/dev/null || true
    tmux set-option -p -t "$pane_target" @current_task "" 2>/dev/null || true
    tmux select-pane -t "$pane_target" -T "${label}" 2>/dev/null || true
}

mas_attach_hint() {
    echo "tmux attach -t ${MAS_SESSION}"
}
