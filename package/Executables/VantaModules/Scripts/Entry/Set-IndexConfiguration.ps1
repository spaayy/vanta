<#
.SYNOPSIS
    Compatibility entry for Set-IndexConfiguration.cmd: one checked Windows Search
    index operation through Vanta.Search, exiting 1 on any failure.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        'Include',
        'Exclude',
        'CleanPolicies',
        'Start',
        'Stop',
        'SetRespectPowerModes',
        'ResetSetupCompleted'
    )]
    [string]$Operation,

    [string]$IndexPath,

    [ValidateSet(0, 1)]
    [int]$SettingValue
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$scriptsRoot = [IO.Path]::GetFullPath([IO.Path]::GetDirectoryName($PSScriptRoot))
$bootstrap = [IO.Path]::Combine($scriptsRoot, 'Initialize-VantaPowerShell.ps1')
if (-not [IO.File]::Exists($bootstrap)) { throw "The PowerShell bootstrap is missing at '$bootstrap'." }
. $bootstrap
$modulesRoot = Join-Path -Path $scriptsRoot -ChildPath 'Modules'
Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Core\Vanta.Core.psd1') `
    -Force -ErrorAction Stop
Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Search\Vanta.Search.psd1') `
    -Force -ErrorAction Stop

try {
    $parameters = @{ Operation = $Operation }
    if ($PSBoundParameters.ContainsKey('IndexPath')) {
        $parameters['IndexPath'] = $IndexPath
    }
    if ($PSBoundParameters.ContainsKey('SettingValue')) {
        $parameters['SettingValue'] = $SettingValue
    }
    Set-VantaIndexConfiguration @parameters
}
catch {
    Write-Error -ErrorRecord $_ -ErrorAction Continue
    exit 1
}

exit 0
