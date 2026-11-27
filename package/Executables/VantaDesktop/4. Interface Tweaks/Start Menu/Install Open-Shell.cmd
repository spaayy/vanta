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
set "script=%VantaWindowsRoot%\VantaModules\Scripts\Entry\Install-OpenShell.ps1"
if not exist "%script%" (
	echo Script not found.
	echo "%script%"
	exit /b 1
)

:: Capture one compatibility token as data; it is never passed on as command text.
set "VantaLauncherArgument=%~1"

"%VantaNativeFltmc%" > nul 2>&1
if not errorlevel 1 goto alreadyElevated

:: This window only waits for the elevated one, which prints the rest of the run.
if not defined VantaLauncherArgument (
	echo Vanta - Install Open-Shell
	echo ----------------------------
	echo.
	echo Asking for administrator permission...
)
"%VantaNativePowerShell%" -NoLogo -NoProfile -Command "$a=$env:VantaLauncherArgument;if($a -and $a -notin @('/silent','-silent')){exit 2};$s=[IO.Path]::Combine([Environment]::GetFolderPath('Windows'),'VantaModules','Scripts','Entry','Install-OpenShell.ps1');$p=[Activator]::CreateInstance([Diagnostics.ProcessStartInfo]);$p.FileName=[IO.Path]::Combine([Environment]::GetFolderPath('System'),'WindowsPowerShell','v1.0','powershell.exe');$p.WorkingDirectory=[Environment]::GetFolderPath('System');$q=[char]34;$p.Arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -File '+$q+$s+$q+' -ShellRefreshByCaller'+$(if($a){' -Silent'});$p.UseShellExecute=$true;$p.Verb='runas';try{$c=[Diagnostics.Process]::Start($p);if($null -eq $c){exit 1};$c.WaitForExit();exit $c.ExitCode}catch{if($_.Exception -is [ComponentModel.Win32Exception] -and $_.Exception.NativeErrorCode -eq 1223){exit 1223};exit 1}"
if errorlevel 0 (
    if errorlevel 1 exit /b
) else (
    exit /b 1
)

:: The UAC child is complete, but this launcher is still medium integrity. Refresh
:: and restart Explorer only in this caller's Windows session.
set "shellRefreshScript=%VantaWindowsRoot%\VantaModules\Scripts\Operations\Invoke-VantaUserShellRefresh.ps1"
if not exist "%shellRefreshScript%" (
    if not defined VantaLauncherArgument echo User-session shell refresh helper not found: "%shellRefreshScript%"
    goto shellRefreshFailed
)
if not defined VantaLauncherArgument echo Restarting File Explorer...
"%VantaNativePowerShell%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%shellRefreshScript%" -CurrentSession
if errorlevel 0 (
    if errorlevel 1 goto shellRefreshFailed
) else (
    goto shellRefreshFailed
)
if not defined VantaLauncherArgument echo File Explorer was restarted to apply this change.
exit /b 0

:shellRefreshFailed
:: The elevated window already said Done and closed, so this one owns the advice.
if not defined VantaLauncherArgument (
    echo Partly done: Open-Shell is installed, but File Explorer could not be restarted safely in this session.
    echo Restart File Explorer, or sign out and back in, to see this change.
    echo.
    set /p "VantaExit=Press Enter to exit. "
)
exit /b 1

:alreadyElevated
"%VantaNativePowerShell%" -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%script%"
if errorlevel 0 (
    if errorlevel 1 exit /b
) else (
    exit /b 1
)
exit /b 0
