# Antigravity Connection Tools

[简体中文](README.md) · 繁體中文 · [English](README.en.md) · [日本語](README.ja.md)

在 Windows 上切換 Google Antigravity 的連線方式。腳本會設定目前使用者的桌面與「開始」功能表捷徑，並備份原始捷徑，以便日後還原。

## 使用方式

需要 Windows、Windows PowerShell 5.1，以及已安裝的 Google Antigravity。解壓縮或複製儲存庫後，請將三個 CMD 檔案與 AntigravityConnection.ps1 放在同一個資料夾。

| 按兩下執行 | 用途 |
| --- | --- |
| 01-Use-Windows-Proxy.cmd | 一鍵使用 Windows 手動 Proxy 設定。Antigravity 每次啟動時都會讀取目前的代理伺服器與連接埠。 |
| 02-Choose-Connection.cmd | 選擇 Windows 手動 Proxy（1）、自訂代理伺服器（2），或直接連線／TUN（3）。 |
| 03-Restore-Original.cmd | 還原原始捷徑與預設啟動方式。 |

切換或還原設定後，如果 Antigravity 仍在執行，請先正常結束程式，再從桌面或「開始」功能表中已設定的捷徑重新開啟。若要從工作列啟動，請將已設定的「開始」功能表捷徑重新釘選到工作列。

### 重新啟動 Windows 或更換代理軟體

01-Use-Windows-Proxy.cmd 只需執行一次。重新啟動 Windows 或更換代理軟體後，先在該軟體啟用 Windows 系統 Proxy，再從已設定的捷徑開啟 Antigravity。代理伺服器的位址或連接埠變更後，會在下次啟動時套用。如果只使用 TUN，請執行 02-Choose-Connection.cmd 並選擇 3。

如果 Windows 或 Antigravity 更新後重新建立了捷徑，請再次執行設定腳本。腳本會先備份仍指向同一套 Antigravity 的捷徑，再為它設定代理伺服器。無法辨識的捷徑會保留原樣。

### 從 GitHub 下載 ZIP

解壓縮後，如果 PowerShell 提示腳本來自網際網路且未簽署，請先檢閱原始碼，再解除該檔案的封鎖。 [PowerShell 執行原則](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies)

~~~powershell
Unblock-File -LiteralPath .\AntigravityConnection.ps1
~~~

### 自訂代理伺服器

代理伺服器位址可使用下列格式。省略通訊協定時，會以 HTTP 處理。

~~~text
127.0.0.1:8080
http://proxy.example.com:8080
https://proxy.example.com:443
socks5://127.0.0.1:1080
socks5h://[::1]:1080
~~~

如果代理伺服器需要驗證，請依提示分別輸入使用者名稱與密碼。腳本使用目前 Windows 使用者的 DPAPI 加密儲存認證資料，並將其提供給 Antigravity 後端。Chromium 介面與外部瀏覽器如需使用有驗證的代理伺服器，請分別設定。

若使用 PAC／WPAD、SOCKS4、Shadowsocks、VMess、VLESS 或 Trojan，請選用代理軟體提供的本機 HTTP 或 SOCKS5 連接埠。若使用 TUN，請選擇「直接連線／TUN」，由 Windows 處理網路路由。選擇 Windows 手動 Proxy 模式時，腳本會將手動設定的代理伺服器位址傳給 Antigravity 後端。Chromium 介面會依 Windows 設定處理 PAC 與 Proxy 例外。

### 還原原始設定

設定與捷徑備份存放在 %LOCALAPPDATA%\AntigravityConnection。還原腳本會恢復由此工具設定的捷徑。如果某個捷徑之後被其他程式替換，腳本會顯示其路徑，並保留目前的捷徑和原始備份。

## 驗證

請在儲存庫根目錄執行下列命令。測試會建立暫時的捷徑，檢查代理參數是否傳到子處理程序、設定是否可重複套用，以及捷徑能否逐位元組還原。

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\Verify-AntigravityConnection.ps1
~~~
