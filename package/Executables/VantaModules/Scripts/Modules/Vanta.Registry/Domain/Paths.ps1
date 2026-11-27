# Vanta.Registry domain: registry path parsing and explicit HKCU scope binding.
#
# A privileged process must never redirect HKCU to a signed-in user's HKEY_USERS hive:
# the user can create registry links inside it, so TrustedInstaller would follow paths
# the user controls. Changes to a signed-in user therefore run in that user's own
# non-elevated process through its own HKCU. The one exception, for the installing
# user, writes only the two Windows-owned policy roots that user cannot write; it runs
# in a short-lived process and cannot resolve any other HKCU path.

$script:VantaRegistryIdentityContext = $null
$script:VantaDefaultUserHiveRoot = 'Registry::HKEY_USERS\Vanta_DefaultUser'
$script:VantaDefaultUserHiveName = 'Vanta_DefaultUser'

function Test-VantaDefaultUserHiveLoaded {
    $usersKey = [Microsoft.Win32.Registry]::Users
    $hiveKey = $usersKey.OpenSubKey($script:VantaDefaultUserHiveName, $false)
    if ($null -eq $hiveKey) {
        return $false
    }
    $hiveKey.Dispose()
    return $true
}

function Test-VantaProtectedCurrentUserPolicyPath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SubPath
    )

    $normalized = $SubPath.Trim('\')
    return (
        $normalized -imatch '^Software\\Policies(?:\\|$)' -or
        $normalized -imatch '^Software\\Microsoft\\Windows\\CurrentVersion\\Policies(?:\\|$)'
    )
}

function ConvertTo-VantaCanonicalRegistrySid {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Sid,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Label
    )

    try {
        $canonicalSid = New-Object Security.Principal.SecurityIdentifier($Sid)
    }
    catch {
        throw "$Label '$Sid' is not a valid Windows SID."
    }

    if (-not [string]::Equals($canonicalSid.Value, $Sid, [StringComparison]::Ordinal)) {
        throw "$Label '$Sid' is not canonical."
    }

    return $canonicalSid.Value
}

