#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAS_ROOT="${MAS_ROOT:-$SCRIPT_DIR}"
source "${MAS_ROOT}/lib/agent_registry.sh"

TARGET="${1:-}"
CONTENT="${2:-}"
TYPE="${3:-}"
FROM="${4:-}"

if [[ -z "$TARGET" || -z "$CONTENT" || -z "$TYPE" || -z "$FROM" ]]; then
    echo "Usage: inbox_write.sh <target_agent> <content> <type> <from>" >&2
    exit 1
fi
if [[ "$TARGET" == "$FROM" ]]; then
    echo "[inbox_write] self-send is not allowed: $TARGET" >&2
    exit 1
fi
if ! agent_registry_agents | grep -qx "$TARGET"; then
    echo "[inbox_write] unknown target: $TARGET" >&2
    exit 1
fi

INBOX="${MAS_ROOT}/queue/inbox/${TARGET}.yaml"
mkdir -p "$(dirname "$INBOX")"
[[ -f "$INBOX" ]] || printf 'messages: []\n' > "$INBOX"

LOCKFILE="${INBOX}.lock"
if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCKFILE"
    flock -w 5 9
else
    LOCKDIR="${LOCKFILE}.d"
    i=0
    while ! mkdir "$LOCKDIR" 2>/dev/null; do
        sleep 0.1
        i=$((i + 1))
        if (( i >= 50 )); then
            echo "[inbox_write] lock timeout: $INBOX" >&2
            exit 1
        fi
    done
    trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT
fi

INBOX_PATH="$INBOX" MSG_FROM="$FROM" MSG_TYPE="$TYPE" MSG_CONTENT="$CONTENT" python3 - <<'PY'
import datetime
import os
import tempfile
import uuid

import yaml

path = os.environ["INBOX_PATH"]
sender = os.environ["MSG_FROM"]
msg_type = os.environ["MSG_TYPE"]
content = os.environ["MSG_CONTENT"]

try:
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
except FileNotFoundError:
    data = {}
except Exception as exc:
    raise SystemExit(f"failed to read {path}: {exc}")

messages = data.get("messages") or []
messages.append({
    "id": f"msg_{datetime.datetime.now():%Y%m%d_%H%M%S}_{uuid.uuid4().hex[:8]}",
    "from": sender,
    "timestamp": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "type": msg_type,
    "content": content,
    "read": False,
})
if len(messages) > 50:
    unread = [m for m in messages if not m.get("read", False)]
    read = [m for m in messages if m.get("read", False)]
    messages = unread + read[-30:]
data["messages"] = messages

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False, indent=2)
    os.replace(tmp, path)
except Exception:
    try:
        os.unlink(tmp)
    except FileNotFoundError:
        pass
    raise
PY
