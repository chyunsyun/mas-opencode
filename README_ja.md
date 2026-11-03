# mas_oc

mas_oc は、ローカルリポジトリ向けの OpenCode 専用マルチエージェント開発環境です。OpenCode 用の無料 AI モデルを利用できるため、追加コストなしでマルチエージェント運用を始められます。6名の固定チームは1つの tmux ウィンドウの6ペインに収まり、1画面で完結します。コマンド、タスク、報告は YAML で受け渡し、キューを正本とするため、再起動やコンテキストリセットの後も作業を復元できます。

本リポジトリは [multi-agent-shogun](https://github.com/yohey-w/multi-agent-shogun) の非公式フォークです。OpenCode 専用の構成と6名の小規模チームに再設計しています。

## 特徴

- OpenCode 専用。各ペインで OpenCode を起動し、他の CLI は管理しません。
- OpenCode 用の無料 AI モデルを利用した、コストをかけないマルチエージェント運用。無料モデルの提供状況やレート制限は変わり得ます。
- 1画面完結。6ペインを1つの tmux ウィンドウに表示するため、チーム全体を同じ画面で運用できます。
- 6名の固定編成と明確な指揮系統。
- inbox、タスク、報告によるイベント駆動の連携。
- YAML を正本とした状態管理。再起動やコンテキストリセット後も復元できます。
- 1つの権限マトリクスからロール別の OpenCode 権限を生成。
- `max_bloom` による軽量タスクの担当制限。
- 実行データはリポジトリ内に閉じます。

## チーム

| agent_id | 表示名 | 役割 |
|---|---|---|
| `director` | 部長 | 人間の窓口、コマンド作成、最終判断 |
| `chief` | 係長 | 分解、割当、進捗管理、品質確認の取り回し |
| `engineer1` | エンジニア1 | 実装、テスト、報告 |
| `engineer2` | エンジニア2 | 実装、テスト、報告 |
| `engineer3` | エンジニア3 | 軽量タスク専用。Bloom L1-L3、`max_bloom: 3` |
| `auditor` | 監査役 | 独立した品質確認、証拠に基づく判定、原因分析 |

指揮系統は次のとおりです。

```
人間 <-> 部長 <-> 係長 <-> エンジニア1 / エンジニア2 / エンジニア3
                    <-> 監査役
```

部長はエンジニアや監査役へ直接指示しません。係長がタスクを作成して割り当て、エンジニアと監査役は係長へ報告します。

## 動作環境

- Linux、macOS、WSL2
- bash
- tmux
- python3 と PyYAML
- OpenCode (`opencode`)
- `inotifywait` は任意。未導入の場合はポーリングで動作します。

OpenCode のバイナリが標準外の場所にある場合は `OPENCODE_BIN` で指定できます。既定のレイアウトには約 240x50 の端末を推奨します。

## クイックスタート

```bash
cd mas_oc
./mas setup
# 有料プロバイダーを使う場合のみ
opencode auth login
# 必要ならモデルを変更
$EDITOR config/settings.yaml
./mas build
./mas start
```

`./mas setup` は `config/settings.yaml.sample` から `config/settings.yaml` を作成し、キューを初期化してエージェント定義を生成します。初回は `opencode models --verbose` から無料モデルを自動選択し、`opencode/*-free` を優先します（利用できない場合のみ `opencode-go/*-free` を候補にします）。director / chief / auditor / engineer1 / engineer2 は高能力モデル、engineer3 は速度優先モデルを使い、`capability_tiers` は高能力4 / engineer3 3 に設定します。既存の `model` は上書きしません。

再選択は `./mas setup --select-free-model`、明示指定は `./mas setup --free-model provider/model`、自動選択の無効化は `./mas setup --no-select-free-model` です。モデル一覧の更新は既定で `opencode models --refresh` を実行し、失敗時はキャッシュを使います。`--no-refresh-free-models` でキャッシュのみにできます。無料モデルを取得できない場合は `model` を空欄のままセットアップを継続します。

同じ `mas_oc` が稼働中の場合、`./mas setup` は実行中エージェントに設定が反映されないため拒否します。停止後に実行するか、強制する場合だけ `--allow-running` を指定してください（実行中エージェントは再起動まで旧設定のままです）。

`./mas start` は既定で15秒間隔で6名を起動するため、完了まで約75秒かかります。`./mas start` が自動でビルドするのは `.opencode/agents/director.md` が存在しない場合だけです。設定や指示の源ファイルを変更したら `./mas build` を実行してください。

## コマンド

| コマンド | 動作 |
|---|---|
| `./mas setup` | 初回セットアップ、無料モデル自動選択、エージェント生成 |
| `./mas setup --select-free-model` | 既存設定でも無料モデルを再選択 |
| `./mas setup --no-select-free-model` | 無料モデルの自動選択を無効化 |
| `./mas setup --free-model provider/model` | 指定した無料モデルを全エージェントに設定 |
| `./mas setup --no-refresh-free-models` | キャッシュ済みのモデル一覧を使う |
| `./mas setup --allow-running` | 稼働中でも設定を変更する（実行中エージェントには未反映） |
| `./mas start` | 6名を1つの tmux ウィンドウで起動 |
| `./mas start --clean` | キューをバックアップして初期化し、起動 |
| `./mas start --purge --yes` | 使用履歴をバックアップなしで完全削除し、無料モデルへ初期化して起動 |
| `./mas start --setup-only` | OpenCode と watcher を起動せず、tmux と設定だけを作成 |
| `./mas start --no-auto` | OpenCode に `--auto` を渡さない |
| `./mas start --layout 2x3` | 縦長画面向けに2列3行で起動 |
| `./mas start --start-interval SEC` | OpenCode の起動間隔を指定（既定15秒） |
| `./mas status` | ペイン状態、タスク状態、未読 inbox 数を表示 |
| `./mas stop` | 対象プロセス、ペイン、セッション、管理対象 cron を停止 |
| `./mas stop --verify` | 停止せずに残存プロセスを検査 |
| `./mas build` | `.opencode/agents/*.md` と `AGENTS.md` を再生成 |
| `./mas switch-model <agent> --model <provider/model> [--force]` | モデルを変更し、再ビルドしてペインを再起動。busy時は `--force` が必要 |
| `./mas dashboard` | `dashboard.md` を `http://127.0.0.1:8787` で表示 |
| `./mas version` | バージョンを表示 |

`./mas start --purge --yes` は取り消しできません。`queue/`、`dashboard.md`、`memory/MEMORY.md`、`memory/global_context.md`、`logs/`、`reports/`、`status/`、`run/` の履歴を削除し、6名のモデルを無料モデルへ再選択します。バックアップは作成しません。無料モデルを選択できない場合は `openrouter/free` に設定します。OpenCode 本体のセッション履歴（`~/.local/share/opencode`）は削除しません。

`./mas stop` は冪等で、再実行しても安全です。このリポジトリと `mas` tmux セッションの範囲だけを停止し、全体の `pkill` は実行しません。

## レイアウト

既定は3列2行です。

```
+-----------+-----------+-----------+
| director  | chief     | auditor   |
+-----------+-----------+-----------+
| engineer1 | engineer2 | engineer3 |
+-----------+-----------+-----------+
```

tmux セッションは `mas`、ウィンドウは `team` です。縦長の端末では `./mas start --layout 2x3` を使用してください。

## モデルルーティング

モデルはエージェントごとに設定します。

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

`engineer3` には Bloom レベル1から3のタスクだけを割り当てます。レベル4以上では `engineer3` を除外し、他のエンジニアへの割当、モデル切替、またはエスカレーションが必要です。割当判定は `find_engineer_for_bloom` が行います。実効的な `max_bloom` は、モデルの能力上限とエージェント固有の上限の小さい方です。

初回セットアップでは `opencode models --verbose` の `cost` が0のモデルから、`opencode/*-free` を優先して選択します。`opencode-go/*-free` は `opencode` の無料モデルが使えない場合のフォールバックです。director / chief / auditor / engineer1 / engineer2 は高能力モデル、engineer3 は速度優先モデル（`flash` / `lightning` 系を優先）を使います。選択結果は `model_selection` に、能力上限は `capability_tiers` に記録されます。

自動選択時の `capability_tiers` は、高能力モデルが `max_bloom: 4`、engineer3 の速度優先モデルが `max_bloom: 3` です。高能力モデルでも Bloom L5/L6 は上限4を超えるため、必要なら `./mas switch-model` で上位モデルへ切り替えるか、`capability_tiers` を手動で調整してください。engineer3 の `max_bloom: 3` は維持されます。

既存の `model` は自動選択で上書きしません。再選択は `./mas setup --select-free-model`、明示指定は `./mas setup --free-model provider/model`、無効化は `./mas setup --no-select-free-model` です。`opencode models --refresh` が失敗した場合はキャッシュを使い、無料モデルがなければ `model` を空欄のままにします。無料モデルは提供状況やレート制限が変わるため、`opencode models --verbose` で定期的に確認してください。

`./mas switch-model` は `config/settings.yaml` を更新し、生成済みエージェントを再ビルドして、対象ペインを再起動します。対象がbusyの場合は設定を変更せずに拒否します。強制再起動はユーザーの明示的な承認がある場合だけ `--force` を付けてください。

## キューと実行データ

| パス | 用途 |
|---|---|
| `queue/inbox/<id>.yaml` | エージェント間メッセージ |
| `queue/tasks/<id>.yaml` | エージェントごとのアクティブタスク |
| `queue/reports/<id>_report.yaml` | エンジニアと監査役の報告 |
| `queue/commands.yaml` | 未完了のコマンド |
| `queue/pending.yaml` | 保留中の作業 |
| `dashboard.md` | 人間向けの進捗概要 |

inbox のメッセージは `id`、`from`、`timestamp`、`type`、`content`、`read` を持ちます。送信には次を使います。

```bash
bash scripts/inbox_write.sh <target> "<message>" <type> <from>
```

処理済みメッセージの既読化には OpenCode の `mark-as-read` ツール（`.opencode/tools/mark-as-read.ts`）を使います。inbox の YAML を直接編集しないでください。

実行データは `mas_oc` 配下の `run/`、`logs/`、`status/`、`queue/` に保存します。`~/.tmux.conf` や `~/.claude` には書き込みません。外部に残る状態は OpenCode の認証だけです。

## セキュリティ

既定では `./mas start` が OpenCode に `--auto` を渡し、権限要求を自動承認します。手動承認にしたい場合は `./mas start --no-auto` を使ってください。ロール別の権限は `config/opencode-permissions.yaml` で定義し、`.opencode/agents/*.md` に生成します。秘密情報や認証情報をキュー、ログ、報告へ書かないでください。

## ドキュメント

- [クイックスタート](docs/quickstart.md)
- [マニュアル](docs/manual.md)
- [帰属情報](docs/attribution.md)
- [コントリビューション](CONTRIBUTING.md)
- [セキュリティ](SECURITY.md)
- [変更履歴](CHANGELOG.md)

## 帰属

- 原プロジェクト: multi-agent-shogun by yohey-w, https://github.com/yohey-w/multi-agent-shogun
- ライセンス: MIT, Copyright (c) 2026 yohey-w
- Claude-Code-Communication by Akira-Papa をベースに開発
- mas_oc は改変を含む非公式フォークであり、原作者とは提携していません。

詳細は [docs/attribution.md](docs/attribution.md) と [NOTICE](NOTICE) を参照してください。

## ライセンス

MIT。[LICENSE](LICENSE) を参照してください。
