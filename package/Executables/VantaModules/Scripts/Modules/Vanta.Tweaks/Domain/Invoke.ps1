# Vanta.Tweaks domain: tweak application.
#
# A tweak is a data-only .psd1 (see Scripts\Tweaks\README.md for the schema). Keys are
# applied in a fixed order. Required work fails immediately; only entries that
# explicitly declare IgnoreErrors remain best-effort.

function Get-VantaTweakEntryValue {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [object]$Default
    )

    if ($Entry.ContainsKey($Key) -and $null -ne $Entry[$Key]) {
        return $Entry[$Key]
    }

    return $Default
}

function Get-VantaTweakUserSid {
    param([Parameter(Mandatory = $true)][object]$Context)

    if (-not $Context.IsInstallStateBacked -or
        [string]::IsNullOrWhiteSpace([string]$Context.InteractiveUserSid)) {
        throw 'RunAs=User requires an install-state user SID.'
    }
    try {
        return (New-Object Security.Principal.SecurityIdentifier(
                [string]$Context.InteractiveUserSid
            )).Value
    }
    catch {
        throw "RunAs=User received an invalid install-state user SID '$($Context.InteractiveUserSid)'."
    }
}

function Invoke-VantaTweakRunEntries {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [hashtable[]]$Entries,

        [Parameter(Mandatory = $true)]
        [bool]$IsArm64,

        [Parameter(Mandatory = $true)]
        [string]$WinDir
    )

    foreach ($entry in $Entries) {
        $ignoreErrors = [bool](Get-VantaTweakEntryValue -Entry $entry -Key 'IgnoreErrors' -Default $false)

        try {
            $arch = [string](Get-VantaTweakEntryValue -Entry $entry -Key 'Arch' -Default '')
            if (-not (Test-VantaArchMatch -Arch $arch -IsArm64 $IsArm64)) {
                continue
            }

            $exe = [string](Get-VantaTweakEntryValue -Entry $entry -Key 'Exe')
            if (-not $exe) {
                throw 'Run entry has no Exe.'
            }
            $exe = $exe -replace '\{windir\}', $WinDir

            $arguments = @()
            if ($entry.ContainsKey('Args')) {
                $arguments = @($entry['Args'])
                if ($entry['Args'] -isnot [array] -or
                    @($arguments | Where-Object { $_ -isnot [string] }).Count) {
                    throw 'Run entry Args must be an array of strings.'
                }
                $arguments = [string[]]@($arguments -replace '\{windir\}', $WinDir)
            }

            $allowedExitCodes = [int[]]@(0)
            if ($entry.ContainsKey('AllowedExitCodes')) {
                $dismPath = Join-Path -Path $WinDir -ChildPath 'System32\dism.exe'
                if (-not [string]::Equals($exe, $dismPath, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "AllowedExitCodes is restricted to @(0, 3010) on '$dismPath'."
                }
                $allowedExitCodes = [int[]]@(0, 3010)
            }

            Invoke-VantaHiddenProcess -FilePath $exe `
                -ArgumentList ([string[]]$arguments) -Wait `
                -AllowedExitCode $allowedExitCodes | Out-Null
        }
        catch {
            if ($ignoreErrors) {
                $entryExe = Get-VantaTweakEntryValue -Entry $entry -Key 'Exe' -Default '<no executable>'
                Write-VantaLog -Message "Ignored Run entry failure (executable: '$entryExe'): $($_.Exception.Message)" -Level Warning
                continue
            }
            throw
        }
    }
}

