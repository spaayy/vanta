<#
.SYNOPSIS
    Replaces the installed Vanta files with those from the extracted package.
.DESCRIPTION
    The install plan's Checkpoint/PayloadReplacement step runs it as TrustedInstaller from
    the extracted package, on every attempt in every install mode.

    The committed install state decides whether an existing installation must be
    stopped and removed. Replacement is blocked while a CBS retry is armed, so the
    recovery command can't be deleted underneath Safe Mode. A retry that was never
    armed, and the Safe Mode package list Vanta 0.5 left in System32, are given up first.
#>

[CmdletBinding()]
param(
    [switch]$LibraryOnly
)

$trustBootstrap = [IO.Path]::GetFullPath([IO.Path]::Combine(
        $PSScriptRoot, '..', '..', 'Initialize-VantaPowerShell.ps1'
    ))
if (-not [IO.File]::Exists($trustBootstrap)) {
    throw "The PowerShell trust bootstrap is missing at '$trustBootstrap'."
}
. $trustBootstrap

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Resolve-VantaPackageReplacementPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][psobject]$InstallState)

    foreach ($property in @('status', 'mode')) {
        if ($null -eq $InstallState.PSObject.Properties[$property]) {
            throw "Install state is missing required '$property' field."
        }
    }
    if ([string]$InstallState.status -cne 'Running') {
        throw "Replacing Vanta's files requires a Running install state, not '$($InstallState.status)'."
    }
    if (@('Fresh', 'Upgrade', 'Reapply', 'Rebase') -cnotcontains [string]$InstallState.mode) {
        throw "Replacing Vanta's files does not support install mode '$($InstallState.mode)'."
    }

    $hasInstalledPackage = [string]$InstallState.mode -cne 'Fresh'
    $completedSteps = @()
    if ($null -ne $InstallState.PSObject.Properties['completedSteps']) {
        $completedSteps = @($InstallState.completedSteps)
    }
    return [pscustomobject][ordered]@{
        Mode                   = [string]$InstallState.mode
        StopInstalledPackage   = $hasInstalledPackage
        RemoveInstalledPackage = $hasInstalledPackage
        ChoicesReplayed        = $completedSteps -icontains 'Defaults'
    }
}

function Assert-VantaPackageReplacementAllowed {
    Remove-VantaLegacyCbsRetryList
    Clear-VantaUnarmedCbsRetry
    $retryState = Read-VantaCbsRetryState
    if ($null -ne $retryState) {
        throw "Replacing Vanta's files is blocked while the CBS retry state is '$($retryState.Phase)' ('$(Get-VantaCbsRetryStatePath)'). $(Get-VantaCbsRetryInstruction -Phase ([string]$retryState.Phase))"
    }
}

function Invoke-VantaInstalledPackageStop {
    & $script:VantaStopInstalledPackageScript
}

function Invoke-VantaProcessExplorerStop {
    & $script:VantaStopProcessExplorerScript
}

function Invoke-VantaInstalledPackageRemove {
    & $script:VantaRemoveInstalledPackageScript
}

function Invoke-VantaExtractedPackageCopy {
    & $script:VantaCopyPackageScript
}

function Test-VantaProcessExplorerChoiceEnabled {
    $statePath = 'HKLM:\SOFTWARE\Vanta\Services\ProcessExplorer'
    if (-not (Test-Path -LiteralPath $statePath)) {
        return $false
    }
    $stateKey = Get-Item -LiteralPath $statePath -ErrorAction Stop
    return @($stateKey.GetValueNames()) -contains 'state' -and
        $stateKey.GetValueKind('state') -eq [Microsoft.Win32.RegistryValueKind]::DWord -and
        [int]$stateKey.GetValue('state') -eq 1
}

function Invoke-VantaProcessExplorerRestore {
    # The same package operation the Defaults replay runs, which leaves pcw as it is.
    try {
        . ([IO.Path]::Combine($script:VantaWindowsPath, 'VantaModules', 'Scripts', 'Operations', 'ProcessExplorer-Package.ps1'))
        Install-VantaProcessExplorerPackage
    }
    catch {
        throw "Reinstalling Process Explorer for the recorded ProcessExplorer choice failed: $($_.Exception.Message)"
    }
    Write-Output 'Reinstalled Process Explorer for the recorded ProcessExplorer choice.'
}

function Assert-VantaPackageInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ExtractedExecutablesRoot,
        [Parameter(Mandatory = $true)][string]$WindowsPath
    )

    $sourceRoot = [IO.Path]::GetFullPath($ExtractedExecutablesRoot)
    $destinationRoot = [IO.Path]::GetFullPath($WindowsPath)
    foreach ($directory in @('VantaModules', 'VantaDesktop')) {
        $source = Join-Path -Path $sourceRoot -ChildPath $directory
        $destination = Join-Path -Path $destinationRoot -ChildPath $directory
        if (-not [IO.Directory]::Exists($source)) {
            throw "Required extracted directory '$source' is missing."
        }
        if (-not [IO.Directory]::Exists($destination)) {
            throw "Installed Vanta directory '$destination' is missing."
        }
    }

    $installedBootstrap = Join-Path -Path $destinationRoot -ChildPath 'VantaModules\Scripts\Initialize-VantaPowerShell.ps1'
    if (-not [IO.File]::Exists($installedBootstrap)) {
        throw "Installed Vanta bootstrap '$installedBootstrap' is missing."
    }

    $themesSource = Join-Path -Path $sourceRoot -ChildPath 'Themes'
    if (-not [IO.Directory]::Exists($themesSource)) {
        throw "Required extracted Themes directory '$themesSource' is missing."
    }
    $themesDestination = Join-Path -Path $destinationRoot -ChildPath 'Resources\Themes'
    foreach ($theme in @(Get-ChildItem -LiteralPath $themesSource -Force -ErrorAction Stop)) {
        $installedTheme = Join-Path -Path $themesDestination -ChildPath $theme.Name
        $installedItem = Get-Item -LiteralPath $installedTheme -Force -ErrorAction SilentlyContinue
        if ($null -eq $installedItem -or $installedItem.PSIsContainer -ne $theme.PSIsContainer) {
            throw "Installed Vanta theme '$installedTheme' is missing."
        }
    }
}

