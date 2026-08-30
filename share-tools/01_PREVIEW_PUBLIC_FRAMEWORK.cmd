@echo off
setlocal
set "PWSH=F:\PowerShell\7\pwsh.exe"
if exist "%PWSH%" goto :run
where pwsh.exe >nul 2>&1
if not errorlevel 1 (
    set "PWSH=pwsh.exe"
) else (
    set "PWSH=powershell.exe"
)
:run
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0preview-public-framework.ps1"
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
