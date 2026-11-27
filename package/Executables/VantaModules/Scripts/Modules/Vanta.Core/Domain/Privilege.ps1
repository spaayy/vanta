# Vanta.Core domain: privilege identity and the closed TrustedInstaller operation API.

function Test-VantaAdmin {
    <#
    .SYNOPSIS
        Whether this process runs with Administrator rights (an elevated token).
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-VantaCurrentUserSid {
    return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function Test-VantaSystem {
    <#
    .SYNOPSIS
        Whether this process runs as LocalSystem (S-1-5-18). Returns $false when the
        identity can't be read.
    #>
    try {
        return (Get-VantaCurrentUserSid) -eq 'S-1-5-18'
    }
    catch {
        return $false
    }
}

function Test-VantaTrustedInstaller {
    <#
    .SYNOPSIS
        Whether this process holds a TrustedInstaller service token: SYSTEM, with the
        TrustedInstaller SID enabled, at System integrity. Returns $false when the
        token can't be read.
    #>
    try {
        return [bool](Get-VantaCurrentTokenEvidence).IsTrustedInstaller
    }
    catch {
        return $false
    }
}

function Assert-VantaPrivilege {
    <#
    .SYNOPSIS
        Throws a [privilege] error naming the current identity unless this process
        holds every privilege requested: Administrator, System or TrustedInstaller.
    #>
    param(
        [switch]$Administrator,
        [switch]$System,
        [switch]$TrustedInstaller
    )

    if ($TrustedInstaller -and -not (Test-VantaTrustedInstaller)) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $evidenceText = try {
            $evidence = Get-VantaCurrentTokenEvidence
            "user=$($evidence.UserSid), enabledTiSid=$($evidence.HasEnabledTrustedInstallerSid), integrity=0x$('{0:X}' -f $evidence.IntegrityRid)"
        }
        catch {
            "tokenEvidenceError=$($_.Exception.Message)"
        }
        throw "[privilege] This operation requires a TrustedInstaller service token (SYSTEM user, enabled NT SERVICE\TrustedInstaller SID, System integrity); current identity is '$($identity.Name)' ($($identity.User.Value)); $evidenceText."
    }

    if ($System -and -not (Test-VantaSystem)) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        throw "[privilege] This operation requires LocalSystem (S-1-5-18); current identity is '$($identity.Name)' ($($identity.User.Value))."
    }

    if ($Administrator -and -not (Test-VantaAdmin)) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        throw "[privilege] This operation requires Administrator rights; current identity is '$($identity.Name)'."
    }
}

function Invoke-VantaTrustedInstaller {
    <#
    .SYNOPSIS
        Runs one closed Vanta operation through the fixed elevated broker. Throws when
        the broker exits nonzero, with its output in the message, so a returned result
        always has ExitCode 0.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Toggle', 'ResetServices', 'Install', 'CbsRetry')]
        [string]$Operation,

        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$', Options = [Text.RegularExpressions.RegexOptions]::None)]
        [string]$Name,

        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$', Options = [Text.RegularExpressions.RegexOptions]::None)]
        [string]$State,

        [bool]$Silent = $true,
        [switch]$JustContext,
        [switch]$NoExplorerRestart,
        [switch]$MachineOnly,

        [ValidateSet('ToggleDefaults', 'WindowsBackup', 'VantaBackup')]
        [string]$RestoreSource,

        [ValidateSet('Capture', 'Run')]
        [string]$InstallPhase,

        [string]$PackageRoot,

        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 900
    )

    $operationParameterAllowlist = @{
        Toggle        = @('Name', 'State', 'Silent', 'JustContext', 'NoExplorerRestart', 'MachineOnly')
        ResetServices = @('RestoreSource')
        Install       = @('InstallPhase', 'PackageRoot')
        CbsRetry      = @()
    }
    foreach ($operationParameter in @(
            'Name', 'State', 'Silent', 'JustContext', 'NoExplorerRestart', 'MachineOnly', 'RestoreSource',
            'InstallPhase', 'PackageRoot'
        )) {
        if ($PSBoundParameters.ContainsKey($operationParameter) -and
            $operationParameter -notin $operationParameterAllowlist[$Operation]) {
            throw "$Operation does not accept the operation input '-$operationParameter'."
        }
    }

    $context = Get-VantaContext
    $brokerModulesPath = $context.VantaModulesPath
    if ($Operation -eq 'Install') {
        if ([string]::IsNullOrWhiteSpace($InstallPhase) -or [string]::IsNullOrWhiteSpace($PackageRoot)) {
            throw 'Install requires typed -InstallPhase and -PackageRoot values.'
        }
        if (-not [IO.Path]::IsPathRooted($PackageRoot)) {
            throw 'Install requires an absolute -PackageRoot.'
        }
        $PackageRoot = [IO.Path]::GetFullPath($PackageRoot)
        $stagingRoot = [IO.Path]::GetFullPath((Join-Path $context.WinDir 'VantaOS\Staging'))
        if (-not $PackageRoot.StartsWith($stagingRoot + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Install PackageRoot must be beneath the protected staging root '$stagingRoot'."
        }
        # A fresh installation has no installed broker yet. Use the broker included
        # with this protected candidate, including when upgrading an older installation.
        $brokerModulesPath = Join-Path $PackageRoot 'VantaModules'
    }

    $argumentList = [Collections.Generic.List[string]]::new()
    foreach ($argument in @(
            '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $brokerModulesPath `
                'Scripts\Entry\Invoke-VantaTrustedInstallerBroker.ps1'),
            '-Operation', $Operation,
            '-TimeoutSeconds', [string]$TimeoutSeconds
        )) {
        $argumentList.Add($argument)
    }

    switch ($Operation) {
        'Toggle' {
            if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($State)) {
                throw 'Toggle requires typed -Name and -State values.'
            }
            if (-not $Silent) {
                throw 'The TrustedInstaller Toggle operation is noninteractive and requires -Silent:$true.'
            }
            $argumentList.Add('-Name')
            $argumentList.Add($Name)
            $argumentList.Add('-State')
            $argumentList.Add($State)
            foreach ($switchName in @('JustContext', 'NoExplorerRestart', 'MachineOnly')) {
                if ($PSBoundParameters[$switchName]) {
                    $argumentList.Add("-$switchName")
                }
            }
        }
        'ResetServices' {
            if ([string]::IsNullOrWhiteSpace($RestoreSource)) {
                throw 'ResetServices requires a typed -RestoreSource value.'
            }
            $argumentList.Add('-RestoreSource')
            $argumentList.Add($RestoreSource)
        }
        'Install' {
            # $InstallPhase and $PackageRoot were checked and normalised above.
            $argumentList.Add('-InstallPhase')
            $argumentList.Add($InstallPhase)
            $argumentList.Add('-PackageRoot')
            $argumentList.Add($PackageRoot)
        }
    }

    Assert-VantaPrivilege -Administrator
    $powershellPath = Join-Path $context.WinDir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    # The broker owns the operation deadline. Give it a short, separate window to
    # terminate and drain its kill-on-close job before the caller treats the broker
    # itself as unresponsive.
    $brokerProcessTimeoutSeconds = $TimeoutSeconds + 15
    return Invoke-VantaHiddenProcess `
        -FilePath $powershellPath `
        -ArgumentList $argumentList.ToArray() `
        -Wait `
        -CaptureOutput `
        -TimeoutSeconds $brokerProcessTimeoutSeconds
}
