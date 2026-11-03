# mas_oc 改修実行計画書

- 版: 1.0
- 作成日: 2026-10-26
- 対象原本: `mas_orig/`（`yohey-w/multi-agent-shogun`、commit `aff8dc8495da26a2aad582257457655fa953b57e`、2026-08-06）
- 成果物: `mas_oc/`
- 状態: **本計画に基づく改修は完了。結果は `REPORT.md` を参照。**
- 原本保持: `mas_orig/` は参照用にそのまま残し、改修は `mas_oc/` のコピー上だけで行う。

---

## 1. 目的とスコープ

`multi-agent-shogun` を OpenCode 専用のマルチエージェント実行基盤へ改修する。戦国風の名称・口調・その他 CLI 向け機能を廃止し、6 名編成・1 画面 tmux・確実な一括停止・日本語の詳細マニュアルを備えたフォークを作る。

### 1.1 必須要件

1. OpenCode 専用化。Claude Code / Codex / Gemini / Copilot / Kimi / Cursor / Antigravity 向けの実行・設定・生成・テストを削除する。
2. 役割名を変更する。
   - 将軍 → 部長
   - 家老 → 係長
   - 足軽 → エンジニア
   - 軍師 → 監査役
3. 戦国風の話し方・演出を廃止し、自然な日本語にする。
4. エンジニアを 3 名にする。エンジニア3 は `max_bloom: 3` とし、軽量・高速タスクを担当させる。
5. 部長・係長・エンジニア3名・監査役の合計 6 名を tmux の 1 ウィンドウ（1 画面）に収める。
6. 終了時に watcher、ntfy、supervisor、dashboard、cron、tmux を一括停止し、残存プロセスを残さない。
7. 詳細な取扱説明書とクイックマニュアルを作成し、原作者 yohey-w への謝辞とオリジナルへのリンクを明記する。

### 1.2 非目標

- 新機能の追加（既存の bloom routing、ntfy、dashboard、branch policy 等は原則維持）。
- 上流への逆マージや上流互換性の維持。
- グローバル環境（`~/.claude/`、`~/.tmux.conf`、`/tmp/shogun_*` 等）への新規依存の追加。
- ユーザーの明示承認なしの git commit。

---

## 2. 現状分析サマリ（`mas_orig`）

### 2.1 構成

- 起動: `shutsujin_departure.sh`（`setup.sh` はラッパー）。初回: `first_setup.sh`。
- 役割定義: `instructions/roles/*.md`、`instructions/*.md`、`.opencode/agents/*.md`。
- 中核: `lib/cli_adapter.sh`、`lib/agent_registry.sh`、`lib/agent_status.sh`。
- 実行時: `scripts/inbox_watcher.sh`、`scripts/switch_cli.sh`、`scripts/ntfy_listener.sh`、`scripts/watcher_supervisor.sh`。
- tmux: `shogun` セッション + `multiagent:agents` の 3x3・9 ペイン。現行 10 名（将軍1、家老1、足軽7、軍師1）。将軍は別セッション。
- 文書: `README.md`（約2,000行）、`README_ja.md`（約1,950行）、`docs/`、`CONTRIBUTING.md`、`SECURITY.md`、`CHANGELOG.md`。
- ライセンス: MIT、`Copyright (c) 2026 yohey-w`。README に Akira-Papa の `Claude-Code-Communication` への言及あり。
- 不要／大容量: `android/`（約50MB、APK 32MB）、`.claude/`、`.cursor/`、`agents/default/`、`.github/copilot-instructions.md`。

### 2.2 改修上の重要事実

- `lib/cli_adapter.sh` に複数 CLI の分岐が集中している。`CLI_ADAPTER_ALLOWED_CLIS`、`get_cli_type`、`build_cli_command`、`get_agent_effort`、`can_model_switch` 等。
- `scripts/inbox_watcher.sh` に CLI 別の送信・リセット・busy 判定・stop hook 連携が集中している。
- `scripts/build_instructions.sh` は 7 CLI 分の instructions と `AGENTS.md` を生成している。OpenCode 用は `.opencode/agents/*.md`。
- エージェント数は `lib/agent_registry.sh`、`shutsujin_departure.sh`、`first_setup.sh`、`scripts/agent_status.sh`、`scripts/ratelimit_check.sh`、`scripts/build_instructions.sh`、`scripts/slim_yaml.py` 等に 7 前提で分散している。
- tmux は `shutsujin_departure.sh:602-619` で 3x3 を固定生成している。6 名でも 9 ペインになり、空きペインが出る。
- watcher / ntfy / supervisor / dashboard は `nohup` + `disown` 等で常駐し、停止専用コマンドが無い。次回起動時の `pkill -f` でしか掃除されない。
- `max_bloom` は現状「モデル」の属性（`capability_tiers.<model>.max_bloom`）であり、「エージェント」の属性ではない。エージェント単位の上限を追加する必要がある。
- 生成物（`.opencode/agents/*.md`、`instructions/generated/*.md`、`AGENTS.md`）は手編集禁止。必ず生成スクリプトとソースを直す。
- `.opencode/agents/*.md` は生成されても削除はされない。役割削減時に旧ファイルを明示削除する必要がある。
- `AGENTS.md` は OpenCode が読むが、現状は Claude/Codex 由来の生成物。OpenCode 正本として再定義する。
- テストは 493 件。役割名・人数・ペイン番号・生成ファイル名に強く依存する。`make test-int` は存在しない `tests/integration/` を参照して壊れている。

---

## 3. 目標仕様

### 3.1 エージェント編成（6 名）

| 表示名 | 内部 ID（推奨） | 役割 | 人数 | 主な担当 |
|---|---|---|---|---|
| 部長 | `director` | 統括・人間との窓口 | 1 | 方針決定、最終承認、エスカレーション対応 |
| 係長 | `chief` | 進行管理 | 1 | 分解、割当、進捗、監査役への品質依頼 |
| エンジニア1 | `engineer1` | 実装 | 1 | 通常〜高難度の実装 |
| エンジニア2 | `engineer2` | 実装 | 1 | 通常〜高難度の実装 |
| エンジニア3 | `engineer3` | 軽量高速実装 | 1 | bloom 1〜3 の定型・軽量タスク。`max_bloom: 3` |
| 監査役 | `auditor` | 独立検証 | 1 | 品質監査、原因分析、設計レビュー、報告 |

