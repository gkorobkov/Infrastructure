@echo off
rem Start the local proxy on Windows. Requires Node.js 22+.
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js 22+ is required: https://nodejs.org/
  pause
  exit /b 1
)
for /f %%v in ('node -p "process.versions.node.split('.')[0]"') do set NODE_MAJOR=%%v
if %NODE_MAJOR% LSS 22 (
  echo Node.js 22 or newer is required.
  pause
  exit /b 1
)
echo Goal: launch the local HTTP proxy on loopback.
echo RUN: node src/proxy-cli.js %*
node src/proxy-cli.js %*
if errorlevel 1 pause
