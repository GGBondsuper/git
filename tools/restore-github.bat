@echo off
chcp 65001 >nul
title GitHub Access Restore
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix-github-host.ps1" -Restore
if errorlevel 1 (
    echo.
    echo [!] Script did not finish normally.
    echo     Try: right-click this file ^> "Run as administrator"
    pause
)
