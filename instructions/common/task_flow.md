# タスクフロー

## 全体像

```
人間 → 部長: 依頼
部長 → queue/commands.yaml: コマンド記録
部長 → 係長: cmd_new
係長 → queue/tasks/engineerN.yaml または auditor.yaml: タスク記録
係長 → エンジニア / 監査役: task_assigned または qc_request
エンジニア / 監査役 → queue/reports/*_report.yaml: 報告
エンジニア / 監査役 → 係長: report_received
係長 → 監査役: qc_request（必要な場合）
監査役 → 係長: qc_result
係長 → dashboard.md: 状態更新
部長 → 人間: 進捗と判断の共有
```

## 状態の定義

状態値は次の範囲だけを使う。新しい状態を独断で追加しない。

- `queue/commands.yaml`: `pending`、`in_progress`、`done`、`cancelled`
- `queue/tasks/engineerN.yaml`: `assigned`、`blocked`、`done`、`failed`
- `queue/tasks/auditor.yaml`: `assigned`、`blocked`、`done`、`failed`
- `queue/reports/*_report.yaml`: `done`、`failed`、`blocked`

### コマンド

- `pending`: 受付済み。係長は読み次第 `in_progress` へ更新する。
- `in_progress`: 分解、割当、実行、品質確認のいずれかが進行中。
- `done`: 受け入れ条件を満たし、必要な品質確認が完了した。
- `cancelled`: 部長の判断で中止した。理由を `notes` に残す。

`pending` のままタスクを割り当てない。`done` のコマンドを再開せず、必要なら新しいコマンドを作る。

### タスク

- `assigned`: 担当者が着手できる。
- `blocked`: 依存待ち、情報不足、担当範囲外などで着手できない。
- `done`: 担当者の作業と報告が完了した。
- `failed`: 作業を完了できなかった。理由と再実行可否を報告に書く。

`blocked` のタスクを担当者へ通知しない。係長が依存を解消してから `assigned` に戻す。

## コマンドの流れ

1. 部長が人間の依頼を `queue/commands.yaml` に `pending` で追加する。
2. 部長が係長へ `cmd_new` を送る。
3. 係長がコマンドを読み、`pending` を `in_progress` へ更新する。
4. 係長が受け入れ条件を確認し、タスクへ分解する。
5. 係長がタスクYAMLを書き、担当者へ通知する。
6. 担当者が作業し、報告YAMLを書く。
7. 係長が必要に応じて監査役へ品質確認を依頼する。
8. 係長が受け入れ条件の達成を確認し、コマンドを `done` にする。
9. 係長が `dashboard.md` を更新し、コマンドをアーカイブへ移す。

## Bloomレベル

| レベル | 名称 | 内容 | 例 |
|---|---|---|---|
| L1 | 記憶 | 定義や値を確認する | 設定値の確認 |
| L2 | 理解 | 内容を説明、要約、整理する | 既存処理の説明 |
| L3 | 応用 | 既知の手順を当てはめる | 小規模な修正、テスト追加 |
| L4 | 分析 | 原因や依存関係を分解する | 障害調査、影響範囲の特定 |
| L5 | 評価 | 比較、判定、リスク評価を行う | 設計案の比較、品質監査 |
| L6 | 創造 | 新しい設計や方針を作る | アーキテクチャ設計 |

## 割当ルール

- エンジニア1と2はL1からL6まで担当できる。
- エンジニア3はL1からL3のみ担当する。`max_bloom: 3` を守る。
- `bloom_level >= 4` のタスクをエンジニア3へ割り当ててはならない。
- エンジニア3しか空いていない場合でも、L4以上を割り当てず待機させる。
- 難易度を下げてエンジニア3へ割り当てない。必要ならエンジニア1・2の完了を待つ。
- 迷った場合は高めのBloomレベルで見積もる。

係長は `lib/cli_adapter.sh` の `find_engineer_for_bloom` で割当先を選べる。

