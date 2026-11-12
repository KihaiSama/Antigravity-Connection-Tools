[CmdletBinding()]
param([string]$Source)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Source) {
    $Source = Join-Path $PSScriptRoot '..\AntigravityConnection.ps1'
}
$Source = (Resolve-Path -LiteralPath $Source).Path
. $Source

function Assert-Equal {
    param($Actual, $Expected, [string]$Description)
    if ($Actual -cne $Expected) {
        throw "Failed: $Description (actual=[$Actual], expected=[$Expected])"
    }
}

foreach ($case in @(
    @('127.0.0.1:8181','http://127.0.0.1:8181'),
    @('https://proxy.example.test','https://proxy.example.test:443'),
    @('socks5://proxy.example.test','socks5://proxy.example.test:1080'),
    @('socks5h://[::1]:1081','socks5h://[::1]:1081')
)) {
    Assert-Equal (ConvertTo-ProxyEndpoint $case[0]) $case[1] 'proxy normalization'
}
foreach ($invalid in '', 'http://host.test:0', 'http://u:p@host.test:81', 'http://host.test/proxy.pac', 'vless://host.test:443', 'http://host.test:70000') {
    $failed = $false
    try { [void](ConvertTo-ProxyEndpoint $invalid) } catch { $failed = $true }
    Assert-Equal $failed $true 'invalid endpoint is rejected'
}
$splitProxy = ConvertFrom-WindowsProxy 'http=127.0.0.1:8001;https=https://proxy.example.test:8443'
Assert-Equal $splitProxy.Http 'http://127.0.0.1:8001' 'HTTP-specific Windows proxy'
Assert-Equal $splitProxy.Https 'https://proxy.example.test:8443' 'HTTPS-specific Windows proxy'
Assert-Equal (ConvertFrom-WindowsProxy 'socks=127.0.0.1:1090').Https 'socks5://127.0.0.1:1090' 'Windows SOCKS endpoint'

