@echo off
rem Install/check Docker Desktop and start local n8n on Windows 11.
rem Usage: double-click this file, or run n8n_deploy_local.cmd from a terminal.
rem Diagnostics: n8n_deploy_local.cmd status; n8n_deploy_local.cmd cancel
rem Example: C:\Infrastructure\n8n\n8n_deploy_local.cmd
setlocal
set "N8N_MODE="
if /I "%~1"=="status" set "N8N_MODE=-SetupStatus"
if /I "%~1"=="cancel" set "N8N_MODE=-CancelSetup"
if "%N8N_MODE%"=="" echo Goal: Run the local n8n setup, load .env.local, and open the UI when it is ready.
if /I "%~1"=="status" echo Goal: Show CURRENT setup processes. No installation or cancellation will run.
if /I "%~1"=="cancel" echo Goal: Cancel only a verified, currently running prerequisite setup from this directory.
echo RUN: powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0n8n_deploy_local.ps1" %N8N_MODE%
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0n8n_deploy_local.ps1" %N8N_MODE%
set "DEPLOY_RESULT=%ERRORLEVEL%"
if not "%DEPLOY_RESULT%"=="0" echo Deployment stopped with exit code %DEPLOY_RESULT%. Read the message above.
echo Press any key to close this window.
pause >nul
exit /b %DEPLOY_RESULT%
