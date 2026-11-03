#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAS_ROOT="${MAS_ROOT:-$SCRIPT_DIR}"
source "${MAS_ROOT}/lib/tmux_layout.sh"
source "${MAS_ROOT}/lib/agent_status.sh"

AGENT_ID="${1:-}"
PANE_TARGET="${2:-}"
ONCE=0
[[ "${3:-}" == "--once" ]] && ONCE=1

if [[ -z "$AGENT_ID" || -z "$PANE_TARGET" ]]; then
    echo "Usage: inbox_watcher.sh <agent_id> <pane_target> [--once]" >&2
    exit 1
fi

INBOX="${MAS_ROOT}/queue/inbox/${AGENT_ID}.yaml"
mkdir -p "$(dirname "$INBOX")"
[[ -f "$INBOX" ]] || printf 'messages: []\n' > "$INBOX"

LAST_COUNT=-1
LAST_SENT=0
COOLDOWN=60
# busy 中にスキップした通知を保留しているかどうか。
BUSY_PENDING=0
# inotifywait の待ち時間兼フォールバックのポーリング間隔（秒）。
POLL_INTERVAL="${INBOX_WATCH_POLL_INTERVAL:-5}"
if ! [[ "$POLL_INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
    echo "[inbox_watcher] invalid INBOX_WATCH_POLL_INTERVAL: $POLL_INTERVAL" >&2
    exit 1
fi

unread_count() {
    INBOX_PATH="$INBOX" python3 - <<'PY'
import os
import yaml
try:
    with open(os.environ["INBOX_PATH"], encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    print(sum(1 for m in (data.get("messages") or []) if not m.get("read", False)))
except Exception:
    print(0)
PY
}

has_unread_clear_command() {
    INBOX_PATH="$INBOX" python3 - <<'PY'
import os
import yaml
try:
    with open(os.environ["INBOX_PATH"], encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    found = any(
        (not m.get("read", False)) and m.get("type") == "clear_command"
        for m in (data.get("messages") or [])
    )
    print("1" if found else "0")
except Exception:
    print("0")
PY
}

send_nudge() {
    local count="$1"
    [[ "$count" -gt 0 ]] || return 0
    mas_pane_exists "$PANE_TARGET" || { echo "[inbox_watcher] pane missing: $PANE_TARGET" >&2; exit 1; }

    # 定期チェックで同じ未読件数のまま何度も送らないための共通ゲート。
    # 未読件数が変わったとき、または COOLDOWN が経過したときだけ送信する。
    local now within_cooldown=0
    now=$(date +%s)
    if [[ "$count" == "$LAST_COUNT" ]] && (( now - LAST_SENT < COOLDOWN )); then
        within_cooldown=1
    fi

    if [[ "$AGENT_ID" == "director" ]]; then
        local active
        active=$(tmux display-message -t "$PANE_TARGET" -p '#{pane_active}' 2>/dev/null || echo 0)
        if [[ "$active" == "1" ]]; then
            [[ "$within_cooldown" == "1" ]] && return 0
            tmux display-message "部長: 新着メッセージ ${count}件" 2>/dev/null || true
            LAST_COUNT="$count"
            LAST_SENT="$now"
            return 0
        fi
    fi

    if agent_is_busy_check "$PANE_TARGET"; then
        # 通知を捨てずに保留する。呼び出し側のポーリングで busy 解除後に再送する。
        BUSY_PENDING=1
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] busy: defer nudge ${AGENT_ID} (unread=${count})" >&2
        return 0
    fi
    if [[ "$BUSY_PENDING" == "1" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] idle: retry deferred nudge ${AGENT_ID} (unread=${count})" >&2
        BUSY_PENDING=0
    fi

    [[ "$within_cooldown" == "1" ]] && return 0

    if [[ "$AGENT_ID" != "director" ]] && [[ "$(has_unread_clear_command)" == "1" ]]; then
        tmux send-keys -t "$PANE_TARGET" "/new" 2>/dev/null || true
        sleep 0.2
        tmux send-keys -t "$PANE_TARGET" Enter 2>/dev/null || true
        LAST_COUNT="$count"
        LAST_SENT="$now"
        return 0
    fi

    tmux send-keys -l -t "$PANE_TARGET" \
        "queue/inbox/${AGENT_ID}.yaml の未読メッセージを確認してください" 2>/dev/null || true
    sleep 0.2
    tmux send-keys -t "$PANE_TARGET" Enter 2>/dev/null || true
    LAST_COUNT="$count"
    LAST_SENT="$now"
}

check_once() {
    local count
    count=$(unread_count)
    send_nudge "$count"
}

if [[ "$ONCE" == "1" ]]; then
    check_once
    exit 0
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] watcher started: ${AGENT_ID} -> ${PANE_TARGET}" >&2
check_once

poll_loop() {
    while true; do
        sleep "$POLL_INTERVAL"
        check_once
    done
}

# inotifywait は待ち時間 POLL_INTERVAL で必ずタイムアウトさせ、同じ間隔で
# check_once を呼ぶ。これにより busy 中にスキップした未読通知を、新しい
# inbox 書き込みがなくても busy 解除後に再送できる。
if [[ "${INBOX_WATCH_DISABLE_INOTIFY:-0}" != "1" ]] && command -v inotifywait >/dev/null 2>&1; then
    inotify_failures=0
    while true; do
        rc=0
        changed=$(inotifywait -t "$POLL_INTERVAL" -e close_write,moved_to,create \
            --format '%f' "$(dirname "$INBOX")" 2>/dev/null) || rc=$?
        case "$rc" in
            0)
                # 対象 inbox の変更イベント時だけ確認する。
                inotify_failures=0
                if [[ "$changed" == "$(basename "$INBOX")" ]]; then
                    check_once
                fi
                ;;
            2)
                # タイムアウト（イベントなし）。定期チェックを行う。
                inotify_failures=0
                check_once
                ;;
            *)
                # 恒常エラー時に待機なしの即時ループへ入らないよう、
                # 段階的に待機し、3回連続で失敗したらポーリングへ切り替える。
                inotify_failures=$((inotify_failures + 1))
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] inotifywait failed (rc=${rc}, count=${inotify_failures})" >&2
                if (( inotify_failures >= 3 )); then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] inotifywait unavailable: switching to polling" >&2
                    poll_loop
                fi
                sleep "$inotify_failures"
                check_once
                ;;
        esac
    done
else
    poll_loop
fi
