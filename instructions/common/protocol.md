# 連携プロトコル

## 基本原則

- エージェント間の連絡は `scripts/inbox_write.sh` とYAMLファイルで行う。
- 通知はインフラが配送する。エージェントは `tmux send-keys` を実行しない。
- 待機はイベント駆動とする。`sleep`、ポーリング、画面監視は行わない。
- 文書は読んでから書く。他ロールが所有するファイルは編集しない。
- 秘密情報、認証情報、個人情報をキューや報告へ書かない。

## メールボックス

```bash
bash scripts/inbox_write.sh <target> "<message>" <type> <from>
```

例:

```bash
bash scripts/inbox_write.sh chief "cmd_001 を追加しました。内容を確認して着手してください。" cmd_new director
bash scripts/inbox_write.sh engineer1 "task_001 を割り当てました。YAMLを読んで着手してください。" task_assigned chief
bash scripts/inbox_write.sh chief "task_001 が完了しました。報告YAMLを確認してください。" report_received engineer1
bash scripts/inbox_write.sh auditor "task_001 の品質確認を依頼します。" qc_request chief
```

本文は短くし、詳細はファイルパスで示す。同じ内容を何度も送らない。

## inboxの形式

`queue/inbox/<id>.yaml` は次の形式とする。

```yaml
messages:
  - id: msg_20261026_120000_ab12cd34
    from: chief
    timestamp: "2026-10-26T12:00:00"
    type: task_assigned
    content: "task_001 を割り当てました。"
    read: false
```

- `id` は `inbox_write.sh` が生成する値を使う。
- `from` は自分のagent_idとする。
- `type` は用途を表す短い識別子とする。
- `read` は未読を `false`、既読を `true` とする。

## 主なメッセージ種別

| type | 用途 | 送信元から送信先 |
|---|---|---|
| `cmd_new` | 新しいコマンドの通知 | director から chief |
| `task_assigned` | タスク割当の通知 | chief から engineer / auditor |
| `report_received` | 報告完了の通知 | engineer / auditor から chief |
| `qc_request` | 品質確認の依頼 | chief から auditor |
| `qc_result` | 品質確認結果の通知 | auditor から chief |
| `task_rejected` | 担当範囲外の返却 | engineer3 から chief |
| `redo` | 再実行の依頼 | chief から engineer / auditor |
| `decision_needed` | 部長の判断依頼 | chief から director |
| `cmd_done` | コマンド完了の共有 | chief から director |
| `clear_command` | コンテキストリセットの依頼 | 係長から対象者（インフラが実行） |

## 受信と既読

`queue/inbox/<自分のagent_id>.yaml の未読メッセージを確認してください`
という通知を受けたら、次の順で処理する。
通知のパスが自分のagent_idと一致しない場合は、そのファイルを読まず、自分のinboxを読む。

1. `queue/inbox/{agent_id}.yaml` を読む。
2. `read: false` のメッセージをすべて確認する。
3. 種類に応じて処理する。
4. 処理したメッセージを `mark-as-read` ツールで既読にする。
5. 通常の作業へ戻る。

inboxの既読化は `.opencode/tools/mark-as-read.ts` の `mark-as-read` を使う。
`queue/inbox/*.yaml` を直接編集してはならない。

## 通知経路

- 部長は人間の窓口とする。人間からの依頼は部長がコマンド化する。
- 部長は係長へ通知する。エンジニアや監査役へ直接指示しない。
- 係長はエンジニアと監査役へタスクを割り当てる。
- エンジニアと監査役は係長へ報告する。
- 監査役の品質確認結果は係長が受け取り、コマンドの完了判断に使う。
- 部長への連絡は、判断が必要な場合とコマンド完了の共有に限る。

## 報告と品質確認

1. エンジニアは自分の報告YAMLを書く。
2. 自分のタスクを `done` または `failed` に更新する。
3. 係長へ `report_received` で通知する。
4. 係長は報告を確認し、必要なら監査役へ `qc_request` を送る。
5. 監査役は `auditor_report.yaml` に判定を書く。
6. 係長は判定を読み、完了、条件付き完了、再実行を決める。
7. 係長は `dashboard.md` を更新する。

## 再実行

再実行が必要な場合は、係長が新しい `task_id` を持つタスクを作り、`redo_of` に元のIDを書く。
担当者へは `redo` で通知する。必要なら `clear_command` でコンテキストをリセットする。
同じ `task_id` を再利用してはならない。

## コンテキストリセット

- コンテキストをリセットする場合は `/new` を使う。
- `/new` の前に、進捗、未完了点、次の手順をタスクまたは報告YAMLへ保存する。
- `/new` の後は `AGENTS.md`（自動読込）と自分のタスクだけを読み、状態を復元する。
- リセット後に過去の会話を前提にしない。

## ファイル操作

- 編集前に必ず対象ファイルを読む。
- 書き込み権限のあるファイルだけを編集する。
- 生成物は直接編集せず、源ファイルを直してビルドする。
- タイムスタンプは `date` コマンドで取得する。

```bash
date "+%Y-%m-%dT%H:%M:%S"
date "+%Y-%m-%d %H:%M"
```

## 禁止事項

- inboxの直接編集。
- `tmux send-keys` の実行。
- 他エージェントのタスク、報告、inboxの編集。
- 人間への無断連絡。
- ポーリングや固定回数の再試行。
- 証拠のない完了報告。
