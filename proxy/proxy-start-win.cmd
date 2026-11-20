@echo off
rem Check/install Node.js and start Universal HTTP Proxy. Options are forwarded.
setlocal
rem Open a dedicated console and return immediately to the calling launcher.
start "Universal HTTP Proxy" /D "%~dp0" powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File "%~dp0proxy-start-win.ps1" %*
exit /b %ERRORLEVEL%
