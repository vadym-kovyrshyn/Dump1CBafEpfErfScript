@echo off
chcp 65001 >nul
setlocal
set "TOOLDIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TOOLDIR%Dump-ExternalToFiles.ps1" -RunBatch %*
set "ERR=%ERRORLEVEL%"
echo.
if not "%ERR%"=="0" (
  echo Failed with code %ERR%.
) else (
  echo OK.
)
pause
exit /b %ERR%
