# 帰属情報

mas_oc は、既存プロジェクトを基にした非公式フォークです。配布物を利用または再配布する場合は、次の帰属情報を保持してください。

## 原プロジェクト

- 名称: multi-agent-shogun
- 作者: yohey-w
- リポジトリ: https://github.com/yohey-w/multi-agent-shogun
- ライセンス: MIT License
- 著作権: Copyright (c) 2026 yohey-w

## 上流の系譜

multi-agent-shogun は、Akira-Papa による Claude-Code-Communication をベースに開発されています。

- Claude-Code-Communication: https://github.com/Akira-Papa/Claude-Code-Communication

## フォークの位置付け

mas_oc は multi-agent-shogun の非公式フォークです。OpenCode 専用の実行環境、6名の固定編成、日本語の指示、独自の運用手順を追加しています。

mas_oc は原作者と提携しておらず、原作者による承認やサポートを受けていません。フォーク固有の問題や質問を原プロジェクトへ送らないでください。

## このフォークの主な変更

- OpenCode 専用化: OpenCode の起動、モデル指定、権限、コンテキストリセットに統一。
- 無料 AI によるコスト不要のマルチエージェント運用: OpenCode 用の無料モデルを利用でき、コストをかけずにマルチエージェントを運用できます。無料モデルの提供状況やレート制限は変わることがあります。
- ロール名の再編: `director`、`chief`、`engineer1`、`engineer2`、`engineer3`、`auditor` の6名構成。
- 日本語指示の自然化: 演技や過剰な装飾を除いた技術日本語のロール指示。
- エンジニア3名体制: `engineer3` を軽量タスク専用とし、`max_bloom: 3` を適用。
- 6ペイン1ウィンドウ（1画面完結）: tmux セッション `mas`、ウィンドウ `team` に3列2行で配置。縦長画面向けに2列3行も選択可能。
- 統一停止処理: watcher、補助プロセス、tmux、管理対象 cron、ロックファイルをリポジトリ単位で停止。
- 新しいマニュアル: README、クイックスタート、詳細マニュアル、帰属情報、コントリビューション、セキュリティ文書を再作成。
- キューの契約: `queue/inbox`、`queue/tasks`、`queue/reports`、`queue/commands.yaml`、`queue/pending.yaml`、`dashboard.md` を中心とした状態管理。
- 権限の生成: `config/opencode-permissions.yaml` からロール別の OpenCode 権限を生成。

## 履歴の保持

上流プロジェクトの `CHANGELOG.md` は履歴として保持しています。mas_oc のバージョンは `./mas version` で確認できます。現在のバージョンは `1.0.0` です。

## ライセンス

mas_oc は MIT License で配布されます。著作権表示と許諾表示は [LICENSE](../LICENSE) にあります。原プロジェクトの著作権表示も保持してください。

## 連絡先

mas_oc に関する問題は、このリポジトリの管理元へ報告してください。原プロジェクトの連絡先やセキュリティ報告窓口を、フォーク固有の問題に使用しないでください。
