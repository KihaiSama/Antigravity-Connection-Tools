# Antigravity Connection Tools

[简体中文](README.md) · [繁體中文](README.zh-TW.md) · English · [日本語](README.ja.md)

Switch how Google Antigravity connects on Windows. The scripts configure the current user's desktop and Start menu shortcuts and back up the originals for rollback.

## Getting started

You need Windows, Windows PowerShell 5.1, and an installed copy of Google Antigravity. After extracting the ZIP or cloning the repository, keep the three CMD files and `AntigravityConnection.ps1` in the same folder.

| Double-click | What it does |
| --- | --- |
| `01-Use-Windows-Proxy.cmd` | Use the current Windows manual proxy. Each new Antigravity process reads the current server and port. |
| `02-Choose-Connection.cmd` | Choose the Windows manual proxy (1), a custom proxy (2), or direct/TUN mode (3). |
| `03-Restore-Original.cmd` | Restore the original shortcuts and default launch behavior. |

After switching modes or restoring the shortcuts, quit Antigravity if it is running. Then open it from the configured desktop or Start menu shortcut. To launch from the taskbar, pin the configured Start menu shortcut again.

### After restarting Windows or changing proxy clients

Run `01-Use-Windows-Proxy.cmd` once. After restarting Windows or changing proxy clients, enable the client's Windows system proxy and open Antigravity from a configured shortcut. The next launch picks up any change to the proxy address or port. If your client only uses TUN, run `02-Choose-Connection.cmd` and select option 3.

If Windows or an Antigravity update recreates a shortcut, run the setup script again. It backs up shortcuts that still point to the same Antigravity installation before applying the proxy settings. It leaves unrecognized shortcuts alone.

### When PowerShell blocks the script

**Allow only `AntigravityConnection.ps1`.** Run `Get-ExecutionPolicy -List` in Windows PowerShell 5.1. `MachinePolicy` and `UserPolicy` come from Group Policy and take precedence over the `RemoteSigned` policy that the CMD launchers request for their PowerShell process. [PowerShell execution policies](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-5.1)

#### The file has a download marker

If `RemoteSigned` blocks the downloaded script, verify its source and review the code. Then unblock just this file from the extracted folder. You can also right-click the file, open **Properties**, select **Unblock** on the **General** tab, and apply the change.

~~~powershell
Unblock-File -LiteralPath .\AntigravityConnection.ps1
~~~

#### Ask an administrator for a per-file allow rule

1. If the computer already uses **AppLocker** to manage scripts, ask an administrator to open the applicable AppLocker policy. For a local policy, open `secpol.msc` and go to **Application Control Policies → AppLocker → Script Rules**.
2. In the existing **Script Rules** collection, choose **Create New Rule**. Select **Allow** and the user or group that needs the script, choose **File hash**, and browse to the extracted `AntigravityConnection.ps1`. Create and deploy the rule. Explicit deny rules take precedence, so the administrator should review the existing rules as well. [Create a file hash rule](https://learn.microsoft.com/windows/security/application-security/application-control/app-control-for-business/applocker/create-a-rule-that-uses-a-file-hash-condition) · [AppLocker rule behavior](https://learn.microsoft.com/windows/security/application-security/application-control/app-control-for-business/applocker/understanding-applocker-rule-behavior)
3. Setup copies the script to `%LOCALAPPDATA%\AntigravityConnection\AntigravityConnection.ps1` for the shortcuts to run. One hash rule covers both copies when their contents match. If an update changes the script, the administrator needs to approve the new hash.

If your organization uses **App Control for Business (WDAC)**, ask the administrator to approve this script in the applicable policy. If Group Policy enforces **AllSigned**, use a copy signed by a publisher your organization trusts. If Group Policy disables script execution (**Restricted**), the administrator must address it through the applicable policy. Unblocking a file only removes its download marker. [App Control script enforcement](https://learn.microsoft.com/windows/security/application-security/application-control/app-control-for-business/design/script-enforcement) · [PowerShell script signing](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-5.1)

### Custom proxies

Enter a proxy address in one of these formats. An address without a scheme is treated as HTTP.

~~~text
127.0.0.1:8080
http://proxy.example.com:8080
https://proxy.example.com:443
socks5://127.0.0.1:1080
socks5h://[::1]:1080
~~~

If your proxy requires authentication, enter the username and password when prompted. The script encrypts the credentials with Windows DPAPI for the current user and passes them to the Antigravity backend. The Chromium interface and external browser need their own settings for authenticated proxies.

For PAC/WPAD, SOCKS4, Shadowsocks, VMess, VLESS, or Trojan, use a local HTTP or SOCKS5 port provided by your proxy client. If you use TUN, select direct/TUN mode and let Windows route the traffic. In Windows manual proxy mode, the script passes the manual proxy addresses to the backend. The Chromium interface uses the Windows settings for PAC and proxy exceptions.

### Restoring the original setup

Settings and shortcut backups are stored in `%LOCALAPPDATA%\AntigravityConnection`. Rollback restores the shortcuts managed by the script. If another program has since replaced a shortcut, rollback displays the path and preserves both the current shortcut and its original backup.

## Verification

Run this command from the repository root. The test creates temporary shortcuts and checks that proxy settings reach the child process, that setup can be repeated, and that rollback restores the original bytes.

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\Verify-AntigravityConnection.ps1
~~~
