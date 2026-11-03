#!/usr/bin/env bash
# switch_model.sh が busy 中の設定変更・再起動を拒否し、--force で許可することを検証する。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mas-switch-model-guard-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

FAKE_ROOT="${WORK}/root"
FAKE_BIN="${WORK}/bin"
mkdir -p "$FAKE_ROOT"/{lib,scripts,config,run} "$FAKE_BIN"
cp "${ROOT}/scripts/switch_model.sh" "${FAKE_ROOT}/scripts/"
cp "${ROOT}/lib/agent_registry.sh" \
   "${ROOT}/lib/cli_adapter.sh" \
   "${ROOT}/lib/tmux_layout.sh" \
   "${ROOT}/lib/agent_status.sh" \
   "${FAKE_ROOT}/lib/"

cat > "${FAKE_ROOT}/scripts/build_instructions.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${FAKE_ROOT}/scripts/build_instructions.sh"

cat > "${FAKE_BIN}/tmux" <<'FAKE'
#!/usr/bin/env bash
set -u
state="${FAKE_TMUX_STATE:?}"
cmd="${1:-}"
shift || true
case "$cmd" in
    list-panes)
        if [[ "${FAKE_PANE_MISSING:-0}" != "1" ]]; then
            echo '%1 engineer3'
        fi
        ;;
    display-message)
        if [[ " $* " == *" -p "* ]]; then
            fmt=""
            for arg in "$@"; do fmt="$arg"; done
            case "$fmt" in
                '#{pane_id}') echo '%1' ;;
                '#{pane_active}') echo '1' ;;
                '#{@agent_id}') echo 'engineer3' ;;
                *) ;;
            esac
        fi
        ;;
    show-environment)
        if [[ -n "${FAKE_SESSION_ROOT:-}" ]]; then
            printf 'MAS_ROOT=%s\n' "$FAKE_SESSION_ROOT"
            exit 0
        fi
        exit 1
        ;;
    capture-pane)
        cat "${state}/pane.txt" 2>/dev/null || true
        ;;
    respawn-pane)
        printf 'respawn-pane %s\n' "$*" >> "${state}/respawn.log"
        ;;
    send-keys)
        printf 'send-keys %s\n' "$*" >> "${state}/send.log"
        ;;
    *)
        ;;
esac
FAKE
chmod +x "${FAKE_BIN}/tmux"

write_settings() {
    cat > "${FAKE_ROOT}/config/settings.yaml" <<'YAML'
cli:
  default: opencode
  agents:
    director:
      type: opencode
      model: opencode/test-director
    chief:
      type: opencode
      model: opencode/test-chief
    engineer1:
      type: opencode
      model: opencode/test-engineer1
    engineer2:
      type: opencode
      model: opencode/test-engineer2
    engineer3:
      type: opencode
      model: opencode/test-engineer3
      variant: low
      max_bloom: 3
    auditor:
      type: opencode
      model: opencode/test-auditor
YAML
}

model_of() {
    python3 - "${FAKE_ROOT}/config/settings.yaml" <<'PY'
import sys
import yaml
with open(sys.argv[1], encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}
print(((data.get("cli") or {}).get("agents") or {}).get("engineer3", {}).get("model", ""))
PY
}

failures=0
pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

run_switch() {
    local state="$1"
    shift
    mkdir -p "$state"
    : > "$state/respawn.log"
    : > "$state/send.log"
    PATH="${FAKE_BIN}:${PATH}" \
    FAKE_TMUX_STATE="$state" \
    FAKE_PANE_MISSING="${FAKE_PANE_MISSING:-0}" \
    FAKE_SESSION_ROOT="${FAKE_SESSION_ROOT:-}" \
    MAS_ROOT="$FAKE_ROOT" \
    bash "${FAKE_ROOT}/scripts/switch_model.sh" engineer3 "$@" \
        >"$state/switch.log" 2>&1
}

# 1. busy 中は --force なしで拒否し、設定も再起動も変更しない
state="${WORK}/busy"
write_settings
mkdir -p "$state"
printf 'thinking: working on task\n' > "$state/pane.txt"
if run_switch "$state" --model opencode-go/new-model; then
    fail "busy 中なのに switch_model.sh が成功した"
