<#
.SYNOPSIS
    Sets the Safe Mode that Windows starts in from the next restart, or leaves it.
.DESCRIPTION
    Changes the safeboot and safebootalternateshell values of the current boot entry
    with bcdedit. The SafeMode toggle runs this script with the call operator in its
    elevated process, so a failure is a terminating error, not an exit code. While a CBS
    retry is waiting, only Exit is allowed.

    CbsRetry.ps1 dot-sources it with -LibraryOnly.
.PARAMETER Mode
    Minimal, Networking or CommandPrompt for that Safe Mode, or Exit to start normally.
.PARAMETER LibraryOnly
    Only defines the functions, for callers that dot-source the script.
#>
[CmdletBinding()]
param(
    [ValidateSet('Minimal', 'Networking', 'CommandPrompt', 'Exit')]
    [string]$Mode,
    [switch]$LibraryOnly
)

Set-StrictMode -Version 3.0

function Get-VantaSafeModePaths {
    $windows = [Environment]::GetFolderPath('Windows')
    if ([string]::IsNullOrWhiteSpace($windows)) {
        throw 'Windows did not provide its Windows directory.'
    }
    $recovery = Join-Path $windows 'VantaOS\Recovery'
    [pscustomobject]@{
        BcdEdit       = Join-Path $windows 'System32\bcdedit.exe'
        Recovery      = $recovery
        ShellState    = Join-Path $recovery 'SafeMode.json'
        CbsRetryState = Join-Path $recovery 'CbsRetry.json'
    }
}

function Invoke-VantaBcdEdit {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $executable = (Get-VantaSafeModePaths).BcdEdit
    if (![IO.File]::Exists($executable)) { throw "Required Windows executable '$executable' is missing." }
    $output = @(& $executable @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "bcdedit.exe failed with exit code $LASTEXITCODE`: $($output -join ' ')"
    }
    return $output
}

function Get-VantaSafeBootConfiguration {
    $safeBoot = $null
    $alternatePresent = $false
    $alternateShell = $false
    foreach ($line in @(Invoke-VantaBcdEdit -Arguments @('/enum', '{current}'))) {
        if ([string]$line -match '^\s*safeboot\s+(\S+)\s*$') {
            $safeBoot = switch ($Matches[1].ToLowerInvariant()) {
                'minimal' { 'minimal' }
                'network' { 'network' }
                default { throw "Unsupported current safeboot value '$($Matches[1])'." }
            }
        }
        elseif ([string]$line -match '^\s*safebootalternateshell\s+(\S+)\s*$') {
            $alternatePresent = $true
            $alternateShell = $Matches[1] -match '^(?i:yes|true)$'
        }
    }
    [pscustomobject]@{
        SafeBoot              = $safeBoot
        AlternateShellPresent = $alternatePresent
        AlternateShell        = $alternateShell
    }
}

function Get-VantaWinlogonShell {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
        'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon', $false)
    if ($null -eq $key) { throw 'The Winlogon registry key is missing.' }
    try {
        [pscustomobject]@{
            Value = [string]$key.GetValue('Shell', $null,
                [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            Kind  = $key.GetValueKind('Shell').ToString()
        }
    }
    finally { $key.Dispose() }
}

function Set-VantaWinlogonShell {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][ValidateSet('String', 'ExpandString')][string]$Kind
    )
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
        'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon', $true)
    if ($null -eq $key) { throw 'The Winlogon registry key could not be opened for writing.' }
    try { $key.SetValue('Shell', $Value, [Microsoft.Win32.RegistryValueKind]::$Kind) }
    finally { $key.Dispose() }
}

