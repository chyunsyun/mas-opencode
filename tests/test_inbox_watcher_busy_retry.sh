#!/usr/bin/env bash
# inbox_watcher.sh の通知制御を検証する。
#  - busy 中にスキップした通知が busy 解除後に再送される
#  - 定期チェックで /new や director の display-message を連続再送しない
#  - inotifywait の恒常エラー時に即時ループせずポーリングへフォールバックする
#  - テスト終了後にテスト用プロセスが残らない
# tmux の実ペインは使わず、PATH の先頭に置いた偽 tmux で pane 状態を模擬する。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHER_SCRIPT="${INBOX_WATCHER_SCRIPT:-${ROOT}/scripts/inbox_watcher.sh}"

failures=0
pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
check_eq() { if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mas-inbox-watcher-test.XXXXXX")"
WATCHER_PIDS=()

cleanup() {
    local pid
    for pid in "${WATCHER_PIDS[@]:-}"; do
        [[ -n "$pid" ]] || continue
        stop_watcher "$pid" >/dev/null 2>&1 || true
    done
    rm -rf "$WORK"
}
trap cleanup EXIT

# --- 偽 tmux ---------------------------------------------------------------
FAKE_BIN="${WORK}/bin"
mkdir -p "$FAKE_BIN"
cat > "${FAKE_BIN}/tmux" <<'FAKE'
#!/usr/bin/env bash
set -u
state="${FAKE_TMUX_STATE:?}"
cmd="${1:-}"
shift || true
case "$cmd" in
    display-message)
        if [[ " $* " == *" -p "* ]]; then
            fmt=""
            for arg in "$@"; do fmt="$arg"; done
            case "$fmt" in
                '#{pane_id}') echo '%1' ;;
                '#{pane_active}') cat "${state}/pane_active" 2>/dev/null || echo "1" ;;
                '#{@agent_id}') echo "engineer2" ;;
                *) ;;
            esac
        else
            printf '%s\n' "$*" >> "${state}/display.log"
        fi
        ;;
    capture-pane)
        cat "${state}/pane.txt" 2>/dev/null || true
        ;;
    send-keys)
        printf '%s\n' "$*" >> "${state}/sent.log"
        ;;
    *)
        ;;
esac
FAKE
chmod +x "${FAKE_BIN}/tmux"

# --- 偽 inotifywait（即時失敗し続ける） ------------------------------------
FAKE_INOTIFY="${WORK}/fake-inotify"
mkdir -p "$FAKE_INOTIFY"
cat > "${FAKE_INOTIFY}/inotifywait" <<'FAKE'
#!/usr/bin/env bash
exit 1
FAKE
chmod +x "${FAKE_INOTIFY}/inotifywait"

# --- 一時 MAS_ROOT ---------------------------------------------------------
FAKE_ROOT="${WORK}/root"
mkdir -p "${FAKE_ROOT}/lib" "${FAKE_ROOT}/scripts" "${FAKE_ROOT}/queue/inbox"
cp "${ROOT}/lib/tmux_layout.sh" "${ROOT}/lib/agent_status.sh" "${FAKE_ROOT}/lib/"
cp "$WATCHER_SCRIPT" "${FAKE_ROOT}/scripts/inbox_watcher.sh"

write_inbox() { # $1=agent, $2=type
    local agent="$1" type="$2"
    cat > "${FAKE_ROOT}/queue/inbox/${agent}.yaml" <<EOF
messages:
  - id: msg_test_0001
    from: chief
    timestamp: "2026-10-31T00:00:00"
    type: ${type}
    content: "test message"
    read: false
EOF
}

reset_state() { # $1=state dir
    rm -rf "$1"
    mkdir -p "$1"
    : > "$1/sent.log"
    : > "$1/display.log"
    echo "0" > "$1/pane_active"
}

