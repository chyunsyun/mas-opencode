---
name: mas-model-switch
description: |
  mas_oc のエージェントモデルを稼働中に安全に切り替える。config/settings.yaml を更新し、
  生成物を再ビルドして対象ペインを再起動する。busy 中は --force なしでは拒否する。
  「モデル切替」「モデル変更」「engineer3 を○○に」「director のモデルを変えて」で起動。
  Do NOT use for: multi-agent-shogun（shogun-model-switch を使う）、モデル一覧の参照だけ（shogun-model-list を使う）。
argument-hint: "[agent-id] [--model provider/model] [--variant variant] [--max-bloom N] [--force]"
allowed-tools: Bash(bash scripts/switch_model.sh *), Bash(./mas status), Read
---

# mas-model-switch — mas_oc モデル切替

## Overview

mas_oc の `config/settings.yaml` を更新し、生成済みエージェント定義を再ビルドし、
対象ペインを新しいモデルで再起動する。実体は `scripts/switch_model.sh` である。

## 対象エージェント

`director`、`chief`、`engineer1`、`engineer2`、`engineer3`、`auditor`

## 基本手順

1. 対象と状態を確認する。

```bash
./mas status
```

2. busy でないことを確認して実行する。

```bash
bash scripts/switch_model.sh <agent_id> --model <provider/model>
```

オプション:

```bash
bash scripts/switch_model.sh <agent_id> \
  --model <provider/model> \
  [--variant <variant>] \
  [--max-bloom <N>] \
  [--force]
```

3. 結果を確認する。

```bash
./mas status
```

## busy 時の扱い

- busy 中に `--force` なしで実行すると、`switch_model.sh` は設定を変更せず終了コード 2 で拒否する。
- 作業中の会話や進捗を失う可能性があるため、原則として idle になるまで待つ。
- ユーザーが明示的に強制を承認した場合だけ `--force` を付ける。

```bash
bash scripts/switch_model.sh engineer3 --model opencode-go/deepseek-v4.1-flash --force
```

## 一括切替

1名ずつ実行し、busy で拒否されたら停止する。`--force` を付ける場合もユーザー確認を取る。

```bash
for agent in director chief engineer1 engineer2 engineer3 auditor; do
  bash scripts/switch_model.sh "$agent" --model <provider/model> || break
done
```

## 制約

- `config/settings.yaml`、`.opencode/agents/*.md`、`instructions/` を直接編集しない。必ず `scripts/switch_model.sh` を使う。
- `scripts/switch_cli.sh`、`/exit`、`@agent_cli`、`ashigaru` / `karo` / `gunshi` は使わない。これらは multi-agent-shogun 用である。
- `engineer3` の `max_bloom` は 3 を上限とする。
- `--model` を指定して `--variant` を省略すると、既存の variant は削除される。
- モデル ID は `provider/model` 形式で指定する。候補は `opencode models --verbose` で確認する。
- 設定の反映には対象ペインの再起動が必要である。`switch_model.sh` が自動で行う。

## Files

| ファイル | 役割 |
|---|---|
| `scripts/switch_model.sh` | settings 更新、再ビルド、ペイン再起動 |
| `lib/cli_adapter.sh` | モデル解決と起動コマンド生成 |
| `config/settings.yaml` | エージェントモデル設定（保護対象） |
| `docs/manual.md` | 運用手順 |
