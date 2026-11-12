# Antigravity Connection Tools

简体中文 · [繁體中文](README.zh-TW.md) · [English](README.en.md) · [日本語](README.ja.md)

在 Windows 上切换 Google Antigravity 的代理连接。脚本为当前用户的桌面和开始菜单快捷方式设置启动参数，并备份原始快捷方式供回退。

## 使用方法

需要 Windows、Windows PowerShell 5.1 和已安装的 Google Antigravity。解压或克隆后，请把三个 CMD 文件和 AntigravityConnection.ps1 放在同一个目录。

| 双击运行 | 用途 |
| --- | --- |
| 01-Use-Windows-Proxy.cmd | 一键跟随 Windows 手动代理。Antigravity 每次启动时读取当前代理服务器和端口。 |
| 02-Choose-Connection.cmd | 选择 Windows 手动代理、自定义代理或直连／TUN。 |
| 03-Restore-Original.cmd | 恢复原始快捷方式及默认启动行为。 |

切换或回退后，请正常退出正在运行的 Antigravity，再从桌面或当前用户的开始菜单启动。若要从任务栏使用代理设置，请从已配置的开始菜单入口重新固定。

### 重启电脑或更换代理客户端

01-Use-Windows-Proxy.cmd 只需运行一次。电脑重启或更换代理客户端后，先开启客户端的 Windows 系统代理，再从已配置的快捷方式打开 Antigravity。代理地址或端口改变时，应用会在下次启动时读取新设置。若当前客户端只开了 TUN，请用 02-Choose-Connection.cmd 切到「直连／TUN」。

如果 Windows 或 Antigravity 更新后重建了快捷方式，请重新运行设置脚本。脚本会备份仍指向同一 Antigravity 安装的快捷方式，再为它配置代理。无法识别的快捷方式会保留原样。

### 从 GitHub 下载 ZIP

如果从 GitHub 下载的 ZIP 解压后，PowerShell 提示脚本来自网络且未经签名，请先审阅源码，再对脚本文件执行解除锁定。 [PowerShell 执行策略](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies)

~~~powershell
Unblock-File -LiteralPath .\AntigravityConnection.ps1
~~~

### 自定义代理

可以直接输入以下格式。省略协议时按 HTTP 处理。

~~~text
127.0.0.1:8080
http://proxy.example.com:8080
https://proxy.example.com:443
socks5://127.0.0.1:1080
socks5h://[::1]:1080
~~~

如需认证，在提示时分别输入用户名和密码。脚本用当前 Windows 用户的 DPAPI 加密保存凭据，并向 Antigravity 后端提供这些凭据。Chromium 界面和外部浏览器需要各自的认证代理配置。

对于 PAC／WPAD、SOCKS4、Shadowsocks、VMess、VLESS、Trojan 等，请使用代理客户端提供的 HTTP 或 SOCKS5 本地端口。如果使用 TUN 客户端，请选择「直连／TUN」交由系统网络路由。跟随 Windows 手动代理时，脚本会把服务器地址传给 Antigravity 后端。Chromium 界面仍按 Windows 的代理设置处理 PAC 和代理例外。

### 恢复原设置

设置和原始快捷方式备份位于 %LOCALAPPDATA%\AntigravityConnection。回退会恢复脚本接管的入口。如果某个快捷方式后来被其他程序替换，回退会保留该文件和原始备份，并显示路径。

## 验证

在仓库根目录运行下面的命令。测试会在临时目录建立替代快捷方式，验证代理参数传递、重复设置和逐字节回退。

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\Verify-AntigravityConnection.ps1
~~~