start_watcher() { # $1=state dir, $2=agent, $3=mode(inotify|poll|spin)
    local state="$1" agent="$2" mode="$3"
    local disable="" path_prefix="${FAKE_BIN}"
    case "$mode" in
        poll) disable="1" ;;
        spin) path_prefix="${FAKE_INOTIFY}:${FAKE_BIN}" ;;
    esac
    PATH="${path_prefix}:${PATH}" \
    FAKE_TMUX_STATE="$state" \
    MAS_ROOT="$FAKE_ROOT" \
    INBOX_WATCH_POLL_INTERVAL=1 \
    INBOX_WATCH_DISABLE_INOTIFY="$disable" \
    setsid bash "${FAKE_ROOT}/scripts/inbox_watcher.sh" "$agent" "%1" \
        >"$state/watcher.log" 2>&1 &
    WATCHER_PIDS+=("$!")
}

stop_watcher() { # $1=pid
    local pid="$1" pgid i
    pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
    # watcher と inotifywait 等の子をまとめて止めるためプロセスグループへ送る。
    if [[ -n "$pgid" && "$pgid" == "$pid" ]]; then
        kill -TERM -- "-$pgid" 2>/dev/null || true
    fi
    kill -TERM "$pid" 2>/dev/null || true
    for ((i = 0; i < 20; i++)); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    if [[ -n "$pgid" && "$pgid" == "$pid" ]]; then
        kill -KILL -- "-$pgid" 2>/dev/null || true
    fi
    kill -KILL "$pid" 2>/dev/null || true
    pkill -KILL -P "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

wait_for_send() { # $1=state dir, $2=pattern, $3=timeout seconds
    local state="$1" pattern="$2" timeout="$3" i
    for ((i = 0; i < timeout * 5; i++)); do
        grep -q -- "$pattern" "${state}/sent.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}

wait_for_display() { # $1=state dir, $2=timeout seconds
    local state="$1" timeout="$2" i
    for ((i = 0; i < timeout * 5; i++)); do
        grep -q '新着メッセージ' "${state}/display.log" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}

# --- 1. busy -> idle 再送（inotify 経路 / ポーリング経路） -----------------
for mode in inotify poll; do
    state="${WORK}/state-${mode}"
    reset_state "$state"
    # busy を模擬: 「thinking」を含む行があると agent_is_busy_check は busy と判定する
    printf 'thinking: working on task\n' > "${state}/pane.txt"
    write_inbox engineer2 task_assigned

    start_watcher "$state" engineer2 "$mode"
    pid="${WATCHER_PIDS[-1]}"

    sleep 2
    if grep -q 'queue/inbox/engineer2.yaml' "${state}/sent.log" 2>/dev/null; then
        fail "${mode}: busy 中に通知してはいけない"
    else
        pass "${mode}: busy 中は通知を保留"
    fi

    # busy 解除。inbox への新しい書き込みは行わない。
    printf 'Ready for input\n' > "${state}/pane.txt"

    if wait_for_send "$state" 'queue/inbox/engineer2.yaml' 8; then
        pass "${mode}: busy 解除後に未読通知を再送"
    else
        fail "${mode}: busy 解除後に未読通知が再送されない"
        sed -n '1,20p' "${state}/watcher.log" >&2 || true
    fi

    # COOLDOWN: 同一未読件数のまま 3 秒待っても再送スパムしない
    before=$(grep -c 'queue/inbox/engineer2.yaml' "${state}/sent.log" 2>/dev/null || true)
    sleep 3
    after=$(grep -c 'queue/inbox/engineer2.yaml' "${state}/sent.log" 2>/dev/null || true)
    check_eq "${after:-0}" "${before:-0}" "${mode}: COOLDOWN 内の再送なし"

    if grep -q -- 'inbox1' "${state}/sent.log" 2>/dev/null; then
        fail "${mode}: 件数のみの通知 inboxN を送ってはいけない"
    else
        pass "${mode}: 宛先パスを含む通知のみを送る"
    fi

    stop_watcher "$pid"
done

# --- 2. clear_command の /new は定期チェックで再送しない -------------------
state="${WORK}/state-clear"
reset_state "$state"
printf 'Ready for input\n' > "${state}/pane.txt"
write_inbox engineer2 clear_command
start_watcher "$state" engineer2 poll
pid="${WATCHER_PIDS[-1]}"
if wait_for_send "$state" '/new' 5; then
    pass "clear_command は /new を送信"
else
    fail "clear_command の /new が送信されない"
fi
sleep 3 # POLL_INTERVAL=1 の定期チェックを複数回またぐ
stop_watcher "$pid"
check_eq "$(grep -c '/new' "${state}/sent.log" 2>/dev/null || true)" "1" "clear_command の /new は COOLDOWN 内で1回だけ"
check_eq "$(grep -c 'Enter' "${state}/sent.log" 2>/dev/null || true)" "1" "clear_command の Enter は1回だけ"

# --- 3. director の pane_active 時 display-message は再表示しない ---------
state="${WORK}/state-director"
reset_state "$state"
printf 'Ready for input\n' > "${state}/pane.txt"
echo "1" > "${state}/pane_active"
write_inbox director task_assigned
start_watcher "$state" director poll
pid="${WATCHER_PIDS[-1]}"
if wait_for_display "$state" 5; then
    pass "director の pane_active 時は display-message"
else
    fail "director の pane_active 分岐が壊れている"
fi
sleep 3 # 定期チェックを複数回またぐ
stop_watcher "$pid"
check_eq "$(grep -c '新着メッセージ' "${state}/display.log" 2>/dev/null || true)" "1" "director の display-message は COOLDOWN 内で1回だけ"
if [[ -s "${state}/sent.log" ]]; then
    fail "director の pane_active 時に send-keys してはいけない"
else
    pass "director の pane_active 時に send-keys しない"
fi

# --- 4. inotifywait 恒常エラー時はバックオフし、ポーリングへ切替 ----------
state="${WORK}/state-spin"
reset_state "$state"
printf 'thinking: working on task\n' > "${state}/pane.txt" # busy のまま check_once 回数を数える
write_inbox engineer2 task_assigned
start_watcher "$state" engineer2 spin
pid="${WATCHER_PIDS[-1]}"
sleep 5
stop_watcher "$pid"
defer_count=$(grep -c 'busy: defer nudge' "${state}/watcher.log" 2>/dev/null || true)
if [[ "${defer_count:-0}" -le 10 ]]; then
    pass "inotifywait 恒常エラー時に即時ループしない（check_once ${defer_count} 回/5秒）"
else
    fail "inotifywait 恒常エラー時に即時ループしている（check_once ${defer_count} 回/5秒）"
fi
if grep -q 'switching to polling' "${state}/watcher.log" 2>/dev/null; then
    pass "inotifywait 恒常エラー時にポーリングへフォールバック"
else
    fail "ポーリングへのフォールバックが記録されていない"
fi

# --- 5. テスト用プロセスの残存確認 ----------------------------------------
sleep 0.5
work_esc="${WORK//./\\.}"
leftover=0
if pgrep -f -- "inotifywait.*${work_esc}" >/dev/null 2>&1; then
    fail "テスト用 inotifywait が残存している"
    pkill -KILL -f -- "inotifywait.*${work_esc}" 2>/dev/null || true
    leftover=1
fi
if pgrep -f -- "${work_esc}/root/scripts/inbox_watcher.sh" >/dev/null 2>&1; then
    fail "テスト用 inbox_watcher が残存している"
    pkill -KILL -f -- "${work_esc}/root/scripts/inbox_watcher.sh" 2>/dev/null || true
    leftover=1
fi
if [[ "$leftover" -eq 0 ]]; then
    pass "テスト用プロセスの残存なし"
fi

if [[ "$failures" -eq 0 ]]; then
    echo "all inbox watcher tests passed"
    exit 0
fi
echo "${failures} failure(s)" >&2
exit 1
