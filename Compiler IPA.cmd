@echo off
setlocal
chcp 65001 >nul
echo Compilation iPhone de Blusic via GitHub Actions
echo.
python "%~dp0tools\github_ipa.py" build
echo.
pause
