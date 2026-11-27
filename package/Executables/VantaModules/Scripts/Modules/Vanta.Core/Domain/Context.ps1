# Vanta.Core domain: active install state and post-install machine state context.
#
# While installation is active, mode, identity, and the options chosen for the
# package's choices come from Vanta.InstallState. After successful completion
# archives that state, the machine state document (%windir%\VantaOS\state.json,
# Vanta.State) carries the installed version, mode and options. The Upgrade and
# option flags remain only as a fallback for machines installed before the document
# existed.

$script:VantaContext = $null

function Read-VantaActiveInstallState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsPath
    )

    $statePath = Join-Path -Path $WindowsPath -ChildPath 'VantaOS\Install\active.json'
    if (-not (Test-Path -LiteralPath $statePath -ErrorAction Stop)) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf -ErrorAction Stop)) {
        throw "The Vanta install-state path is not a regular file: '$statePath'."
    }

    $stateManifest = [IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot `
        -ChildPath '..\..\Vanta.InstallState\Vanta.InstallState.psd1'))
    if (-not (Test-Path -LiteralPath $stateManifest -PathType Leaf)) {
        throw "The active Vanta install state exists, but its reader module is missing: '$stateManifest'."
    }

    Import-Module -Name $stateManifest -DisableNameChecking -ErrorAction Stop
    return Get-VantaInstallState -StatePath $statePath
}

function Read-VantaStateDocument {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsPath
    )

    $documentPath = Join-Path -Path $WindowsPath -ChildPath 'VantaOS\state.json'
    if (-not (Test-Path -LiteralPath $documentPath -PathType Leaf -ErrorAction Stop)) {
        return $null
    }

    $stateManifest = [IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot `
        -ChildPath '..\..\Vanta.State\Vanta.State.psd1'))
    if (-not (Test-Path -LiteralPath $stateManifest -PathType Leaf)) {
        throw "The Vanta state document exists, but its reader module is missing: '$stateManifest'."
    }

    Import-Module -Name $stateManifest -ErrorAction Stop
    return Get-VantaState -Path $documentPath
}

