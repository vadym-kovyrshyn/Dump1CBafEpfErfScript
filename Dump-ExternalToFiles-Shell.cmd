@echo off
rem Optional fallback. Prefer context menu via Enqueue-Hidden.vbs (no window flash).
setlocal
set "TOOLDIR=%~dp0"
wscript.exe //nologo //B "%TOOLDIR%Enqueue-Hidden.vbs" %*
exit /b 0
