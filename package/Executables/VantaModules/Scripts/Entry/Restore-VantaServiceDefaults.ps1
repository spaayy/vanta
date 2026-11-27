<#
.SYNOPSIS
    Fixed noninteractive implementation for the broker's ResetServices operation.
.DESCRIPTION
    Always applies the unique service-toggle state whose launcher is marked '(default)'.
    WindowsBackup and VantaBackup then restore typed Start values from one strictly
    validated Vanta-owned snapshot, preserving the established defaults-first order.
    No caller-selected script, executable, registry file, or argument vector is accepted.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('ToggleDefaults', 'WindowsBackup', 'VantaBackup')]
    [string]$RestoreSource
)

$scriptsRoot = [IO.Path]::GetFullPath([IO.Path]::GetDirectoryName($PSScriptRoot))
$bootstrap = [IO.Path]::Combine($scriptsRoot, 'Initialize-VantaPowerShell.ps1')
if (-not [IO.File]::Exists($bootstrap)) { throw "The PowerShell bootstrap is missing at '$bootstrap'." }
. $bootstrap

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

try {
    $validRestoreSources = @('ToggleDefaults', 'WindowsBackup', 'VantaBackup')
    if ($validRestoreSources -cnotcontains $RestoreSource) {
        throw 'RestoreSource must use exact canonical casing.'
    }

    $scriptsRoot = Split-Path -Parent $PSScriptRoot
    $modulesRoot = Join-Path -Path $scriptsRoot -ChildPath 'Modules'
    $coreManifest = Join-Path -Path $modulesRoot -ChildPath 'Vanta.Core\Vanta.Core.psd1'
    $servicesManifest = Join-Path -Path $modulesRoot -ChildPath 'Vanta.Services\Vanta.Services.psd1'
    $togglesManifest = Join-Path -Path $modulesRoot -ChildPath 'Vanta.Toggles\Vanta.Toggles.psd1'
    Import-Module -Name $coreManifest -Force -ErrorAction Stop
    $servicesModules = @(Import-Module -Name $servicesManifest -Force -PassThru -ErrorAction Stop)
    if ($servicesModules.Count -ne 1) {
        throw "The fixed Vanta.Services manifest loaded $($servicesModules.Count) module objects; expected exactly one."
    }
    $servicesModule = $servicesModules[0]
    $expectedServicesModulePath = [IO.Path]::GetFullPath(
        (Join-Path -Path (Split-Path -Parent $servicesManifest) -ChildPath 'Vanta.Services.psm1')
    )
    if ([string]::IsNullOrWhiteSpace([string]$servicesModule.Path) -or
        -not [string]::Equals(
            [IO.Path]::GetFullPath([string]$servicesModule.Path),
            $expectedServicesModulePath,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        throw "The loaded Vanta.Services module does not match the fixed manifest '$servicesManifest'."
    }
    $togglesModules = @(Import-Module -Name $togglesManifest -Force -PassThru -ErrorAction Stop)
    if ($togglesModules.Count -ne 1) {
        throw "The fixed Vanta.Toggles manifest loaded $($togglesModules.Count) module objects; expected exactly one."
    }
    $togglesModule = $togglesModules[0]
    $expectedTogglesModulePath = [IO.Path]::GetFullPath(
        (Join-Path -Path (Split-Path -Parent $togglesManifest) -ChildPath 'Vanta.Toggles.psm1')
    )
    if ([string]::IsNullOrWhiteSpace([string]$togglesModule.Path) -or
        -not [string]::Equals(
            [IO.Path]::GetFullPath([string]$togglesModule.Path),
            $expectedTogglesModulePath,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        throw "The loaded Vanta.Toggles module does not match the fixed manifest '$togglesManifest'."
    }
    Assert-VantaPrivilege -TrustedInstaller

    $context = Get-VantaContext
    $snapshot = $null
    if ($RestoreSource -cne 'ToggleDefaults') {
        $fileName = if ($RestoreSource -ceq 'WindowsBackup') { 'winServices.reg' } else { 'vantaServices.reg' }
        $snapshot = Join-Path -Path $context.VantaModulesPath -ChildPath "Other\$fileName"
    }

    # Enter the exact module object loaded from the fixed manifest. The private function is
    # parameterless and owns the complete service-definition and state allowlist.
    & $togglesModule { Invoke-VantaServiceDefaultsReset }

    if ($snapshot) {
        [void](Restore-VantaServicesBackup -FilePath $snapshot)
    }

    exit 0
}
catch {
    # The native launcher gives this process no console or standard handles, so the
    # broker sees only the exit code. Keep the reason in the machine log.
    $failureMessage = "Resetting services to defaults ($RestoreSource) failed: $($_.Exception.Message)"
    if (Get-Command -Name Write-VantaLog -ErrorAction SilentlyContinue) {
        Write-VantaLog -Level Error -Message $failureMessage -ErrorRecord $_
    }
    else {
        [Console]::Error.WriteLine($failureMessage)
    }
    exit 1
}
