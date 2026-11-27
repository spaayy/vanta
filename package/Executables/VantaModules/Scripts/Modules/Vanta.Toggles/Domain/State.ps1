# Vanta.Toggles domain: user setting state registry.
#
# Every toggle choice is recorded under HKLM\SOFTWARE\Vanta\Services\<SettingName> as
# declarative data: the subkey identifies the toggle and 'state' is its REG_DWORD value.
# Executable paths are deliberately not persisted. Upgrade replay resolves the current
# installed definition by name so writable registry data can never become code.
# Records represent applied choices, including their user work queued for first sign-in.
# Launcher defaults are definition metadata and do not seed records. Legacy records are
# retained because they cannot be distinguished from choices made by the user.

$script:VantaToggleDefaultStateRoot = 'HKLM:\SOFTWARE\Vanta\Services'

function Test-VantaToggleProductionStateRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StateRoot
    )

    return [string]::Equals(
        $StateRoot.TrimEnd('\'),
        $script:VantaToggleDefaultStateRoot.TrimEnd('\'),
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function New-VantaToggleStateAcl {
    <#
    .SYNOPSIS
        Builds the protected ACL used for the production toggle state tree.
    #>
    $acl = New-Object -TypeName System.Security.AccessControl.RegistrySecurity
    $acl.SetAccessRuleProtection($true, $false)

    $administrators = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-32-544'
    $acl.SetOwner($administrators)

    # Keep the state readable by ordinary launcher processes, but writable only by the
    # privileged identities that apply Vanta and its TrustedInstaller-only toggles.
    $rules = @(
        # LocalSystem, Administrators, NT SERVICE\TrustedInstaller and Users.
        @{ Sid = 'S-1-5-18'; Rights = [System.Security.AccessControl.RegistryRights]::FullControl }
        @{ Sid = 'S-1-5-32-544'; Rights = [System.Security.AccessControl.RegistryRights]::FullControl }
        @{ Sid = 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'; Rights = [System.Security.AccessControl.RegistryRights]::FullControl }
        @{ Sid = 'S-1-5-32-545'; Rights = [System.Security.AccessControl.RegistryRights]::ReadKey }
    )

    foreach ($entry in $rules) {
        $identity = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList $entry.Sid
        $rule = New-Object -TypeName System.Security.AccessControl.RegistryAccessRule -ArgumentList @(
            $identity,
            $entry.Rights,
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($rule) | Out-Null
    }

    return $acl
}

function Set-VantaToggleStateKeyAcl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$KeyPath
    )

    Set-Acl -LiteralPath $KeyPath -AclObject (New-VantaToggleStateAcl) -ErrorAction Stop
}

function New-VantaToggleProductionStateRoot {
    <#
    .SYNOPSIS
        Atomically creates the production state root with its protected DACL.
    .DESCRIPTION
        RegistryKey.CreateSubKey applies RegistrySecurity as part of key creation. The
        caller subsequently reopens the path to reset an existing key if another process
        created it immediately before this call.
    #>
    $baseKey = $null
    $stateKey = $null
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Default
        )
        $acl = New-VantaToggleStateAcl
        $stateKey = $baseKey.CreateSubKey(
            'SOFTWARE\Vanta\Services',
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [Microsoft.Win32.RegistryOptions]::None,
            $acl
        )
        if ($null -eq $stateKey) {
            throw 'Creating the Vanta toggle state root returned no registry key.'
        }
    }
    finally {
        if ($stateKey) {
            $stateKey.Dispose()
        }
        if ($baseKey) {
            $baseKey.Dispose()
        }
    }
}

function Protect-VantaToggleStateRoot {
    <#
    .SYNOPSIS
        Creates or migrates the production state tree to its protected DACL.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StateRoot,

        [switch]$Create,

        [switch]$IncludeChildren
    )

    # Tests use other roots. Only the fixed HKLM root, which replay uses, needs this DACL.
    if (-not (Test-VantaToggleProductionStateRoot -StateRoot $StateRoot)) {
        return
    }

    if (-not (Test-Path -LiteralPath $StateRoot)) {
        if (-not $Create) {
            return
        }
        New-VantaToggleProductionStateRoot
    }

    # Existing installs may have inherited a user-writable DACL. Reopen with the registry
    # provider's ACL rights and replace it before inspecting or migrating any child record.
    # This also closes a race where CreateSubKey opened a key another process just created.
    Set-VantaToggleStateKeyAcl -KeyPath $StateRoot

    if ($IncludeChildren) {
        foreach ($child in @(Get-ChildItem -LiteralPath $StateRoot -Recurse -ErrorAction Stop)) {
            Set-VantaToggleStateKeyAcl -KeyPath $child.PSPath
        }
    }
}

