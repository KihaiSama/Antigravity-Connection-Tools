[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Restore', 'Launch')][string]$Action = 'Apply',
    [ValidateSet('Programs', 'Desktop')][string]$Entry = 'Programs',
    [ValidateSet('Prompt', 'System')][string]$ConnectionMode = 'Prompt'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-ProxyEndpoint {
    param([AllowEmptyString()][string]$Address)

    $addressText = $Address.Trim()
    if ($addressText -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        $addressText = "http://$addressText"
    }
    $uri = $null
    if (-not [Uri]::TryCreate($addressText, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin 'http', 'https', 'socks5', 'socks5h' -or
        $uri.HostNameType -eq [UriHostNameType]::Unknown -or $uri.UserInfo -or
        $uri.AbsolutePath -notin '', '/' -or $uri.Query -or $uri.Fragment -or
        $addressText -match '[\s\\;@"]' -or $uri.Port -eq 0) {
        throw '请输入有效的 HTTP、HTTPS、SOCKS5 或 SOCKS5H 地址，例如 127.0.0.1:8080 或 socks5://127.0.0.1:1080。账号密码请单独填写。'
    }
    $port = $uri.Port
    if ($port -lt 0) {
        $port = 1080
    }
    $proxyHost = $uri.IdnHost
    if ($uri.HostNameType -eq [UriHostNameType]::IPv6) {
        $proxyHost = '[{0}]' -f [Net.IPAddress]::Parse($uri.DnsSafeHost).ToString()
    }
    return '{0}://{1}:{2}' -f $uri.Scheme, $proxyHost, $port
}

function ConvertFrom-WindowsProxy {
    param([AllowEmptyString()][string]$ProxyServer)

    $proxyText = $ProxyServer.Trim()
    if (-not $proxyText) {
        throw 'Windows 没有启用手动代理。请先开启代理客户端的系统代理，或选择自定义代理或直连／TUN。'
    }
    if ($proxyText -notmatch '=') {
        $endpoint = ConvertTo-ProxyEndpoint $proxyText
        return @{ Http = $endpoint; Https = $endpoint }
    }

    $servers = @{}
    foreach ($item in ($proxyText -split ';')) {
        if ($item -match '^\s*(http|https|socks)\s*=\s*(\S.*?)\s*$') {
            $servers[$Matches[1]] = $Matches[2]
        }
    }
    $socks = $servers['socks']
    if ($socks -and $socks -notmatch '://') {
        $socks = "socks5://$socks"
    }
    $http = $servers['http']
    $https = $servers['https']
    if (-not $https) {
        $https = $socks
    }
    if (-not $https) {
        throw 'Windows 手动代理没有为 HTTPS 指定服务器。请选择自定义代理并填入可用地址。'
    }
    if (-not $http) {
        $http = $https
    }
    return @{
        Http = ConvertTo-ProxyEndpoint $http
        Https = ConvertTo-ProxyEndpoint $https
    }
}

function Get-WindowsProxy {
    $settings = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $enabled = $settings.PSObject.Properties['ProxyEnable']
    $server = $settings.PSObject.Properties['ProxyServer']
    if (-not $enabled -or $enabled.Value -ne 1 -or -not $server -or -not $server.Value) {
        return ConvertFrom-WindowsProxy ''
    }
    return ConvertFrom-WindowsProxy $server.Value
}

function Protect-ProxyCredential {
    param([string]$UserName, [Security.SecureString]$Password)

    $passwordText = [Net.NetworkCredential]::new('', $Password).Password
    $encoded = '{0}:{1}' -f [Uri]::EscapeDataString($UserName), [Uri]::EscapeDataString($passwordText)
    return ConvertFrom-SecureString (ConvertTo-SecureString -String $encoded -AsPlainText -Force)
}

function Get-ProxyCredential {
    param([string]$ProtectedCredential)

    $secure = ConvertTo-SecureString -String $ProtectedCredential
    return [Net.NetworkCredential]::new('', $secure).Password
}

function New-SystemConnection {
    [void](Get-WindowsProxy)
    return [pscustomobject]@{ Mode = 'System'; Endpoint = ''; Credential = '' }
}

function Read-Connection {
    param($CurrentConnection)

    Write-Host '1. 跟随 Windows 手动代理（每次启动时读取地址）'
    Write-Host '2. 自定义代理（HTTP / HTTPS / SOCKS5 / SOCKS5H）'
    Write-Host '3. 直连／TUN（由当前网络或 TUN 客户端路由）'
    Write-Host '0. 取消'
    $default = '跟随 Windows 手动代理'
    if ($CurrentConnection) {
        $default = '保留当前设置'
    }

    while ($true) {
        $choice = (Read-Host "选择连接方式，直接回车：$default").Trim()
        if (-not $choice -and $CurrentConnection) {
            return $CurrentConnection
        }
        if (-not $choice) {
            $choice = '1'
        }
        try {
            switch ($choice) {
                '1' {
                    return New-SystemConnection
                }
                '2' {
                    $endpoint = ConvertTo-ProxyEndpoint (Read-Host '代理地址，例如 127.0.0.1:8080')
                    $credential = ''
                    $userName = Read-Host '代理用户名（无需认证则回车）'
                    if ($userName) {
                        $password = Read-Host '代理密码' -AsSecureString
                        $credential = Protect-ProxyCredential -UserName $userName -Password $password
                    }
                    return [pscustomobject]@{ Mode = 'Custom'; Endpoint = $endpoint; Credential = $credential }
                }
                '3' {
                    return [pscustomobject]@{ Mode = 'Direct'; Endpoint = ''; Credential = '' }
                }
                '0' { return $null }
                default { Write-Host '请输入 0、1、2 或 3。' -ForegroundColor Yellow }
            }
        } catch {
            Write-Host $_.Exception.Message -ForegroundColor Yellow
        }
    }
}

function Get-ConnectionPaths {
    $local = [Environment]::GetFolderPath('LocalApplicationData')
    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    $programs = [Environment]::GetFolderPath('Programs')
    if (-not $local -or -not $desktop -or -not $programs) {
        throw '无法定位当前用户的桌面、开始菜单或本地应用数据目录。'
    }
    $directory = Join-Path $local 'AntigravityConnection'
    return @{
        Directory = $directory
        State = Join-Path $directory 'connection.json'
        Launcher = Join-Path $directory 'AntigravityConnection.ps1'
        PowerShell = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
        Desktop = Join-Path $desktop 'Antigravity.lnk'
        Programs = Join-Path $programs 'Antigravity.lnk'
    }
}

function Get-LauncherArguments {
    param($Paths, [string]$Location)

    return '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "{0}" -Action Launch -Entry {1}' -f $Paths.Launcher, $Location
}

function Test-ManagedLink {
    param($Link, $Paths, [string]$Location)

    return $Link.TargetPath -ieq $Paths.PowerShell -and
        $Link.Arguments -ceq (Get-LauncherArguments $Paths $Location)
}

function Test-AntigravityShellLink {
    param([string]$Path)

    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.NameSpace((Split-Path -Parent $Path))
    if (-not $folder) {
        return $false
    }
    $item = $folder.ParseName((Split-Path -Leaf $Path))
    return $null -ne $item -and
        $item.ExtendedProperty('System.Link.TargetParsingPath') -ieq 'electron.app.Antigravity'
}

function Get-LinkContents {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
    }
    return ''
}

function Write-FileAtomically {
    param([string]$Path, [byte[]]$Content)

    $directory = Split-Path -Parent $Path
    $temporary = Join-Path $directory ('.agy-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temporary, $Content)
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Replace($temporary, $Path, [NullString]::Value)
        } else {
            [IO.File]::Move($temporary, $Path)
        }
    } finally {
        if ([IO.File]::Exists($temporary)) {
            [IO.File]::Delete($temporary)
        }
    }
}

