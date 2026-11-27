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

if not "%~2"=="" exit /b 87
set "VantaResetSilent="
if "%~1"=="" goto VantaResetRun
if /i "%~1"=="/silent" (
    set "VantaResetSilent=-Silent"
    goto VantaResetRun
)
exit /b 87

:VantaResetRun
"%VantaNativePowerShell%" -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%VantaWindowsRoot%\VantaModules\Scripts\Entry\Invoke-VantaResetServices.ps1" %VantaResetSilent%
if errorlevel 0 (
    if errorlevel 1 exit /b
) else (
    exit /b 1
)
exit /b 0
