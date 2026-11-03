@echo off
title Student API - java -jar
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-demo.ps1" -Serve
echo.
pause