- 内部 ID は英字にして保守性を確保し、画面・文書・ログでは日本語表示名を必ず使う。
- `shogun` / `karo` / `ashigaru` / `gunshi` はソース・設定・ファイル名・tmux 名・環境変数から排除する。上流の謝辞・CHANGELOG の歴史的記述のみ許可リストで例外とする。
- 内部 ID を変更したくない場合は表示名だけの変更も可能だが、設定キーと画面表示が乖離するため推奨しない。実行時に最終確認する。

### 3.2 ファイル・識別子の改名対応

| 旧 | 新 |
|---|---|
| `instructions/roles/shogun_role.md` | `instructions/roles/director_role.md` |
| `instructions/roles/karo_role.md` | `instructions/roles/chief_role.md` |
| `instructions/roles/ashigaru_role.md` | `instructions/roles/engineer_role.md` |
| `instructions/roles/gunshi_role.md` | `instructions/roles/auditor_role.md` |
| `instructions/shogun.md` 等 | `instructions/director.md` 等 |
| `.opencode/agents/shogun.md` 等 | `.opencode/agents/director.md` 等 |
| `ashigaru1..7` | `engineer1..3`（4〜7 は削除） |
| `queue/tasks/ashigaruN.yaml` | `queue/tasks/engineerN.yaml` |
| `queue/reports/ashigaruN_report.yaml` | `queue/reports/engineerN_report.yaml` |
| `queue/inbox/ashigaruN.yaml` | `queue/inbox/engineerN.yaml` |
| tmux `shogun` / `multiagent` | 単一セッション `mas`、ウィンドウ `team` |
| `SHOGUN_*` 環境変数 | `MAS_*` |
| `/tmp/shogun_*` | `mas_oc/run/` 配下 |
| `shutsujin_departure.sh` | `start.sh`（`mas start` から呼ぶ） |
| `setup.sh`（起動ラッパー） | 廃止し `mas` ディスパッチャに統合 |
| `scripts/switch_cli.sh` | `scripts/switch_model.sh`（OpenCode 内のモデル切替専用） |

### 3.3 コマンド体系

```text
./mas setup            初回セットアップ（OpenCode 前提）
./mas start            6 名を 1 画面で起動
./mas stop             全関連プロセスを一括停止
./mas status           稼働状態・残存プロセス検査
./mas build            instructions / agents を再生成
./mas switch-model     モデル切替（OpenCode のみ）
./mas dashboard        dashboard 起動（任意）
```

- `start.sh` / `stop.sh` は内部実装として残してよいが、利用者向けの入口は `mas` に統一する。
- `make start` / `make stop` / `make status` / `make test` も用意する。

### 3.4 tmux レイアウト（1 セッション・1 ウィンドウ・6 ペイン）

```text
+----------------------+----------------------+----------------------+
| 部長                 | 係長                 | 監査役               |
| director             | chief                | auditor              |
+----------------------+----------------------+----------------------+
| エンジニア1          | エンジニア2          | エンジニア3          |
| engineer1            | engineer2            | engineer3 (bloom<=3) |
+----------------------+----------------------+----------------------+
```

- セッション `mas`、ウィンドウ `team`、6 ペインの 3 列 x 2 行を既定とする。
- `tmux select-layout tiled` で 6 ペインを 3x2 にし、作成順ではなく `#{pane_top}` / `#{pane_left}` で役割を割り当てる。
- `pane-border-status top` で「日本語表示名 + モデル + 現在タスク」を表示する。
- ステータスバーは最小化し、1 画面に収める。`window-size largest` と `aggressive-resize` をセッション単位で設定する。
- 端末サイズ検査を起動時に行う。推奨 `240x50` 以上、最低 `210x44`。不足時は警告し、`--layout 2x3`（縦長画面向け）を案内する。
- 旧 `shogun` セッションと `multiagent` セッションは廃止する。全ペインを `mas:team` に統合する。
- `pane_is_active` 等の「将軍は別セッション」前提を `director` が同一ウィンドウにいる前提へ修正する。

### 3.5 `config/settings.yaml` の目標例

```yaml
language: ja
shell: bash

cli:
  default: opencode
  agents:
    director:
      type: opencode
      model: "<deep-model>"
    chief:
      type: opencode
      model: "<standard-model>"
    engineer1:
      type: opencode
      model: "<standard-model>"
    engineer2:
      type: opencode
      model: "<standard-model>"
    engineer3:
      type: opencode
      model: "<light-model>"
      max_bloom: 3
    auditor:
      type: opencode
      model: "<deep-model>"

capability_tiers:
  "<light-model>":
    max_bloom: 3
  "<standard-model>":
    max_bloom: 5
  "<deep-model>":
    max_bloom: 6

bloom_routing:
  enabled: true
```

- `<light-model>` / `<standard-model>` / `<deep-model>` はセットアップ時に利用可能な OpenCode プロバイダから選択する。固定のモデル名をハードコードしない。
- エージェント単位 `max_bloom` は本フォークで追加する。実効上限は `min(モデル階層の max_bloom, エージェントの max_bloom)` とする。
- エンジニア3 は bloom 1〜3 のタスクを優先して受ける。bloom 4 以上はエンジニア3 に割り当てず、エンジニア1/2、キュー、または係長判断でエスカレーションする。
- 既存の `capability_tiers` と `bloom_routing` の互換性を維持しつつ、`find_agent_for_model` の「空きエージェントへの無条件フォールバック」を廃止し、上限超過を防ぐ。

### 3.6 実行時ディレクトリ（親フォルダを使わない）

```text
mas_oc/
  run/                  PID/PGID、起動マーカー、ロック、idle フラグ
  queue/                tasks / reports / inbox
  logs/                 watcher / ntfy / dashboard / start / stop
  status/               実行状態
  .runtime/             任意の隔離実行用（XDG_* をここへ向ける場合）
```

- 旧 `~/.local/share/multi-agent-shogun/inbox`、`/tmp/shogun_idle_*`、`/tmp/shogun_watcher_start_*` は使わない。
- `~/.tmux.conf` は変更しない。tmux 設定はセッション単位で行う。
- `~/.claude/skills` へのコピーは廃止。プロジェクト内の `.opencode/` または `skills/` を正本とする。OpenCode のプロジェクトローカル skills/commands の探索仕様は Phase 0 で実機確認する。
- OpenCode の認証情報のみ、OpenCode 標準の保存先を使う。これは例外として文書化する。`--isolate-home` を用意し、`XDG_CONFIG_HOME` / `XDG_DATA_HOME` / `XDG_STATE_HOME` / `XDG_CACHE_HOME` を `mas_oc/.runtime/` に向けられるようにする。