function Invoke-VantaTweakRemovePathEntries {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [hashtable[]]$Entries,

        [Parameter(Mandatory = $true)]
        [bool]$IsArm64,

        [Parameter(Mandatory = $true)]
        [string]$WinDir
    )

    $windowsRoot = [IO.Path]::GetFullPath($WinDir).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $windowsPrefix = $windowsRoot + [IO.Path]::DirectorySeparatorChar

    foreach ($entry in $Entries) {
        $ignoreErrors = [bool](Get-VantaTweakEntryValue -Entry $entry -Key 'IgnoreErrors' -Default $false)
        try {
            $arch = [string](Get-VantaTweakEntryValue -Entry $entry -Key 'Arch' -Default '')
            if (-not (Test-VantaArchMatch -Arch $arch -IsArm64 $IsArm64)) {
                continue
            }

            $declaredPath = [string](Get-VantaTweakEntryValue -Entry $entry -Key 'Path')
            if (-not $declaredPath) {
                throw 'RemovePaths entry has no Path.'
            }
            if (-not $declaredPath.StartsWith('{windir}\', [StringComparison]::OrdinalIgnoreCase)) {
                throw "RemovePaths entry '$declaredPath' must start with '{windir}\'."
            }

            $relativePath = $declaredPath.Substring('{windir}\'.Length)
            $targetPath = [IO.Path]::GetFullPath([IO.Path]::Combine($windowsRoot, $relativePath))
            if (-not $targetPath.StartsWith($windowsPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "RemovePaths entry '$declaredPath' resolves outside the Windows directory."
            }
            if (Test-Path -LiteralPath $targetPath) {
                Remove-Item -LiteralPath $targetPath -Recurse -Force -ErrorAction Stop
            }
        }
        catch {
            $entryPath = Get-VantaTweakEntryValue -Entry $entry -Key 'Path' -Default '<no path>'
            if ($ignoreErrors) {
                Write-VantaLog -Message "Ignored RemovePaths entry failure (path: '$entryPath'): $($_.Exception.Message)" -Level Warning
                continue
            }
            throw
        }
    }
}

function Get-VantaUpgradeRegistryEntries {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][hashtable[]]$Entries,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Records,
        [switch]$IgnoreInvalidDefinitions
    )

    # Recorded choices are replayed from current definitions by Defaults and the
    # user migration. Do not overwrite their registry targets with install defaults.
    $owned = @{}
    $ownedTrees = @{}
    foreach ($name in $Records.Keys) {
        try { $definition = Get-VantaToggleDefinition -Name $name }
        catch {
            # Health reports definition failures separately through toggle drift.
            # Application must fail rather than overwrite an unresolved choice.
            if ($IgnoreInvalidDefinitions) { continue }
            throw
        }
        foreach ($state in $definition.States.Values) {
            # An unlock state may deliberately leave the user's current preference
            # alone. Protect the targets owned by every state, not just its writes.
            if (-not $state.Contains('StateValue')) { continue }
            if (-not $state.Contains('Registry')) { continue }
            foreach ($entry in @($state.Registry)) {
                if ($null -eq $entry) { continue }
                $path = (([string]$entry.Path).Replace(':', '') -replace '\\+', '\').TrimEnd('\').ToUpperInvariant()
                $owned[$path + '|' + ([string]$entry['Name']).ToUpperInvariant()] = $true
                if ([string]$entry['Operation'] -ceq 'DeleteKey') { $ownedTrees[$path] = $true }
            }
        }
    }
    foreach ($entry in $Entries) {
        $path = (([string]$entry.Path).Replace(':', '') -replace '\\+', '\').TrimEnd('\').ToUpperInvariant()
        $key = $path + '|' + ([string]$entry['Name']).ToUpperInvariant()
        if ($owned.ContainsKey($key)) { continue }
        $overlapsTree = $false
        foreach ($tree in $ownedTrees.Keys) {
            if ($path -ceq $tree -or $path.StartsWith($tree + '\', [StringComparison]::Ordinal)) {
                $overlapsTree = $true
                break
            }
        }
        if (-not $overlapsTree -and [string]$entry['Operation'] -ceq 'DeleteKey') {
            foreach ($target in $owned.Keys) {
                $ownedPath = $target.Substring(0, $target.IndexOf('|'))
                if ($ownedPath -ceq $path -or $ownedPath.StartsWith($path + '\', [StringComparison]::Ordinal)) {
                    $overlapsTree = $true
                    break
                }
            }
        }
        if ($overlapsTree) { continue }
        if ($entry.ContainsKey('VerifyWithToggle')) {
            $choice = $entry.VerifyWithToggle
            if ($Records.Contains($choice.Name) -and [int]$Records[$choice.Name] -eq [int]$choice.State) {
                $entry = $entry.Clone()
                foreach ($field in 'Operation', 'Type', 'Data') { $entry.Remove($field) }
                foreach ($field in 'Operation', 'Type', 'Data') {
                    if ($choice.ContainsKey($field)) { $entry[$field] = $choice[$field] }
                }
            }
        }
        $entry
    }
}

function Invoke-VantaTweak {
    <#
    .SYNOPSIS
        Loads a tweak .psd1, checks its gates and applies its keys in order: Registry,
        Services, ScheduledTasks, Toggle, Run, RemovePaths, then the companion Script.
        Every required sub-step failure is fatal; individual entries may opt into
        reviewed best-effort behaviour with IgnoreErrors.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [ValidateSet('All', 'Machine', 'ProtectedCurrentUser', 'CurrentUser', 'DefaultUser')]
        [string]$RegistryScope = 'All',

        [switch]$RegistryOnly,

        [psobject]$Context
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Tweak file not found: '$Path'."
    }

    $tweak = Import-VantaDataFile -LiteralPath $Path
    if (-not $tweak.ContainsKey('Name') -or [string]::IsNullOrWhiteSpace([string]$tweak['Name'])) {
        throw "Tweak file '$Path' has no 'Name' key."
    }

    $tweakName = [string]$tweak['Name']
    if (-not $PSBoundParameters.ContainsKey('Context')) {
        $Context = Get-VantaContext
    }
    $skipReason = Get-VantaTweakSkipReason -Tweak $tweak -Context $Context
    if ($skipReason) {
        Write-VantaLog -Message "Skipping tweak '$tweakName': $skipReason."
        return
    }

    Write-VantaLog -Message "Applying tweak '$tweakName'."

    if ($tweak.ContainsKey('Registry') -and $tweak['Registry']) {
        $registryEntries = @($tweak['Registry'])
        if ($Context.IsUpgrade -and $RegistryScope -cne 'DefaultUser') {
            $registryEntries = @(Get-VantaUpgradeRegistryEntries -Entries $registryEntries -Records (Get-VantaToggleStateRecords))
        }
        Invoke-VantaRegistryEntries -Entries $registryEntries `
            -Scope $RegistryScope -IsArm64 ([bool]$Context.IsArm64)
    }

    if ($RegistryOnly) {
        return
    }

    if ($tweak.ContainsKey('Services') -and $tweak['Services']) {
        Invoke-VantaServiceEntries -Entries $tweak['Services']
    }

    if ($tweak.ContainsKey('ScheduledTasks') -and $tweak['ScheduledTasks']) {
        Invoke-VantaScheduledTaskEntries -Entries $tweak['ScheduledTasks']
    }

    if ($tweak.ContainsKey('Toggle') -and $tweak['Toggle']) {
        # The install shares the toggle's machine implementation and records the
        # state, so the VantaDesktop launcher and the install cannot drift apart.
        foreach ($entry in @($tweak['Toggle'])) {
            $state = [string]$entry['State']
            if ($Context.IsUpgrade) {
                $record = Get-VantaToggleState -Name ([string]$entry['Name'])
                if ($null -ne $record -and $null -ne $record.State) {
                    $definition = Get-VantaToggleDefinition -Name ([string]$entry['Name'])
                    $states = @($definition.States.Values | Where-Object {
                        $_.Contains('StateValue') -and [int]$_.StateValue -eq [int]$record.State
                    })
                    if ($states.Count -ne 1) { throw "Recorded toggle '$($entry['Name'])' has no unique installed state." }
                    $state = [string]$states[0].Name
                }
            }
            Invoke-VantaToggleMachineState -Name ([string]$entry['Name']) -State $state
        }
    }

    if ($tweak.ContainsKey('Run') -and $tweak['Run']) {
        Invoke-VantaTweakRunEntries -Entries $tweak['Run'] -IsArm64 ([bool]$Context.IsArm64) `
            -WinDir ([string]$Context.WinDir)
    }

    if ($tweak.ContainsKey('RemovePaths') -and $tweak['RemovePaths']) {
        Invoke-VantaTweakRemovePathEntries -Entries $tweak['RemovePaths'] `
            -IsArm64 ([bool]$Context.IsArm64) -WinDir ([string]$Context.WinDir)
    }

    if ($tweak.ContainsKey('Script') -and $tweak['Script']) {
        $scriptPath = Join-Path -Path (Split-Path -Path $Path -Parent) -ChildPath ([string]$tweak['Script'])
        $runAs = [string](Get-VantaTweakEntryValue -Entry $tweak -Key 'RunAs' -Default '')
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            throw "Tweak '$tweakName': companion script '$scriptPath' is missing."
        }

        if ([string]::IsNullOrWhiteSpace($runAs)) {
            & $scriptPath
            return
        }
        if ($runAs -cne 'User') {
            throw "Tweak '$tweakName' has unsupported companion RunAs '$runAs'."
        }

        $expectedUserSid = Get-VantaTweakUserSid -Context $Context
        $arguments = ConvertTo-VantaWindowsArgumentString -ArgumentList @(
            '-NoProfile', '-NoLogo', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath,
            '-ExpectedUserSid', $expectedUserSid
        )
        $powerShellPath = Join-Path -Path $Context.WinDir `
            -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $exitCode = Invoke-VantaAsUser -FilePath $powerShellPath -Arguments $arguments
        if ($exitCode -ne 0) {
            throw "Tweak '$tweakName' companion script (RunAs=$runAs) exited with code $exitCode."
        }
    }
}

function Invoke-VantaTweakCategory {
    <#
    .SYNOPSIS
        Applies every tweak of a manifest category in order. A missing or failing tweak
        is fatal; individual entries must declare IgnoreErrors to be best-effort.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [string]$TweaksRoot,

        [ValidateSet('All', 'Machine', 'ProtectedCurrentUser', 'CurrentUser', 'DefaultUser')]
        [string]$RegistryScope = 'All',

        [switch]$RegistryOnly,

        [psobject]$Context
    )

    if ($null -eq $Context) {
        $Context = Get-VantaContext
    }
    if (-not $TweaksRoot) {
        $TweaksRoot = Join-Path -Path $Context.VantaModulesPath -ChildPath 'Scripts\Tweaks'
    }

    $manifest = Get-VantaTweakManifest -Path (Join-Path -Path $TweaksRoot -ChildPath 'tweaks.manifest.psd1')

    $category = $manifest['Categories'] |
        Where-Object { [string]$_['Name'] -ceq $Name } | Select-Object -First 1
    if ($null -eq $category) {
        throw "Category '$Name' is not defined in the tweak manifest."
    }

    $tweakNames = @($category['Tweaks'])
    $categoryRoot = Join-Path -Path $TweaksRoot -ChildPath $Name

    $passDescription = if ($RegistryOnly) {
        "$RegistryScope registry-only"
    }
    else {
        "$RegistryScope registry and companion"
    }
    Write-VantaLog -Message (
        "Applying tweak category '$Name' ($(@($tweakNames).Count) tweak(s); $passDescription pass)."
    )

    foreach ($tweakName in $tweakNames) {
        $relativePath = ([string]$tweakName -replace '/', '\') + '.psd1'
        $tweakFile = Join-Path -Path $categoryRoot -ChildPath $relativePath

        Invoke-VantaTweak -Path $tweakFile -RegistryScope $RegistryScope `
            -RegistryOnly:$RegistryOnly -Context $Context
    }
}

function Get-VantaTweakCategoryPostUserRegistryRefresh {
    <#
    .SYNOPSIS
        Returns the ordered, de-duplicated post-live-HKCU shell refresh operations
        declared by applicable definitions in one tweak category.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [string]$TweaksRoot,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$Context
    )

    if (-not $TweaksRoot) {
        if ($null -eq $Context.PSObject.Properties['VantaModulesPath'] -or
            [string]::IsNullOrWhiteSpace([string]$Context.VantaModulesPath)) {
            throw 'Post-user-registry refresh resolution requires a protected VantaModulesPath.'
        }
        $TweaksRoot = Join-Path -Path ([string]$Context.VantaModulesPath) -ChildPath 'Scripts\Tweaks'
    }

    $manifest = Get-VantaTweakManifest `
        -Path (Join-Path -Path $TweaksRoot -ChildPath 'tweaks.manifest.psd1')
    $category = $manifest['Categories'] |
        Where-Object { [string]$_['Name'] -ceq $Name } | Select-Object -First 1
    if ($null -eq $category) {
        throw "Category '$Name' is not defined in the tweak manifest."
    }

    $categoryRoot = Join-Path -Path $TweaksRoot -ChildPath $Name
    $operations = @()
    foreach ($tweakName in @($category['Tweaks'])) {
        $relativePath = ([string]$tweakName -replace '/', '\') + '.psd1'
        $tweakPath = Join-Path -Path $categoryRoot -ChildPath $relativePath
        $tweak = Import-VantaDataFile -LiteralPath $tweakPath
        if ($null -ne (Get-VantaTweakSkipReason -Tweak $tweak -Context $Context) -or
            -not $tweak.ContainsKey('PostUserRegistryRefresh')) {
            continue
        }

        $operation = [string]$tweak['PostUserRegistryRefresh']
        if ($script:VantaTweakPostUserRegistryRefreshOperations -cnotcontains $operation) {
            throw "Tweak '$Name/$tweakName' has invalid PostUserRegistryRefresh operation '$operation'."
        }
        if ($operations -cnotcontains $operation) {
            $operations += $operation
        }
    }

    return $operations
}
