# Vanta.Registry domain: verification of declarative registry entries.
#
# Apply and verify share one vocabulary. Invoke-VantaRegistryEntries applies a Registry
# array; Test-VantaRegistryEntries reads the same array back and reports every entry
# whose current value differs from what it declares. The health check, the upgrade
# reconciliation report and tests use it; it never writes.

function Get-VantaRegistryValueState {
    <#
    .SYNOPSIS
        Reads one value (or key) through the same identity-scoped resolution that
        writes use, without expanding environment strings.
    .OUTPUTS
        KeyExists, ValueExists, Kind and Data.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [AllowEmptyString()]
        [string]$Name = ''
    )

    $state = [pscustomobject]@{ KeyExists = $false; ValueExists = $false; Kind = $null; Data = $null }
    Invoke-VantaRegistryTargetOperation -Path $Path -Action {
        param($providerPath)

        $split = Split-VantaRegistryProviderPath -ProviderPath $providerPath
        $key = $split.BaseKey.OpenSubKey($split.SubPath, $false)
        if ($null -eq $key) {
            return
        }
        try {
            $state.KeyExists = $true
            if (@($key.GetValueNames()) -contains $Name) {
                $state.ValueExists = $true
                $state.Kind = [string]$key.GetValueKind($Name)
                $state.Data = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            }
        }
        finally {
            $key.Close()
        }
    }
    return $state
}

function Test-VantaRegistryDataEqual {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [object]$Expected,
        [object]$Actual
    )

    switch ($Type) {
        'DWord' { return [int64](ConvertTo-VantaDwordData -Data $Expected) -eq [int64]$Actual }
        'QWord' { return [int64](ConvertTo-VantaQwordData -Data $Expected) -eq [int64]$Actual }
        'Binary' {
            $left = [byte[]]$Expected
            $right = [byte[]]$Actual
            if ($left.Length -ne $right.Length) { return $false }
            for ($index = 0; $index -lt $left.Length; $index++) {
                if ($left[$index] -ne $right[$index]) { return $false }
            }
            return $true
        }
        'MultiString' {
            $left = @([string[]]$Expected)
            $right = @([string[]]$Actual)
            if ($left.Count -ne $right.Count) { return $false }
            for ($index = 0; $index -lt $left.Count; $index++) {
                if ($left[$index] -cne $right[$index]) { return $false }
            }
            return $true
        }
        'None' { return $true }
        default { return [string]$Expected -ceq [string]$Actual }
    }
}

function Test-VantaRegistryEntries {
    <#
    .SYNOPSIS
        Reports every Registry entry whose current state differs from its declaration.
        Scope selects the same subset Invoke-VantaRegistryEntries would apply.
    .OUTPUTS
        One object per drifted entry: Path, Name, Operation, Expected, Actual, Reason.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [hashtable[]]$Entries,

        [ValidateSet('All', 'Machine', 'ProtectedCurrentUser', 'CurrentUser', 'DefaultUser')]
        [string]$Scope = 'All',

        [bool]$IsArm64
    )

    $arm64 = if ($PSBoundParameters.ContainsKey('IsArm64')) { $IsArm64 } else { [bool](Get-VantaContext).IsArm64 }
    $drift = @()

    foreach ($entry in $Entries) {
        if (-not $entry.ContainsKey('Path') -or [string]::IsNullOrWhiteSpace([string]$entry['Path'])) {
            continue
        }
        $targetScope = Get-VantaRegistryEntryTargetScope -Path ([string]$entry['Path'])
        if (-not (Test-VantaRegistryEntryInScope -Entry $entry -TargetScope $targetScope -Scope $Scope -IsArm64 $arm64)) {
            continue
        }

        if ($entry.ContainsKey('SkipVerification')) {
            if ($entry['SkipVerification'] -isnot [string] -or
                [string]::IsNullOrWhiteSpace($entry['SkipVerification'])) {
                throw "Registry entry 'SkipVerification' must be a non-empty reason string."
            }
            Write-Verbose "Skipping registry verification for '$($entry['Path'])': $($entry['SkipVerification'])"
            continue
        }

        $operation = Get-VantaRegistryEntryOperation -Entry $entry
        $name = if ($entry.ContainsKey('Name')) { [string]$entry['Name'] } else { '' }
        $path = [string]$entry['Path']

        try {
            $actual = Get-VantaRegistryValueState -Path $path -Name $name
        }
        catch {
            $drift += [pscustomobject]@{
                Path = $path; Name = $name; Operation = $operation
                Expected = $null; Actual = $null; Reason = "could not be read: $($_.Exception.Message)"
            }
            continue
        }

        $reason = $null
        switch ($operation) {
            'Set' {
                $type = [string]$entry['Type']
                if (-not $actual.ValueExists) {
                    $reason = 'value is missing'
                }
                elseif ($type -cne 'None' -and $actual.Kind -cne $type) {
                    $reason = "value kind is $($actual.Kind), expected $type"
                }
                elseif ($entry.ContainsKey('Mask')) {
                    try {
                        $merged = Merge-VantaRegistryMaskedData -Entry $entry -Current $actual.Data
                        if (-not (Test-VantaRegistryDataEqual -Type $type -Expected $merged -Actual $actual.Data)) { $reason = 'selected value bits differ' }
                    }
                    catch { $reason = $_.Exception.Message }
                }
                elseif (-not (Test-VantaRegistryDataEqual -Type $type -Expected $entry['Data'] -Actual $actual.Data)) {
                    $reason = 'value data differs'
                }
            }
            'Delete' { if ($actual.ValueExists) { $reason = 'value still exists' } }
            'DeleteKey' { if ($actual.KeyExists) { $reason = 'key still exists' } }
            'AddKey' { if (-not $actual.KeyExists) { $reason = 'key is missing' } }
            default { $reason = "unknown operation '$operation'" }
        }

        if ($null -ne $reason) {
            $drift += [pscustomobject]@{
                Path = $path; Name = $name; Operation = $operation
                Expected = if ($entry.ContainsKey('Data')) { $entry['Data'] } else { $null }
                Actual = $actual.Data; Reason = $reason
            }
        }
    }

    return $drift
}
