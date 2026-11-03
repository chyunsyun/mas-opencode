#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="print"
QUIET=0

usage() {
    cat <<'EOF'
Usage: setup_cron.sh [--print] [--install] [--uninstall] [--quiet]
  --print      管理対象の cron ブロックを表示する
  --install    管理対象の cron ブロックを導入・置換する
  --uninstall  管理対象の cron ブロックを削除する
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --print|--dry-run) MODE="print"; shift ;;
        --install) MODE="install"; shift ;;
        --uninstall) MODE="uninstall"; shift ;;
        --quiet) QUIET=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

cron_block() {
    cat <<EOF
# mas_oc branch policy start
0 * * * * bash $SCRIPT_DIR/scripts/branch_drift_check.sh >> $SCRIPT_DIR/logs/branch_drift_check.log 2>&1
0 */6 * * * bash $SCRIPT_DIR/scripts/auto_merge_short_lived.sh >> $SCRIPT_DIR/logs/auto_merge_short_lived.log 2>&1
# mas_oc branch policy end
EOF
}

strip_managed() {
    sed -e '/# mas_oc branch policy start/,/# mas_oc branch policy end/d'
}

if [[ "$MODE" == "print" ]]; then
    cron_block
    exit 0
fi

existing="$(crontab -l 2>/dev/null || true)"
if [[ "$MODE" == "install" ]]; then
    {
        printf '%s\n' "$existing" | strip_managed
        cron_block
    } | crontab -
    [[ "$QUIET" == "1" ]] || echo "[OK] branch policy cron installed"
else
    printf '%s\n' "$existing" | strip_managed | crontab -
    [[ "$QUIET" == "1" ]] || echo "[OK] branch policy cron removed"
fi
