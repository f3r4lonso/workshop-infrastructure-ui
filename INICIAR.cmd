@echo off
setlocal
powershell.exe -NoLogo -NoProfile -Sta -File "%~dp0src\main.ps1"
if errorlevel 1 (
  echo.
  echo No se pudo iniciar Workshop Infraestructura.
  pause
)
