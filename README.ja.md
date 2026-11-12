# Antigravity Connection Tools

[简体中文](README.md) · [繁體中文](README.zh-TW.md) · [English](README.en.md) · 日本語

Windows で Google Antigravity の接続方法を切り替えるツールです。現在のユーザーのデスクトップとスタートメニューのショートカットを設定し、元に戻せるように元のショートカットをバックアップします。

## 使い方

Windows、Windows PowerShell 5.1、および Google Antigravity が必要です。ZIP を展開するかリポジトリをクローンしたら、3 つの CMD ファイルと `AntigravityConnection.ps1` を同じフォルダーに置いてください。

| ダブルクリックするファイル | 動作 |
| --- | --- |
| `01-Use-Windows-Proxy.cmd` | Windows の手動プロキシ設定を使用します。Antigravity の起動時に、その時点のプロキシサーバーとポートを読み込みます。 |
| `02-Choose-Connection.cmd` | Windows の手動プロキシ（1）、カスタムプロキシ（2）、または直接接続／TUN（3）を選びます。 |
| `03-Restore-Original.cmd` | 元のショートカットと既定の起動方法を復元します。 |

接続方法を変更した後や設定を復元した後は、Antigravity が起動中であれば終了し、デスクトップまたはスタートメニューの設定済みショートカットから開き直してください。タスクバーから起動する場合は、設定済みのスタートメニューのショートカットをピン留めし直してください。

### Windows を再起動した場合やプロキシクライアントを変更した場合

`01-Use-Windows-Proxy.cmd` の実行は初回だけで済みます。Windows の再起動後やプロキシクライアントの変更後は、クライアントで Windows のシステムプロキシを有効にしてから、設定済みのショートカットで Antigravity を開いてください。アドレスやポートの変更は次回起動時に反映されます。TUN のみを使う場合は、`02-Choose-Connection.cmd` を実行し、3 を選んでください。

### GitHub から ZIP をダウンロードした場合

展開したスクリプトについて、PowerShell がインターネットから取得した未署名のファイルだと表示した場合は、ソースを確認したうえで対象ファイルのブロックを解除してください。 [PowerShell の実行ポリシー](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies)

~~~powershell
Unblock-File -LiteralPath .\AntigravityConnection.ps1
~~~

### カスタムプロキシ

以下の形式でプロキシアドレスを入力できます。スキームを省略すると HTTP として扱います。

~~~text
127.0.0.1:8080
http://proxy.example.com:8080
https://proxy.example.com:443
socks5://127.0.0.1:1080
socks5h://[::1]:1080
~~~

認証が必要な場合は、入力を求められたときにユーザー名とパスワードを指定してください。認証情報は現在の Windows ユーザーの DPAPI で暗号化して保存し、Antigravity のバックエンドに渡します。Chromium ベースの画面や外部ブラウザーで認証付きプロキシを使う場合は、それぞれの設定が必要です。

PAC／WPAD、SOCKS4、Shadowsocks、VMess、VLESS、Trojan などを使う場合は、プロキシクライアントが提供するローカルの HTTP または SOCKS5 ポートを指定してください。TUN を使う場合は、直接接続／TUN を選ぶと Windows が通信をルーティングします。Windows の手動プロキシを使うモードでは、手動で設定されたプロキシアドレスをバックエンドに渡します。Chromium ベースの画面では、Windows の PAC 設定とプロキシの例外設定が適用されます。

### 元の設定に戻す

設定とショートカットのバックアップは `%LOCALAPPDATA%\AntigravityConnection` に保存されます。復元スクリプトは、このツールで設定したショートカットを元に戻します。別のプログラムがその後ショートカットを置き換えた場合は、対象のパスを表示し、現在のショートカットと元のバックアップを両方残します。

## 動作確認

リポジトリのルートで以下を実行してください。テストでは一時的なショートカットを使い、プロキシ設定が子プロセスに渡ること、設定を繰り返し適用できること、元のファイルをバイト単位で復元できることを確認します。

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\Verify-AntigravityConnection.ps1
~~~
