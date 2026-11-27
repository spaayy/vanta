@echo off
rem Shared body for every generated VantaDesktop and Toolbox toggle launcher.
rem
rem A generated launcher is a two-line stub that calls this file with the toggle
rem name, the requested state (or - for a menu toggle), its own path, and any user
rem flags:
rem
rem     call "%__APPDIR__%..\VantaModules\Scripts\Entry\Invoke-VantaToggleLauncher.cmd" ^
rem         <Name> <State|-> "<launcher path>" [flags]
rem
rem The stub deliberately has no exit line: cmd.exe returns the last errorlevel from
rem this file as the process exit code, including negative values.
rem
rem Accepted flags are /silent, /quiet, /justcontext and /noaction, with either a
rem / or - prefix, case-insensitive. Anything else exits 87 before Windows PowerShell
rem starts, so no unvalidated token ever reaches PowerShell.
verify other 2>nul
setlocal EnableExtensions DisableDelayedExpansion
if errorlevel 1 exit /b 1
cd /d "%__APPDIR__%"
if errorlevel 1 exit /b 1
for %%I in ("%__APPDIR__%..") do set "VantaWindowsRoot=%%~fI"
set "VantaLauncherEnvironment=%VantaWindowsRoot%\VantaModules\Scripts\Entry\Initialize-PowerShellLauncherEnvironment.cmd"
if not exist "%VantaLauncherEnvironment%" (
    echo PowerShell launcher environment helper not found: "%VantaLauncherEnvironment%"
    exit /b 1
)
call "%VantaLauncherEnvironment%"
if errorlevel 1 exit /b 1

set "VantaToggleName=%~1"
set "VantaToggleState=%~2"
set "VantaLauncherPath=%~3"
if not defined VantaToggleName exit /b 87
if not defined VantaToggleState exit /b 87
if not defined VantaLauncherPath exit /b 87
shift /1
shift /1
shift /1

set "VantaLauncherSilent="
set "VantaLauncherJustContext="
set "VantaLauncherNoAction="
:parseArguments
if "%~1"=="" goto run
if /i "%~1"=="/silent" goto flagSilent
if /i "%~1"=="-silent" goto flagSilent
if /i "%~1"=="/quiet" goto flagSilent
if /i "%~1"=="-quiet" goto flagSilent
if /i "%~1"=="/justcontext" goto flagJustContext
if /i "%~1"=="-justcontext" goto flagJustContext
if /i "%~1"=="/noaction" goto flagNoAction
if /i "%~1"=="-noaction" goto flagNoAction
exit /b 87
:flagSilent
set "VantaLauncherSilent=/silent"
shift /1
goto parseArguments
:flagJustContext
set "VantaLauncherJustContext=/justcontext"
shift /1
goto parseArguments
:flagNoAction
set "VantaLauncherNoAction=/noaction"
shift /1
goto parseArguments

:run
set "VantaStateArgument="
if not "%VantaToggleState%"=="-" set "VantaStateArgument=-State "%VantaToggleState%""
"%VantaNativePowerShell%" -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%VantaWindowsRoot%\VantaModules\Scripts\Entry\Invoke-Toggle.ps1" -Name "%VantaToggleName%" %VantaStateArgument% -LauncherPath "%VantaLauncherPath%" %VantaLauncherSilent% %VantaLauncherJustContext% %VantaLauncherNoAction%
rem The code is named: a bare exit /b reports 0 when this file is run directly by
rem cmd /c rather than called, as Vanta Manager and the Toolbox do.
if errorlevel 0 (
    if errorlevel 1 exit /b %errorlevel%
) else (
    exit /b 1
)
exit /b 0
