@echo off
setlocal enabledelayedexpansion
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

if not "%VCVARS%"=="" (
    call "%VCVARS%" >nul
    if errorlevel 1 exit /b 1
    cd /d "%CJ_DIR%"

    cl /nologo /std:c++17 /W4 /WX /EHsc /O2 /MT /LD crystaljobs.cpp /link /DEF:crystaljobs.def /OUT:crystaljobs.dll
    if errorlevel 1 exit /b 1

    cl /nologo /std:c++17 /W4 /WX /EHsc /O2 /MT selftest.cpp /Fe:selftest.exe
    if errorlevel 1 exit /b 1
) else (
    where i686-w64-mingw32-clang++ >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Could not locate vcvars32.bat or i686-w64-mingw32-clang++
        exit /b 1
    )

    (
        echo LIBRARY crystaljobs
        echo EXPORTS
        echo     CrystalJobsInitialize=CrystalJobsInitialize@0
        echo     CrystalJobsShutdown=CrystalJobsShutdown@0
        echo     CrystalJobsGetStatus=CrystalJobsGetStatus@8
        echo     CrystalJobsSetState=CrystalJobsSetState@8
        echo     expCreatePlugin=expCreatePlugin@4
        echo     expDestroyPlugin=expDestroyPlugin@4
        echo     expGetInterfaceVersion=expGetInterfaceVersion@0
    ) > crystaljobs.mingw.def

    i686-w64-mingw32-clang++ -std=c++17 -O2 -Wall -Wextra -Werror -fms-extensions -fasm-blocks -static -shared crystaljobs.cpp crystaljobs.mingw.def -o crystaljobs.dll
    set "BUILD_RC=!ERRORLEVEL!"
    del /q crystaljobs.mingw.def 2>nul
    if not "!BUILD_RC!"=="0" exit /b !BUILD_RC!

    i686-w64-mingw32-clang++ -std=c++17 -O2 -Wall -Wextra -Werror -fms-extensions -fasm-blocks -static selftest.cpp -o selftest.exe
    if errorlevel 1 exit /b 1
)

selftest.exe
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

if not exist "%CJ_DIR%..\..\plugins\ashita4" mkdir "%CJ_DIR%..\..\plugins\ashita4"
copy /y "%CJ_DIR%crystaljobs.dll" "%CJ_DIR%..\..\plugins\ashita4\crystaljobs.dll" >nul
if errorlevel 1 exit /b 1

del /q *.obj *.exp *.lib selftest.exe 2>nul
echo Built and verified crystaljobs.dll to plugins\ashita4\crystaljobs.dll