function Invoke-VantaPackageReplacementCore {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][psobject]$Plan)

    Assert-VantaPackageReplacementAllowed
    $restoreProcessExplorer = $false
    if ([bool]$Plan.StopInstalledPackage) {
        # The teardown below removes an enabled Process Explorer and Defaults puts it
        # back, but a resumed install skips Defaults once it has completed.
        $restoreProcessExplorer = [bool]$Plan.ChoicesReplayed -and (Test-VantaProcessExplorerChoiceEnabled)
        Invoke-VantaInstalledPackageStop
        Invoke-VantaProcessExplorerStop
    }
    if ([bool]$Plan.RemoveInstalledPackage) {
        Invoke-VantaInstalledPackageRemove
    }
    Invoke-VantaExtractedPackageCopy
    Assert-VantaPackageInstalled -ExtractedExecutablesRoot $script:VantaExtractedExecutablesRoot `
        -WindowsPath $script:VantaWindowsPath
    if ($restoreProcessExplorer) {
        Invoke-VantaProcessExplorerRestore
    }
}

if ($LibraryOnly) {
    return
}

$scriptsRoot = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, '..', '..'))
$script:VantaExtractedExecutablesRoot = [IO.Path]::GetFullPath([IO.Path]::Combine(
        $scriptsRoot, '..', '..'
    ))
$script:VantaWindowsPath = [Environment]::GetFolderPath('Windows')
if ([string]::IsNullOrWhiteSpace($script:VantaWindowsPath) -or
    -not [IO.Directory]::Exists($script:VantaWindowsPath)) {
    throw "Windows directory '$($script:VantaWindowsPath)' is not available."
}

$script:VantaStopInstalledPackageScript = Join-Path -Path $PSScriptRoot `
    -ChildPath 'Stop-VantaFolderProcess.ps1'
$script:VantaStopProcessExplorerScript = Join-Path -Path $PSScriptRoot `
    -ChildPath 'Stop-ProcessExplorerUpgrade.ps1'
$script:VantaRemoveInstalledPackageScript = Join-Path -Path $PSScriptRoot `
    -ChildPath 'Remove-PreviousVantaInstall.ps1'
$script:VantaCopyPackageScript = Join-Path -Path $PSScriptRoot -ChildPath 'Copy-VantaPackage.ps1'
$cbsRetryScript = Join-Path -Path $scriptsRoot -ChildPath 'Operations\CbsRetry.ps1'
$installStateManifest = Join-Path -Path $scriptsRoot `
    -ChildPath 'Modules\Vanta.InstallState\Vanta.InstallState.psd1'

foreach ($requiredFile in @(
        $script:VantaStopInstalledPackageScript,
        $script:VantaStopProcessExplorerScript,
        $script:VantaRemoveInstalledPackageScript,
        $script:VantaCopyPackageScript,
        $cbsRetryScript,
        $installStateManifest
    )) {
    if (-not [IO.File]::Exists($requiredFile)) {
        throw "Required extracted file is missing at '$requiredFile'."
    }
}

. $cbsRetryScript -LibraryOnly
Import-Module -Name $installStateManifest -Force -DisableNameChecking -ErrorAction Stop

$installState = Get-VantaInstallState
if ($null -eq $installState) {
    throw 'No Vanta install state is active.'
}
$plan = Resolve-VantaPackageReplacementPlan -InstallState $installState
Invoke-VantaPackageReplacementCore -Plan $plan

# Removing the previous files took the Vanta packages' repair source with them. The
# Features phase recreates it but runs once, so a retried install recreates it here,
# and Windows never names a repair source that is gone.
if ([bool]$plan.RemoveInstalledPackage) {
    try {
        $installedScripts = [IO.Path]::Combine($script:VantaWindowsPath, 'VantaModules', 'Scripts')
        . ([IO.Path]::Combine($installedScripts, 'Preparation', 'WindowsTransition.ps1'))
        Import-Module -Name ([IO.Path]::Combine($installedScripts, 'Modules', 'Vanta.Software', 'Vanta.Software.psd1')) -ErrorAction Stop
        Write-Output "Vanta packages' repair source: $(Update-VantaCbsRepairSource -VantaPackages @(Get-VantaInstalledVantaPackage))."
    }
    catch {
        Write-Warning "The Vanta packages' repair source was not checked after replacing Vanta's files: $($_.Exception.Message)"
    }
}
