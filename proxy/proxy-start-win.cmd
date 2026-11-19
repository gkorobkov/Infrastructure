@echo off
rem Check/install Node.js and start Universal HTTP Proxy. Options are forwarded.
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0proxy-start-win.ps1" %*
set "PROXY_EXIT=%ERRORLEVEL%"
if not "%PROXY_EXIT%"=="0" pause
exit /b %PROXY_EXIT%