function Read-State {
    param($Paths)

    if (-not (Test-Path -LiteralPath $Paths.State -PathType Leaf)) {
        return $null
    }
    $state = Get-Content -LiteralPath $Paths.State -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.Version -ne 1) {
        throw '连接设置的版本无法识别。原有配置和备份仍在。'
    }
    return $state
}

function New-ConnectionState {
    param($Paths, $Shell)

    $backups = @()
    foreach ($name in 'Programs', 'Desktop') {
        $path = $Paths[$name]
        $contents = Get-LinkContents $path
        if (-not $contents -and $name -eq 'Desktop') {
            continue
        }
        $app = $null
        $arguments = ''
        $workingDirectory = ''
        if ($contents) {
            $link = $Shell.CreateShortcut($path)
            if ($link.TargetPath -and
                [IO.Path]::GetFileName($link.TargetPath) -ieq 'Antigravity.exe' -and
                (Test-Path -LiteralPath $link.TargetPath -PathType Leaf)) {
                $app = $link.TargetPath
            } elseif ($link.TargetPath -or -not (Test-AntigravityShellLink $path)) {
                Write-Warning "保留了目标无法识别的快捷方式：$path"
                continue
            }
            $arguments = $link.Arguments
            $workingDirectory = $link.WorkingDirectory
        }
        $backups += [pscustomobject]@{
            Location = $name
            Path = $path
            Original = $contents
            AppPath = $app
            AppArguments = $arguments
            WorkingDirectory = $workingDirectory
        }
    }
    if ($backups.Count -eq 0) {
        throw '现有快捷方式的目标无法识别。'
    }
    $appPath = $backups.AppPath | Where-Object { $_ } | Select-Object -First 1
    if (-not $appPath) {
        $candidates = @(
            (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\Antigravity\Antigravity.exe'),
            (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Antigravity\Antigravity.exe')
        )
        $appPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    }
    if (-not $appPath) {
        throw '找不到 Antigravity.exe。请确认已安装 Antigravity。'
    }
    foreach ($backup in $backups) {
        if (-not $backup.AppPath) {
            $backup.AppPath = $appPath
        }
        if (-not $backup.WorkingDirectory) {
            $backup.WorkingDirectory = Split-Path -Parent $backup.AppPath
        }
    }
    return [pscustomobject]@{ Version = 1; Connection = $null; Shortcuts = $backups }
}

function Get-TrackedPath {
    param($Paths, $Shortcut)

    $path = $Paths[$Shortcut.Location]
    if (-not $path -or $path -ine $Shortcut.Path) {
        throw '桌面或开始菜单文件夹已移到别处。备份仍在，请将文件夹恢复到原位置后重试。'
    }
    return $path
}

function Update-ShortcutBackups {
    param($Paths, $State, $Shell)

    foreach ($shortcut in $State.Shortcuts) {
        $path = Get-TrackedPath $Paths $shortcut
        $current = Get-LinkContents $path
        if ($current -and $current -cne $shortcut.Original) {
            $link = $Shell.CreateShortcut($path)
            if (-not (Test-ManagedLink $link $Paths $shortcut.Location)) {
                $sameApp = $link.TargetPath -ieq $shortcut.AppPath -or
                    (-not $link.TargetPath -and (Test-AntigravityShellLink $path))
                if (-not $sameApp -or -not (Test-Path -LiteralPath $shortcut.AppPath -PathType Leaf)) {
                    Write-Warning "快捷方式已改为其他或无法识别的目标，已保留：$path"
                    continue
                }

                # Preserve the replacement made by Windows or the app installer for rollback.
                $shortcut.Original = $current
                $shortcut.AppArguments = $link.Arguments
                $shortcut.WorkingDirectory = $link.WorkingDirectory
                if (-not $shortcut.WorkingDirectory) {
                    $shortcut.WorkingDirectory = Split-Path -Parent $shortcut.AppPath
                }
            }
        }
        $shortcut
    }
}

function Set-ManagedLinks {
    param($Paths, $Shortcuts, $Shell)

    foreach ($shortcut in $Shortcuts) {
        $path = Get-TrackedPath $Paths $shortcut
        $current = Get-LinkContents $path
        if ($current) {
            if (Test-ManagedLink ($Shell.CreateShortcut($path)) $Paths $shortcut.Location) {
                continue
            }
            if ($current -cne $shortcut.Original) {
                throw "快捷方式在备份后已被修改，脚本保留了这个文件：$path"
            }
        }

        $temporary = Join-Path $Paths.Directory ('.agy-' + [Guid]::NewGuid().ToString('N') + '.lnk')
        try {
            $link = $Shell.CreateShortcut($temporary)
            $link.TargetPath = $Paths.PowerShell
            $link.Arguments = Get-LauncherArguments $Paths $shortcut.Location
            $link.WorkingDirectory = $shortcut.WorkingDirectory
            $link.IconLocation = $shortcut.AppPath + ',0'
            $link.Description = 'Antigravity'
            $link.WindowStyle = 7
            $link.Save()
            Write-FileAtomically -Path $path -Content ([IO.File]::ReadAllBytes($temporary))
        } finally {
            if ([IO.File]::Exists($temporary)) {
                [IO.File]::Delete($temporary)
            }
        }
    }
}

function Restore-Connection {
    param($Paths, $State, $Shell)

    $modified = @()
    foreach ($shortcut in $State.Shortcuts) {
        $path = Get-TrackedPath $Paths $shortcut
        $current = Get-LinkContents $path
        if ($current -ceq $shortcut.Original) {
            continue
        }
        if ($current -and -not (Test-ManagedLink ($Shell.CreateShortcut($path)) $Paths $shortcut.Location)) {
            $modified += $path
            continue
        }
        if ($shortcut.Original) {
            Write-FileAtomically -Path $path -Content ([Convert]::FromBase64String($shortcut.Original))
        } elseif ($current) {
            Remove-Item -LiteralPath $path
        }
    }

    if ($modified.Count) {
        throw "其余入口已恢复。以下快捷方式后来被其他程序改过，已保留现有快捷方式及其备份：$($modified -join '；')"
    }
    if (Test-Path -LiteralPath $Paths.Launcher -PathType Leaf) {
        Remove-Item -LiteralPath $Paths.Launcher
    }
    Remove-Item -LiteralPath $Paths.State
    if (-not (Get-ChildItem -LiteralPath $Paths.Directory -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $Paths.Directory
    }
}

function New-AppStartInfo {
    param($Connection, $Shortcut, $SystemProxy)

    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Shortcut.AppPath
    $info.WorkingDirectory = $Shortcut.WorkingDirectory
    $info.UseShellExecute = $false
    $info.Arguments = [string]$Shortcut.AppArguments
    foreach ($variable in 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY') {
        $info.EnvironmentVariables.Remove($variable)
    }
    if ($Connection.Mode -eq 'Direct') {
        $info.Arguments = ($info.Arguments + ' --no-proxy-server').TrimStart()
        return $info
    }

    if ($Connection.Mode -eq 'System') {
        $proxy = $SystemProxy
    } elseif ($Connection.Mode -eq 'Custom') {
        $endpoint = ConvertTo-ProxyEndpoint $Connection.Endpoint
        $backendEndpoint = $endpoint
        if ($Connection.Credential) {
            $credential = Get-ProxyCredential $Connection.Credential
            $scheme, $authority = $endpoint -split '://', 2
            $backendEndpoint = '{0}://{1}@{2}' -f $scheme, $credential, $authority
        } else {
            $chromiumEndpoint = $endpoint -replace '^socks5h://', 'socks5://'
            $info.Arguments = ($info.Arguments + ' --proxy-server=' + $chromiumEndpoint).TrimStart()
        }
        $proxy = @{ Http = $backendEndpoint; Https = $backendEndpoint }
    } else {
        throw '无法识别保存的连接方式。'
    }
    $info.EnvironmentVariables['HTTP_PROXY'] = $proxy.Http
    $info.EnvironmentVariables['HTTPS_PROXY'] = $proxy.Https
    $info.EnvironmentVariables['NO_PROXY'] = 'localhost,127.0.0.1,::1'
    return $info
}

function Start-Antigravity {
    param($State, [string]$Location)

    $shortcut = $State.Shortcuts | Where-Object Location -EQ $Location | Select-Object -First 1
    if (-not $shortcut -or -not (Test-Path -LiteralPath $shortcut.AppPath -PathType Leaf)) {
        throw '找不到这个快捷方式对应的 Antigravity。请恢复原设置，再从新的快捷方式重新配置。'
    }
    $systemProxy = $null
    if ($State.Connection.Mode -eq 'System') {
        $systemProxy = Get-WindowsProxy
    }
    $info = New-AppStartInfo -Connection $State.Connection -Shortcut $shortcut -SystemProxy $systemProxy
    $process = [Diagnostics.Process]::Start($info)
    if ($process) {
        $process.Dispose()
    }
}

function Write-RestartNote {
    if (Get-Process -Name Antigravity -ErrorAction SilentlyContinue) {
        Write-Host 'Antigravity 仍在运行。请正常退出后，再用桌面或开始菜单重新打开。'
    }
}

function Invoke-ConnectionAction {
    param([string]$SelectedAction, [string]$Location, [string]$SelectedMode)

    $paths = Get-ConnectionPaths
    if ($SelectedAction -eq 'Launch') {
        $state = Read-State $paths
        if (-not $state) {
            throw '未找到连接设置，请重新运行设置脚本。'
        }
        Start-Antigravity $state $Location
        return
    }

    $mutex = [Threading.Mutex]::new($false, 'Local\AntigravityConnection-' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    $locked = $false
    try {
        try {
            $locked = $mutex.WaitOne(0)
        } catch [Threading.AbandonedMutexException] {
            $locked = $true
        }
        if (-not $locked) {
            throw '另一个设置或恢复窗口正在运行，请先关闭它。'
        }

        $state = Read-State $paths
        if ($SelectedAction -eq 'Restore' -and -not $state) {
            Write-Host '没有已安装的连接设置。'
            return
        }
        $shell = New-Object -ComObject WScript.Shell
        if ($SelectedAction -eq 'Restore') {
            Restore-Connection -Paths $paths -State $state -Shell $shell
            Write-Host '已恢复原来的 Antigravity 启动方式。'
            Write-RestartNote
            return
        }

        if (-not $state) {
            $state = New-ConnectionState -Paths $paths -Shell $shell
        }
        $connection = if ($SelectedMode -eq 'System') {
            New-SystemConnection
        } else {
            Read-Connection $state.Connection
        }
        if (-not $connection) {
            Write-Host '已取消。'
            return
        }
        $shortcuts = @(Update-ShortcutBackups -Paths $paths -State $state -Shell $shell)
        if ($shortcuts.Count -eq 0) {
            throw '找不到可配置的 Antigravity 快捷方式。'
        }
        $state.Connection = $connection
        [void][IO.Directory]::CreateDirectory($paths.Directory)
        Write-FileAtomically -Path $paths.Launcher -Content ([IO.File]::ReadAllBytes($PSCommandPath))
        $json = $state | ConvertTo-Json -Depth 8
        Write-FileAtomically -Path $paths.State -Content ([Text.Encoding]::UTF8.GetBytes($json))
        Set-ManagedLinks -Paths $paths -Shortcuts $shortcuts -Shell $shell
        foreach ($shortcut in $shortcuts) {
            Write-Host "连接方式已保存：$($shortcut.Path)"
        }
        Write-RestartNote
    } finally {
        if ($locked) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-ConnectionAction $Action $Entry $ConnectionMode
    } catch {
        $message = $_.Exception.Message
        if ($Action -eq 'Launch') {
            $shell = New-Object -ComObject WScript.Shell
            [void]$shell.Popup($message, 0, 'Antigravity', 16)
        } else {
            Write-Host $message -ForegroundColor Red
        }
        exit 1
    }
}
