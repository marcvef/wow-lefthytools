@echo off
rem LefthyTools for WoW: Forever - double-click to install or update.
rem Downloads the current install.ps1 from GitHub and runs it; settings in WTF are kept.
title LefthyTools updater
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; iex (irm 'https://raw.githubusercontent.com/marcvef/wow-lefthytools/main/install.ps1')"
echo.
pause
