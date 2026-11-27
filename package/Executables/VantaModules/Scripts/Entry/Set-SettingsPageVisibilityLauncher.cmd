@echo off
verify other 2>nul
setlocal EnableExtensions DisableDelayedExpansion
if errorlevel 1 exit /b 1
cd /d "%__APPDIR__%"
if errorlevel 1 exit /b 1
for %%I in ("%__APPDIR__%..") do set "VantaWindowsRoot=%%~fI"

set "launcherEnvironment=%VantaWindowsRoot%\VantaModules\Scripts\Entry\Initialize-PowerShellLauncherEnvironment.cmd"
if not exist "%launcherEnvironment%" (
    echo PowerShell launcher environment helper not found: "%launcherEnvironment%"
    exit /b 1
)
call "%launcherEnvironment%"
if errorlevel 1 exit /b 1

set "script=%VantaWindowsRoot%\VantaModules\Scripts\Entry\Set-SettingsPageVisibility.ps1"
if not exist "%script%" (
    echo Script not found: "%script%"
    exit /b 1
)

if /i "%~1"=="/hide" goto validateArguments
if /i "%~1"=="hide" goto validateArguments
if /i "%~1"=="/unhide" goto validateArguments
if /i "%~1"=="unhide" goto validateArguments
goto unsupportedArguments

:validateArguments
if "%~2"=="" goto unsupportedArguments
if "%~3"=="" goto invoke
if /i not "%~3"=="-Silent" goto unsupportedArguments
if not "%~4"=="" goto unsupportedArguments
goto invokeSilent

:invoke
"%VantaNativePowerShell%" -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%script%" "%~1" "%~2"
if errorlevel 1 exit /b
exit /b 0

:invokeSilent
"%VantaNativePowerShell%" -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%script%" "%~1" "%~2" -Silent
if errorlevel 1 exit /b
exit /b 0

:unsupportedArguments
echo Unsupported Settings page visibility launcher arguments.
exit /b 2
