@echo off
setlocal
set "PATH=C:\msys64\ucrt64\bin;%PATH%"
set "GCC=C:\msys64\ucrt64\bin\gcc.exe"
cd /d "%~dp0"
if not exist "%GCC%" (
  echo gcc do UCRT64 nao encontrado: %GCC%
  exit /b 1
)
if not exist "sdl3\SDL3\" mklink /J "sdl3\SDL3" "sdl3\include"
if errorlevel 1 exit /b 1
"%GCC%" -shared -O2 -o video_c.dll src\video_c.c -I "C:\msys64\ucrt64\include\lua5.4" -I "sdl3" -L "C:\msys64\ucrt64\lib" "sdl3\SDL3-3.4.18-win32-x64\SDL3.dll" "-llua5.4" -lwinmm -static-libgcc
if errorlevel 1 exit /b 1
copy /Y "sdl3\SDL3-3.4.18-win32-x64\SDL3.dll" "SDL3.dll" >nul
echo video_c.dll
exit /b 0
