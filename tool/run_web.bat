@echo off
REM Builds the Flutter web app (release), serves it on 127.0.0.1:%PORT%, and opens Chrome.
REM Usage:  tool\run_web.bat [SERVER_URL=http://127.0.0.1:8765] [PORT=8780]
REM Chrome opens a separate profile (fake mic UI, autoplay). The server allows http://127.0.0.1:8780 via CORS
REM (server.cors_origins, livetrans-server PR #13); if you change PORT, add that origin on the server side.
REM Requires: flutter, python 3 on PATH, Google Chrome.
setlocal
cd /d "%~dp0.."
set "SERVER_URL=%~1"
if "%SERVER_URL%"=="" set "SERVER_URL=http://127.0.0.1:8765"
set "PORT=%~2"
if "%PORT%"=="" set "PORT=8780"
set "OUT=build\web"
set "PROFILE=%TEMP%\livetrans-chrome-profile"
set "CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME%" set "CHROME=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"

echo [run_web] building release web (server=%SERVER_URL%) ...
call flutter build web --release -o "%OUT%" --dart-define=LIVETRANS_SERVER=%SERVER_URL%
if errorlevel 1 (
  echo [run_web] build failed
  exit /b 1
)

echo [run_web] serving %OUT% at http://127.0.0.1:%PORT% (close the server window to stop)
start "livetrans web %PORT%" python tool\serve_web.py "%OUT%" %PORT%
timeout /t 2 /nobreak >nul

if exist "%CHROME%" (
  echo [run_web] opening Chrome
  start "" "%CHROME%" --user-data-dir="%PROFILE%" --autoplay-policy=no-user-gesture-required --use-fake-ui-for-media-stream --no-first-run --no-default-browser-check --window-size=520,900 --app=http://127.0.0.1:%PORT%
) else (
  echo [run_web] Chrome not found; open http://127.0.0.1:%PORT% manually in Chrome
)
endlocal