---

## 4. 実行原則

1. **原本不変**: `mas_orig/` は編集しない。`mas_oc/` のみ変更する。
2. **小さなステップ**: 1 ステップ = 1 目的。複数領域を同時に変えない。各ステップで差分と検証結果を確認する。
3. **サブエージェント優先**: 調査・実装・検証をサブエージェントへ分割し、メインは計画判断・差分レビュー・最終検証に集中する。詳細は第 6 章。
4. **生成物は生成元から**: `.opencode/agents/*.md`、`instructions/generated/*.md`、`AGENTS.md` は必ず `scripts/build_instructions.sh` 経由で再生成する。
5. **親フォルダ禁止**: 新規の書き込み先は `mas_oc/` 内。`$HOME`・`/tmp`・`~/.config` への書き込みは禁止（OpenCode 認証のみ例外）。
6. **削除より隔離**: 判断に迷う非 OpenCode 資産は最初から削除せず、`mas_oc/.archive/` へ退避してから削除可否を決める。ただし最終成果物には残さない。
7. **謝辞保持**: `LICENSE` の MIT 全文と `Copyright (c) 2026 yohey-w`、Akira-Papa への言及、上流 CHANGELOG の履歴を保持する。削除した上流機能の説明は「フォークでの変更点」として残す。
8. **コミット禁止**: ユーザーの明示許可があるまで commit しない。チェックポイントは `git diff` と `mas_oc/.work/patches/` に保存する（`.work/` は git 管理外）。

---

## 5. 作業フェーズとステップ

各フェーズの最後にフェーズゲートを置き、検証結果を報告してから次へ進む。1 ステップごとに実装サブエージェントを分ける。

### Phase 0: 準備・基準値の固定

**Step 0.1 作業コピー作成**
- `mas_orig/` から `mas_oc/` へ `.git` を除いてコピーする。
- `mas_oc/` で `git init` し、初期ツリーを `git add -A` する（commit はしない）。これにより以降の差分を `git diff` で確認できる。
- `.work/`、`.archive/`、`run/`、`logs/`、`status/`、`.runtime/` を `.gitignore` に追加する。
- 検証: `mas_orig` のファイル数・ハッシュが変わっていないこと。`mas_oc` で `git status` が想定どおりであること。

**Step 0.2 ベースライン記録**
- `make lint`、`make test`、`bats tests/e2e/` の実行可否と失敗一覧を `mas_oc/.work/baseline.md` に記録する。
- 依存が無い場合は `make install-deps` の必要性を記録する。失敗を改修起因と誤認しないための基準にする。
- 検証: ベースラインの失敗が「既知・上流由来」か「環境不足」かに分類されていること。

**Step 0.3 OpenCode 実機仕様の確認**
- `opencode --version`、`opencode --help`、プロジェクト内 `.opencode/agents` の認識、`/new`、モデル指定、project-local skills/commands の探索を確認する。
- 認証情報の保存先と、`XDG_*` 隔離の可否を確認する。
- 結果を `mas_oc/.work/opencode-notes.md` に記録し、計画の前提と異なる点を反映する。
- 検証: 起動コマンド・終了方法・リセット方法・権限設定の実機根拠が揃っていること。

**Step 0.4 変更対象の完全インベントリ**
- `shogun|karo|ashigaru|gunshi|将軍|家老|足軽|軍師|戦国|ござる|拙者` の全出現をファイル別に記録する。
- `claude|codex|gemini|copilot|kimi|cursor|antigravity` の全出現をファイル別に記録する。
- 7 名前提、9 ペイン前提、`/tmp`・`$HOME` 依存の箇所を記録する。
- 検証: 後続フェーズで「見落とし」を検査できる許可リスト（謝辞・CHANGELOG 用）を作る。

### Phase 1: OpenCode 専用化

**Step 1.1 CLI アダプタの単一化**
- `lib/cli_adapter.sh` を OpenCode 専用に整理する。
- 許可 CLI を `opencode` のみにし、Gemini 別名、Cursor/Claude/Codex/Copilot/Kimi 分岐、`get_agent_effort`、Codex 起動プロンプト、CLI 切替可否判定を削除する。
- OpenCode のモデル正規化、`--model`、`--agent`、`OPENCODE_AGENT_ID`、`OPENCODE_TUI_CONFIG`、`env`、`variant` は維持する。
- `get_cli_type` は常に `opencode` を返すか、設定検証だけ残して単純化する。
- 検証: `tests/unit/test_cli_adapter.bats` の OpenCode ケースが通り、他 CLI 参照がコードから消えていること。

**Step 1.2 状態判定・watcher・モデル切替の単一化**
- `lib/agent_status.sh`: OpenCode の busy/idle 判定だけ残す。Cursor/Claude/Codex のステータスバー・スピナー判定を削除。
- `scripts/inbox_watcher.sh`: CLI 引数を `opencode` 固定に近づけ、Claude idle flag、Codex クールダウン、stop hook、Escape エスカレーション、他 CLI の送信分岐を削除。OpenCode の `/new` リセットは維持。
- `scripts/switch_cli.sh` を `scripts/switch_model.sh` に改名。`/exit` の CLI 別分岐とモデル→CLI 推論を削除し、OpenCode 内のモデル切替と `-runtime` frontmatter 同期だけ残す。
- 検証: watcher の単体テスト、モデル切替テストが OpenCode 前提で通る。`rg 'codex|claude|cursor|copilot|kimi|antigravity|gemini'` がコードにヒットしない。

**Step 1.3 生成・セットアップの単一化**
- `scripts/build_instructions.sh`: OpenCode 用 `.opencode/agents/*.md`、`AGENTS.md`、permissions、runtime frontmatter のみ生成。Claude/Codex/Copilot/Kimi/Cursor/Antigravity の生成関数と 7 CLI マトリクスを削除。
- `first_setup.sh`: Claude Code の検出・インストールを OpenCode の検出・導入案内に置換。`cli.default: opencode` と 6 名分の `cli.agents` を生成。Memory MCP の Claude 依存処理を削除。
- `install.bat`: OpenCode 前提の案内に変更（WSL2/Ubuntu の導入補助は維持）。
- `Makefile` / `.github/workflows/test.yml`: Claude/Codex フィルタ、integration の空参照、非 OpenCode の build 差分検査を整理。
- `.gitignore`: 非 OpenCode 用の許可リストを整理し、`config/settings.yaml.sample` を追跡可能にする。
- 検証: クリーンな一時ディレクトリで `./mas setup --dry-run` 相当が OpenCode 設定を生成できること。`make build` が冪等であること。

