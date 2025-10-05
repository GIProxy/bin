@echo off
setlocal enabledelayedexpansion

:: ========================================
:: GIProxy Auto-Updater and Launcher (BAT)
:: ========================================
:: Version: 1.0.0
:: Author: GIProxy Team

title GIProxy Auto-Updater ^& Launcher

:: Configuration
set "REPO_URL=https://github.com/GIProxy/bin.git"
set "REPO_BRANCH=main"
set "INSTALL_DIR=%~dp0GIProxy"
set "GIT_PORTABLE_DIR=%~dp0.git-portable"
set "VERSION_FILE=version"
set "SKIP_UPDATE="
set "FORCE_UPDATE="

:: Parse command line arguments
:parse_args
if "%~1"=="" goto end_parse
if /i "%~1"=="-SkipUpdate" set "SKIP_UPDATE=1"
if /i "%~1"=="-ForceUpdate" set "FORCE_UPDATE=1"
if /i "%~1"=="-Architecture" set "FORCE_ARCH=%~2" & shift
shift
goto parse_args
:end_parse

:: Detect architecture
call :detect_architecture
echo [INFO] Detected architecture: %ARCH%
echo.

:: Get Git command
call :get_git_command
if errorlevel 1 (
    echo [ERROR] Failed to get Git command
    pause
    exit /b 1
)

echo [INFO] Using Git: %GIT_CMD%
echo.

:: Check if repository exists
if not exist "%INSTALL_DIR%\.git" (
    echo [INFO] Repository not found. Initializing...
    call :initialize_repository
    if errorlevel 1 (
        echo [ERROR] Failed to initialize repository
        pause
        exit /b 1
    )
) else (
    if not defined SKIP_UPDATE (
        call :check_and_update
    ) else (
        echo [WARNING] Skipping update check
    )
)

:: Check and create desktop shortcut (after repo is cloned)
call :create_desktop_shortcut

echo.
echo ========================================
echo      GIProxy Starting...
echo ========================================
echo.

:: Start GIProxy
call :start_giproxy
goto :eof

:: ========================================
:: Functions
:: ========================================

:detect_architecture
if defined FORCE_ARCH (
    set "ARCH=%FORCE_ARCH%"
    goto :eof
)

set "ARCH=x64"
if defined PROCESSOR_ARCHITEW6432 (
    if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" set "ARCH=x64"
    if /i "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "ARCH=arm64"
) else (
    if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "ARCH=x64"
    if /i "%PROCESSOR_ARCHITECTURE%"=="x86" set "ARCH=x86"
    if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "ARCH=arm64"
)
goto :eof

:test_git_installed
where git >nul 2>&1
if %errorlevel% equ 0 (
    set "GIT_CMD=git"
    exit /b 0
)
exit /b 1

:install_git_portable
echo [INFO] Git not found. Installing Git Portable for %ARCH%...

if "%ARCH%"=="x64" (
    set "GIT_URL=https://github.com/git-for-windows/git/releases/download/v2.47.0.windows.2/PortableGit-2.47.0.2-64-bit.7z.exe"
) else if "%ARCH%"=="x86" (
    set "GIT_URL=https://github.com/git-for-windows/git/releases/download/v2.47.0.windows.2/PortableGit-2.47.0.2-32-bit.7z.exe"
) else if "%ARCH%"=="arm64" (
    set "GIT_URL=https://github.com/git-for-windows/git/releases/download/v2.47.0.windows.2/PortableGit-2.47.0.2-64-bit.7z.exe"
) else (
    echo [ERROR] Unsupported architecture: %ARCH%
    exit /b 1
)

set "GIT_INSTALLER=%TEMP%\git-portable-%ARCH%.exe"

echo [INFO] Downloading Git Portable...
powershell -Command "& {[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%GIT_URL%' -OutFile '%GIT_INSTALLER%' -UseBasicParsing}"

if not exist "%GIT_INSTALLER%" (
    echo [ERROR] Failed to download Git Portable
    exit /b 1
)

echo [INFO] Extracting Git Portable...
if not exist "%GIT_PORTABLE_DIR%" mkdir "%GIT_PORTABLE_DIR%"
"%GIT_INSTALLER%" -o"%GIT_PORTABLE_DIR%" -y >nul 2>&1

del /f /q "%GIT_INSTALLER%" >nul 2>&1

if exist "%GIT_PORTABLE_DIR%\cmd\git.exe" (
    set "GIT_CMD=%GIT_PORTABLE_DIR%\cmd\git.exe"
    echo [SUCCESS] Git Portable installed successfully!
    exit /b 0
)

if exist "%GIT_PORTABLE_DIR%\bin\git.exe" (
    set "GIT_CMD=%GIT_PORTABLE_DIR%\bin\git.exe"
    echo [SUCCESS] Git Portable installed successfully!
    exit /b 0
)

echo [ERROR] Git executable not found after extraction
exit /b 1

:get_git_command
call :test_git_installed
if %errorlevel% equ 0 goto :eof

if exist "%GIT_PORTABLE_DIR%\cmd\git.exe" (
    set "GIT_CMD=%GIT_PORTABLE_DIR%\cmd\git.exe"
    goto :eof
)

