# mas_oc 改修完了報告

- 版: 1.0.0
- 完了日: 2026-10-26
- 原本: `mas_orig/`（multi-agent-shogun commit `aff8dc8495da26a2aad582257457655fa953b57e`）
- 成果物: `mas_oc/`
- 状態: 改修完了。ユーザー承認前の commit は行っていない。

## 1. 実装した要件

### (1) OpenCode 専用化
- Claude Code、Codex、Copilot、Kimi、Cursor、Gemini、Antigravity の実行・設定・生成・テストを削除。
- `.claude/`、`.cursor/`、`agents/default/`、`.github/copilot-instructions.md`、非 OpenCode の instructions とテストを削除。
- `lib/cli_adapter.sh` は OpenCode の起動・モデル・variant・権限だけを扱う。
- `scripts/inbox_watcher.sh`、`lib/agent_status.sh`、`scripts/switch_model.sh` を OpenCode 専用に整理。
- Android アプリと bats サブモジュール依存を削除。

### (2) 役割名の変更
| 旧 | 新 | 内部 ID |
|---|---|---|
| 将軍 | 部長 | `director` |
| 家老 | 係長 | `chief` |
| 足軽 | エンジニア | `engineer1` / `engineer2` / `engineer3` |
| 軍師 | 監査役 | `auditor` |

- 設定キー、tmux メタデータ、キューファイル、inbox、報告、生成エージェント、テスト、文書を新名称に統一。
- 旧名称は帰属情報、上流 CHANGELOG、上流プロジェクト名の参照だけに残している。

### (3) 自然な日本語化
- 役割指示、共通プロトコル、タスクフロー、禁止事項、OpenCode 固有ルールを技術日本語で再作成。
- 戦国風の掛け声、一人称、完了報告、起動バナー、ログ表現を削除。
- `AGENTS.md` と `.opencode/agents/*.md` を新しい指示から生成。

### (4) エンジニア3名と `max_bloom: 3`
- 固定編成を6名に変更。
- `engineer3` は `max_bloom: 3`。実効上限は「モデル階層の上限」と「エージェント固有の上限」の小さい方。
- `find_engineer_for_bloom` は L1-L3 で `engineer3` を優先し、L4 以上では `engineer3` を除外。
- `engineer3` 専用の軽量高速タスク指示を追加。
- `./mas switch-model` でモデル、variant、`max_bloom` を変更できる。

### (5) tmux 1画面6名
- 単一セッション `mas`、単一ウィンドウ `team`。
- 既定は3列 x 2行。上段が部長、係長、監査役、下段がエンジニア1-3。
- `--layout 2x3` で縦長画面向けの2列 x 3行も選択可能。
- ペイン境界に表示名、モデル、現在タスクを表示。
- `MAS_TMUX_COLS` / `MAS_TMUX_LINES` で起動サイズを調整可能。
- OpenCode の起動間隔は既定15秒。`--start-interval` または `MAS_START_INTERVAL` で変更可能。短い間隔での連続起動によるクラッシュを避ける。

### (6) 一括停止
- `./mas stop` で以下を停止・削除する。
  - inbox watcher（PID/PGID 管理）
  - `inotifywait` / ポーリング watcher
  - ntfy listener、watcher supervisor、dashboard viewer
  - tmux ペインの子プロセスと `mas` セッション
  - 管理対象 cron ブロック
  - PID ファイル、ロック、idle フラグ、`session.env`
- `./mas stop --verify` で残存を検査。
- 停止対象は `mas_oc` のパスと PID に限定し、他クローンや他の tmux セッションを無差別に停止しない。

### (7) 詳細・クイックマニュアルと謝辞
- `README.md` / `README_ja.md`
- `docs/quickstart.md`（クイックマニュアル）
- `docs/manual.md`（詳細マニュアル）
- `docs/attribution.md`、`NOTICE`
- yohey-w、上流 URL、MIT、Akira-Papa への謝辞を明記。
- 上流 CHANGELOG の履歴を保持し、フォーク初版を追記。

## 2. 主な構成

```text
mas_oc/
  mas
  start.sh
  stop.sh
  first_setup.sh
  lib/
    agent_registry.sh
    cli_adapter.sh
    agent_status.sh
    tmux_layout.sh
    run_state.sh
  scripts/
    build_instructions.sh
    inbox_write.sh
    inbox_watcher.sh
    agent_status.sh
    switch_model.sh
    setup_cron.sh
  config/
    settings.yaml.sample
    opencode-permissions.yaml
    opencode-tui.json
  .opencode/agents/       # 6名分を生成
  instructions/
    AGENTS.md
    roles/
    common/
    opencode_tools.md
  tests/
    test_smoke.sh
    test_stop.sh
  docs/
  README.md
  README_ja.md
  NOTICE
  LICENSE
```

## 3. 検証結果

実行済み:

```bash
make lint
make check
make test
./mas stop --verify
```

結果:

- `make lint`: 成功。`shellcheck` は環境に無いためスキップ。
- `make check`: 成功。生成物は冪等。
- `make test`: 成功（停止テストは `MAS_START_INTERVAL=0` で高速化）。
  - 6名編成、3名のエンジニア、表示名、`engineer3` の `max_bloom: 3`。
  - bloom 1 で `engineer3` を優先、bloom 4 で `engineer3` を除外。
  - `.opencode/agents` が6ファイル。
  - 旧役割名・戦国表現・旧 CLI 機能の参照が無い。
  - tmux 6ペイン、6名のラベル、停止後のセッション削除。
  - モック OpenCode を使った起動・watcher 起動・一括停止。
- `./mas stop --verify`: 成功。残存プロセスなし。
- `mas_orig/` に変更なし。

## 4. 既知の制約

- `config/settings.yaml` の `model` は空欄で生成される。利用者が `opencode models` を確認し、`provider/model` 形式で設定する必要がある。
- 自動テストの OpenCode はモック。実 OpenCode TUI の起動は開発中に確認済みだが、最終自動テストでは認証・課金を避けるためモックを使っている。
- `shellcheck` はこの環境に未導入のため、`make lint` では構文検査と Python コンパイルのみ実行された。
- cron の実インストールはユーザー環境を変更しないため実行していない。`setup_cron.sh --print` と停止時の削除ロジックを実装済み。
- macOS は `setsid` 不在時の Python フォールバックを実装しているが、実機検証はしていない。
- 既定で OpenCode に `--auto` を渡す。手動承認が必要な場合は `./mas start --no-auto` を使う。
- 外部に残る状態は OpenCode の認証情報のみ。`~/.tmux.conf`、`~/.claude`、`/tmp/shogun_*` には書き込まない。

## 5. 起動方法

```bash
cd mas_oc
./mas setup
opencode auth login
opencode models
$EDITOR config/settings.yaml
./mas build
./mas start
```

状態確認と停止:

```bash
./mas status
./mas stop
./mas stop --verify
```

## 6. 謝辞

- Original: multi-agent-shogun by yohey-w
  - https://github.com/yohey-w/multi-agent-shogun
  - MIT License, Copyright (c) 2026 yohey-w
- Based on Claude-Code-Communication by Akira-Papa
  - https://github.com/Akira-Papa/Claude-Code-Communication

mas_oc は非公式フォークであり、原作者との提携・承認・サポートはない。