**Step 1.4 起動スクリプトの単一化**
- `shutsujin_departure.sh` から Claude のハードコードモデル fallback、`_default_cli` の `claude` 前提バグ、Codex MCP health、他 CLI の ready pattern を削除。
- OpenCode の起動待ち・起動遅延・`@agent_cli` メタデータを固定化する。
- `setup.sh` ラッパーを廃止し、`mas start` に統合する。
- 検証: モック `opencode` で起動シーケンスが完走し、CLI 選択が常に OpenCode になること。

**Step 1.5 非 OpenCode 資産の削除**
- 削除候補: `.claude/`、`.cursor/`、`agents/default/`、`.github/copilot-instructions.md`、`instructions/cli_specific/` の非 OpenCode ファイル、`instructions/generated/` の非 OpenCode ファイル、`scripts/session_start_hook.sh`、`scripts/stop_hook_inbox.sh`、`scripts/mcp_health_check.sh`、非 OpenCode の E2E/unit ケース、`docs/vps_pr118_verification_plan.md`。
- `android/` は OpenCode CLI と無関係で旧ブランドを大量に含むため、`mas_oc` からは削除する（`mas_orig` に原本が残る）。削除前に `.archive/` へ退避し、最終的に成果物へ含めない。
- `scripts/ratelimit_check.sh` は OpenCode の情報だけ残す。
- 検証: 削除対象が `git status` で意図どおり。参照切れが無いこと。

**Step 1.6 OpenCode 専用テストへの更新**
- `tests/unit/test_cli_adapter.bats`、`test_switch_cli.bats`、`test_build_system.bats`、`test_dynamic_model_routing.bats` から非 OpenCode ケースを削除。
- モック CLI を `opencode` のみに整理。
- `make test` の対象を現実的なテスト群に修正し、`make test-int` の壊れた参照を削除または実装する。
- 検証: OpenCode 専用のテストスイートが単独で動くこと。

**フェーズゲート 1**
- コード・設定・生成物・テストから非 OpenCode バックエンドが消えている。
- `make build` が冪等、`make test` がベースライン同等以上。
- 起動・停止の基本シーケンスがモックで動く。

### Phase 2: 役割名の全面変更

**Step 2.1 中央レジストリの変更**
- `lib/agent_registry.sh` の既定配列を `director chief engineer1 engineer2 engineer3 auditor` に変更。
- 表示名の対応表を 1 箇所（例: `lib/agent_registry.sh` または `config/agents.yaml`）に定義し、tmux ラベル・ログ・status がそこを参照するようにする。
- 検証: `get_agent_ids` が 6 名を返し、表示名が日本語で解決されること。

**Step 2.2 設定・権限・エージェント定義の改名**
- `config/opencode-permissions.yaml` のロールキーと glob を `director/chief/engineer*/auditor` に変更。
- `instructions/roles/*.md`、`instructions/*.md`、`.opencode/agents/*.md` を改名・再生成。
- `AGENTS.md` を OpenCode 正本として再生成。
- 検証: `.opencode/agents/` に 6 ファイルだけが存在し、旧名ファイルが無いこと。

**Step 2.3 キュー・レポート・inbox・watcher の改名**
- `queue/tasks/engineerN.yaml`、`queue/reports/engineerN_report.yaml`、`queue/inbox/engineerN.yaml` に統一。
- watcher の引数、ログ名、lock 名、idle フラグ名を新 ID に変更。
- 検証: watcher が 6 名分だけ起動し、旧 `ashigaru` 名のファイルを参照しないこと。

**Step 2.4 セッション・環境変数・一時パスの改名**
- tmux セッション名を `mas`、ウィンドウ名を `team` に統一（Phase 5 でレイアウトと同時に実施）。
- `SHOGUN_*` 環境変数を `MAS_*` に統一。テスト用の上書き変数も同様。
- `/tmp/shogun_idle_*`、`/tmp/shogun_watcher_start_*` を `run/` 配下へ移動。
- `scripts/agent_status.sh`、`ratelimit_check.sh`、`slim_yaml.py`、`switch_model.sh`、skills の旧名を更新。
- 検証: `rg 'shogun|karo|ashigaru|gunshi'` が謝辞・CHANGELOG の許可リスト以外にヒットしないこと。

**Step 2.5 文書・スキル・テストの旧名更新**
- README、docs、skills、CHANGELOG の用語を新名称に統一。ただし上流の歴史的記述と謝辞は保持。
- テストの役割名・ファイル名・固定ペイン番号を更新。
- 検証: 用語統一チェック（旧名の残存数を 0 に近づける）。テストが新名称で通る。

**Step 2.6 旧名の完全監査**
- `mas_oc` 全体を検索し、許可リスト（LICENSE、NOTICE、上流 CHANGELOG、謝辞、`mas_orig` への参照）以外の旧名を排除。
- 検証: 監査スクリプト `scripts/check_naming.sh` を作り、CI からも実行する。

**フェーズゲート 2**
- 画面・ログ・設定・ファイル名・テストがすべて新名称。
- 旧名は謝辞と上流履歴のみ。
- 6 名のレジストリと生成物が一致。

### Phase 3: 話し方・トーンの自然化

**Step 3.1 役割指示の書き換え**
- `director_role.md` / `chief_role.md` / `engineer_role.md` / `auditor_role.md` の口調指定を削除し、「自然で簡潔な日本語。技術文書・コード・YAML では通常の文体」と明記。
- 「はっ！」「ござる」「拙者」「御意」「戦」「出陣」等の例文・演出を削除。
- 進捗報告・完了報告・エスカレーションの例文をビジネス日本語に置換。
- 検証: 役割指示に戦国風の語彙が無いこと。