function Get-VantaRegistryCurrentTokenSid {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($null -eq $identity -or $null -eq $identity.User) {
        throw 'The current process token has no user SID; refusing to resolve HKCU.'
    }

    return ConvertTo-VantaCanonicalRegistrySid -Sid $identity.User.Value `
        -Label 'Current process token SID'
}

function Get-VantaActiveRegistryTransaction {
    <#
    .SYNOPSIS
        Returns the install context, after checking that it's backed by install state
        and belongs to the expected transaction.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Mode,
        [AllowEmptyString()][string]$TransactionId
    )

    $transaction = Get-VantaContext -Refresh
    if (-not [bool]$transaction.IsInstallStateBacked) {
        throw "$Mode registry identity requires an active Vanta install state."
    }
    if (-not [string]::Equals(
            [string]$transaction.TransactionId,
            $TransactionId,
            [StringComparison]::Ordinal
        )) {
        throw "The active Vanta transaction '$($transaction.TransactionId)' does not match expected transaction '$TransactionId'."
    }
    return $transaction
}

function Initialize-VantaRegistryIdentityContext {
    <#
    .SYNOPSIS
        Binds HKCU operations to either the current process token or the fixed Vanta
        default-user hive. The binding is immutable for the module lifetime.
    .DESCRIPTION
        CurrentToken is used by a process running as the user and never redirects
        through HKU.
        DefaultUserOnly is accepted only from strict TrustedInstaller and is bound to
        the active install state. InstallingUserPoliciesOnly is also strict
        TrustedInstaller and transaction-bound, but may resolve only the fixed Windows
        policy roots beneath the exact installing-user SID.
    #>
    [CmdletBinding(DefaultParameterSetName = 'CurrentToken')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'CurrentToken')]
        [switch]$CurrentToken,

        [Parameter(Mandatory = $true, ParameterSetName = 'CurrentToken')]
        [ValidateNotNullOrEmpty()]
        [string]$ExpectedUserSid,

        [Parameter(Mandatory = $true, ParameterSetName = 'DefaultUserOnly')]
        [switch]$DefaultUserOnly,

        [Parameter(Mandatory = $true, ParameterSetName = 'DefaultUserOnly')]
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $true, ParameterSetName = 'InstallingUserPoliciesOnly')]
        [string]$TransactionId,

        [Parameter(Mandatory = $true, ParameterSetName = 'InstallingUserPoliciesOnly')]
        [switch]$InstallingUserPoliciesOnly,

        [Parameter(Mandatory = $true, ParameterSetName = 'InstallingUserPoliciesOnly')]
        [ValidateNotNullOrEmpty()]
        [string]$InstallingUserSid
    )

    $newContext = $null
    switch ($PSCmdlet.ParameterSetName) {
        'CurrentToken' {
            if (-not $CurrentToken) {
                throw 'CurrentToken registry identity context requires -CurrentToken:$true.'
            }
            if (Test-VantaSystem) {
                throw 'CurrentToken registry identity context cannot be initialized from LocalSystem or TrustedInstaller.'
            }

            $expectedSid = ConvertTo-VantaCanonicalRegistrySid -Sid $ExpectedUserSid `
                -Label 'Expected current-user SID'
            $actualSid = Get-VantaRegistryCurrentTokenSid
            if (-not [string]::Equals($actualSid, $expectedSid, [StringComparison]::Ordinal)) {
                throw "The current process token SID '$actualSid' does not match expected user SID '$expectedSid'."
            }

            $newContext = [pscustomobject]@{
                Mode          = 'CurrentToken'
                UserSid       = $actualSid
                TransactionId = $null
            }
        }
        'DefaultUserOnly' {
            if (-not $DefaultUserOnly) {
                throw 'DefaultUserOnly registry identity context requires -DefaultUserOnly:$true.'
            }
            if (-not (Test-VantaTrustedInstaller)) {
                throw 'DefaultUserOnly registry identity context requires strict TrustedInstaller token evidence.'
            }

            $transaction = Get-VantaActiveRegistryTransaction -Mode 'DefaultUserOnly' -TransactionId $TransactionId

            $newContext = [pscustomobject]@{
                Mode          = 'DefaultUserOnly'
                UserSid       = $null
                TransactionId = [string]$transaction.TransactionId
            }
        }
        'InstallingUserPoliciesOnly' {
            if (-not $InstallingUserPoliciesOnly) {
                throw 'InstallingUserPoliciesOnly registry identity context requires -InstallingUserPoliciesOnly:$true.'
            }
            if (-not (Test-VantaTrustedInstaller)) {
                throw 'InstallingUserPoliciesOnly registry identity context requires strict TrustedInstaller token evidence.'
            }

            $expectedSid = ConvertTo-VantaCanonicalRegistrySid -Sid $InstallingUserSid `
                -Label 'Expected installing-user SID'
            $transaction = Get-VantaActiveRegistryTransaction -Mode 'InstallingUserPoliciesOnly' -TransactionId $TransactionId
            if ([string]::IsNullOrWhiteSpace([string]$transaction.InteractiveUserSid)) {
                throw 'The active Vanta install state has no installing-user SID.'
            }
            $activeSid = ConvertTo-VantaCanonicalRegistrySid `
                -Sid ([string]$transaction.InteractiveUserSid) -Label 'Active installing-user SID'
            if (-not [string]::Equals($activeSid, $expectedSid, [StringComparison]::Ordinal)) {
                throw "The active installing-user SID '$activeSid' does not match expected SID '$expectedSid'."
            }

            $newContext = [pscustomobject]@{
                Mode          = 'InstallingUserPoliciesOnly'
                UserSid       = $activeSid
                TransactionId = [string]$transaction.TransactionId
            }
        }
    }

    if ($null -ne $script:VantaRegistryIdentityContext) {
        if ([string]$script:VantaRegistryIdentityContext.Mode -cne [string]$newContext.Mode -or
            [string]$script:VantaRegistryIdentityContext.UserSid -cne [string]$newContext.UserSid -or
            [string]$script:VantaRegistryIdentityContext.TransactionId -cne [string]$newContext.TransactionId) {
            throw 'Vanta.Registry identity context is already initialized to a different immutable scope.'
        }

        return $script:VantaRegistryIdentityContext
    }

    $script:VantaRegistryIdentityContext = $newContext
    return $script:VantaRegistryIdentityContext
}

