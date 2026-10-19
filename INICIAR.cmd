@echo off
setlocal
cd /d "%~dp0"

if not exist "web\dist\index.html" (
  echo Preparando la interfaz por primera vez. Puede tardar un minuto...
  pushd web
  call npm install || goto fail
  call npm run build || goto fail
  popd
)

echo Abriendo Workshop en el navegador. Deja esta ventana abierta mientras lo uses.
python server\server.py
if errorlevel 1 goto fail
exit /b 0

:fail
echo.
echo No se pudo iniciar Workshop. Revisa el mensaje de arriba.
pause
exit /b 1