**Step 3.2 メタデータ・共通指示の書き換え**
- `speech_style` を `natural_ja` 等に変更。`CLAUDE.md` 由来の persona 記述を OpenCode 用 `AGENTS.md` に整理。
- 各ロールの「コードや文書には口調を混ぜない」制約は維持し、より明確化。
- 検証: `AGENTS.md` と生成 agents の内容が一致し、再生成で差分が出ないこと。

**Step 3.3 起動バナー・ログ・ヘルプ・セットアップメッセージの書き換え**
- `start.sh` の「出陣」「七名」「実働×7」「只今、戦闘中」等を通常の日本語に変更。
- `first_setup.sh` の完了メッセージ、ヘルプ、エラーメッセージを自然な日本語に変更。
- 検証: 起動ログに戦国風表現が無いこと。

**Step 3.4 旧 stop hook 依存の除去確認**
- Claude 専用 stop hook は Phase 1 で削除済み。`「任務完了|完了でござる」` 検出に依存する処理が残っていないことを確認。
- 検証: 完了検出が自然文でも成立する（または完了検出を廃止して状態ファイルベースにする）。

**Step 3.5 ドキュメントのトーン統一**
- README / manual / quickstart の比喩・戦国用語を排除。必要な歴史的説明は謝辞・CHANGELOG のみ。
- 検証: 用語チェックと読みやすさレビュー。

**フェーズゲート 3**
- ソース・生成物・ログ・文書から戦国風の口調が消えている。
- 完了報告の例が自然な日本語になっている。

### Phase 4: エンジニア 3 名化と `max_bloom: 3`

**Step 4.1 人数の 3 名化（コード）**
- `lib/agent_registry.sh` の既定を 3 名に変更。
- `lib/cli_adapter.sh` の `get_ashigaru_ids` 相当を `get_engineer_ids` に改名し、fallback を `engineer1..3` に変更。
- `start.sh` の `_ASHIGARU_COUNT` 相当を `_ENGINEER_COUNT=3` に変更。
- `first_setup.sh`、`scripts/agent_status.sh`、`ratelimit_check.sh`、`slim_yaml.py`、`switch_model.sh`、`build_instructions.sh` の 7 前提を 3 に変更。
- 検証: レジストリ、起動、status、生成物がすべて 3 名。

**Step 4.2 旧 4〜7 名の残骸掃除**
- `mas setup` / `mas start --clean` で旧 `engineer4..7`（および旧 `ashigaru4..7`）の queue、reports、inbox、logs、watcher、`.opencode/agents` を削除する。
- 起動時に旧 lock / idle flag / PID を掃除する。
- 検証: 何度 setup しても 3 名分しか残らない。旧ファイルが残らない。

**Step 4.3 設定生成とモデル階層**
- `first_setup.sh` が 6 名分の `cli.agents`、`capability_tiers`、`bloom_routing` を生成。
- エンジニア3 に `max_bloom: 3` を設定。軽量モデルを選択できる対話または引数を用意。
- 設定サンプル `config/settings.yaml.sample` を追加。
- 検証: 生成された設定で起動でき、6 名のモデルが解決される。

**Step 4.4 エージェント単位 `max_bloom` の実装**
- `lib/cli_adapter.sh` に `get_agent_max_bloom(agent_id)` を追加。`cli.agents.<id>.max_bloom` を読み、無ければモデル階層の値を使う。
- `get_capability_tier` / `get_recommended_model` / `needs_model_switch` / `find_agent_for_model` を実効上限ベースに修正。
- エンジニア3 は bloom 4 以上で候補から除外。候補が無い場合の「上位モデルを無条件で返す」フォールバックを廃止し、キュー投入または係長へのエスカレーションにする。
- `find_agent_for_model` の `ashigaru` 限定検索を `engineer` に一般化。
- 検証: bloom 1〜3 はエンジニア3 が優先候補、bloom 4 以上は絶対にエンジニア3 に割り当たらないテスト。

**Step 4.5 エンジニア3 の軽量タスク用プロファイル**
- `instructions/roles/engineer_fast_role.md` を追加、または `engineer3` 生成時に軽量タスク向けセクションを追加。
- 対象例: 単純修正、文言変更、小さなテスト追加、定型調査。高難度実装は係長へ返す。
- 品質ルール（テスト、差分確認、報告）は他エンジニアと同じ水準を維持。
- 検証: `.opencode/agents/engineer3.md` にだけ軽量プロファイルが反映され、他は共通であること。

**Step 4.6 画面・文書・テストの 3 名化**
- tmux ラベル、status、ヘルプ、README、manual、skills の人数を 3 に統一。
- 7 名前提のテスト（`test_agent_registry.bats`、`test_dynamic_model_routing.bats`、`test_switch_cli.bats`、E2E bloom routing 等）を 6 名編成に更新。
- 検証: 6 名以外を前提とするテストが無いこと。

**フェーズゲート 4**
- 起動すると必ず 6 名（エンジニア 3 名）。
- エンジニア3 の実効 `max_bloom` が 3。
- bloom 4 以上がエンジニア3 に流れない。
- 旧 7 名の残骸が無い。

### Phase 5: tmux 1 画面・6 ペイン化

**Step 5.1 単一セッション・単一ウィンドウ化**
- `start.sh` から `shogun` セッションと `multiagent` セッションの生成を削除。
- `mas` セッション、`team` ウィンドウを 1 つ作り、6 ペインを生成する。
- `select-layout tiled` で 3x2 に固定。ペインは作成順ではなく座標で役割に割り当てる。
- 検証: `tmux list-panes -t mas:team` が 6 件。`#{pane_top}` / `#{pane_left}` の期待値と役割が一致。

**Step 5.2 表示の最適化**
- `pane-border-status top`、`pane-border-format` に日本語表示名・モデル・タスクを設定。
- tmux ステータスバーを最小化し、1 画面に収める。
- `window-size largest`、`aggressive-resize on` をセッション単位で設定。`~/.tmux.conf` は変更しない。
- 端末サイズ検査と `--layout 2x3` の代替を実装。
- 検証: 240x50 の端末で 6 ペインが欠けない。狭い場合は明確な警告が出る。

**Step 5.3 ペイン参照の一元化**
- `scripts/switch_model.sh`、`scripts/inbox_watcher.sh`、`scripts/agent_status.sh`、dashboard、テストの固定ペイン番号を廃止し、`@agent_id` からペインを解決する共通関数（例: `lib/tmux_layout.sh`）に統一。
- `pane_is_active` の将軍別セッション前提を director 同一ウィンドウ前提に修正。
- 検証: ペイン順が変わってもモデル切替・watcher・status が壊れない。