function ConvertTo-VantaRegistryPathInfo {
    <#
    .SYNOPSIS
        Parses a registry path in any common notation (HKCU:\, HKCU\, Registry::HKEY_...,
        HKU\...) into a canonical root name and subkey path.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $normalized = $Path.Trim().TrimEnd('\')
    if ($normalized -match '^(?i)Registry::(.*)$') {
        $normalized = $Matches[1]
    }

    $root = $normalized
    $subPath = ''
    $separatorIndex = $normalized.IndexOf('\')
    if ($separatorIndex -ge 0) {
        $root = $normalized.Substring(0, $separatorIndex)
        $subPath = $normalized.Substring($separatorIndex + 1).Trim('\')
    }

    $rootMap = @{
        'HKCU'                = 'HKEY_CURRENT_USER'
        'HKEY_CURRENT_USER'   = 'HKEY_CURRENT_USER'
        'HKLM'                = 'HKEY_LOCAL_MACHINE'
        'HKEY_LOCAL_MACHINE'  = 'HKEY_LOCAL_MACHINE'
        'HKU'                 = 'HKEY_USERS'
        'HKEY_USERS'          = 'HKEY_USERS'
        'HKCR'                = 'HKEY_CLASSES_ROOT'
        'HKEY_CLASSES_ROOT'   = 'HKEY_CLASSES_ROOT'
        'HKCC'                = 'HKEY_CURRENT_CONFIG'
        'HKEY_CURRENT_CONFIG' = 'HKEY_CURRENT_CONFIG'
    }

    $rootToken = $root.TrimEnd(':').ToUpperInvariant()
    if (-not $rootMap.ContainsKey($rootToken)) {
        throw "Unsupported registry root '$root' in path '$Path'."
    }

    return [pscustomobject]@{
        Root    = $rootMap[$rootToken]
        SubPath = $subPath
    }
}

function Resolve-VantaRegistryPath {
    <#
    .SYNOPSIS
        Normalizes a registry path without changing its identity scope. Privileged
        live-user HKU redirection is deliberately not part of this API.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $pathInfo = ConvertTo-VantaRegistryPathInfo -Path $Path
    $isHkcu = ($pathInfo.Root -eq 'HKEY_CURRENT_USER')

    $primary = "Registry::$($pathInfo.Root)"
    if ($pathInfo.SubPath) {
        $primary = "Registry::$($pathInfo.Root)\$($pathInfo.SubPath)"
    }

    return [pscustomobject]@{
        Primary     = $primary
        HkcuSubPath = $null
        IsHkcu      = $isHkcu
    }
}

function Resolve-VantaRegistryTarget {
    <#
    .SYNOPSIS
        Resolves a registry path for the explicitly proven process context. A
        non-System token uses only its own ambient HKCU. TrustedInstaller can resolve
        HKCU only after an explicit DefaultUserOnly transaction binding.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $pathInfo = ConvertTo-VantaRegistryPathInfo -Path $Path
    $isSystem = Test-VantaSystem

    if ($isSystem -and $pathInfo.Root -eq 'HKEY_USERS') {
        $hiveName = @($pathInfo.SubPath -split '\\', 2)[0]
        if ([string]::IsNullOrWhiteSpace($hiveName) -or
            $hiveName -cne $script:VantaDefaultUserHiveName) {
            throw "A privileged Vanta.Registry caller may target only the fixed '$($script:VantaDefaultUserHiveName)' HKEY_USERS hive, not '$Path'."
        }
    }

    if ($pathInfo.Root -ne 'HKEY_CURRENT_USER') {
        return Resolve-VantaRegistryPath -Path $Path
    }

    if ($null -eq $script:VantaRegistryIdentityContext) {
        if ($isSystem) {
            throw 'Privileged HKCU access has no explicit DefaultUserOnly identity context; live-user HKU redirection is forbidden.'
        }

        # This is not discovery: Windows binds ambient HKCU to the current process token.
        # Resolve the token SID on every operation so no process-global identity guess is
        # cached or reused after an embedding host changes impersonation state.
        $null = Get-VantaRegistryCurrentTokenSid
        return Resolve-VantaRegistryPath -Path $Path
    }

    switch ([string]$script:VantaRegistryIdentityContext.Mode) {
        'CurrentToken' {
            if ($isSystem) {
                throw 'A CurrentToken registry identity context became privileged; refusing HKCU access.'
            }

            $actualSid = Get-VantaRegistryCurrentTokenSid
            if (-not [string]::Equals(
                    $actualSid,
                    [string]$script:VantaRegistryIdentityContext.UserSid,
                    [StringComparison]::Ordinal
                )) {
                throw 'The current process token changed after Vanta.Registry identity initialization.'
            }
            return Resolve-VantaRegistryPath -Path $Path
        }
        'DefaultUserOnly' {
            if (-not $isSystem -or -not (Test-VantaTrustedInstaller)) {
                throw 'The DefaultUserOnly registry identity context lost strict TrustedInstaller identity.'
            }
            if (-not (Test-VantaDefaultUserHiveLoaded)) {
                throw "The fixed Vanta default-user hive is not loaded at '$($script:VantaDefaultUserHiveRoot)'."
            }

            $primary = $script:VantaDefaultUserHiveRoot
            if ($pathInfo.SubPath) {
                $primary = "$primary\$($pathInfo.SubPath)"
            }
            return [pscustomobject]@{
                Primary     = $primary
                HkcuSubPath = $pathInfo.SubPath
                IsHkcu      = $true
            }
        }
        'InstallingUserPoliciesOnly' {
            if (-not $isSystem -or -not (Test-VantaTrustedInstaller)) {
                throw 'The InstallingUserPoliciesOnly registry identity context lost strict TrustedInstaller identity.'
            }
            if (-not (Test-VantaProtectedCurrentUserPolicyPath -SubPath $pathInfo.SubPath)) {
                throw "The installing-user policy writer cannot target HKCU path '$Path'."
            }

            $primary = "Registry::HKEY_USERS\$($script:VantaRegistryIdentityContext.UserSid)"
            if ($pathInfo.SubPath) {
                $primary = "$primary\$($pathInfo.SubPath)"
            }
            return [pscustomobject]@{
                Primary     = $primary
                HkcuSubPath = $pathInfo.SubPath
                IsHkcu      = $true
            }
        }
        default {
            throw "Unsupported Vanta.Registry identity context mode '$($script:VantaRegistryIdentityContext.Mode)'."
        }
    }
}

function Split-VantaRegistryProviderPath {
    <#
    .SYNOPSIS
        Splits a provider path into a Microsoft.Win32 base registry key and a subkey path
        for direct .NET registry access (needed for value-kind fidelity and REG_NONE).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProviderPath
    )

    $pathInfo = ConvertTo-VantaRegistryPathInfo -Path $ProviderPath

    $baseKey = switch ($pathInfo.Root) {
        'HKEY_LOCAL_MACHINE' { [Microsoft.Win32.Registry]::LocalMachine }
        'HKEY_CURRENT_USER' { [Microsoft.Win32.Registry]::CurrentUser }
        'HKEY_USERS' { [Microsoft.Win32.Registry]::Users }
        'HKEY_CLASSES_ROOT' { [Microsoft.Win32.Registry]::ClassesRoot }
        'HKEY_CURRENT_CONFIG' { [Microsoft.Win32.Registry]::CurrentConfig }
    }

    return [pscustomobject]@{
        BaseKey = $baseKey
        SubPath = $pathInfo.SubPath
    }
}

function Invoke-VantaRegistryTargetOperation {
    <#
    .SYNOPSIS
        Runs a registry operation against the explicitly resolved target of a path.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    $resolved = Resolve-VantaRegistryTarget -Path $Path
    & $Action $resolved.Primary
}
