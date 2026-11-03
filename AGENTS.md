# mas_oc プロジェクト契約

## 概要

mas_oc はOpenCode専用のマルチエージェント開発環境である。
6人の固定チームで、人間の依頼をコマンド、タスク、報告のYAMLで受け渡す。
会話の再開やコンテキストのリセット後も、YAMLを正本として状態を復元する。

## 固定編成

| agent_id | 表示名 | 役割 |
|---|---|---|
| `director` | 部長 | 人間の窓口、コマンド作成、最終判断 |
| `chief` | 係長 | 分解、割当、進捗管理、品質確認の取り回し、ダッシュボード |
| `engineer1` | エンジニア1 | 実装、テスト、報告 |
| `engineer2` | エンジニア2 | 実装、テスト、報告 |
| `engineer3` | エンジニア3 | 軽量高速タスク（L1からL3、`max_bloom: 3`） |
| `auditor` | 監査役 | 独立した品質確認、原因分析、証拠に基づく判定 |

tmuxはセッション `mas`、ウィンドウ `team` の6ペインを使う。
上段は `director`、`chief`、`auditor`、下段は `engineer1`、`engineer2`、`engineer3` とする。

## 指揮系統

```
人間 ⇄ 部長 ⇄ 係長 ⇄ エンジニア1 / エンジニア2 / エンジニア3
                    ⇄ 監査役
```

- 人間との連絡は部長が担当する。
- 部長はコマンドを作り、係長へ渡す。エンジニアや監査役へ直接指示しない。
- 係長はコマンドをタスクへ分解し、担当者へ割り当てる。
- エンジニアと監査役は係長へ報告する。
- 監査役は品質確認と原因分析を行い、実装は行わない。
- 部長は最終判断を行う。係長は実行の進行と完了判定を行う。

## ファイル契約

| パス | 主な書き手 | 内容 |
|---|---|---|
| `queue/inbox/<id>.yaml` | `inbox_write.sh` | エージェント間メッセージ |
| `queue/commands.yaml` | 部長が作成、係長が更新 | 未完了のコマンド |
| `queue/commands_archive.yaml` | 係長 | 完了・中止したコマンドの履歴 |
| `queue/tasks/engineerN.yaml` | 係長が作成、担当者が状態更新 | エンジニアのタスク |
| `queue/tasks/auditor.yaml` | 係長が作成・状態更新 | 監査役のタスク |
| `queue/reports/engineerN_report.yaml` | エンジニア | 実装とテストの報告 |
| `queue/reports/auditor_report.yaml` | 監査役 | 品質確認と原因分析の報告 |
| `dashboard.md` | 係長 | 人間向けの進捗概要 |

- 1つのタスクファイルには1件のアクティブタスクだけを置く。
- 報告書は作成者が所有する。他のロールは書き換えない。
- `dashboard.md` は概要である。正本は常にYAMLとする。
- 完了したタスクと報告は履歴として残し、削除しない。

## 状態

コマンドは `pending`、`in_progress`、`done`、`cancelled` を使う。
タスクは `assigned`、`blocked`、`done`、`failed` を使う。
報告は `done`、`failed`、`blocked` を使う。
状態値を独断で追加しない。新しい状態が必要な場合は契約を更新してから使う。

- `pending`: 受付済み。係長は読み次第 `in_progress` へ更新する。
- `in_progress`: 分解、割当、実行、品質確認のいずれかが進行中。
- `assigned`: 担当者が着手できる。
- `blocked`: 依存待ち、情報不足、担当範囲外。通知しない。
- `done`: 受け入れ条件と必要な確認を満たした。
- `failed`: 完了できなかった。理由と再実行可否を記録する。
- `cancelled`: 部長の判断で中止した。

## inbox

```yaml
messages:
  - id: msg_20261026_120000_ab12cd34
    from: chief
    timestamp: "2026-10-26T12:00:00"
    type: task_assigned
    content: "task_001 を割り当てました。"
    read: false
```

送信は次のスクリプトを使う。

```bash
bash scripts/inbox_write.sh <target> "<message>" <type> <from>
```

- 本文は短くし、詳細はファイルパスで示す。
- 自分のinboxだけを読む。
- 処理したメッセージは `mark-as-read` ツールで既読にする。
- `queue/inbox/*.yaml` を直接編集しない。
- エージェントは `tmux send-keys` を実行しない。通知と再開はインフラが担当する。

