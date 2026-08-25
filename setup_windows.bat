@echo off
REM 雙擊此檔案即可執行 PowerShell 安裝腳本
REM 若遇到執行原則限制，會自動以 Bypass 模式執行

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_windows.ps1"
pause
