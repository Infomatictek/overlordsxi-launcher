@echo off
setlocal
set "CJ_DIR=%~dp0"
cd /d "%CJ_DIR%"

set "VCVARS="
if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars32.bat" (
    set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars32.bat"
) else if exist "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars32.bat" (
    set "VCVARS=C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars32.bat"
) else if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" (
    for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property installationPath`) do (
        if exist "%%i\VC\Auxiliary\Build\vcvars32.bat" set "VCVARS=%%i\VC\Auxiliary\Build\vcvars32.bat"
    )
)

if "%VCVARS%"=="" (
    echo ERROR: Could not locate vcvars32.bat
    exit /b 1
)

call "%VCVARS%" >nul
if errorlevel 1 exit /b 1
cd /d "%CJ_DIR%"

cl /nologo /std:c++17 /W4 /WX /EHsc /O2 /MT /LD crystaljobs.cpp /link /DEF:crystaljobs.def /OUT:crystaljobs.dll
if errorlevel 1 exit /b 1

cl /nologo /std:c++17 /W4 /WX /EHsc /O2 /MT selftest.cpp /Fe:selftest.exe
if errorlevel 1 exit /b 1

selftest.exe
if errorlevel 1 exit /b 1

copy /y "%CJ_DIR%crystaljobs.dll" "%CJ_DIR%..\..\addons\ashita4\crystalsocket\crystaljobs.dll" >nul
if errorlevel 1 exit /b 1

del /q *.obj *.exp *.lib selftest.exe 2>nul
echo Built and verified crystaljobs.dll to addons\ashita4\crystalsocket\crystaljobs.dll