function Remove-VantaToggleLegacyPath {
    <#
    .SYNOPSIS
        Removes the legacy executable 'path' value without disturbing declarative or
        product metadata that other Vanta components may read.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$KeyPath
    )

    $key = Get-Item -LiteralPath $KeyPath -ErrorAction Stop
    if (@($key.GetValueNames()) -contains 'path') {
        Remove-ItemProperty -LiteralPath $KeyPath -Name 'path' -Force -ErrorAction Stop
    }
}

function Repair-VantaLegacyContextMenuState {
    <#
    .SYNOPSIS
        Corrects the OldContextMenu record that Vanta 0.5 launchers left.
    .DESCRIPTION
        Both 0.5 launchers wrote state 0. The file name distinguishes their intent;
        the stored path is never executed.
    #>
    param([Parameter(Mandatory = $true)]$Key)

    if ($Key.PSChildName -eq 'OldContextMenu' -and
        $Key.GetValue('state', $null) -eq 0 -and
        $Key.GetValueKind('state') -eq [Microsoft.Win32.RegistryValueKind]::DWord -and
        $Key.GetValue('path', $null) -is [string] -and
        [string]$Key.GetValue('path') -cmatch '(^|[\\/])Old Context Menu \(default\)\.cmd$') {
        $state = Get-VantaLegacyToggleObservedState -Name OldContextMenu
        if ($null -eq $state) { $state = 1 }
        Set-ItemProperty -LiteralPath $Key.PSPath -Name 'state' -Value ([int]$state) -ErrorAction Stop
        Write-VantaLog -Message "Migrated the legacy context-menu choice to state $state before removing its launcher path."
    }
}

function Repair-VantaLegacyVerboseMessagesState {
    <#
    .SYNOPSIS
        Corrects the VerboseMessages record that the Vanta 0.5 disable launcher left.
    .DESCRIPTION
        That launcher wrote state 1. Its file name identifies the disabled choice; the
        stored path is inspected as data and never executed.
    #>
    param([Parameter(Mandatory = $true)]$Key)

    if ($Key.PSChildName -eq 'VerboseMessages' -and
        $Key.GetValue('state', $null) -eq 1 -and
        $Key.GetValueKind('state') -eq [Microsoft.Win32.RegistryValueKind]::DWord -and
        $Key.GetValue('path', $null) -is [string] -and
        [string]$Key.GetValue('path') -match '(^|[\\/])Disable Verbose Messages \(default\)\.cmd$') {
        Set-ItemProperty -LiteralPath $Key.PSPath -Name 'state' -Value 0 -ErrorAction Stop
        Write-VantaLog -Message 'Migrated the legacy disabled verbose-message choice before removing its launcher path.'
    }
}

function Initialize-VantaToggleStateStore {
    <#
    .SYNOPSIS
        Hardens the production state tree and removes legacy executable paths.
    #>
    param(
        [ValidateNotNullOrEmpty()]
        [string]$StateRoot = $script:VantaToggleDefaultStateRoot
    )

    Protect-VantaToggleStateRoot -StateRoot $StateRoot -Create -IncludeChildren
    if (-not (Test-Path -LiteralPath $StateRoot)) {
        return
    }
    Repair-VantaLegacyToggleAlias -StateRoot $StateRoot
    foreach ($child in @(Get-ChildItem -LiteralPath $StateRoot -ErrorAction Stop)) {
        Repair-VantaLegacyContextMenuState -Key $child
        Repair-VantaLegacyVerboseMessagesState -Key $child
        Repair-VantaLegacyToggleState -Key $child
        Remove-VantaToggleLegacyPath -KeyPath $child.PSPath
    }
    Sync-VantaToggleStateDocument -StateRoot $StateRoot
}

