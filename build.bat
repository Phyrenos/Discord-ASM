@echo off
setlocal enabledelayedexpansion

echo ========================================
echo  Discord ASM Bot - NASM Build Script
echo ========================================
echo.

:: Check for NASM
where nasm >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: NASM not found in PATH
    echo Install NASM from https://www.nasm.us/
    exit /b 1
)

:: Ensure the MSVC linker is available; if not, import the VS x64 environment
:: automatically so this script also works from a plain command prompt.
:: (Done in a subroutine to avoid the ")" in "%ProgramFiles(x86)%" breaking an
::  inline parenthesized if-block.)
where link.exe >nul 2>&1
if %errorlevel% neq 0 call :import_vs_env
if %errorlevel% neq 0 exit /b 1

:: Create build directory
if not exist build mkdir build

echo [1/2] Assembling with NASM...
nasm -f win64 src\bot.asm -o build\bot.obj -Iinclude\ -Isrc\
if %errorlevel% neq 0 (
    echo ERROR: Assembly failed!
    exit /b 1
)
echo       OK

echo [2/2] Linking...
link.exe build\bot.obj /SUBSYSTEM:CONSOLE /ENTRY:main /OUT:build\bot.exe ^
    kernel32.lib winhttp.lib /NODEFAULTLIB /MACHINE:X64
if %errorlevel% neq 0 (
    echo ERROR: Linking failed!
    exit /b 1
)
echo       OK

echo.
echo Build successful! Output: build\bot.exe
echo.
echo Usage:
echo   set DISCORD_TOKEN=your_bot_token_here
echo   build\bot.exe
echo.

endlocal
exit /b 0

:: ------------------------------------------------------------
:: import_vs_env - Locate Visual Studio via vswhere and import
::                 the x64 Native Tools environment (vcvars64).
:: Returns errorlevel 0 on success, 1 on failure.
:: ------------------------------------------------------------
:import_vs_env
echo link.exe not on PATH - importing Visual Studio x64 environment...
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo ERROR: vswhere.exe not found. Install Visual Studio Build Tools,
    echo        or run this script from an x64 Native Tools Command Prompt.
    exit /b 1
)
set "VSPATH="
:: Use delayed expansion (!VSWHERE!) here: the path contains "(x86)", and an
:: immediately-expanded "%VSWHERE%" would let that ")" close the for-loop's
:: "in (...)" parentheses early.
for /f "usebackq tokens=*" %%i in (`"!VSWHERE!" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSPATH=%%i"
if not defined VSPATH (
    echo ERROR: No Visual Studio with the C++ x64 toolset was found.
    exit /b 1
)
call "%VSPATH%\VC\Auxiliary\Build\vcvars64.bat" >nul
where link.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: link.exe still unavailable after importing the VS environment.
    exit /b 1
)
exit /b 0
