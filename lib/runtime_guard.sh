#!/usr/bin/env bash

# MAS_ROOT のインスタンスが稼働中かどうかを判定する。
# - watcher のプロセス（MAS_ROOT 配下の inbox_watcher.sh）
# - tmux セッション内のペインの作業ディレクトリが MAS_ROOT と一致
# のいずれかで稼働中とみなす。別ディレクトリの mas_oc とは区別する。
mas_root_is_running() {
    local root="${1:-${MAS_ROOT:-}}"
    [[ -n "$root" ]] || return 1
    root="${root%/}"

    if command -v pgrep >/dev/null 2>&1; then
        if pgrep -f -- "${root}/scripts/inbox_watcher.sh" >/dev/null 2>&1; then
            return 0
        fi
    fi

    command -v tmux >/dev/null 2>&1 || return 1
    local session="${MAS_SESSION:-mas}"
    tmux has-session -t "$session" 2>/dev/null || return 1

    local pane_path
    while IFS= read -r pane_path; do
        [[ -n "$pane_path" ]] || continue
        if [[ "${pane_path%/}" == "$root" ]]; then
            return 0
        fi
    done < <(tmux list-panes -t "$session" -F '#{pane_current_path}' 2>/dev/null || true)

    return 1
}
