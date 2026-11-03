# mas_oc ドキュメント

mas_oc は、OpenCode 専用のマルチエージェント開発環境です。6名の固定チームが tmux の1ウィンドウで動作し、YAML のコマンド、タスク、報告を通じて連携します。

## 特徴

1. OpenCode 専用: 起動、モデル指定、権限、コンテキストリセットを OpenCode に統一しています。
2. 無料 AI によるコスト不要のマルチエージェント運用: OpenCode 用の無料モデルを利用でき、コストをかけずにマルチエージェントを運用できます。無料モデルの提供状況やレート制限は変わり得ます。
3. 1画面完結: 6ペインを1つの tmux ウィンドウに表示し、1画面でチーム全体を操作できます。

## まず読む

- [クイックスタート](quickstart.md) — セットアップから最初の起動まで
- [マニュアル](manual.md) — 設定、運用、キュー契約、トラブルシューティング
- [帰属情報](attribution.md) — 原プロジェクト、ライセンス、このフォークの変更点

## リポジトリ案内

- [README（日本語）](../README_ja.md) — 概要とコマンド一覧
- [README（英語）](../README.md) — English landing page
- [コントリビューション](../CONTRIBUTING.md) — 開発手順と生成物の扱い
- [セキュリティ](../SECURITY.md) — 脆弱性報告と権限の考え方
- [変更履歴](../CHANGELOG.md) — 上流の履歴を保持

## チーム構成

| agent_id | 表示名 | 役割 |
|---|---|---|
| `director` | 部長 | 人間の窓口、コマンド作成、最終判断 |
| `chief` | 係長 | 分解、割当、進捗管理、品質確認の取り回し |
| `engineer1` | エンジニア1 | 実装、テスト、報告 |
| `engineer2` | エンジニア2 | 実装、テスト、報告 |
| `engineer3` | エンジニア3 | 軽量タスク専用。`max_bloom: 3` |
| `auditor` | 監査役 | 独立した品質確認、原因分析、判定 |

## 最短手順

```bash
./mas setup
opencode auth login
opencode models
$EDITOR config/settings.yaml
./mas build
./mas start
```

起動後は `tmux attach -t mas` で接続し、`./mas status` で状態を確認できます。停止は `./mas stop` です。

## 帰属

- 原プロジェクト: multi-agent-shogun by yohey-w, https://github.com/yohey-w/multi-agent-shogun
- ライセンス: MIT, Copyright (c) 2026 yohey-w
- Claude-Code-Communication by Akira-Papa をベースに開発
- mas_oc は改変を含む非公式フォークであり、原作者とは提携していません。

詳細は [帰属情報](attribution.md) を参照してください。