function Get-VantaToggleState {
    <#
    .SYNOPSIS
        Reads the recorded state of a toggle from the Vanta state registry. Returns $null
        when the toggle has never been recorded.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [ValidateNotNullOrEmpty()]
        [string]$StateRoot = $script:VantaToggleDefaultStateRoot
    )

    $keyPath = Join-Path -Path $StateRoot -ChildPath $Name
    if (-not (Test-Path -LiteralPath $keyPath)) {
        return $null
    }

    $key = Get-Item -LiteralPath $keyPath -ErrorAction SilentlyContinue
    if ($null -eq $key) {
        return $null
    }

    $state = $null
    try {
        if (@($key.GetValueNames()) -contains 'state') {
            if ($key.GetValueKind('state') -ne [Microsoft.Win32.RegistryValueKind]::DWord) {
                throw "Toggle '$Name' has a non-REG_DWORD 'state' record under '$keyPath'."
            }
            $state = [int]$key.GetValue('state')
        }
    }
    finally {
        $key.Close()
    }

    return [pscustomobject]@{
        Name  = $Name
        State = $state
    }
}

function Set-VantaToggleState {
    <#
    .SYNOPSIS
        Records a declarative toggle choice in the Vanta state registry.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [int]$State,

        # Retained as an ignored compatibility parameter for older internal callers.
        [string]$LauncherPath,

        [ValidateNotNullOrEmpty()]
        [string]$StateRoot = $script:VantaToggleDefaultStateRoot
    )

    # Referencing this compatibility-only parameter documents that it is intentionally
    # discarded rather than accidentally omitted from persistence.
    $null = $LauncherPath

    $productionStateRoot = Test-VantaToggleProductionStateRoot -StateRoot $StateRoot
    Protect-VantaToggleStateRoot -StateRoot $StateRoot -Create

    $keyPath = Join-Path -Path $StateRoot -ChildPath $Name
    if (-not (Test-Path -LiteralPath $keyPath)) {
        New-Item -Path $keyPath -Force -ErrorAction Stop | Out-Null
    }

    if ($productionStateRoot) {
        Set-VantaToggleStateKeyAcl -KeyPath $keyPath
    }

    Remove-VantaToggleLegacyPath -KeyPath $keyPath
    New-ItemProperty -LiteralPath $keyPath -Name 'state' -Value $State -PropertyType DWord -Force | Out-Null

    # The registry tree is the write store the Toolbox app still reads; the machine
    # state document mirrors it for every other reader. A choice toggle run between
    # installs also keeps its install choice in step there; during an install,
    # completion records what the PC has.
    if ($productionStateRoot) {
        $activeInstall = [IO.Path]::Combine([IO.Path]::GetDirectoryName((Get-VantaStatePath)), 'Install', 'active.json')
        $null = Set-VantaStateToggle -Name $Name -State $State -SyncChoice:(-not [IO.File]::Exists($activeInstall))
    }
}

function Get-VantaToggleStateRecords {
    <#
    .SYNOPSIS
        Returns every recorded toggle state under a state root as a name-to-value table.
    #>
    param(
        [ValidateNotNullOrEmpty()]
        [string]$StateRoot = $script:VantaToggleDefaultStateRoot
    )

    $records = @{}
    if (-not (Test-Path -LiteralPath $StateRoot)) {
        return $records
    }
    foreach ($child in @(Get-ChildItem -LiteralPath $StateRoot -ErrorAction Stop)) {
        $recorded = Get-VantaToggleState -Name ([string]$child.PSChildName) -StateRoot $StateRoot
        if ($null -ne $recorded -and $null -ne $recorded.State) {
            $records[[string]$child.PSChildName] = [int]$recorded.State
        }
    }
    return $records
}

function Sync-VantaToggleStateDocument {
    <#
    .SYNOPSIS
        Rebuilds the state document's toggle view from the production state store.
    #>
    param(
        [ValidateNotNullOrEmpty()]
        [string]$StateRoot = $script:VantaToggleDefaultStateRoot
    )

    if (-not (Test-VantaToggleProductionStateRoot -StateRoot $StateRoot)) {
        return
    }
    $null = Sync-VantaStateToggles -Records (Get-VantaToggleStateRecords -StateRoot $StateRoot)
}