if exist "%GIT_PORTABLE_DIR%\bin\git.exe" (
    set "GIT_CMD=%GIT_PORTABLE_DIR%\bin\git.exe"
    goto :eof
)

call :install_git_portable
goto :eof

:get_local_version
set "LOCAL_VERSION="
if exist "%INSTALL_DIR%\%VERSION_FILE%" (
    set /p LOCAL_VERSION=<"%INSTALL_DIR%\%VERSION_FILE%"
)
goto :eof

:initialize_repository
echo [INFO] Cloning repository from %REPO_URL%...
"%GIT_CMD%" clone --branch %REPO_BRANCH% %REPO_URL% "%INSTALL_DIR%"
if %errorlevel% equ 0 (
    echo [SUCCESS] Repository cloned successfully!
    exit /b 0
)
echo [ERROR] Failed to clone repository
exit /b 1

:update_repository
echo [INFO] Updating repository...
pushd "%INSTALL_DIR%"

"%GIT_CMD%" fetch origin %REPO_BRANCH% >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Git fetch failed
    popd
    exit /b 1
)

echo [INFO] Preserving local changes...
"%GIT_CMD%" stash push -m "Auto-stash before update %date% %time%" >nul 2>&1
set "STASHED=%errorlevel%"

echo [INFO] Pulling latest changes...
"%GIT_CMD%" pull origin %REPO_BRANCH% --rebase >nul 2>&1
if errorlevel 1 (
    echo [WARNING] Pull failed, attempting to resolve...
    "%GIT_CMD%" rebase --abort >nul 2>&1
    "%GIT_CMD%" pull origin %REPO_BRANCH% --strategy-option=theirs >nul 2>&1
)

if "%STASHED%"=="0" (
    echo [INFO] Restoring local changes...
    "%GIT_CMD%" stash pop >nul 2>&1
    if errorlevel 1 (
        echo [WARNING] Could not automatically restore all changes
    )
)

echo [SUCCESS] Repository updated successfully!
popd
goto :eof

:check_and_update
call :get_local_version
if defined LOCAL_VERSION (
    echo [INFO] Local version: %LOCAL_VERSION%
) else (
    echo [INFO] Local version: unknown
)

if defined FORCE_UPDATE (
    echo [WARNING] Force update requested
    call :update_repository
    goto :eof
)

echo [INFO] Checking for updates...
call :update_repository

call :get_local_version
if defined LOCAL_VERSION (
    echo [SUCCESS] Version: %LOCAL_VERSION%
) else (
    echo [SUCCESS] Already up to date
)
goto :eof

:get_executable_path
if exist "%INSTALL_DIR%\win\%ARCH%\Debug\GIProxy.exe" (
    set "BUILD_TYPE=Debug"
) else (
    set "BUILD_TYPE=Release"
)

set "EXE_PATH=%INSTALL_DIR%\win\%ARCH%\!BUILD_TYPE!\GIProxy.exe"

if not exist "!EXE_PATH!" (
    echo [ERROR] Executable not found for %ARCH%
    echo [ERROR] Expected path: %INSTALL_DIR%\win\%ARCH%\Debug\GIProxy.exe
    echo [ERROR]            or: %INSTALL_DIR%\win\%ARCH%\Release\GIProxy.exe
    exit /b 1
)

exit /b 0

:start_giproxy
call :get_executable_path
if errorlevel 1 (
    echo [ERROR] Cannot start GIProxy: executable not found
    pause
    exit /b 1
)

set "WORKING_DIR=%INSTALL_DIR%\win\%ARCH%\!BUILD_TYPE!"

echo [INFO] Starting GIProxy...
echo [INFO] Executable: !EXE_PATH!
echo [INFO] Working Directory: !WORKING_DIR!
echo.

cd /d "!WORKING_DIR!"
"!EXE_PATH!"

if errorlevel 1 (
    echo.
    echo [ERROR] GIProxy exited with error code %errorlevel%
    pause
)
goto :eof

:create_desktop_shortcut
set "DESKTOP=%USERPROFILE%\Desktop"
set "SHORTCUT_PATH=%DESKTOP%\GIProxy.lnk"

if exist "%SHORTCUT_PATH%" (
    echo [INFO] Desktop shortcut already exists
    goto :eof
)

:: Wait until repository is cloned to create shortcut with actual exe path
if not exist "%INSTALL_DIR%\.git" (
    goto :eof
)

:: Get the executable path for shortcut
call :get_executable_path 2>nul
if errorlevel 1 goto :eof

set "SHORTCUT_WORKING_DIR=%INSTALL_DIR%\win\%ARCH%\!BUILD_TYPE!"

echo [INFO] Creating desktop shortcut...

powershell -Command "& {$WshShell = New-Object -ComObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut('%SHORTCUT_PATH%'); $Shortcut.TargetPath = '!EXE_PATH!'; $Shortcut.WorkingDirectory = '!SHORTCUT_WORKING_DIR!'; $Shortcut.IconLocation = '!EXE_PATH!'; $Shortcut.Description = 'GIProxy - Growtopia Proxy'; $Shortcut.Save()}"

if exist "%SHORTCUT_PATH%" (
    echo [SUCCESS] Desktop shortcut created successfully!
) else (
    echo [WARNING] Failed to create desktop shortcut
)
goto :eof
