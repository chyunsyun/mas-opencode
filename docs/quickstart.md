# クイックスタート

このページでは、mas_oc を初めて起動し、最初の依頼を出すまでの手順を説明します。詳細は [マニュアル](manual.md) を参照してください。

## 1. 前提を確認する

次のコマンドが使えることを確認します。

```bash
bash --version
tmux -V
python3 -c 'import yaml; print("PyYAML OK")'
opencode --version
```

OpenCode が見つからない場合は、公式の手順でインストールし、`PATH` を通してください。標準外の場所にバイナリがある場合は、後で `OPENCODE_BIN` を指定できます。

`inotifywait` は必須ではありません。未導入の場合は inbox の監視がポーリングに切り替わります。

既定の6ペインを快適に表示するには、約 240x50 の端末を推奨します。縦長の画面では `--layout 2x3` を使います。

## 2. セットアップする

リポジトリのルートで次を実行します。

```bash
./mas setup
```

mas_oc は OpenCode 専用です。セットアップでは OpenCode 用の無料モデルを自動選択できるため、コストをかけずにマルチエージェントを運用できます。6ペインは1つの tmux ウィンドウに表示され、1画面で完結します。無料モデルの提供状況やレート制限は変わり得ます。

主な処理は次のとおりです。

- `config/settings.yaml` を `config/settings.yaml.sample` から作成
- `opencode models --verbose` から無料モデルを自動選択（既存の `model` は上書きしない）
- `queue/`、`run/`、`logs/`、`status/` などの初期化
- 各エージェントの inbox、タスク、報告ファイルの作成
- `scripts/build_instructions.sh` による `.opencode/agents/*.md` と `AGENTS.md` の生成

無料モデルは `opencode/*-free` を優先し、director / chief / auditor / engineer1 / engineer2 は高能力モデル、engineer3 は速度優先モデルを使います。`capability_tiers` は高能力4 / engineer3 3 に設定されます。再選択は `./mas setup --select-free-model`、明示指定は `./mas setup --free-model provider/model`、無効化は `./mas setup --no-select-free-model`、キャッシュ利用は `./mas setup --no-refresh-free-models` です。無料モデルを取得できない場合は `model` を空欄のままセットアップを継続します。

稼働中の `mas_oc` を検出すると `./mas setup` は拒否します。停止後に実行するか、強制する場合だけ `--allow-running` を指定してください。

`opencode` が見つからない場合、セットアップは警告を出して続行しますが、起動には OpenCode が必要です。

## 3. OpenCode に認証する

mas_oc は OpenCode の認証情報をそのまま使います。設定ファイルに API キーを書く必要はありません。

```bash
opencode auth login
```

利用するプロバイダーを選び、案内に従って認証します。

## 4. モデルを確認する

初回セットアップでは無料モデルが自動選択されるため、通常はこの手順は不要です。モデルを変更する場合だけ確認します。

```bash
opencode models --verbose
```

`cost` が0の無料モデルを `opencode/*-free` 優先で選びます。`opencode-go/*-free` はフォールバックです。無料モデルは提供状況やレート制限が変わるため、実際の一覧を確認してください。

## 5. モデルを設定する

初回セットアップでは無料モデルが自動選択され、`config/settings.yaml` に書き込まれます。`opencode/*-free` を優先し、director / chief / auditor / engineer1 / engineer2 は高能力モデル、engineer3 は速度優先モデルを使います。`capability_tiers` は高能力4 / engineer3 3 に設定され、選択結果は `model_selection` に記録されます。既存の `model` は上書きしません。

再選択は `./mas setup --select-free-model`、明示指定は `./mas setup --free-model provider/model`、自動選択の無効化は `./mas setup --no-select-free-model` です。既定では `opencode models --refresh` を実行し、失敗時はキャッシュを使います。`--no-refresh-free-models` でキャッシュのみにできます。無料モデルが取得できない場合は `model` を空欄のままセットアップを継続します。

手動で変更する場合は `config/settings.yaml` の `model` を編集します。

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
```

`engineer3` の `max_bloom: 3` は変更しないでください。高能力モデルの自動設定は `max_bloom: 4` です。Bloom L5/L6 が必要な場合は `./mas switch-model` で上位モデルへ切り替えるか、`capability_tiers.<model>.max_bloom` を手動で調整してください。実効的な `max_bloom` は、モデルの能力上限とエージェント固有の上限の小さい方です。

## 6. ビルドして起動する

```bash
./mas build
./mas start
```

`./mas build` は設定を反映したエージェント定義を再生成します。`./mas start` が自動でビルドするのは `.opencode/agents/director.md` が存在しない場合だけです。設定を変えたら必ず `./mas build` を実行してください。

起動に成功すると、tmux セッション `mas`、ウィンドウ `team` に6ペインが作成されます。OpenCode の起動間隔は既定で15秒です。6名を順番に起動するため、完了まで約75秒かかります。間隔は `MAS_START_INTERVAL` または `--start-interval` で変更できます。

```
+-----------+-----------+-----------+
| director  | chief     | auditor   |
+-----------+-----------+-----------+
| engineer1 | engineer2 | engineer3 |
+-----------+-----------+-----------+
```

## 7. 画面に接続する

```bash
tmux attach -t mas
```

切断するときは `Ctrl-b` を押してから `d` を押します。セッションはバックグラウンドで動き続けます。

## 8. 最初の依頼を出す

接続後、`director`（部長）のペインで依頼を入力します。部長がコマンドを作成し、係長へ渡します。係長がタスクへ分解し、エンジニアまたは監査役へ割り当てます。

進捗は次のどちらかで確認できます。

```bash
./mas status
./mas dashboard
```

`./mas dashboard` は `dashboard.md` を `http://127.0.0.1:8787` で表示します。

## 9. 停止する

```bash
./mas stop
```

停止後もキューと報告は残ります。次回の起動で状態を復元できます。停止処理が冪等なので、再実行しても安全です。残存プロセスだけを確認したい場合は次を使います。

```bash
./mas stop --verify
```

## よくある詰まり

- `opencode: command not found` — `PATH` を確認するか `OPENCODE_BIN` を設定してください。
- `agent not found` — `./mas build` を実行してください。
- 6ペインが作成できない — 端末を広げるか `./mas start --layout 2x3` を使ってください。
- モデルエラー — `opencode models` で ID を確認し、`provider/model` 形式で設定してください。
- 残存プロセスがある — `./mas stop --verify` で確認し、必要なら `./mas stop` を再実行してください。

## 帰属

- 原プロジェクト: multi-agent-shogun by yohey-w, https://github.com/yohey-w/multi-agent-shogun
- ライセンス: MIT, Copyright (c) 2026 yohey-w
- Claude-Code-Communication by Akira-Papa をベースに開発
- mas_oc は改変を含む非公式フォークであり、原作者とは提携していません。

詳細は [帰属情報](attribution.md) を参照してください。
