.PHONY: help setup start stop status build lint test check install-deps clean

help:
	@echo "mas_oc - OpenCode 専用マルチエージェント環境"
	@echo ""
	@echo "  make setup        初回セットアップ"
	@echo "  make start        6名を1画面で起動"
	@echo "  make stop         関連プロセスを一括停止"
	@echo "  make status       稼働状態を表示"
	@echo "  make build        .opencode/agents と AGENTS.md を再生成"
	@echo "  make lint         シェルと Python の静的検査"
	@echo "  make test         スモークテスト"
	@echo "  make check        build の冪等性と生成物を検査"
	@echo "  make install-deps 依存関係を確認"

setup:
	@./mas setup

start:
	@./mas start

stop:
	@./mas stop

status:
	@./mas status

build:
	@bash scripts/build_instructions.sh

lint:
	@echo "bash syntax..."
	@find . -path ./.git -prune -o -path ./.venv -prune -o -path ./.opencode/node_modules -prune -o -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n
	@bash -n mas
	@python3 -m py_compile scripts/*.py
	@if command -v shellcheck >/dev/null 2>&1; then \
		find lib scripts -type f -name '*.sh' -print0 | xargs -0 -n1 shellcheck --exclude=SC1091; \
	else \
		echo "shellcheck not installed; skipped"; \
	fi
	@echo "OK"

test:
	@bash tests/test_smoke.sh
	@bash tests/test_stop.sh
	@python3 tests/test_select_free_model.py
	@bash tests/test_first_setup_free_model.sh
	@bash tests/test_inbox_watcher_nudge.sh
	@bash tests/test_setup_running_guard.sh
	@bash tests/test_switch_model_guard.sh
	@bash tests/test_purge_history.sh

check: build
	@tmp=$$(mktemp -d); cp AGENTS.md $$tmp/AGENTS.md; cp -a .opencode/agents $$tmp/agents; \
		bash scripts/build_instructions.sh >/dev/null; \
		diff -u $$tmp/AGENTS.md AGENTS.md; \
		diff -ru $$tmp/agents .opencode/agents; \
		rm -rf $$tmp; echo "generated files are idempotent"

install-deps:
	@command -v tmux >/dev/null || { echo "tmux required"; exit 1; }
	@command -v opencode >/dev/null || echo "WARN: opencode not found"
	@python3 -c 'import yaml' || { echo "PyYAML required: sudo apt-get install python3-yaml"; exit 1; }
	@echo "OK"

clean:
	@find tests -name '*.tap' -delete 2>/dev/null || true
	@rm -rf .pytest_cache __pycache__ scripts/__pycache__
	@echo "OK"