else
    pass "busy 中は --force なしで拒否する"
fi
if [[ "$(model_of)" == "opencode/test-engineer3" ]]; then
    pass "busy 拒否時は settings.yaml を変更しない"
else
    fail "busy 拒否時に settings.yaml が変更された"
fi
if [[ -s "$state/respawn.log" ]]; then
    fail "busy 拒否時に respawn してはいけない"
else
    pass "busy 拒否時は respawn しない"
fi

# 2. --force なら busy 中でも切り替える
state="${WORK}/busy-force"
write_settings
mkdir -p "$state"
printf 'thinking: working on task\n' > "$state/pane.txt"
if run_switch "$state" --model opencode-go/new-model --force; then
    pass "--force なら busy 中でも実行できる"
else
    fail "--force でも busy 中に失敗した"
fi
if [[ "$(model_of)" == "opencode-go/new-model" ]]; then
    pass "--force で settings.yaml を更新する"
else
    fail "--force で settings.yaml が更新されない"
fi
if grep -q 'respawn-pane' "$state/respawn.log" 2>/dev/null; then
    pass "--force でペインを再起動する"
else
    fail "--force でペインを再起動しない"
fi

# 3. idle なら通常どおり切り替える
state="${WORK}/idle"
write_settings
mkdir -p "$state"
printf 'Ready for input\n' > "$state/pane.txt"
if run_switch "$state" --model opencode-go/new-model; then
    pass "idle なら通常どおり実行できる"
else
    fail "idle なのに switch_model.sh が失敗した"
fi
if [[ "$(model_of)" == "opencode-go/new-model" ]]; then
    pass "idle で settings.yaml を更新する"
else
    fail "idle で settings.yaml が更新されない"
fi
if grep -q 'respawn-pane' "$state/respawn.log" 2>/dev/null; then
    pass "idle でペインを再起動する"
else
    fail "idle でペインを再起動しない"
fi

# 4. ペイン不在なら設定だけ更新し、respawn しない
state="${WORK}/no-pane"
write_settings
mkdir -p "$state"
printf 'Ready for input\n' > "$state/pane.txt"
if FAKE_PANE_MISSING=1 run_switch "$state" --model opencode-go/new-model; then
    pass "ペイン不在でも設定を更新できる"
else
    fail "ペイン不在で switch_model.sh が失敗した"
fi
if [[ "$(model_of)" == "opencode-go/new-model" ]]; then
    pass "ペイン不在で settings.yaml を更新する"
else
    fail "ペイン不在で settings.yaml が更新されない"
fi
if [[ -s "$state/respawn.log" ]]; then
    fail "ペイン不在で respawn してはいけない"
else
    pass "ペイン不在では respawn しない"
fi

# 5. 別ディレクトリの tmux セッションなら、設定は更新してもペインは再起動しない
state="${WORK}/other-session"
write_settings
mkdir -p "$state"
printf 'Ready for input\n' > "$state/pane.txt"
if FAKE_SESSION_ROOT="/tmp/other-mas-root" run_switch "$state" --model opencode-go/new-model; then
    pass "別セッションでも設定更新自体は成功する"
else
    fail "別セッションで switch_model.sh が失敗した"
fi
if [[ "$(model_of)" == "opencode-go/new-model" ]]; then
    pass "別セッションで settings.yaml を更新する"
else
    fail "別セッションで settings.yaml が更新されない"
fi
if [[ -s "$state/respawn.log" ]]; then
    fail "別セッションのペインを respawn してはいけない"
else
    pass "別セッションのペインを respawn しない"
fi
if grep -q -- 'ペイン再起動は行いません' "$state/switch.log"; then
    pass "別セッションであることを警告する"
else
    fail "別セッションの警告がない"
fi

if [[ "$failures" -eq 0 ]]; then
    echo "all switch_model guard tests passed"
    exit 0
fi
echo "${failures} failure(s)" >&2
exit 1
