@echo off
setlocal
set "PATH=C:\rtools45\x86_64-w64-mingw32.static.posix\bin;C:\rtools45\usr\bin;%PATH%"
set "GCC=C:\rtools45\x86_64-w64-mingw32.static.posix\bin\gcc.exe"
cd /d "%~dp0"
if not exist "%GCC%" (
  echo gcc do Rtools nao encontrado: %GCC%
  exit /b 1
)
"%GCC%" -shared -O2 -o video_c.dll src\video_c.c -I "C:\msys64\ucrt64\include\lua5.4" -I "C:\msys64\ucrt64\include\SDL2" -L "C:\msys64\ucrt64\lib" -lSDL2 "-llua5.4" -lwinmm -static-libgcc
if errorlevel 1 exit /b 1
echo video_c.dll
exit /b 0
