<#
.SYNOPSIS
    Puts back the Windows Update settings Vanta Manager turned on to update Windows,
    after this install has replayed the user's recorded choices and written its pin.
.DESCRIPTION
    Runs in every install mode. Without an open Windows Update record it does nothing.
    A problem here is a warning, never an install failure: the record stays open and
    Vanta Manager offers to put the settings back from Home.
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Assert-VantaPrivilege -TrustedInstaller
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Preparation\WindowsTransition.ps1')

try {
    foreach ($line in @(Complete-VantaWindowsTransition -Rebased:([bool](Get-VantaContext).IsRebase))) {
        Write-VantaLog -Message ([string]$line)
    }
}
catch {
    Write-VantaLog -Level Warning -Message "Windows Update settings were not put back: $($_.Exception.Message) Vanta Manager offers to put them back from Home."
}