**Step 5.4 6 ペインの実機確認**
- モック OpenCode で起動し、6 ペインすべてにプロンプトが出ること、入力・出力・リサイズができることを確認。
- スクリーンショットを取得し、`images/` の旧 9 ペイン画像を差し替える。
- 検証: 1 画面に 6 名が収まり、旧 3x3 / 9 ペインの記述が無いこと。

**フェーズゲート 5**
- `mas start` で 1 セッション・1 ウィンドウ・6 ペイン。
- 役割ラベルが正しい。
- 端末サイズ不足時に安全に案内できる。

### Phase 6: 一括停止とプロセス管理

**Step 6.1 実行時 PID/PGID 管理**
- `run/` に `mas.pid`、`session.env`、`inbox_watcher.<agent>.pid`、`inbox_watcher.<agent>.pgid`、`ntfy_listener.pid`、`watcher_supervisor.pid`、`dashboard.pid` を保存。
- 常駐プロセスは `setsid` で起動し、プロセスグループ単位で管理。PID 再利用対策として `/proc/<pid>/cmdline` と起動時刻を検証。
- 検証: 起動後に全 PID ファイルが存在し、内容が実プロセスと一致。

**Step 6.2 `stop.sh` / `mas stop` の実装**
- 停止順: cron の管理ブロック除去 → supervisor → watcher と `inotifywait`/`fswatch` → ntfy と `curl` → dashboard → エージェント CLI（猶予付き）→ tmux セッション → 旧 grouped session → lock / idle flag の掃除。
- `TERM` → 待機 → `KILL` の順。PID/PGID が無い場合はリポジトリパスで限定した `pgrep` にフォールバックし、他クローンを殺さない。
- 何度実行しても安全（冪等）。停止後に `mas status --verify` で残存 0 を確認。
- 検証: モックの常駐プロセスを使い、停止後に `pgrep` が 0、tmux セッションが 0、ポート 8787 が閉じていること。

**Step 6.3 cron / dashboard / lock の後始末**
- `setup_cron.sh` に `--uninstall` を追加し、管理マーカー間だけを削除。
- dashboard の PID を管理し、`mas stop` で停止。
- `run/` の lock、idle flag、一時ファイルを削除。
- 検証: 停止後に `crontab -l` の管理ブロックが無い。`lsof -i:8787` が空。

**Step 6.4 起動失敗時のクリーンアップ**
- `start.sh` に `trap` を追加し、途中失敗時に生成済み tmux セッション・watcher・PID ファイルを巻き戻す。
- 起動ロックを `run/` に置き、二重起動を防止。
- 検証: 故意に起動を失敗させても残存プロセスが無い。

**Step 6.5 停止の自動テスト**
- モックプロセスを起動する統合テストを追加。`mas start` → `mas stop` → 残存検査。
- 他クローンを巻き込まないことを、別ディレクトリのダミープロセスで確認。
- 検証: テストが安定して通る。

**フェーズゲート 6**
- `mas stop` 1 回で全関連プロセスが消える。
- 親フォルダに一時ファイルが残らない。
- 二重起動・二重停止で壊れない。

### Phase 7: ドキュメント・謝辞

**Step 7.1 文書構成の確定**
- `README.md`: 短い入口。概要、必要環境、5 分クイックスタート、`mas` コマンド一覧、詳細マニュアルへのリンク。
- `README_ja.md`: 日本語の入口。README.md と同等。
- `docs/quickstart.md`: クイックマニュアル。OpenCode の導入、認証、モデル設定、`mas setup`、`mas start`、`mas stop`、最初のタスク、よくある失敗。
- `docs/manual.md`: 詳細取扱説明書。概念、6 名の役割、bloom と `max_bloom`、設定リファレンス、tmux レイアウト、起動・停止・状態確認、モデル切替、キュー、メモリ、ntfy、dashboard、branch policy、トラブルシューティング、セキュリティ、FAQ。
- `docs/attribution.md` と `NOTICE`: 原作者・上流・ベースプロジェクト・ライセンス・フォーク変更点。
- `docs/index.md`: 文書一覧。
- 検証: 目次とリンクが一致し、初心者が quickstart だけで起動・停止できる。

**Step 7.2 謝辞・ライセンスの明記**
- `README.md` / `README_ja.md` / `docs/manual.md` / `NOTICE` に以下を明記する。
  - Original: `multi-agent-shogun` by yohey-w
  - URL: https://github.com/yohey-w/multi-agent-shogun
  - License: MIT、`Copyright (c) 2026 yohey-w`
  - Base: `Claude-Code-Communication` by Akira-Papa
  - Fork: `mas_oc` の変更点
- `LICENSE` は改変せず保持。上流 CHANGELOG の履歴も保持。
- `.github/FUNDING.yml` と上流スポンサー案内はフォークの資金募集と誤認されるため削除または明確に「上流のもの」と注記。
- 検証: 謝辞・URL・ライセンスが 4 箇所以上で一致。

**Step 7.3 旧文書・旧画像の整理**
- `docs/vps_pr118_verification_plan.md`（VPS IP/SSH を含む）を削除。
- Android 文書、非 OpenCode CLI 文書、旧ブランドのスクリーンショットを削除または差し替え。
- 6 ペインの新しいスクリーンショットを `images/` に追加。
- 検証: 旧名称・旧人数・旧レイアウトの画像が残っていない。

**Step 7.4 `AGENTS.md` / 開発者向け文書**
- `AGENTS.md` を OpenCode 用の正本にし、リポジトリ構成、ビルド、テスト、生成物の扱い、禁止事項を記載。
- `CONTRIBUTING.md` を現実の構成に合わせて修正（存在しない `tests/integration/` を削除）。
- `SECURITY.md` をフォークの連絡先・OpenCode 前提に更新。
- `CHANGELOG.md` にフォーク初版を追加し、上流履歴はそのまま残す。
- 検証: 開発者が `make build` / `make test` / `mas start` の順で再現できる。

**Step 7.5 用語・リンク・整合性チェック**
- 旧名、旧人数、9 ペイン、戦国口調、他 CLI の残存を検査。
- 相対リンク切れ、画像パス、コマンド名の不一致を検査。
- 検証: `scripts/check_docs.sh` を作り CI で実行。