# Earlier Vanta builds set the Winlogon shell to cmd.exe for CommandPrompt mode and saved
# the original here; it's read only to put that shell back.
function Read-VantaSafeModeShellState {
    param([string]$Path = (Get-VantaSafeModePaths).ShellState)
    if (![IO.File]::Exists($Path)) { return $null }
    $state = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($state.Version -ne 1 -or $state.Owner -cne 'Vanta' -or
        [string]::IsNullOrEmpty([string]$state.OriginalShell) -or
        [string]$state.OriginalKind -notin @('String', 'ExpandString')) {
        throw "Safe Mode shell state '$Path' is invalid."
    }
    return $state
}

function Clear-VantaSafeModeShellState {
    param([string]$Path = (Get-VantaSafeModePaths).ShellState)
    if ([IO.File]::Exists($Path)) { [IO.File]::Delete($Path) }
}

function Test-VantaCbsRetryPending {
    $path = (Get-VantaSafeModePaths).CbsRetryState
    if (![IO.File]::Exists($path)) { return $false }
    $state = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($state.Version -ne 1 -or [string]$state.Phase -notin @('Pending', 'Armed')) {
        throw "CBS retry state '$path' is invalid."
    }
    return $true
}

function Restore-VantaSafeModeShell {
    param($CurrentShell, $State)
    if ($null -eq $State) { return }
    if ([string]::Equals([string]$CurrentShell.Value, 'cmd.exe', [StringComparison]::OrdinalIgnoreCase)) {
        Set-VantaWinlogonShell -Value ([string]$State.OriginalShell) -Kind ([string]$State.OriginalKind)
    }
    Clear-VantaSafeModeShellState
}

function Set-VantaSafeMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Minimal', 'Networking', 'CommandPrompt', 'Exit')]
        [string]$Mode,
        [switch]$AllowCbsRetryPending
    )

    if ($Mode -cne 'Exit' -and !$AllowCbsRetryPending -and (Test-VantaCbsRetryPending)) {
        # CbsRetry.ps1 owns the wording of how to give up the retry.
        . (Join-Path $PSScriptRoot 'CbsRetry.ps1') -LibraryOnly
        throw "A CBS retry is pending; only Exit may change Safe Mode. $(Get-VantaCbsRetryInstruction -Phase Pending)"
    }
    $boot = Get-VantaSafeBootConfiguration
    $shell = Get-VantaWinlogonShell
    $shellState = Read-VantaSafeModeShellState

    if ($Mode -ceq 'Exit') {
        if ($boot.AlternateShellPresent) {
            Invoke-VantaBcdEdit -Arguments @('/deletevalue', '{current}', 'safebootalternateshell') | Out-Null
        }
        if ($null -ne $boot.SafeBoot) {
            Invoke-VantaBcdEdit -Arguments @('/deletevalue', '{current}', 'safeboot') | Out-Null
        }
        Restore-VantaSafeModeShell -CurrentShell $shell -State $shellState
        return
    }

    $target = if ($Mode -ceq 'Networking') { 'network' } else { 'minimal' }
    if ($boot.SafeBoot -cne $target) {
        Invoke-VantaBcdEdit -Arguments @('/set', '{current}', 'safeboot', $target) | Out-Null
    }
    if ($Mode -ceq 'CommandPrompt') {
        # This boot starts the SafeBoot AlternateShell (cmd.exe). The Winlogon shell is left
        # alone because normal boots use it, including after leaving Safe Mode through msconfig.
        if (!$boot.AlternateShellPresent -or !$boot.AlternateShell) {
            Invoke-VantaBcdEdit -Arguments @('/set', '{current}', 'safebootalternateshell', 'yes') | Out-Null
        }
    }
    elseif ($boot.AlternateShellPresent) {
        Invoke-VantaBcdEdit -Arguments @('/deletevalue', '{current}', 'safebootalternateshell') | Out-Null
    }
    Restore-VantaSafeModeShell -CurrentShell $shell -State $shellState
}

if (!$LibraryOnly) {
    if ([string]::IsNullOrEmpty($Mode)) { throw 'Specify -Mode or use -LibraryOnly.' }
    Set-VantaSafeMode -Mode $Mode
}