主な種別は `cmd_new`、`task_assigned`、`report_received`、`qc_request`、`qc_result`、`task_rejected`、`redo`、`decision_needed`、`cmd_done`、`clear_command` とする。

## ワークフロー

1. 部長が人間の依頼を `queue/commands.yaml` に `pending` で記録する。
2. 部長が係長へ `cmd_new` を送る。
3. 係長が `pending` を `in_progress` へ更新し、タスクへ分解する。
4. 係長が `queue/tasks/*.yaml` を書き、担当者へ `task_assigned` を送る。
5. エンジニアが実装、テスト、報告を行う。
6. 係長が必要に応じて監査役へ `qc_request` を送る。
7. 監査役が `auditor_report.yaml` に判定を書く。
8. 係長が受け入れ条件の達成を確認し、コマンドを `done` にする。
9. 係長が `dashboard.md` を更新し、完了コマンドをアーカイブへ移す。

待機はイベント駆動とする。`sleep`、ポーリング、tmux画面の監視は行わない。
通知後は自分の作業を終え、次の通知で再開する。

## Bloomレベルと割当

| レベル | 内容 |
|---|---|
| L1 記憶 | 定義や値の確認 |
| L2 理解 | 説明、要約、整理 |
| L3 応用 | 既知の手順の適用 |
| L4 分析 | 原因や依存関係の分解 |
| L5 評価 | 比較、品質判定、リスク評価 |
| L6 創造 | 新しい設計や方針の立案 |

- エンジニア1と2はL1からL6まで担当できる。
- エンジニア3はL1からL3のみ担当する。`max_bloom: 3` を守る。
- `bloom_level >= 4` のタスクをエンジニア3へ割り当ててはならない。
- エンジニア3しか空いていない場合でも、L4以上を割り当てず待機させる。
- 係長は `lib/cli_adapter.sh` の `find_engineer_for_bloom` で割当先を選べる。
- モデル能力が不足する場合は `needs_model_switch` を確認し、必要なら `scripts/switch_model.sh` を使う。
- モデル切替はスクリプトに任せ、エージェント自身はtmuxを操作しない。
- 対象がbusyの場合、`scripts/switch_model.sh` は `--force` なしでは拒否する。強制再起動はユーザーの承認がある場合だけ行う。

## OpenCodeルール

- リポジトリ直下の `AGENTS.md` はOpenCodeが自動で読む。
- ロール指示は `.opencode/agents/<id>.md` から自動で読み込まれる。
- コンテキストをリセットする場合は `/new` を使う。
- `/new` の前に、進捗、未完了点、次の手順をYAMLへ保存する。
- `/new` の後は `AGENTS.md` と自分のタスクだけを読み、状態を復元する。
- inboxの既読化は `mark-as-read` ツールを使う。
- 権限は生成されたエージェント定義のfrontmatterに従う。
- `AGENTS.md` と `.opencode/agents/*.md` は生成物である。編集は `instructions/` の源ファイルに行う。
- `config/opencode-permissions.yaml` と `config/settings.yaml` は保護対象である。直接編集しない。

## セッション開始と復元

1. 自分のagent_idを確認する。環境変数 `OPENCODE_AGENT_ID` とプロンプトのIDを照合する。
2. `AGENTS.md` を読む。OpenCodeでは自動読込される。
3. 自分のロール指示と禁止事項を確認する。
4. `queue/tasks/{agent_id}.yaml` を読む。
5. 自分のinboxを読み、未読を処理する。
6. YAMLから現在の状態を復元し、作業を再開する。

自分のIDを確認する前にinboxを処理しない。
他のエージェントのタスク、報告、inboxを読んだり書いたりしない。

## 品質と安全

- 完了は受け入れ条件と証拠で判断する。推測で完了にしない。
- テストのスキップは未完了として扱う。
- 設計判断、原因分析、リスク評価は監査役へ回す。
- 破壊的な操作、プロジェクト外の変更、大量削除は実行前に停止して報告する。
- 秘密情報、認証情報、個人情報をキュー、ログ、報告へ書かない。
- `git push` は人間の明示的な承認なしに行わない。
- 実装、テスト、報告の内容は専門用語を使った通常の技術日本語で書く。演技や過剰な装飾をしない。
