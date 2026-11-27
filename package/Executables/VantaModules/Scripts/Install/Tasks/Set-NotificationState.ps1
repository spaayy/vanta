<#
.SYNOPSIS
    Turns toast notifications off while Vanta installs, then puts the policy back as it was.
.DESCRIPTION
    The install plan's NotificationDisable and NotificationRestore checkpoints run it as
    TrustedInstaller, at the start and the end of every install attempt.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Disable', 'Enable')]
    [string]$Mode
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$scriptsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$installStateModule = Join-Path -Path $scriptsRoot -ChildPath `
    'Modules\Vanta.InstallState\Vanta.InstallState.psd1'
Import-Module -Name $installStateModule -Force -DisableNameChecking -ErrorAction Stop

$installState = Get-VantaInstallState
if ($null -eq $installState -or [string]$installState.status -cne 'Running') {
    throw 'Notification changes require committed Vanta install state.'
}

$script:VantaNotificationPolicyPath =
    'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'
$script:VantaNotificationPolicyName = 'NoToastApplicationNotification'

function Get-VantaNotificationPolicyState {
    if (-not (Test-Path -LiteralPath $script:VantaNotificationPolicyPath)) {
        return [pscustomobject][ordered]@{ existed = $false; value = $null }
    }

    $key = Get-Item -LiteralPath $script:VantaNotificationPolicyPath -ErrorAction Stop
    if (@($key.GetValueNames()) -cnotcontains $script:VantaNotificationPolicyName) {
        return [pscustomobject][ordered]@{ existed = $false; value = $null }
    }

    $kind = $key.GetValueKind($script:VantaNotificationPolicyName)
    if ($kind -ne [Microsoft.Win32.RegistryValueKind]::DWord) {
        throw "Notification policy '$script:VantaNotificationPolicyName' must be a DWORD."
    }

    $value = $key.GetValue(
        $script:VantaNotificationPolicyName,
        $null,
        [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
    )
    if ($null -eq $value -or $value -isnot [int]) {
        throw "Notification policy '$script:VantaNotificationPolicyName' has an invalid DWORD value."
    }

    return [pscustomobject][ordered]@{ existed = $true; value = [int]$value }
}

function Write-VantaNotificationPolicyState {
    param([Parameter(Mandatory = $true)]$State)

    if ($State.existed) {
        # New-Item -Force recreates an existing key empty, which would drop the other
        # notification policies set beside this one.
        if (-not (Test-Path -LiteralPath $script:VantaNotificationPolicyPath)) {
            [void](New-Item -Path $script:VantaNotificationPolicyPath -Force -ErrorAction Stop)
        }
        [void](New-ItemProperty -LiteralPath $script:VantaNotificationPolicyPath `
                -Name $script:VantaNotificationPolicyName -PropertyType DWord `
                -Value ([int]$State.value) -Force -ErrorAction Stop)
    }
    elseif (Test-Path -LiteralPath $script:VantaNotificationPolicyPath) {
        Remove-ItemProperty -LiteralPath $script:VantaNotificationPolicyPath `
            -Name $script:VantaNotificationPolicyName -ErrorAction SilentlyContinue
    }

    $actual = Get-VantaNotificationPolicyState
    if ([bool]$actual.existed -ne [bool]$State.existed -or
        ($State.existed -and [int]$actual.value -ne [int]$State.value)) {
        throw 'Notification policy did not match the requested state after writeback.'
    }
}

function Read-VantaNotificationSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $snapshot = [IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Notification snapshot '$Path' is invalid: $($_.Exception.Message)"
    }

    $properties = @($snapshot.PSObject.Properties.Name)
    if ($properties.Count -ne 2 -or
        $properties -cnotcontains 'existed' -or
        $properties -cnotcontains 'value' -or
        $snapshot.existed -isnot [bool]) {
        throw "Notification snapshot '$Path' has an unsupported shape."
    }
    if ($snapshot.existed) {
        if ($null -eq $snapshot.value) {
            throw "Notification snapshot '$Path' is missing its DWORD value."
        }
        try {
            $value = [int]$snapshot.value
        }
        catch {
            throw "Notification snapshot '$Path' has an invalid DWORD value."
        }
        if ([long]$value -ne [long]$snapshot.value) {
            throw "Notification snapshot '$Path' has an invalid DWORD value."
        }
        $snapshot.value = $value
    }
    elseif ($null -ne $snapshot.value) {
        throw "Notification snapshot '$Path' contains a value for an absent policy."
    }

    return $snapshot
}

function Write-VantaNotificationSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$State
    )

    $temporaryPath = '{0}.{1}.tmp' -f $Path, [Guid]::NewGuid().ToString('N')
    try {
        $json = $State | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($temporaryPath, $json, (New-Object Text.UTF8Encoding($false)))
        [IO.File]::Move($temporaryPath, $Path)
    }
    finally {
        if ([IO.File]::Exists($temporaryPath)) {
            [IO.File]::Delete($temporaryPath)
        }
    }
}

$workRoot = Get-VantaInstallWorkRoot
if (-not [IO.Directory]::Exists($workRoot)) {
    throw "Vanta install work directory '$workRoot' does not exist."
}
$snapshotPath = Join-Path -Path $workRoot -ChildPath 'notification.json'

if ($Mode -eq 'Disable') {
    if (-not [IO.File]::Exists($snapshotPath)) {
        Write-VantaNotificationSnapshot -Path $snapshotPath `
            -State (Get-VantaNotificationPolicyState)
    }
    else {
        [void](Read-VantaNotificationSnapshot -Path $snapshotPath)
    }

    Write-VantaNotificationPolicyState -State (
        [pscustomobject][ordered]@{ existed = $true; value = 1 }
    )
    return
}

if (-not [IO.File]::Exists($snapshotPath)) {
    return
}

$previous = Read-VantaNotificationSnapshot -Path $snapshotPath
Write-VantaNotificationPolicyState -State $previous
[IO.File]::Delete($snapshotPath)
