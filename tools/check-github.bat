@echo off
chcp 65001 >nul
title GitHub Check
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0check-github.ps1"
if errorlevel 1 (
    echo.
    echo [!] Script did not finish normally.
    pause
)
