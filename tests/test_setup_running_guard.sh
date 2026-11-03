#!/usr/bin/env bash
# first_setup.sh が稼働中の mas_oc を検出して設定変更を拒否することを検証する。
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mas-setup-guard-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

failures=0
pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

new_root() {
    local root="$1"
    mkdir -p "$root/scripts" "$root/testbin"
    cp "$SRC/first_setup.sh" "$root/first_setup.sh"
    cp -a "$SRC/lib" "$root/lib"
    mkdir -p "$root/config"
    cp "$SRC/config/settings.yaml.sample" "$root/config/settings.yaml.sample"

    cat > "$root/scripts/build_instructions.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p .opencode/agents
for agent in director chief engineer1 engineer2 engineer3 auditor; do
    printf '# %s\n' "$agent" > ".opencode/agents/${agent}.md"
done
EOF
    chmod +x "$root/scripts/build_instructions.sh"

    cat > "$root/testbin/opencode" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$root/testbin/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ "${FAKE_RUNNING:-0}" == "1" ]] && exit 0
exit 1
EOF
    cat > "$root/testbin/tmux" <<'EOF'
#!/usr/bin/env bash
cmd="${1:-}"
shift || true
case "$cmd" in
    has-session)
        [[ "${FAKE_TMUX_RUNNING:-0}" == "1" ]] && exit 0
        exit 1
        ;;
    list-panes)
        if [[ "${FAKE_TMUX_RUNNING:-0}" == "1" ]]; then
            printf '%s\n' "${FAKE_PANE_ROOT:?}"
        fi
        exit 0
        ;;
esac
exit 0
EOF
    chmod +x "$root/testbin/opencode" "$root/testbin/pgrep" "$root/testbin/tmux"
}

run_setup() {
    local root="$1"
    shift
    (
        cd "$root"
        PATH="$root/testbin:$PATH" \
        MAS_ROOT="$root" \
        FAKE_RUNNING="${FAKE_RUNNING:-0}" \
        FAKE_TMUX_RUNNING="${FAKE_TMUX_RUNNING:-0}" \
        FAKE_PANE_ROOT="$root" \
        bash "$root/first_setup.sh" --non-interactive --no-select-free-model "$@"
    ) >"$root/setup.log" 2>&1
}

# 1. pgrep で稼働中を検出したら、--allow-running なしでは拒否する
root="${WORK}/running-pgrep"
new_root "$root"
if FAKE_RUNNING=1 run_setup "$root"; then
    fail "稼働中なのに first_setup.sh が成功した（pgrep）"
else
    pass "稼働中は first_setup.sh を拒否する（pgrep）"
fi
if [[ -f "$root/config/settings.yaml" ]]; then
    fail "拒否時に settings.yaml を作成してはいけない"
else
    pass "拒否時は settings.yaml を作成しない"
fi
if grep -q -- '稼働中' "$root/setup.log"; then
    pass "拒否理由を表示する"
else
    fail "拒否理由が表示されない"
fi

# 2. pgrep が検出できなくても tmux のペインcwdで稼働中を検出する
root="${WORK}/running-tmux"
new_root "$root"
if FAKE_TMUX_RUNNING=1 run_setup "$root"; then
    fail "稼働中なのに first_setup.sh が成功した（tmux）"
else
    pass "稼働中は first_setup.sh を拒否する（tmux）"
fi

# 3. --allow-running なら稼働中でも設定を書き換える
root="${WORK}/allowed"
new_root "$root"
if FAKE_RUNNING=1 run_setup "$root" --allow-running; then
    pass "--allow-running では実行できる"
else
    fail "--allow-running でも失敗した"
fi
if [[ -f "$root/config/settings.yaml" ]]; then
    pass "--allow-running では settings.yaml を作成する"
else
    fail "--allow-running なのに settings.yaml がない"
fi
if grep -q -- 'WARN: --allow-running' "$root/setup.log"; then
    pass "--allow-running の警告を表示する"
else
    fail "--allow-running の警告がない"
fi

# 4. 停止中は通常どおり設定を作成する
root="${WORK}/stopped"
new_root "$root"
if run_setup "$root"; then
    pass "停止中は通常どおり実行できる"
else
    fail "停止中なのに first_setup.sh が失敗した"
fi
if [[ -f "$root/config/settings.yaml" ]]; then
    pass "停止中は settings.yaml を作成する"
else
    fail "停止中なのに settings.yaml がない"
fi

if [[ "$failures" -eq 0 ]]; then
    echo "all setup running guard tests passed"
    exit 0
fi
echo "${failures} failure(s)" >&2
exit 1