**フェーズゲート 7**
- 詳細マニュアルとクイックマニュアルが存在し、内容が実装と一致。
- 原作者への謝辞とオリジナルリンクが明記されている。
- 旧ブランドの文書・画像が成果物に残っていない。

### Phase 8: 総合検証・受け入れ

**Step 8.1 静的検査**
- `bash -n` 全シェル、`shellcheck`、`python -m py_compile`、YAML パース、`make lint`。
- 旧名・非 OpenCode 参照の監査。
- 検証: 重大な警告 0。

**Step 8.2 自動テスト**
- `make build` を 2 回実行して差分 0。
- `make test`、`bats tests/e2e/`、新規の停止テスト・bloom テスト・レイアウトテスト。
- `make check` で生成物の同期を確認。
- 検証: ベースラインで既知だった失敗以外は 0。既知失敗は文書化。

**Step 8.3 手動スモークテスト**
- 隔離した `HOME` / `XDG_*` で `mas setup` → `mas start`（モック OpenCode）→ `mas status` → `mas stop`。
- 6 ペイン、ラベル、モデル、watcher、inbox、bloom 3 の挙動を確認。
- 停止後に `pgrep`、`tmux ls`、`crontab`、`ss -ltnp`、`find run` を検査。
- 検証: 残存プロセス 0、親フォルダへの新規書き込み 0（OpenCode 認証を除く）。

**Step 8.4 受け入れ基準の確認**
- 第 8 章のチェックリストをすべて満たす。
- 未達がある場合は Phase に戻り、小さなステップで修正する。

**Step 8.5 成果物の整理**
- `.work/`、`.archive/`、`run/`、`logs/`、`status/`、`.runtime/` を成果物から除外（`.gitignore` 済み）。
- `mas_orig/` は参照用に残す。`mas_oc/` に最終成果物を揃える。
- 変更点一覧、既知の制約、テスト結果を `mas_oc/REPORT.md` にまとめる。
- ユーザー承認後にのみ commit する。

---

## 6. サブエージェント活用方針

### 6.1 役割分担

| 担当 | 内容 | メインへの返却 |
|---|---|---|
| メイン | 計画判断、設計決定、差分レビュー、フェーズゲート、最終検証 | 保持するのは計画・決定・差分・テスト結果のみ |
| `explore` | 対象ファイルの正確な行番号・依存・影響範囲の調査 | 箇条書き 100 行以内。ファイル本文は返さない |
| `general` | 1 ステップ分の限定実装、テスト追加、生成物更新 | 変更ファイル一覧、検証コマンド結果、未解決点 |
| `general`（検証） | 実装後の独立監査、grep、リンク検査、停止テスト | 合否と根拠のみ |

### 6.2 進め方

- 1 ステップにつき「調査 → 実装 → 検証」を分割する。調査結果を実装サブエージェントへ渡し、メインはファイル本文を読まない。
- 同一ファイルを触るステップは並列化しない。文書・テストなど独立領域のみ並列化する。
- 実装サブエージェントには、変更対象ファイル、禁止事項、完了条件、実行する検証コマンドを明示する。
- メインは `git diff --stat` と失敗テストだけを確認し、必要時のみ該当差分を読む。
- 大きな一括置換は禁止。ファイル群を 3〜5 個ずつに分割し、各回で grep とテストを行う。
- 生成物は直接編集させず、生成スクリプトの修正と再生成を指示する。

### 6.3 コンテキスト節約の目安

- 1 サブエージェントの返答は 150 行以内。
- ファイル全文の貼り戻しは禁止。`path:line` と要約のみ。
- ベースライン・調査メモ・パッチは `mas_oc/.work/` に保存し、会話には要点だけを載せる。
- フェーズごとに新しいサブエージェントを起動し、前フェーズの長い文脈を引き継がない。

---

## 7. 要件別の変更対象マトリクス

| 要件 | 主な変更ファイル | 検証 |
|---|---|---|
| (1) OpenCode 専用 | `lib/cli_adapter.sh`、`lib/agent_status.sh`、`scripts/inbox_watcher.sh`、`scripts/switch_model.sh`、`scripts/build_instructions.sh`、`first_setup.sh`、`start.sh`、`install.bat`、`Makefile`、CI、`.claude/` `.cursor/` `agents/default/` 等の削除 | 非 OpenCode 文字列の監査、CLI 単体テスト |
| (2) 役割名変更 | `lib/agent_registry.sh`、`lib/cli_adapter.sh`、`config/opencode-permissions.yaml`、`instructions/`、`.opencode/agents/`、`queue/`、`scripts/*`、`skills/*`、テスト、文書 | 6 名のレジストリ、旧名 0、表示名一致 |
| (3) 自然な日本語 | `instructions/roles/*`、`instructions/*`、`AGENTS.md`、`start.sh`、`first_setup.sh`、README、manual | 戦国語彙の監査、生成物の差分 0 |
| (4) エンジニア3名 + bloom3 | `lib/agent_registry.sh`、`lib/cli_adapter.sh`、`first_setup.sh`、`scripts/build_instructions.sh`、`scripts/agent_status.sh`、`scripts/ratelimit_check.sh`、`scripts/slim_yaml.py`、`instructions/roles/engineer*`、`config/settings.yaml.sample`、テスト | 人数 3、実効上限 3、bloom 4 以上を除外 |
| (5) tmux 1画面6名 | `start.sh`、`lib/tmux_layout.sh`（新規）、`scripts/switch_model.sh`、`scripts/inbox_watcher.sh`、`scripts/agent_status.sh`、dashboard、テスト | 6 ペイン、座標マッピング、端末サイズ検査 |
| (6) 一括停止 | `stop.sh`（新規）、`mas`（新規）、`start.sh`、`run/` 管理、`scripts/setup_cron.sh`、`scripts/watcher_supervisor.sh`、`scripts/ntfy_listener.sh`、dashboard、Makefile、テスト | 停止後 `pgrep` 0、tmux 0、port 0、cron 0 |
| (7) 文書・謝辞 | `README.md`、`README_ja.md`、`docs/manual.md`、`docs/quickstart.md`、`docs/attribution.md`、`NOTICE`、`LICENSE`、`CHANGELOG.md`、`images/` | リンク検査、謝辞・URL・MIT の一致 |

---

## 8. 受け入れ基準