```bash
source lib/cli_adapter.sh
engineer=$(find_engineer_for_bloom "$bloom_level")
```

戻り値は `engineerN`、`QUEUE`、空文字のいずれかとする。
`QUEUE` は空きなし、空文字は設定エラーとして扱う。
モデル能力が不足する場合は `needs_model_switch` を確認し、必要なら `scripts/switch_model.sh` を使う。
対象がbusyの場合はスクリプトが拒否する。強制再起動はユーザーの承認がある場合だけ `--force` を付ける。

```bash
bash scripts/switch_model.sh <agent_id> [--model <model>] [--variant <variant>] [--max-bloom <N>] [--force]
```

## タスクYAML

`queue/tasks/engineerN.yaml` と `queue/tasks/auditor.yaml` は1ファイル1アクティブタスクとする。

```yaml
task_id: task_YYYYMMDD_NNN
parent_cmd: cmd_YYYYMMDD_NNN
assignee: engineer1
bloom_level: 3
status: assigned
objective: "完了時に満たす状態"
scope:
  - "変更してよい範囲"
acceptance_criteria:
  - "検証可能な条件"
context:
  - "参照すべきファイルや情報"
redo_of: null
```

監査役のタスクは `assignee: auditor` とし、`review_scope`、`target_task`、`target_report` を追加する。
監査役のタスクYAMLは係長が作成し、状態も係長が更新する。

## 報告YAML

エンジニアは `queue/reports/engineerN_report.yaml`、監査役は `queue/reports/auditor_report.yaml` に書く。
必須項目は `worker_id`、`task_id`、`parent_cmd`、`status`、`timestamp`、`summary`、`evidence` とする。
エンジニアは `changes` と `tests`、監査役は `verdict`、`severity`、`findings`、`required_actions` を追加する。

## 品質確認

- エンジニアの報告だけで完了にしない。受け入れ条件と証拠を照合する。
- 設計判断、原因分析、リスク評価を含む場合は監査役へ回す。
- 監査役の判定は `pass`、`pass_with_conditions`、`fail` の3種類とする。
- `pass` は完了、`pass_with_conditions` は条件を記録して完了、`fail` は再実行とする。
- `fail` の場合は新しい `task_id` と `redo_of` を持つタスクを作る。
- 監査役は実装も報告書の書き換えも行わない。

## 再実行

1. 係長が元タスクの `failed` または監査役の `fail` を確認する。
2. 新しい `task_id` を作り、`redo_of` に元のIDを書く。
3. 原因を解消するための情報を `context` に追加する。
4. 担当者へ `redo` で通知する。
5. 必要なら `clear_command` でコンテキストをリセットする。
6. 完了後、同じ手順で報告と品質確認を行う。

## 待機と再開

- 通知後は待機する。`sleep`、ポーリング、tmux画面の監視は行わない。
- 通知で再開したときは自分のinboxを読み、未読を処理する。
- 係長は通知で再開したときに報告YAML全体を確認し、未反映の報告がないか照合する。
- エージェントは自分のタスクと報告だけを更新する。

## ダッシュボード

`dashboard.md` は係長が更新する。構成は次のとおり。

- 更新時刻
- 進行中のコマンド
- 進行中のタスク
- 品質確認の状況
- ブロッカー
- 要判断
- 直近の完了

部長は `dashboard.md` を読み、人間へ進捗を伝える。ダッシュボードは概要であり、正本はYAMLとする。

## アーカイブ

コマンドが `done` または `cancelled` になったら、係長が `queue/commands_archive.yaml` へ移す。
`queue/commands.yaml` には `pending` と `in_progress` だけを残す。
完了したタスクと報告は履歴として残し、削除しない。

## 完了条件

コマンドを `done` にするには、次をすべて満たす必要がある。

- すべての子タスクが `done` である。
- 受け入れ条件を満たす証拠がある。
- 必要な品質確認が完了している。
- `dashboard.md` が更新されている。
- 未解決のブロッカーや要判断が残っていない。
