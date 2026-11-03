#!/usr/bin/env bash
# inbox_watcher.sh が通知に対象エージェントのinboxパスを含めることを検証する。
# 件数のみの inboxN 通知では、engineer3 が inbox1 を engineer1 のinboxと
# 誤読する可能性があるため、宛先パスが必ず含まれることを回帰テストする。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHER_SCRIPT="${INBOX_WATCHER_SCRIPT:-${ROOT}/scripts/inbox_watcher.sh}"

failures=0
pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mas-inbox-nudge-test.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

FAKE_BIN="${WORK}/bin"
FAKE_ROOT="${WORK}/root"
mkdir -p "$FAKE_BIN" "${FAKE_ROOT}/lib" "${FAKE_ROOT}/scripts" "${FAKE_ROOT}/queue/inbox"
cp "${ROOT}/lib/tmux_layout.sh" "${ROOT}/lib/agent_status.sh" "${FAKE_ROOT}/lib/"
cp "$WATCHER_SCRIPT" "${FAKE_ROOT}/scripts/inbox_watcher.sh"

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
                '#{@agent_id}') echo "test" ;;
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

write_inbox() { # $1=agent
    local agent="$1"
    cat > "${FAKE_ROOT}/queue/inbox/${agent}.yaml" <<EOF
messages:
  - id: msg_test_${agent}
    from: chief
    timestamp: "2026-10-31T00:00:00"
    type: task_assigned
    content: "test message"
    read: false
EOF
}

agents=(director chief engineer1 engineer2 engineer3 auditor)
for agent in "${agents[@]}"; do
    state="${WORK}/state-${agent}"
    mkdir -p "$state"
    : > "${state}/sent.log"
    : > "${state}/display.log"
    echo "0" > "${state}/pane_active"

    write_inbox "$agent"

    if ! PATH="${FAKE_BIN}:${PATH}" \
        FAKE_TMUX_STATE="$state" \
        MAS_ROOT="$FAKE_ROOT" \
        bash "${FAKE_ROOT}/scripts/inbox_watcher.sh" "$agent" "%1" --once \
        > "${state}/watcher.log" 2>&1; then
        fail "${agent}: watcher が異常終了した"
        sed -n '1,20p' "${state}/watcher.log" >&2 || true
        continue
    fi

    expected="queue/inbox/${agent}.yaml"
    if grep -Fq -- "$expected" "${state}/sent.log" 2>/dev/null; then
        pass "${agent}: 通知に自分のinboxパスを含む"
    else
        fail "${agent}: 通知に ${expected} が含まれない"
        sed -n '1,20p' "${state}/sent.log" >&2 || true
    fi

    if grep -Fq -- 'inbox1' "${state}/sent.log" 2>/dev/null; then
        fail "${agent}: 件数のみの inboxN 通知が残っている"
    else
        pass "${agent}: 件数のみの inboxN 通知を送らない"
    fi

    for other in "${agents[@]}"; do
        [[ "$other" == "$agent" ]] && continue
        if grep -Fq -- "$other" "${state}/sent.log" 2>/dev/null; then
            fail "${agent}: 通知に別エージェント ${other} が含まれる"
            break
        fi
    done
done

if [[ "$failures" -eq 0 ]]; then
    echo "all inbox nudge tests passed"
    exit 0
fi
echo "${failures} failure(s)" >&2
exit 1
