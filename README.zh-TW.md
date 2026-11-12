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

### PowerShell 封鎖指令碼時

**僅允許 `AntigravityConnection.ps1`。** 請先在 Windows PowerShell 5.1 執行 `Get-ExecutionPolicy -List`。`MachinePolicy` 與 `UserPolicy` 由群組原則設定，優先於 CMD 入口為這次處理程序指定的 `RemoteSigned`。 [PowerShell 執行原則](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-5.1)

#### 檔案有下載標記

如果 `RemoteSigned` 因下載標記封鎖指令碼，請先確認來源並檢閱原始碼，再到解壓縮目錄中僅解除這個檔案的封鎖。也可以對檔案按一下滑鼠右鍵，開啟「內容」，在「一般」頁籤勾選「解除封鎖」並套用。

~~~powershell
Unblock-File -LiteralPath .\AntigravityConnection.ps1
~~~

#### 請系統管理員新增單一檔案允許規則

1. 如果電腦已透過 **AppLocker** 管理指令碼，請由系統管理員開啟適用的 AppLocker 原則。管理單台電腦時，可從 `secpol.msc` →「應用程式控制原則」→「AppLocker」→「指令碼規則」開啟。
2. 在現有的「指令碼規則」中選擇「建立新規則」，選取「允許」及需要執行指令碼的使用者或群組，再選取「檔案雜湊」，瀏覽並選取解壓縮後的 `AntigravityConnection.ps1`，然後建立並部署規則。明確的拒絕規則優先，請系統管理員一併檢查現有規則。 [建立檔案雜湊規則](https://learn.microsoft.com/windows/security/application-security/application-control/app-control-for-business/applocker/create-a-rule-that-uses-a-file-hash-condition) · [AppLocker 規則優先順序](https://learn.microsoft.com/windows/security/application-security/application-control/app-control-for-business/applocker/understanding-applocker-rule-behavior)
3. 安裝時，指令碼會將自身複製到 `%LOCALAPPDATA%\AntigravityConnection\AntigravityConnection.ps1`，供捷徑啟動。內容相同的兩份檔案可使用同一條雜湊規則。如果更新改變了指令碼內容，請系統管理員為新版更新雜湊規則。

如果組織使用 **App Control for Business（WDAC）**，請由系統管理員在適用原則中核准此指令碼。若群組原則強制 **AllSigned**，請使用由組織信任的發行者簽署的版本。若群組原則停用指令碼執行（**Restricted**），請由系統管理員依組織規範調整適用原則。解除下載標記只處理檔案的來源標記。 [App Control 指令碼原則](https://learn.microsoft.com/windows/security/application-security/application-control/app-control-for-business/design/script-enforcement) · [PowerShell 簽署](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-5.1)

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
