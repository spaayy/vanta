# Starts the four supported TrustedInstaller operations through Vanta.Native.cs.
# Requests select a fixed operation; callers cannot supply an executable or command
# line. Native code resolves protected entry points and uses the TrustedInstaller
# token, with no fallback to LSASS, winlogon or a generic SYSTEM process.

function Get-VantaCurrentTokenEvidence {
    Initialize-VantaNativeType
    return [Vanta.Native.TrustedInstallerProcess]::GetCurrentTokenEvidence()
}

function Invoke-VantaTrustedInstallerNativeOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Toggle', 'ResetServices', 'Install', 'CbsRetry')]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 86400000)]
        [int]$TimeoutMilliseconds,

        [string]$Name,
        [string]$State,
        [switch]$Silent,
        [switch]$JustContext,
        [switch]$NoExplorerRestart,
        [switch]$MachineOnly,
        [ValidateSet('ToggleDefaults', 'WindowsBackup', 'VantaBackup')]
        [string]$RestoreSource,
        [ValidateSet('Capture', 'Run')]
        [string]$InstallPhase,
        [string]$PackageRoot
    )

    Initialize-VantaNativeType

    $request = New-Object -TypeName Vanta.Native.TrustedInstallerLaunchRequest
    $request.Operation = $Operation
    $request.VantaModulesPath = (Get-VantaContext).VantaModulesPath
    $request.ToggleName = $Name
    $request.ToggleState = $State
    $request.Silent = [bool]$Silent
    $request.JustContext = [bool]$JustContext
    $request.NoExplorerRestart = [bool]$NoExplorerRestart
    $request.MachineOnly = [bool]$MachineOnly
    $request.RestoreSource = $RestoreSource
    $request.InstallPhase = $InstallPhase
    $request.PackageRoot = $PackageRoot
    $request.TimeoutMilliseconds = $TimeoutMilliseconds

    return [Vanta.Native.TrustedInstallerProcess]::LaunchNonInteractive($request)
}
