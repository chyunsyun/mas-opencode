# mas_oc マニュアル

このマニュアルは、mas_oc の設計、設定、運用手順、キュー契約、トラブルシューティングをまとめたものです。最初の起動だけを確認したい場合は [クイックスタート](quickstart.md) を参照してください。

## 目次

1. [概要](#1-概要)
2. [設計の要点](#2-設計の要点)
3. [動作環境と前提](#3-動作環境と前提)
4. [セットアップ](#4-セットアップ)
5. [チームと指揮系統](#5-チームと指揮系統)
6. [起動と停止](#6-起動と停止)
7. [日常操作](#7-日常操作)
8. [コマンドリファレンス](#8-コマンドリファレンス)
9. [設定リファレンス](#9-設定リファレンス)
10. [Bloom レベルとモデルルーティング](#10-bloom-レベルとモデルルーティング)
11. [キューとファイル契約](#11-キューとファイル契約)
12. [ダッシュボードと状態確認](#12-ダッシュボードと状態確認)
13. [停止と後片付け](#13-停止と後片付け)
14. [トラブルシューティング](#14-トラブルシューティング)
15. [FAQ](#15-faq)
16. [セキュリティ](#16-セキュリティ)
17. [開発とカスタマイズ](#17-開発とカスタマイズ)
18. [帰属とライセンス](#18-帰属とライセンス)

## 1. 概要

mas_oc は OpenCode 専用のマルチエージェント開発環境です。6名の固定チームが tmux の1ウィンドウで動作し、人間の依頼をコマンド、タスク、報告の YAML として受け渡します。

キューを正本とするため、会話の再開、コンテキストのリセット、プロセスの再起動の後も状態を復元できます。現在のバージョンは `1.0.0` で、`./mas version` で確認できます。

mas_oc の主な特徴は次の3点です。

- OpenCode 専用: 起動、モデル指定、権限、コンテキストリセットを OpenCode に統一。
- 無料 AI によるコスト不要のマルチエージェント運用: OpenCode 用の無料モデルを利用でき、コストをかけずにマルチエージェントを運用できます。無料モデルの提供状況やレート制限は変わり得ます。
- 1画面完結: 6ペインを1つの tmux ウィンドウに表示し、1画面で完結します。

## 2. 設計の要点

- 固定編成: `director`、`chief`、`engineer1`、`engineer2`、`engineer3`、`auditor` の6名。
- OpenCode 専用: 起動、モデル指定、権限、コンテキストリセットを OpenCode に統一。
- イベント駆動: エージェントは `sleep` やポーリングで待たず、inbox 通知で再開。
- 状態の復元: コマンド、タスク、報告を YAML に保存し、再起動後に読み直す。
- 権限の生成: `config/opencode-permissions.yaml` からロール別 frontmatter を生成。
- 軽量タスクの分離: `engineer3` は Bloom L1-L3 と `max_bloom: 3` に制限。
- 実行データの局所化: `run/`、`logs/`、`status/`、`queue/` をリポジトリ内に置く。

## 3. 動作環境と前提

| 種類 | 内容 |
|---|---|
| 必須 | bash、tmux、python3 と PyYAML、OpenCode (`opencode`) |
| 任意 | `inotifywait`（未導入なら2秒間隔のポーリング） |
| 任意 | `shellcheck`（`make lint` の追加検査） |
| OS | Linux、macOS、WSL2 |
| 端末 | 約 240x50 を推奨 |

`./mas setup` は python3、PyYAML、tmux を検査します。OpenCode がない場合は警告を出して続行しますが、`./mas start` は失敗します。標準外のバイナリは `OPENCODE_BIN` で指定できます。

```bash
OPENCODE_BIN=/opt/opencode/bin/opencode ./mas start
```

tmux の内部サイズは `MAS_TMUX_COLS`（既定 `240`）と `MAS_TMUX_LINES`（既定 `50`）で変更できます。Windows では WSL2 上の Linux 環境で実行してください。

## 4. セットアップ

```bash
./mas setup
```

`./mas setup` は `first_setup.sh` を呼び出し、依存関係の確認、`config/`、`queue/`、`logs/`、`run/`、`status/`、`memory/`、`context/`、`projects/`、`reports/` の作成、`config/settings.yaml.sample` からの設定生成、inbox、タスク、報告の初期化、`AGENTS.md` と `.opencode/agents/*.md` の生成を行います。初回は `opencode models --verbose` から無料モデルを自動選択し、`opencode/*-free` を優先します（`opencode-go/*-free` はフォールバック）。director / chief / auditor / engineer1 / engineer2 は高能力モデル、engineer3 は速度優先モデルを使い、`capability_tiers` は高能力4 / engineer3 3 に設定します。既存の `model` は上書きしません。

設定は `cli.default: opencode`、各エージェントの `type: opencode`、`engineer3` の `max_bloom: 3` に正規化されます。生成後、`.opencode/agents` に6ファイル存在することが確認されます。

初回は次の順で進めます。`$EDITOR` はモデルを変更する場合だけ必要です。

```bash
./mas setup
# 有料プロバイダーを使う場合のみ
opencode auth login
# 必要ならモデルを変更
$EDITOR config/settings.yaml
./mas build
./mas start
```

`config/settings.yaml` がない状態で `./mas start` を実行した場合も、内部で非対話セットアップと無料モデル選択が実行されます。無料モデルが取得できない場合だけ、`model` を手動で設定してください。

`./mas setup` は稼働中の `mas_oc` を検出すると、設定を書き換えずに停止します。停止後に再実行するか、どうしても稼働中に変更する場合だけ `--allow-running` を指定してください。実行中エージェントには次回起動・再起動まで反映されません。

再選択は `./mas setup --select-free-model`、明示指定は `./mas setup --free-model provider/model`、自動選択の無効化は `./mas setup --no-select-free-model` です。モデル一覧は既定で `opencode models --refresh` を実行して更新し、失敗時はキャッシュを使います。`--no-refresh-free-models` でキャッシュのみにできます。無料モデルは提供状況やレート制限が変わるため、`opencode models --verbose` で定期確認してください。

`./mas start --clean` は起動前にキューを `logs/backup_YYYYmmdd_HHMMSS/` へバックアップして初期化します。`dashboard.md` もバックアップ対象です。既存のタスクと報告を残す場合は `--clean` を付けないでください。

`./mas start --purge --yes` は使用履歴をバックアップなしで完全に削除して起動します。`--yes` は必須で、省略すると停止も削除も行いません。削除対象は `queue/`、`dashboard.md`、`memory/MEMORY.md`、`memory/global_context.md`、`logs/`、`reports/`、`status/`、`run/` の履歴です（各ディレクトリの `.gitkeep` は残します）。あわせて各エージェントの `variant` を削除し、6名のモデルを無料モデルへ再選択します。無料モデルを選択できない場合は警告を表示し、全エージェントを `openrouter/free` に設定します。`config/settings.yaml.bak.*` も削除します。OpenCode 本体のセッション履歴（`~/.local/share/opencode`）は削除しません。

## 5. チームと指揮系統

| agent_id | 表示名 | 主な責任 |
|---|---|---|
| `director` | 部長 | 人間の窓口、コマンド作成、最終判断 |
| `chief` | 係長 | 分解、割当、進捗管理、品質確認の取り回し、ダッシュボード |
| `engineer1` | エンジニア1 | 実装、テスト、報告 |
| `engineer2` | エンジニア2 | 実装、テスト、報告 |
| `engineer3` | エンジニア3 | 軽量高速タスク（L1-L3、`max_bloom: 3`） |
| `auditor` | 監査役 | 独立した品質確認、原因分析、証拠に基づく判定 |

```
人間 <-> 部長 <-> 係長 <-> エンジニア1 / エンジニア2 / エンジニア3
                    <-> 監査役
```

人間との連絡は部長が担当します。部長はコマンドを作成して係長へ渡し、エンジニアや監査役へ直接指示しません。係長がコマンドをタスクへ分解して割り当て、エンジニアと監査役は係長へ報告します。監査役は実装を行わず、判定と根拠を返します。部長が最終判断を行い、係長が実行の進行と完了判定を行います。

## 6. 起動と停止

### 起動

```bash
./mas start
```

`./mas start` は tmux と、通常起動では OpenCode を確認し、必要なら非対話セットアップを実行します。`--clean` が指定されていればキューを初期化し、このリポジトリに属する既存プロセスを `./mas stop --quiet` で停止します。`.opencode/agents/director.md` がない場合だけビルドし、tmux セッション `mas`、ウィンドウ `team` に6ペインを作成します。

各ペインには `agent_id`、表示名、モデル名がメタデータとして設定されます。モデル名は枠にもペインタイトルにも表示しません。OpenCode は既定で `--auto`、設定済みなら `--model`、必ず `--agent <agent_id>` を付けて起動します。エージェントの起動間隔は既定で15秒です。短い間隔で連続起動するとシステムが不安定になるため、6名の起動には約75秒かかります。間隔は `MAS_START_INTERVAL` または `--start-interval` で変更できます。その後、各エージェントの inbox watcher が起動し、PID と PGID が `run/` に保存されます。`run/session.env` にはセッション名、ルート、開始時刻が記録されます。

| オプション | 動作 |
|---|---|
| `--clean` | キューをバックアップして初期化してから起動 |
| `--purge --yes` | 使用履歴をバックアップなしで完全削除し、無料モデルへ初期化してから起動 |
| `--setup-only` | tmux と設定だけを作成し、OpenCode と watcher を起動しない |
| `--start-interval SEC` | エージェントの起動間隔（秒、既定15） |
| `--no-auto` | OpenCode に `--auto` を渡さない |
| `--layout 3x2` | 既定。3列2行 |
| `--layout 2x3` | 縦長画面向け。2列3行 |

`--setup-only` は画面構成やペインのメタデータを確認したいときに使います。OpenCode は起動しないため、エージェントは作業できません。

### 停止

```bash
./mas stop
```

`./mas stop` は冪等です。再実行しても安全で、存在しないプロセスやセッションは無視されます。停止対象はこのリポジトリと `mas` セッションに限定され、全体の `pkill` は使いません。詳細は [13. 停止と後片付け](#13-停止と後片付け) を参照してください。

## 7. 日常操作

起動後、人間は `director` のペインで依頼を入力します。部長がコマンドを作成し、係長へ通知します。以降は係長がタスクを分解し、担当者へ割り当てます。

```bash
tmux attach -t mas    # 接続
./mas status          # 状態確認
./mas dashboard       # ダッシュボード表示
```

切断は `Ctrl-b` の後に `d` です。`./mas dashboard` は `dashboard.md` を `http://127.0.0.1:8787` で表示し、約1.5秒間隔で更新します。停止は `./mas stop` です。

コンテキストをリセットする場合は、対象ペインで `/new` を使います。リセット前に、進捗、未完了点、次の手順が YAML に保存されていることを確認してください。

エージェントは `tmux send-keys` を実行しません。通知と再開は watcher が担当します。人間が手動でペインを操作することは可能ですが、通常運用では部長への依頼だけを行います。

watcher は `queue/inbox/<agent_id>.yaml の未読メッセージを確認してください` という通知を送ります。通知には対象エージェントのinboxパスが含まれるため、別エージェントのinboxと取り違えません。

## 8. コマンドリファレンス

| コマンド | 説明 |
|---|---|
| `./mas setup` | 初回セットアップ、無料モデル自動選択 |
| `./mas setup --select-free-model` | 既存設定でも無料モデルを再選択 |
| `./mas setup --no-select-free-model` | 無料モデルの自動選択を無効化 |
| `./mas setup --free-model provider/model` | 指定した無料モデルを全エージェントに設定 |
| `./mas setup --no-refresh-free-models` | キャッシュ済みのモデル一覧を使う |
| `./mas setup --allow-running` | 稼働中でも設定を変更する（実行中エージェントには未反映） |
| `./mas start` | 6名を1画面で起動 |
| `./mas start --clean` | キューを初期化して起動 |
| `./mas start --purge --yes` | 使用履歴を完全削除し、無料モデルへ初期化して起動 |
| `./mas start --setup-only` | tmux と設定だけを作成 |
| `./mas start --no-auto` | `--auto` を付けずに起動 |
| `./mas start --layout 2x3` | 2列3行で起動 |
| `./mas status` | エージェントの状態を表示 |
| `./mas stop` | 関連プロセスとセッションを停止 |
| `./mas stop --verify` | 停止せずに残存を検査 |
| `./mas build` | 生成物を再作成 |
| `./mas switch-model` | モデルを変更してペインを再起動 |
| `./mas dashboard` | ダッシュボードビューアを起動 |
| `./mas version` | バージョンを表示 |

### build

```bash
./mas build
```

`scripts/build_instructions.sh` を実行し、`instructions/`、`config/opencode-permissions.yaml`、`config/settings.yaml` から `.opencode/agents/*.md` と `AGENTS.md` を生成します。生成物は直接編集せず、源ファイルを変更してから再ビルドしてください。

### switch-model

```bash
./mas switch-model <agent> --model <provider/model> [--variant <variant>] [--max-bloom <N>] [--force]
```

`config/settings.yaml` を更新し、生成物を再作成し、対象ペインが存在すれば再起動します。再起動時は `--auto` 付きで OpenCode を起動します。`--max-bloom` はそのエージェントの `max_bloom` を更新します。`engineer3` は `3` を上限として扱ってください。

対象エージェントがbusyの場合、設定を変更せずに拒否します。作業中の会話や進捗を失う可能性があるため、idleになるまで待ってください。ユーザーが明示的に強制再起動を承認した場合だけ `--force` を付けます。

`mas_oc` 専用のモデル切替スキル `.opencode/skills/mas-model-switch/SKILL.md` も同じスクリプトを使います。multi-agent-shogun 用の `shogun-model-switch` は使いません。

`./mas status` は Agent、表示名、Pane（`稼働中`、`待機中`、`不在`）、Task、Status、未読 Inbox 数を表示します。`./mas dashboard` はローカル専用ビューアを起動し、ポート 8787 が使用中の場合は失敗します。`./mas version` は `mas_oc 1.0.0` を表示します。

## 9. 設定リファレンス

設定は `config/settings.yaml` に置きます。初回セットアップで `config/settings.yaml.sample` から生成されます。

| キー | 内容 |
|---|---|
| `cli.default` | `opencode` 固定 |
| `cli.agents.<id>.type` | `opencode` 固定 |
| `cli.agents.<id>.model` | `provider/model` 形式。空欄なら OpenCode の既定モデル |
| `cli.agents.<id>.variant` | 任意。生成される frontmatter に反映 |
| `cli.agents.<id>.max_bloom` | 任意。エージェント固有の能力上限 |
| `capability_tiers.<model>.max_bloom` | モデルごとの能力上限。未設定は 6 |
| `model_selection` | 無料モデル自動選択の結果（`source`、`selected_at`、`high_model`、`fast_model`、`candidates`） |
| `bloom_routing.enabled` | サンプルに含まれる予約設定 |
| `ntfy_topic` | 任意の ntfy 連携スクリプトが参照 |

`engineer3` の `max_bloom` は `3` を維持してください。実効的な `max_bloom` は、モデルの能力上限とエージェント固有の上限の低い方です。

初回セットアップは `opencode models --verbose` の `cost` が0のモデルから、`opencode/*-free` を優先して選択します。`opencode-go/*-free` はフォールバックです。director / chief / auditor / engineer1 / engineer2 は高能力モデル、engineer3 は速度優先モデルを使い、`capability_tiers` は高能力4 / engineer3 3 が設定されます。既存の `model` は自動選択で上書きしません。

再選択は `./mas setup --select-free-model`、明示指定は `./mas setup --free-model provider/model`、無効化は `./mas setup --no-select-free-model` です。既定では `opencode models --refresh` を実行し、失敗時はキャッシュを使います。`--no-refresh-free-models` でキャッシュのみにできます。無料モデルが取得できない場合は `model` を空欄のままセットアップを継続します。無料モデルは提供状況やレート制限が変わるため、`opencode models --verbose` で定期確認してください。

設定例:

```yaml
cli:
  default: opencode
  agents:
    engineer1:
      type: opencode
      model: "provider/model"
    engineer3:
      type: opencode
      model: "provider/model"
      max_bloom: 3

capability_tiers:
  "provider/model":
    max_bloom: 3
```

`language`、`shell`、`screenshot.paths`、`logging.level` はサンプルに含まれる予約設定です。`./mas start` は ntfy listener を起動しません。

### 権限設定

ロール別の権限は `config/opencode-permissions.yaml` で定義します。`scripts/build_instructions.sh` が `common.edit_deny` と `roles.<role>` を読み、`.opencode/agents/*.md` の frontmatter に変換します。

- 共通の編集禁止対象には、生成物、保護設定、inbox が含まれます。
- 部長はコマンドを作成できますが、タスク、報告、ダッシュボードは編集できません。
- 係長はコマンド、タスク、ダッシュボードを更新できますが、報告書は編集できません。
- エンジニアは自分のタスクと自分の報告書だけを編集できます。
- 監査役は自分の報告書だけを編集できます。

権限を変更する場合は `config/opencode-permissions.yaml` を編集し、`./mas build` を実行してください。生成された `.opencode/agents/*.md` を直接編集しないでください。

### 環境変数

| 変数 | 既定値 | 用途 |
|---|---|---|
| `OPENCODE_BIN` | `opencode` | OpenCode の実行ファイル |
| `MAS_TMUX_COLS` | `240` | 起動時の tmux 幅 |
| `MAS_TMUX_LINES` | `50` | 起動時の tmux 高さ |
| `MAS_START_INTERVAL` | `15` | エージェントの起動間隔（秒） |

## 10. Bloom レベルとモデルルーティング

| レベル | 内容 | 例 |
|---|---|---|
| L1 記憶 | 定義や値を確認する | 設定値の確認 |
| L2 理解 | 説明、要約、整理する | 既存処理の説明 |
| L3 応用 | 既知の手順を当てはめる | 小規模な修正、テスト追加 |
| L4 分析 | 原因や依存関係を分解する | 障害調査、影響範囲の特定 |
| L5 評価 | 比較、判定、リスク評価を行う | 設計案の比較、品質監査 |
| L6 創造 | 新しい設計や方針を作る | アーキテクチャ設計 |

`engineer1` と `engineer2` は L1-L6 を担当できます。`engineer3` は L1-L3 だけを担当し、`max_bloom: 3` を守ります。L4 以上のタスクを `engineer3` へ割り当ててはいけません。`engineer3` しか空いていない場合でも、L4 以上を割り当てず待機させます。

`lib/cli_adapter.sh` の `find_engineer_for_bloom` は、空き状況と能力上限から担当者を選びます。

```bash
source lib/cli_adapter.sh
engineer=$(find_engineer_for_bloom 2)
```

L1-L3 では `engineer3`、`engineer1`、`engineer2` の順に確認します。L4 以上では `engineer3` を除外し、`engineer1`、`engineer2` の順に確認します。割当可能なエージェントがない場合は非ゼロで終了します。

モデル能力が不足する場合は `needs_model_switch` で確認できます。L4 以上が必要な場合は、`engineer1` または `engineer2` へ割り当てるか、モデルを切り替えた上で担当を変更します。`engineer3` の上限は 3 のままにしてください。

初回セットアップの自動選択では、高能力モデルに `max_bloom: 4`、engineer3 の速度優先モデルに `max_bloom: 3` を設定します。高能力モデルでも L5/L6 は上限4を超えるため、`./mas switch-model` で上位モデルへ切り替えるか、`capability_tiers` を手動で調整してください。`engineer3` の上限は 3 のままです。

## 11. キューとファイル契約

| パス | 主な書き手 | 内容 |
|---|---|---|
| `queue/inbox/<id>.yaml` | `inbox_write.sh` | エージェント間メッセージ |
| `queue/tasks/<id>.yaml` | 係長が作成、担当者が状態更新 | エージェントごとのアクティブタスク |
| `queue/reports/<id>_report.yaml` | エンジニア、監査役 | 実装、テスト、品質判定の報告 |
| `queue/commands.yaml` | 部長が作成、係長が更新 | 未完了のコマンド |
| `queue/commands_archive.yaml` | 係長 | 完了・中止したコマンドの履歴 |
| `queue/pending.yaml` | 運用者 | 保留中の作業（任意） |
| `dashboard.md` | 係長 | 人間向けの進捗概要 |

1つのタスクファイルには1件のアクティブタスクだけを置きます。報告書は作成者が所有し、他のロールは書き換えません。完了したタスクと報告は履歴として残し、削除しません。

### inbox

```yaml
messages:
  - id: msg_20261026_120000_ab12cd34
    from: chief
    timestamp: "2026-10-26T12:00:00"
    type: task_assigned
    content: "task_001 を割り当てました。"
    read: false
```

送信:

```bash
bash scripts/inbox_write.sh <target> "<message>" <type> <from>
```

`inbox_write.sh` は自分自身への送信と、存在しない `agent_id` への送信を拒否します。本文は短くし、詳細はファイルパスで示します。

主な種別は `cmd_new`、`task_assigned`、`report_received`、`qc_request`、`qc_result`、`task_rejected`、`redo`、`decision_needed`、`cmd_done`、`clear_command` です。

処理したメッセージは OpenCode の `mark-as-read` ツール（`.opencode/tools/mark-as-read.ts`）で既読にします。`queue/inbox/*.yaml` を直接編集しないでください。`mark-as-read` は `OPENCODE_AGENT_ID` を確認し、自分の inbox だけを更新します。

### 状態とワークフロー

コマンドは `pending`、`in_progress`、`done`、`cancelled` を使います。タスクは `assigned`、`blocked`、`done`、`failed` を使います。報告は `done`、`failed`、`blocked` を使います。状態値を独断で追加しないでください。

1. 部長が依頼を `queue/commands.yaml` に `pending` で記録する。
2. 部長が係長へ `cmd_new` を送る。
3. 係長が `pending` を `in_progress` へ更新し、タスクへ分解する。
4. 係長が `queue/tasks/*.yaml` を書き、担当者へ `task_assigned` を送る。
5. エンジニアが実装、テスト、報告を行う。
6. 係長が必要に応じて監査役へ `qc_request` を送る。
7. 監査役が `auditor_report.yaml` に判定を書く。
8. 係長が受け入れ条件を確認し、コマンドを `done` にしてアーカイブへ移す。

待機はイベント駆動です。エージェントは `sleep`、ポーリング、tmux 画面の監視を行いません。

## 12. ダッシュボードと状態確認

`./mas status` は tmux のペイン状態とキューの状態をまとめて表示します。ペインが存在しない場合は `不在`、OpenCode が作業中の場合は `稼働中`、入力待ちの場合は `待機中` と表示します。

`dashboard.md` は係長が更新する人間向けの概要です。更新時刻、進行中のコマンド、進行中のタスク、品質確認の状況、ブロッカー、要判断、直近の完了を含みます。正本は常に YAML です。

`./mas dashboard` は `dashboard.md` を表示するローカルビューアを起動し、`http://127.0.0.1:8787` を案内します。約1.5秒間隔で更新します。ブラウザを自動で開く場合は `MAS_OPEN_BROWSER=1 ./mas dashboard` を使います。ログは `logs/` に出力され、inbox watcher のログは `logs/watcher.<agent_id>.log` です。

## 13. 停止と後片付け

```bash
./mas stop
```

停止対象は、`run/` に PID と PGID が保存された inbox watcher、ntfy listener、watcher supervisor、dashboard viewer、`mas` セッションの各ペインの子プロセス、`mas` セッション、管理対象の cron ブロック、`queue/` 配下のロックディレクトリ、`run/` 配下のロックファイル、PID ファイル、`session.env`、`idle_*` です。

停止処理はこのリポジトリの範囲に限定されます。全体の `pkill` や、他の tmux セッションの無差別停止は行いません。`./mas stop` は冪等で、プロセスが残っていなくても成功します。`./mas start` も起動前に `./mas stop --quiet` を呼び出します。

残存だけを確認する:

```bash
./mas stop --verify
```

`--verify` は停止を行わず、tmux セッションと対象プロセスの有無を検査します。残存があれば一覧を表示し、非ゼロで終了します。キュー、報告、ダッシュボードは停止では削除されません。

## 14. トラブルシューティング

### opencode: command not found

OpenCode が `PATH` にありません。公式の手順でインストールし、`opencode --version` を確認してください。標準外の場所にある場合は `OPENCODE_BIN=/path/to/opencode ./mas start` のように指定できます。

### agent not found

生成済みのエージェント定義が欠けています。`./mas build` を実行してください。直らない場合は、`instructions/roles/` と `config/opencode-permissions.yaml` が存在するか確認してください。

### 6ペインが作成できない

端末が小さすぎる可能性があります。端末を広げるか、`./mas start --layout 2x3` を使ってください。既定のレイアウトには約 240x50 の端末を推奨します。tmux の内部サイズは `MAS_TMUX_COLS` と `MAS_TMUX_LINES` で調整できます。

### モデルエラーになる

`opencode models` でモデル ID を確認し、`provider/model` 形式で `config/settings.yaml` に設定してください。認証が切れている場合は `opencode auth login` を再実行します。設定変更後は `./mas build` を実行してください。

### 残存プロセスがある

`./mas stop --verify` で確認し、残存があれば `./mas stop` を実行します。それでも残る場合は、表示されたプロセスが本当にこのリポジトリのものか確認してから、個別に停止してください。

### tmux に接続できない

`tmux ls` でセッションを確認し、`tmux attach -t mas` で接続します。セッションがない場合は `./mas start` を実行します。接続を切るときは `Ctrl-b` の後に `d` を押します。

### 通知が来ない

`inotifywait` がない場合、watcher は2秒間隔のポーリングで動作します。`logs/watcher.<agent_id>.log` を確認してください。ペインが存在しない場合、watcher はエラーで終了します。`./mas status` でペイン状態を確認し、必要なら `./mas start` で再起動します。

### 設定を変えたのに反映されない

```bash
./mas build
```

実行中のエージェントに反映するには、`./mas start` で再起動するか、対象エージェントに `./mas switch-model` を使ってください。

## 15. FAQ

### 対応 OS は何ですか

Linux、macOS、WSL2 です。Windows のネイティブ環境では動作しません。

### Claude Code や他の CLI は使えますか

いいえ。mas_oc は OpenCode 専用です。`cli.default` は `opencode` 固定です。

### エージェントを追加できますか

固定6名を前提としています。追加する場合は、`lib/agent_registry.sh`、ロール指示、権限、レイアウト、キューの初期化を一貫して変更する必要があります。標準の設定だけでは追加できません。

### 複数のリポジトリで同時に動かせますか

tmux セッション名が `mas` で固定されているため、同時運用は想定していません。別のリポジトリで起動する前に、現在のセッションを停止してください。

### コンテキストをリセットするには

対象ペインで `/new` を使います。リセット前に、進捗と次の手順が YAML に保存されていることを確認してください。

### 秘密情報を設定ファイルに書いてもよいですか

いいえ。API キーやトークンは OpenCode の認証機能で管理し、キュー、ログ、報告、設定ファイルへ書かないでください。

### 外部に残る状態はありますか

通常の起動と停止で外部に残る状態は OpenCode の認証だけです。`~/.tmux.conf` や `~/.claude` には書き込みません。任意の cron 連携を使った場合だけ、管理対象ブロックが crontab に追加され、`./mas stop` で削除されます。

## 16. セキュリティ

`./mas start` は既定で OpenCode に `--auto` を渡します。`--auto` は権限要求を自動承認するため、信頼できるリポジトリとタスクでのみ使ってください。手動承認が必要な場合は `./mas start --no-auto` を使います。

ロール別の権限は `config/opencode-permissions.yaml` から生成されます。これは OpenCode のファイル操作に対する制御であり、OS レベルのサンドボックスではありません。エージェントが実行するシェルコマンドの影響範囲は、実行ユーザーの権限に依存します。

信頼できないコードやプロンプトを含むリポジトリでは、`--no-auto` を使い、タスクの範囲を限定してください。秘密情報、認証情報、個人情報をキュー、ログ、報告へ書かないでください。脆弱性の報告方法は [SECURITY.md](../SECURITY.md) を参照してください。

## 17. 開発とカスタマイズ

指示の源ファイルは `instructions/AGENTS.md`、`instructions/roles/*.md`、`instructions/common/*.md`、`instructions/opencode_tools.md` です。権限は `config/opencode-permissions.yaml`、モデルと能力上限は `config/settings.yaml` で設定します。

生成物は `AGENTS.md` と `.opencode/agents/*.md` です。直接編集せず、源ファイルを変更してから実行してください。

```bash
make build
make lint
make test
make check
```

`make lint` はシェル構文、Python コンパイル、利用可能なら shellcheck を実行します。`make test` はスモークテストを実行します。`make check` はビルドの冪等性と生成物の差分を検査します。詳細は [CONTRIBUTING.md](../CONTRIBUTING.md) を参照してください。

## 18. 帰属とライセンス

- 原プロジェクト: multi-agent-shogun by yohey-w, https://github.com/yohey-w/multi-agent-shogun
- ライセンス: MIT, Copyright (c) 2026 yohey-w
- Claude-Code-Communication by Akira-Papa をベースに開発
- mas_oc は改変を含む非公式フォークであり、原作者とは提携していません。

このフォークの主な変更点は、OpenCode 専用化、ロール名の再編、自然な日本語の指示、3名のエンジニア構成と `engineer3` の `max_bloom: 3`、6ペイン1ウィンドウ、統一された停止処理、新しいマニュアルです。上流の `CHANGELOG.md` は履歴として保持しています。

詳細は [帰属情報](attribution.md) と [NOTICE](../NOTICE) を参照してください。ライセンス全文は [LICENSE](../LICENSE) にあります。
