<#
.SYNOPSIS
    Hides or unhides one Settings page for the Vanta launcher scripts.
#>
[CmdletBinding()]
param (
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('/hide', '/unhide', 'hide', 'unhide')]
    [string]$Operation,

    [Parameter(Position = 1, Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Page,

    [switch]$Silent,

    [switch]$NoProcessCleanup
)

$ErrorActionPreference = 'Stop'
# Launchers pass -Silent for parity with the toggle launchers; a visibility change has
# no interactive output to suppress.
[void]$Silent

$scriptsRoot = [IO.Path]::GetFullPath([IO.Path]::GetDirectoryName($PSScriptRoot))
$bootstrap = [IO.Path]::Combine($scriptsRoot, 'Initialize-VantaPowerShell.ps1')
if (-not [IO.File]::Exists($bootstrap)) { throw "The PowerShell bootstrap is missing at '$bootstrap'." }
. $bootstrap
Import-Module -Name (Join-Path -Path $scriptsRoot -ChildPath 'Modules\Vanta.Shell\Vanta.Shell.psd1') -ErrorAction Stop

Set-VantaSettingsPageVisibility -Operation $Operation.TrimStart('/') -Page $Page `
    -NoProcessCleanup:$NoProcessCleanup
