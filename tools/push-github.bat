@echo off
chcp 65001 >nul
title GitHub Push
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0git-remote.ps1" -Task push
