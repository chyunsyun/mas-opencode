#!/usr/bin/env bash

MAS_RUN_DIR="${MAS_RUN_DIR:-${MAS_ROOT}/run}"

mas_run_init() {
    mkdir -p "$MAS_RUN_DIR"
}

mas_pid_file() {
    local name="${1:-}"
    echo "${MAS_RUN_DIR}/${name}.pid"
}

mas_write_pid() {
    local name="$1"
    local pid="$2"
    local pgid
    pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ -n "$pgid" ]] || pgid="$pid"
    mas_run_init
    printf '%s %s\n' "$pid" "$pgid" > "$(mas_pid_file "$name")"
}

mas_read_pid() {
    local name="$1"
    local file
    file=$(mas_pid_file "$name")
    [[ -f "$file" ]] || return 1
    local pid pgid
    read -r pid pgid < "$file" || return 1
    printf '%s %s\n' "$pid" "$pgid"
}

mas_remove_pid() {
    rm -f "$(mas_pid_file "${1:-}")"
}

mas_kill_tree() {
    local pid="$1"
    local signal="${2:-TERM}"
    local child
    for child in $(pgrep -P "$pid" 2>/dev/null || true); do
        mas_kill_tree "$child" "$signal"
    done
    kill -"$signal" "$pid" 2>/dev/null || true
}

mas_stop_pid() {
    local name="$1"
    local expected="${2:-}"
    local file pid pgid
    file=$(mas_pid_file "$name")
    [[ -f "$file" ]] || return 1
    read -r pid pgid < "$file" || return 1
    if [[ "$pid" == "$$" ]] || mas_is_ancestor_of_self "$pid"; then
        mas_remove_pid "$name"
        return 0
    fi
    if [[ -n "$expected" ]] && [[ -r "/proc/${pid}/cmdline" ]]; then
        if ! tr '\0' ' ' < "/proc/${pid}/cmdline" | grep -Fq -- "$expected"; then
            mas_remove_pid "$name"
            return 0
        fi
    fi
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        if [[ -n "$pgid" ]] && [[ "$pgid" != "1" ]]; then
            kill -TERM -- "-$pgid" 2>/dev/null || mas_kill_tree "$pid" TERM
        else
            mas_kill_tree "$pid" TERM
        fi
        local i
        for i in 1 2 3 4 5; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.2
        done
        if kill -0 "$pid" 2>/dev/null; then
            if [[ -n "$pgid" ]] && [[ "$pgid" != "1" ]]; then
                kill -KILL -- "-$pgid" 2>/dev/null || mas_kill_tree "$pid" KILL
            else
                mas_kill_tree "$pid" KILL
            fi
        fi
    fi
    mas_remove_pid "$name"
    return 0
}

mas_is_ancestor_of_self() {
    local target="$1"
    local current="$$"
    while [[ -n "$current" && "$current" != "0" && "$current" != "1" ]]; do
        [[ "$current" == "$target" ]] && return 0
        current=$(ps -o ppid= -p "$current" 2>/dev/null | tr -d ' ')
    done
    return 1
}

mas_stop_pattern() {
    local pattern="$1"
    local pids
    pids=$(pgrep -f -- "$pattern" 2>/dev/null || true)
    [[ -z "$pids" ]] && return 0
    local pid matched=()
    for pid in $pids; do
        [[ "$pid" == "$$" ]] && continue
        mas_is_ancestor_of_self "$pid" && continue
        matched+=("$pid")
    done
    [[ ${#matched[@]} -eq 0 ]] && return 0
    for pid in "${matched[@]}"; do
        mas_kill_tree "$pid" TERM
    done
    sleep 0.3
    for pid in "${matched[@]}"; do
        kill -0 "$pid" 2>/dev/null && mas_kill_tree "$pid" KILL
    done
    return 0
}
