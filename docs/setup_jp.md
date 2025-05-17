# Vibe Blocks MCP ローカル環境セットアップ手順

## 1. 環境準備

### 必要なソフトウェア
- Python 3.10以上
- Roblox Studio
- Cursor (AI コーディングエディタ)
- Rojo
- Git

### 環境変数ファイルの作成
プロジェクトのルートディレクトリに `.env` ファイルを作成し、以下の内容を記述します:
```
# Roblox API Configuration
ROBLOX_API_KEY=dummy_api_key
ROBLOX_UNIVERSE_ID=0
ROBLOX_PLACE_ID=0

# MCP Server Configuration
MCP_SERVER_PORT=8001
DEBUG=False
```

この設定はMCPサーバーの起動に必須です。設定値はダミーでも問題ありませんが、実際のRobloxプロジェクトで利用する場合は適切な値に変更してください。

### 仮想環境のセットアップ
```bash
# リポジトリのクローン
git clone https://github.com/majidmanzarpour/vibe-blocks-mcp.git
cd vibe-blocks-mcp

# 仮想環境の作成と有効化
python -m venv .venv
source .venv/Scripts/activate  # Windows (bash)
# source .venv/bin/activate    # macOS/Linux

# 依存関係のインストール
pip install -e .
```

## 2. MCP サーバーの起動

### ポート8001を使用する場合
```bash
# 仮想環境が有効化されていることを確認
# プロンプトの先頭に (.venv) と表示されているはず

# サーバーの起動
uvicorn src.roblox_mcp.server:app --reload --port 8001
```

## 3. Roblox Studio プラグインの設定

### プラグインのビルド
```bash
# プロジェクトのルートディレクトリで
cd roblox_mcp_plugin

# プラグインのビルド
rojo build default.project.json --output VibeBlocksMCP_Companion.rbxm
```

### プラグインのインストール
1. 生成された `VibeBlocksMCP_Companion.rbxm` を Roblox Studio のプラグインフォルダにコピー
   - Windows: `%LOCALAPPDATA%\Roblox\Plugins`
   - macOS: `~/Documents/Roblox/Plugins`
2. Roblox Studio を再起動

## 4. Cursor の設定

1. Cursor を起動
2. `File > Settings > MCP` (または `Code > Settings > MCP` on Mac) を開く
3. "Add New Global MCP Server" をクリック
4. SSE URL に `http://localhost:8001/sse` を入力

## 5. 動作確認

1. Roblox Studio を起動
2. Studio の Output ウィンドウでプラグインの接続ログを確認
3. Cursor で AI に簡単な指示を出してテスト
   - 例: 「`Workspace` に赤いパーツを作成して」

## 注意点

### ポート番号の変更について
- ポート8001を使用する場合、以下の2箇所の設定を確認する必要があります：
  1. MCP サーバー起動時のポート番号 (`--port 8001`)
  2. Cursor の MCP 設定の SSE URL (`http://localhost:8001/sse`)
  3. Roblox プラグインの `SERVER_URL` 設定 (`http://localhost:8001/plugin_command`)

### プラグインの再ビルド
- プラグインの設定を変更した場合は、必ず再ビルドが必要です
- 再ビルド後は、新しい `.rbxm` ファイルを Studio のプラグインフォルダに上書きコピー
- Studio を再起動するか、プラグインをリロード

### 仮想環境について
- 仮想環境は Python の依存関係管理のためだけのもの
- Rojo のビルドは仮想環境の有無に関係なく実行可能
- MCP サーバーを起動する際は必ず仮想環境を有効化する必要がある

### トラブルシューティング
- ポート8000が使用中の場合は、上記の手順で8001を使用
- プラグインが接続できない場合は、`SERVER_URL` の設定を確認
- 依存関係のエラーが出る場合は、`pip install -e .` を実行して再インストール
- サーバー起動時に「No tools available」エラーが表示される場合は、`.env` ファイルが正しく作成されているか確認
- サーバーログに「Failed to load configuration」エラーが表示される場合も、`.env` ファイルの内容を確認

## 6. 作業終了時の手順

### 仮想環境の終了
```bash
# 仮想環境を終了するには、以下のコマンドを実行
deactivate

# プロンプトの先頭の (.venv) が消えることを確認
```

### サーバーの停止
- MCP サーバーを実行しているターミナルで `Ctrl+C` を押してサーバーを停止
- 必要に応じて、Roblox Studio も終了 