1. `mas_oc` のコード・設定・生成物・テストに、OpenCode 以外のエージェント CLI 向け機能が無い。
2. 起動すると部長・係長・エンジニア1〜3・監査役の 6 名だけが生成される。
3. エンジニア3 の実効 `max_bloom` が 3 で、bloom 4 以上のタスクが割り当てられない。
4. `mas start` で tmux の 1 セッション・1 ウィンドウ・6 ペインが表示され、全員が 1 画面に収まる。
5. `mas stop` 1 回で tmux、watcher、`inotifywait`、ntfy、supervisor、dashboard、cron 管理ブロックが停止・削除される。
6. 停止後に `pgrep`、`tmux ls`、`ss -ltnp`、`crontab -l` に `mas_oc` 関連の残存が無い。
7. 新規の実行時ファイルは `mas_oc/` 内に閉じる。`~/.tmux.conf`、`~/.claude/`、`/tmp/shogun_*` を使わない。OpenCode 認証のみ例外として文書化。
8. 詳細マニュアル `docs/manual.md` とクイックマニュアル `docs/quickstart.md` が存在し、実装と一致する。
9. README・マニュアル・NOTICE に yohey-w、上流 URL、MIT、Akira-Papa への謝辞が明記されている。
10. `mas_orig` が変更されていない。
11. 既知のベースライン失敗を除き、`make lint`、`make build`、`make test`、E2E、停止テスト、bloom テスト、レイアウトテストが通る。
12. ユーザーの承認前に commit していない。

---

## 9. リスクと対策

| リスク | 影響 | 対策 |
|---|---|---|
| 役割名が設定キー・ファイル名・tmux 名・テストに深く結合 | 広範囲の破損 | 中央レジストリ化、改名マトリクス、Step 2.6 の完全監査、小さな単位でテスト |
| 生成物の更新漏れ | 起動時に旧名・旧人数が復活 | 生成元だけ修正し、`make build` を 2 回実行して差分 0 を確認 |
| `.opencode/agents` の旧ファイル残存 | 7 名や旧役割が認識される | setup/clean で明示削除、生成後にファイル数 6 を検証 |
| `max_bloom` の無条件フォールバック | bloom 4 以上がエンジニア3 に流れる | 実効上限を厳格化し、候補なしはキュー/エスカレーション。専用テスト |
| 6 ペインが端末に収まらない | 画面崩れ、操作不能 | 240x50 を推奨、サイズ検査、`--layout 2x3`、ステータス最小化 |
| `pkill -f` が他クローンを巻き込む | 他プロジェクト停止 | PID/PGID 優先、リポジトリパスで限定、PID 再利用検証 |
| 停止漏れ（nohup/disown、cron、dashboard） | プロセス残存 | `run/` 管理、停止順の固定、`status --verify`、統合テスト |
| OpenCode の仕様・フラグ差分 | 起動失敗 | Phase 0 で実機確認、最小バージョンを文書化、モック E2E |
| 親フォルダへの書き込み | 要件違反・環境汚染 | パス監査、隔離 HOME でのスモークテスト、グローバル設定の削除 |
| Android 削除の判断 | 成果物の範囲変更 | `mas_orig` に原本保持、削除前に `.archive/` 退避、最終判断を記録 |
| 謝辞・ライセンスの欠落 | ライセンス違反 | `LICENSE` 不変、`NOTICE`、README/manual の 4 箇所に明記、リンク検査 |
| ベースラインの既存失敗 | 改修成果の誤判定 | Phase 0 で記録し、既知失敗と新規失敗を分離 |

---

## 10. 未決事項・前提

1. **内部 ID**: `director` / `chief` / `engineer1..3` / `auditor` を推奨。表示名は日本語。異論があれば Phase 2 開始前に確定する。
2. **エンジニア3 の軽量モデル**: 特定モデルをハードコードせず、セットアップ時に対話または設定で選択する。サンプルはプレースホルダーとする。
3. **文書言語**: 日本語を正本とし、英語は短い入口と概要に留める。既存の英語 README は簡潔化して維持する。
4. **Android**: `mas_oc` から削除する。理由は OpenCode CLI と無関係、旧ブランド資産が多く、50MB の容量。`mas_orig` に原本を保持。
5. **ntfy / dashboard / branch policy / memory**: 既存機能として維持するが、OpenCode 前提で動作確認する。不要なら削除ではなく任意機能として無効化する。
6. **tmux 既定レイアウト**: 3 列 x 2 行。縦長環境向けに `--layout 2x3` を用意する。
7. **スクリプト名**: 利用者向けは `./mas`。内部の `start.sh` / `stop.sh` は残す。`shutsujin_departure.sh` は廃止。
8. **commit**: ユーザーの明示許可があるまで行わない。ステップごとの差分は `git diff` と `.work/patches/` で管理する。
9. **所要時間**: 実装は Phase 0〜8 の段階実行。各フェーズで一度停止して報告し、承認後に次へ進む。

---

## 11. 成果物一覧（最終）

```text
mas_oc/
  mas                          # 利用者向け CLI
  start.sh / stop.sh           # 起動・一括停止
  first_setup.sh               # 初回セットアップ
  lib/                         # 単一 CLI・レジストリ・tmux・bloom
  scripts/                     # watcher, build, switch_model, status, cron
  config/                      # opencode permissions / TUI / settings sample
  .opencode/agents/            # 6 名分（director, chief, engineer1-3, auditor）
  .opencode/tools/             # mark-as-read
  instructions/roles/          # 自然な日本語の役割指示
  skills/                      # 必要なものだけ改名して維持
  queue/ logs/ run/ status/    # 実行時（git 管理外）
  docs/
    manual.md                  # 詳細取扱説明書
    quickstart.md              # クイックマニュアル
    attribution.md             # 謝辞・上流・ライセンス
    index.md
  README.md
  README_ja.md
  NOTICE
  LICENSE                      # 上流 MIT を保持
  CHANGELOG.md                 # 上流履歴 + フォーク履歴
  REPORT.md                    # 最終変更点・検証結果
```

---

## 12. 次のアクション

この計画書の承認後、Phase 0 から開始する。Phase 0 ではコピー・ベースライン・OpenCode 実機確認・インベントリのみを行い、Phase 1 以降の改修には進まない。各フェーズ完了時に、変更ファイル、検証結果、残課題を報告して停止する。