function Get-VantaContext {
    <#
    .SYNOPSIS
        Returns cached information about the machine and the current install run.
    .OUTPUTS
        PSCustomObject with filesystem paths, Windows facts and the recorded install
        mode, option set, update path (Choices, IsChoosingAgain), target version and
        interactive-user identity.
    #>
    param(
        [switch]$Refresh,

        # Read-only stand-ins keep context behaviour deterministic in Pester without
        # touching the host registry or canonical Windows transaction store.
        [string]$WindowsPath,
        [scriptblock]$StateReader,
        [scriptblock]$DocumentReader,
        [scriptblock]$WindowsBuildReader
    )

    $usingReadSeam = $PSBoundParameters.ContainsKey('WindowsPath') -or
        $PSBoundParameters.ContainsKey('StateReader') -or
        $PSBoundParameters.ContainsKey('DocumentReader') -or
        $PSBoundParameters.ContainsKey('WindowsBuildReader')
    if ($script:VantaContext -and -not $Refresh -and -not $usingReadSeam) {
        return $script:VantaContext
    }

    $winDir = if ([string]::IsNullOrWhiteSpace($WindowsPath)) {
        [Environment]::GetFolderPath('Windows')
    }
    else {
        [IO.Path]::GetFullPath($WindowsPath)
    }
    $vantaModulesPath = Join-Path -Path $winDir -ChildPath 'VantaModules'
    $flagsPath = Join-Path -Path $vantaModulesPath -ChildPath 'Flags'

    $windowsBuild = 0
    try {
        $buildNumber = if ($null -ne $WindowsBuildReader) {
            & $WindowsBuildReader
        }
        else {
            (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
                -Name CurrentBuildNumber -ErrorAction Stop).CurrentBuildNumber
        }
        $windowsBuild = [int]$buildNumber
    }
    catch {
        Write-Warning "Couldn't read the Windows build number: $($_.Exception.Message)"
    }

    $statePath = Join-Path -Path $winDir -ChildPath 'VantaOS\Install\active.json'
    $installState = if ($null -ne $StateReader) {
        & $StateReader $statePath
    }
    else {
        Read-VantaActiveInstallState -WindowsPath $winDir
    }

    $isInstallStateBacked = $null -ne $installState
    $documentPath = Join-Path -Path $winDir -ChildPath 'VantaOS\state.json'
    $document = $null
    if (-not $isInstallStateBacked) {
        $document = if ($null -ne $DocumentReader) {
            & $DocumentReader $documentPath
        }
        else {
            Read-VantaStateDocument -WindowsPath $winDir
        }
    }
    $isDocumentBacked = $null -ne $document
    $installedVersion = $null
    $mode = $null
    $targetVersion = $null
    $interactiveUserSid = $null
    $interactiveUserSessionId = $null
    $transactionId = $null
    $options = @()
    # How this install treats the choices the PC has. An install state written before
    # the update path existed, and every context outside an install, keeps them.
    $choices = 'Keep'
    if ($isInstallStateBacked) {
        $mode = [string]$installState.mode
        if ($mode -cnotin @('Fresh', 'Upgrade', 'Reapply', 'Rebase')) {
            throw "The Vanta install-state mode '$mode' is invalid."
        }
        $storedChoices = $installState.PSObject.Properties['choices']
        if ($null -ne $storedChoices) {
            $choices = [string]$storedChoices.Value
            if ($choices -cnotin @('Keep', 'ChooseAgain')) {
                throw "The Vanta install-state choices value '$choices' is invalid."
            }
        }
        $targetVersion = [string]$installState.targetVersion
        $interactiveUserSid = if ([string]::IsNullOrWhiteSpace([string]$installState.userSid)) {
            $null
        }
        else {
            [string]$installState.userSid
        }
        if ($null -ne $installState.userSessionId) {
            $interactiveUserSessionId = [long]$installState.userSessionId
        }
        $transactionId = [string]$installState.transactionId
        $options = @($installState.options | ForEach-Object { [string]$_ })
    }
    elseif ($isDocumentBacked) {
        $installedVersion = [string]$document.installedVersion
        # Recording a toggle can create the document before an install records a mode.
        if (-not [string]::IsNullOrWhiteSpace([string]$document.mode)) {
            $mode = [string]$document.mode
        }
        $options = @($document.options | ForEach-Object { [string]$_ })
    }

    # Rebase is an upgrade that also repeats the fresh-install work a rebuilt
    # Windows undid; IsRebase tells the steps that differ.
    $isUpgrade = if ($isInstallStateBacked) {
        $mode -cin @('Upgrade', 'Reapply', 'Rebase')
    }
    elseif ($isDocumentBacked) {
        # A Reapply records its own mode, but the fresh-install work an earlier
        # update skipped is still not on this PC.
        $history = $document.PSObject.Properties['history']
        $updated = $null -ne $history -and @(@($history.Value) | Where-Object {
                $null -ne $_ -and $null -ne $_.PSObject.Properties['mode'] -and [string]$_.mode -cin @('Upgrade', 'Rebase')
            }).Count -gt 0
        [string]$document.mode -cin @('Upgrade', 'Rebase') -or $updated
    }
    else {
        Test-Path -LiteralPath (Join-Path -Path $flagsPath -ChildPath 'Upgrade.flag') -PathType Leaf
    }

    $script:VantaContext = [pscustomobject]@{
        WinDir             = $winDir
        VantaModulesPath   = $vantaModulesPath
        FlagsPath          = $flagsPath
        LogsPath           = Join-Path -Path $vantaModulesPath -ChildPath 'Logs'
        IsArm64            = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64')
        WindowsBuild       = $windowsBuild
        IsUpgrade          = $isUpgrade
        IsRebase           = $isInstallStateBacked -and $mode -ceq 'Rebase'
        IsInstallStateBacked     = $isInstallStateBacked
        IsStateDocumentBacked    = $isDocumentBacked
        StateDocumentPath        = $documentPath
        InstalledVersion         = $installedVersion
        Mode                     = if ($null -ne $mode) { $mode } else { 'Legacy' }
        TargetVersion            = $targetVersion
        InteractiveUserSid       = $interactiveUserSid
        InteractiveUserSessionId = $interactiveUserSessionId
        TransactionId            = $transactionId
        Options                  = $options
        Choices                  = $choices
        # Only an update applies changed choices: a first installation applies every
        # choice anyway, and a Rebase keeps the ones it had.
        IsChoosingAgain          = $isInstallStateBacked -and $choices -ceq 'ChooseAgain' -and $mode -cin @('Upgrade', 'Reapply')
    }

    return $script:VantaContext
}

function Test-VantaOption {
    <#
    .SYNOPSIS
        Returns whether the active install state contains an option, by the id the
        package manifest gives it. After completion, reads the machine state document,
        or the published option flag on a machine installed before the document existed.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $context = Get-VantaContext
    if ($context.IsInstallStateBacked -or $context.IsStateDocumentBacked) {
        return @($context.Options) -ccontains $Name
    }

    $flagsPath = $context.FlagsPath
    return Test-Path -LiteralPath (Join-Path -Path $flagsPath -ChildPath "option-$Name.flag") -PathType Leaf
}
