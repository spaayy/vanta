@echo off
rem Runs the armed Safe Mode retry of Vanta packages that failed to install, or gives
rem it up with /discard. It lets the retry start from the bare Safe Mode command
rem prompt; CbsRetry.ps1 names it in every retry message.
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

if not "%~2"=="" goto unsupportedArguments
set "VantaCbsRetryMode=-Recover"
if "%~1"=="" goto VantaCbsRetryRun
if /i "%~1"=="/discard" (
    set "VantaCbsRetryMode=-Discard"
    goto VantaCbsRetryRun
)
goto unsupportedArguments

:VantaCbsRetryRun
"%VantaNativePowerShell%" -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%VantaWindowsRoot%\VantaModules\Scripts\Operations\CbsRetry.ps1" %VantaCbsRetryMode%
if errorlevel 0 (
    if errorlevel 1 exit /b
) else (
    exit /b 1
)
rem CbsRetry.ps1 set the PROMPT this window opened with to name the retry; once the
rem retry is done or given up, the window goes back to the default prompt.
if "%PROMPT:~0,30%"=="Vanta: Safe Mode package retry" (endlocal & prompt) else endlocal
exit /b 0

:unsupportedArguments
echo Run this without arguments to retry the packages, or with /discard to give up the retry.
exit /b 87
