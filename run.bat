@echo off
setlocal
set "PATH=%~dp0;%~dp0sdl3\SDL3-3.4.18-win32-x64;C:\msys64\ucrt64\bin;%PATH%"
cd /d "%~dp0"
if /I "%~1"=="lua" (
  "C:\msys64\ucrt64\bin\lua5.4.exe" main.lua %2 %3 %4 %5 %6 %7 %8 %9
) else if /I "%~1"=="jit" (
  "C:\msys64\ucrt64\bin\luajit.exe" main.lua %2 %3 %4 %5 %6 %7 %8 %9
) else (
  "C:\msys64\ucrt64\bin\luajit.exe" main.lua %*
)
exit /b %ERRORLEVEL%
