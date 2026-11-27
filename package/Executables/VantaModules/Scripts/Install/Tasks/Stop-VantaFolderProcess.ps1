<#
.SYNOPSIS
    Stops the processes and scheduled tasks that run from the installed Vanta folders, so
    their files can be replaced.
.DESCRIPTION
    Invoke-VantaPackageReplacement.ps1 runs it as TrustedInstaller on an update, a
    reinstall or a Rebase.
#>
[CmdletBinding()]
param()

$trustBootstrap = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, '..', '..', 'Initialize-VantaPowerShell.ps1'))
if (-not [IO.File]::Exists($trustBootstrap)) {
    throw "The PowerShell trust bootstrap is missing at '$trustBootstrap'."
}
. $trustBootstrap

$ErrorActionPreference = 'Stop'

# Runs before Vanta's files are copied on upgrades, so the module is imported from
# the extracted package directory rather than the (stale) copy in %windir%.
$executablesRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$coreModule = Join-Path -Path $executablesRoot -ChildPath 'VantaModules\Scripts\Modules\Vanta.Core\Vanta.Core.psd1'
if (-not (Test-Path -LiteralPath $coreModule -PathType Leaf)) {
    throw "Vanta core module '$coreModule' is missing."
}

Import-Module $coreModule -Force

$tasksProcsModule = Join-Path -Path $executablesRoot -ChildPath 'VantaModules\Scripts\Modules\Vanta.TasksProcs\Vanta.TasksProcs.psd1'
if (-not (Test-Path -LiteralPath $tasksProcsModule -PathType Leaf)) {
    throw "Vanta tasks/processes module '$tasksProcsModule' is missing."
}

Import-Module $tasksProcsModule -Force

$windir = [Environment]::GetFolderPath('Windows')
$targetRoots = @(
    Join-Path -Path $windir -ChildPath 'VantaModules'
    Join-Path -Path $windir -ChildPath 'VantaDesktop'
) | ForEach-Object {
    try {
        ([System.IO.Path]::GetFullPath($_)).TrimEnd('\')
    }
    catch {
        $null
    }
} | Where-Object { $_ }

if (-not $targetRoots) {
    return
}

$rootsLower = $targetRoots | ForEach-Object { ($_ + '\').ToLowerInvariant() }
# This helper runs as TrustedInstaller in session 0. Interactive Vanta tools in
# another Windows session are not cleanup targets; open handles will make replacement fail.
Stop-VantaProcessUnderRoot -RootsLower $rootsLower -SessionId 0
Stop-VantaScheduledTaskUnderRoot -RootsLower $rootsLower

$timerExePath = Join-Path -Path $windir -ChildPath 'VantaModules\Tools\SetTimerResolution.exe'
if (Test-Path -LiteralPath $timerExePath -PathType Leaf) {
    try {
        $stream = [System.IO.File]::Open($timerExePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $stream.Dispose()
    }
    catch {
        Stop-VantaProcessUnderRoot -RootsLower $rootsLower -SessionId 0
        Start-Sleep -Milliseconds 500
    }
}