$testParent = Get-Item -LiteralPath $PSScriptRoot
$fixtureName = 'AntigravityConnection-fixture-' + [Guid]::NewGuid().ToString('N')
$testRoot = Join-Path $testParent.FullName $fixtureName
try {
    $fakeDesktop = Join-Path $testRoot 'desktop'
    $fakePrograms = Join-Path $testRoot 'start'
    $stateRoot = Join-Path $testRoot 'state'
    foreach ($directory in $fakeDesktop,$fakePrograms,$stateRoot) {
        [void][IO.Directory]::CreateDirectory($directory)
    }
    $paths = @{
        Directory = $stateRoot
        State = Join-Path $stateRoot 'connection.json'
        Launcher = Join-Path $stateRoot 'AntigravityConnection.ps1'
        PowerShell = (Get-Command powershell.exe -CommandType Application).Source
        Desktop = Join-Path $fakeDesktop 'Antigravity.lnk'
        Programs = Join-Path $fakePrograms 'Antigravity.lnk'
    }

    function Get-ConnectionPaths { return $paths }
    function Get-WindowsProxy { return @{ Http = 'http://127.0.0.1:8001'; Https = 'https://proxy.example.test:8443' } }

    $fakeApp = Join-Path $testRoot 'Antigravity.exe'
    Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\whoami.exe') -Destination $fakeApp
    $shell = New-Object -ComObject WScript.Shell
    foreach ($name in 'Desktop', 'Programs') {
        $link = $shell.CreateShortcut($paths[$name])
        $link.TargetPath = $fakeApp
        $link.Arguments = "--fixture-$name"
        $link.WorkingDirectory = $testRoot
        $link.Save()
    }
    $originalDesktop = Get-LinkContents $paths.Desktop
    $originalPrograms = Get-LinkContents $paths.Programs

    Invoke-ConnectionAction 'Apply' 'Programs' 'System'
    $state = Read-State $paths
    Assert-Equal $state.Connection.Mode 'System' 'one-click mode'
    Assert-Equal $state.Shortcuts.Count 2 'both shortcuts backed up'
    Assert-Equal ($state.Shortcuts | Where-Object Location -EQ 'Desktop').AppArguments '--fixture-Desktop' 'original arguments per entry'
    Assert-Equal ((Get-FileHash -LiteralPath $paths.Launcher).Hash) ((Get-FileHash -LiteralPath $Source).Hash) 'runtime copied verbatim'
    foreach ($name in 'Desktop', 'Programs') {
        Assert-Equal (Test-ManagedLink ($shell.CreateShortcut($paths[$name])) $paths $name) $true 'shortcut now points to installed launcher'
    }
    $managedPrograms = Get-LinkContents $paths.Programs
    Invoke-ConnectionAction 'Apply' 'Programs' 'System'
    Assert-Equal (Get-LinkContents $paths.Programs) $managedPrograms 'reapplying leaves already managed shortcut intact'
    Assert-Equal ((Read-State $paths).Shortcuts | Where-Object Location -EQ 'Programs').Original $originalPrograms 'reapply preserves initial backup'

    $shortcut = $state.Shortcuts | Where-Object Location -EQ 'Desktop'
    $custom = [pscustomobject]@{ Mode='Custom'; Endpoint='socks5h://[::1]:1091'; Credential='' }
    $info = New-AppStartInfo -Connection $custom -Shortcut $shortcut -SystemProxy $null
    Assert-Equal $info.Arguments '--fixture-Desktop --proxy-server=socks5://[::1]:1091' 'Chromium SOCKS5 routing'
    Assert-Equal $info.EnvironmentVariables['HTTPS_PROXY'] 'socks5h://[::1]:1091' 'Go SOCKS5H routing'
    Assert-Equal $info.EnvironmentVariables['NO_PROXY'] 'localhost,127.0.0.1,::1' 'OAuth local callback bypass'

    $testSecret = ConvertTo-SecureString 'fixture@!:' -AsPlainText -Force
    $custom.Credential = Protect-ProxyCredential -UserName 'fixture:user' -Password $testSecret
    $info = New-AppStartInfo -Connection $custom -Shortcut $shortcut -SystemProxy $null
    $credentialUri = [Uri]$info.EnvironmentVariables['HTTPS_PROXY']
    $encodedUser, $encodedPassword = $credentialUri.UserInfo -split ':',2
    Assert-Equal ([Uri]::UnescapeDataString($encodedUser)) 'fixture:user' 'username survives encoding'
    Assert-Equal ([Uri]::UnescapeDataString($encodedPassword)) 'fixture@!:' 'password survives encoding'
    Assert-Equal $info.Arguments '--fixture-Desktop' 'credentials stay out of command line'
    Assert-Equal ($custom.Credential -match 'fixture') $false 'protected credential is opaque'

    $info = New-AppStartInfo -Connection $state.Connection -Shortcut $shortcut -SystemProxy (Get-WindowsProxy)
    Assert-Equal $info.EnvironmentVariables['HTTPS_PROXY'] 'https://proxy.example.test:8443' 'system proxy passed to child'
    $info.FileName = $paths.PowerShell
    $info.Arguments = '-NoProfile -NonInteractive -Command "[Console]::Write($env:HTTPS_PROXY)"'
    $info.RedirectStandardOutput = $true
    $info.CreateNoWindow = $true
    $proc = [Diagnostics.Process]::Start($info)
    try {
        $received = $proc.StandardOutput.ReadToEnd()
        $proc.WaitForExit()
        Assert-Equal $proc.ExitCode 0 'child execution'
        Assert-Equal $received 'https://proxy.example.test:8443' 'child actually inherits proxy setting'
    } finally {
        $proc.Dispose()
    }

    $direct = [pscustomobject]@{ Mode='Direct'; Endpoint=''; Credential='' }
    $info = New-AppStartInfo -Connection $direct -Shortcut $shortcut -SystemProxy $null
    Assert-Equal $info.Arguments '--fixture-Desktop --no-proxy-server' 'Chromium direct/TUN'
    Assert-Equal $info.EnvironmentVariables.ContainsKey('HTTPS_PROXY') $false 'direct/TUN removes inherited HTTPS proxy'

    Invoke-ConnectionAction 'Restore' 'Programs' 'Prompt'
    Assert-Equal (Get-LinkContents $paths.Desktop) $originalDesktop 'desktop rollback is byte-identical'
    Assert-Equal (Get-LinkContents $paths.Programs) $originalPrograms 'start menu rollback is byte-identical'
    Assert-Equal (Test-Path -LiteralPath $paths.State) $false 'state removed on successful rollback'

    Remove-Item -LiteralPath $paths.Programs
    Invoke-ConnectionAction 'Apply' 'Programs' 'System'
    Assert-Equal (Test-Path -LiteralPath $paths.Programs) $true 'missing start shortcut created'
    Invoke-ConnectionAction 'Restore' 'Programs' 'Prompt'
    Assert-Equal (Test-Path -LiteralPath $paths.Programs) $false 'new shortcut removed on rollback'

    Invoke-ConnectionAction 'Apply' 'Programs' 'System'
    $link = $shell.CreateShortcut($paths.Desktop)
    $link.TargetPath = $fakeApp
    $link.Arguments = '--updated-app-shortcut'
    $link.Save()
    $updatedDesktop = Get-LinkContents $paths.Desktop
    Invoke-ConnectionAction 'Apply' 'Programs' 'System'
    Assert-Equal (Test-ManagedLink ($shell.CreateShortcut($paths.Desktop)) $paths 'Desktop') $true 'same app shortcut can be reapplied after replacement'
    $updatedBackup = (Read-State $paths).Shortcuts | Where-Object Location -EQ 'Desktop'
    Assert-Equal $updatedBackup.AppArguments '--updated-app-shortcut' 'replacement app arguments are preserved'
    Invoke-ConnectionAction 'Restore' 'Programs' 'Prompt'
    Assert-Equal (Get-LinkContents $paths.Desktop) $updatedDesktop 'rollback restores the replacement shortcut byte for byte'

    Invoke-ConnectionAction 'Apply' 'Programs' 'System'
    $link = $shell.CreateShortcut($paths.Desktop)
    $link.TargetPath = $paths.PowerShell
    $link.Arguments = '-NoProfile'
    $link.Save()
    $externalDesktop = Get-LinkContents $paths.Desktop
    Invoke-ConnectionAction 'Apply' 'Programs' 'System'
    Assert-Equal (Get-LinkContents $paths.Desktop) $externalDesktop 'unrelated shortcut survives reapply'
    Assert-Equal (Test-ManagedLink ($shell.CreateShortcut($paths.Programs)) $paths 'Programs') $true 'unrelated desktop shortcut does not block Start menu'
    $failed = $false
    try { Invoke-ConnectionAction 'Restore' 'Programs' 'Prompt' } catch { $failed = $true }
    Assert-Equal $failed $true 'external edit is reported'
    Assert-Equal (Get-LinkContents $paths.Desktop) $externalDesktop 'external edit survives restore'
    Assert-Equal (Test-Path -LiteralPath $paths.State) $true 'original backup survives external edit'
    Assert-Equal (Test-Path -LiteralPath $paths.Programs) $false 'independent start shortcut still restored'
    'PASS: Windows PowerShell proxy modes, child environment, shortcut management and restore'
} finally {
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        $testDirectory = Get-Item -LiteralPath $testRoot
        if ($testDirectory.Name -ne $fixtureName -or
            $testDirectory.Parent.FullName.TrimEnd('\') -ne $testParent.FullName.TrimEnd('\') -or
            ($testDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Unexpected test fixture path: $($testDirectory.FullName)"
        }
        Remove-Item -LiteralPath $testDirectory.FullName -Recurse -Force
    }
}
