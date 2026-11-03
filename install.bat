@echo off
chcp 65001 >nul 2>&1
title mas_oc Installer

echo.
echo   +============================================================+
echo   ^|  mas_oc - OpenCode multi-agent environment                 ^|
echo   ^|  WSL2 + Ubuntu setup                                       ^|
echo   +============================================================+
echo.

wsl.exe --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   WSL2 not found. Install it from an administrator terminal:
    echo     wsl --install
    echo   Restart Windows, then run install.bat again.
    pause
    exit /b 1
)

wsl.exe -d Ubuntu -- echo test >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   Ubuntu for WSL was not found.
    echo   Install it with:
    echo     wsl --install -d Ubuntu
    pause
    exit /b 1
)

echo   Installing Linux dependencies inside Ubuntu...
wsl.exe -d Ubuntu -- bash -lc "sudo apt-get update && sudo apt-get install -y tmux python3 python3-yaml inotify-tools curl git"
if %ERRORLEVEL% NEQ 0 (
    echo   Dependency installation failed. Run the command manually and retry.
    pause
    exit /b 1
)

echo   Installing OpenCode...
wsl.exe -d Ubuntu -- bash -lc "command -v opencode >/dev/null || curl -fsSL https://opencode.ai/install | bash"
if %ERRORLEVEL% NEQ 0 (
    echo   OpenCode installation failed. See https://opencode.ai/docs/
    pause
    exit /b 1
)

echo.
echo   Setup finished. Inside Ubuntu, open this folder and run:
echo     ./mas setup
echo     ./mas start
echo.
pause
