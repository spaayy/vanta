<#
.SYNOPSIS
    Opens Vanta Manager before the desktop on a PC installed from Vanta media.
.DESCRIPTION
    Never runs on the PC that built the ISO. In before-desktop mode, Setup.ps1 registers
    this script as the setup account's Windows shell, so it runs at that account's
    sign-in from %windir%\VantaISO. It relaunches itself without a console, waits for
    the account preparation to finish, starts Vanta Manager elevated and then starts
    Explorer behind it.

    When Vanta Manager exits, the desktop cleanup task removes the shell policy, so the
    next sign-in opens the normal desktop. When Vanta Manager closes for a restart it
    asked for, the policy stays for the next sign-in. Every failure is appended to
    %LOCALAPPDATA%\Vanta-desktop-recovery.log and still leaves Explorer running.
.PARAMETER RestoreDesktop
    Removes the shell policy through the cleanup task and starts Explorer; for recovery
    by hand.
.PARAMETER Detached
    Marks the relaunch without a console.
.NOTES
    Windows starts it as a shell and reads no exit code, so failures go to the recovery
    log instead.
#>
[CmdletBinding()]
param([switch]$RestoreDesktop, [switch]$Detached)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:WINDIR 'VantaISO'
if ([IO.Path]::GetFullPath($PSScriptRoot) -ine [IO.Path]::GetFullPath($root)) { throw 'Unexpected desktop setup location.' }
. (Join-Path $root 'Desktop-Policy.ps1')
$policyPath = 'Software\Microsoft\Windows\CurrentVersion\Policies\System'
$shell = Get-VantaDesktopShell $root
$state = 'HKCU:\Software\Vanta\DesktopSetup'
function Start-VantaWindowsShell {
    # Explorer runs unelevated: Settings, Windows Security and Store activation
    # need its shell services. Vanta covers the desktop but does not lock it.
    $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session)) {
        Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe')
    }
}
function Restore-VantaDesktop {
    $readOwned = {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($policyPath)
        try { Test-VantaOwnedShell $key $shell }
        finally { if ($key) { $key.Dispose() } }
    }
    try {
        if (-not (& $readOwned)) { return }
        Request-VantaDesktopCleanup ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
        # Starting the task doesn't wait for it, so poll until SYSTEM has removed the policy.
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        do {
            Start-Sleep -Milliseconds 200
            $ownedShell = & $readOwned
        } while ($ownedShell -and [DateTime]::UtcNow -lt $deadline)
        if ($ownedShell) { throw 'Vanta desktop policy cleanup did not finish. Retry Desktop.ps1 -RestoreDesktop.' }
    }
    catch { Write-VantaDesktopRecoveryLog $_ }
    finally { Start-VantaWindowsShell }
}
if ($RestoreDesktop) { Restore-VantaDesktop; exit }
if (-not $Detached) {
    try {
        # WindowStyle Hidden still opens the default terminal and blocks its Store
        # update. Relaunch without a console, then release the original terminal.
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = Get-VantaPowerShellPath
        $start.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Detached'
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $process = [Diagnostics.Process]::Start($start)
        $process.Dispose()
    } catch {
        Write-VantaDesktopRecoveryLog $_
        Restore-VantaDesktop
    }
    exit
}
$mutex = New-Object Threading.Mutex($false, ('Local\Vanta.DesktopSetup.' + [Diagnostics.Process]::GetCurrentProcess().SessionId))
$owned = $false
try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
if (-not $owned) {
    # Explorer recovery can ask Windows to start the configured shell again.
    # Leave the existing supervisor and its recovery policy alone.
    $mutex.Dispose()
    exit
}
try {
    # FirstLogonCommands prepares the account and signs out. Do not show Explorer
    # during that bootstrap, or run updates before the user's native password change.
    $marker = Join-Path $root 'account-ready'
    $deadline = [DateTime]::UtcNow.AddMinutes(3)
    $bootstrap = -not (Test-Path -LiteralPath $marker)
    while (-not (Test-Path -LiteralPath $marker)) {
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Account preparation timed out.' }
        Start-Sleep -Seconds 1
    }
    # The marker appeared during this session, so Setup.ps1 is signing out. Wait
    # for that rather than show the desktop.
    if ($bootstrap) { Start-Sleep -Seconds 60; throw 'Account preparation did not sign out.' }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ([IO.File]::ReadAllText($marker).Trim() -ne $sid) { throw 'This account does not own Vanta setup.' }
    New-Item -Path $state -Force | Out-Null
    Remove-ItemProperty -LiteralPath $state -Name RestartRequested -ErrorAction SilentlyContinue
    $app = Join-Path $root 'VantaManager.exe'
    if (-not (Test-Path -LiteralPath $app)) { throw 'The Vanta setup app is missing.' }
    # Windows Update and Store preparation need this user's elevated token.
    # Declining UAC returns to the desktop.
    $child = Start-Process -FilePath $app -ArgumentList '--before-desktop' -Verb RunAs -PassThru
    # Let the full-screen app appear before starting the normal shell behind it.
    # A failed or hung app must still leave access to Windows.
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        $child.Refresh()
        if ($child.HasExited -or $child.MainWindowHandle -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    Start-VantaWindowsShell
    # Wait for Vanta itself. Settings or help windows may outlive it and must
    # not prevent the user from returning to the desktop.
    $child.WaitForExit()
    $intent = Get-ItemProperty -LiteralPath $state -ErrorAction SilentlyContinue
    if ($intent -and $intent.PSObject.Properties['RestartRequested']) {
        $requested = [DateTimeOffset]::FromUnixTimeSeconds([long]$intent.RestartRequested)
        # Vanta Manager records the time right before it asks Windows to restart. A
        # request older than two minutes is a restart that didn't happen.
        if (([DateTimeOffset]::UtcNow - $requested).TotalSeconds -lt 120) {
            # Windows closes the app before shutting down. Keep the shell policy
            # until the next sign-in instead of mistaking this for a user exit.
            Start-Sleep -Seconds 60
        }
    }
    if ($child.ExitCode -ne 0) { throw "Vanta exited with code $($child.ExitCode)." }
}
catch {
    # A broken app, declined elevation or bootstrap failure must leave a usable PC.
    Write-VantaDesktopRecoveryLog $_
}
finally {
    try { Restore-VantaDesktop }
    finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
}
