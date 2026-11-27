<#
.SYNOPSIS
    Brings back what a Windows that rebuilt itself during Vanta Manager's move to a
    newer release left behind: the service backups and the recorded choices.
.DESCRIPTION
    Runs in Rebase installs only, after Vanta's files are copied and before the
    recorded choices are read. Setup moves %windir%\VantaModules to Windows.old, so
    the service backups made before Vanta first changed the services are copied back
    from there. The recorded choices come from Vanta Manager's record of the move
    when the registry that held them is gone; existing records are never replaced.
    Those of an Vanta before 0.6 are then read as Vanta 0.6 means them, as an
    update's Capture reads the records it finds.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Assert-VantaPrivilege -TrustedInstaller
$scriptsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $scriptsRoot 'Preparation\WindowsTransition.ps1')
Import-Module -Name (Join-Path $scriptsRoot 'Modules\Vanta.Toggles\Vanta.Toggles.psd1') -Force -ErrorAction Stop
Import-Module -Name (Join-Path $scriptsRoot 'Modules\Vanta.InstallState\Vanta.InstallState.psd1') -Force -DisableNameChecking -ErrorAction Stop

$rebase = Get-VantaWindowsTransitionRebase
if ($null -eq $rebase) {
    throw 'A Rebase install needs Vanta Manager''s record of the Windows move, which is gone or unreadable.'
}
foreach ($name in @('winServices.reg', 'vantaServices.reg')) {
    Write-VantaLog -Message (Copy-VantaRebaseServiceBackup -Name $name)
}
foreach ($line in @(Restore-VantaRebaseChoice $rebase.Carry)) {
    Write-VantaLog -Message ([string]$line)
}
