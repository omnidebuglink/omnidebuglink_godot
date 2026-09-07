@echo off
rem Double-click launcher for the OmniDebugLink Godot sample (Web build).
rem Starts a tiny local static server (PowerShell, no install needed) on
rem 127.0.0.1:8123 and opens the sample in your default browser.
rem Optional: put your client token (one line, odl-dev-...) into
rem web_token.txt next to this file and it is passed as ?token= automatically.
setlocal
cd /d "%~dp0"

set PORT=8123
set "URL=http://127.0.0.1:%PORT%/index.html"
if exist web_token.txt (
    set /p TOKEN=<web_token.txt
)
if defined TOKEN set "URL=%URL%?token=%TOKEN%"

start "" "%URL%"
echo Serving build\web on http://127.0.0.1:%PORT%/ - keep this window open, close it to stop.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1" -Port %PORT% -Root "build\web"
endlocal
