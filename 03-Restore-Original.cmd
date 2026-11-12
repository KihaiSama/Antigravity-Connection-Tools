@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0AntigravityConnection.ps1" -Action Restore
set "AGY_RESULT=%ERRORLEVEL%"
pause
exit /b %AGY_RESULT%
