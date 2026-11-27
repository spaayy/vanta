# Installs a closed, UAC-backed RunAs verb for .reg files. The transition accepts
# only absent state, the exact former Vanta TrustedInstaller verb, the exact new
# Administrator verb, or a known partial transition between those states.

Set-StrictMode -Version 3.0

$script:VantaMergeParentPath = 'SOFTWARE\Classes\regfile\Shell\RunAs'
$script:VantaMergeCommandPath = "$script:VantaMergeParentPath\Command"
$script:VantaMergeLegacyLabel = 'Merge As TrustedInstaller'
$script:VantaMergeLegacyCommands = @(
    'cmd /c "%windir%\VantaModules\Scripts\RunAsTI.cmd" "%1"'
    'RunAsTI.cmd reg import "%1"'
    'cmd /c %windir%\VantaModules\Scripts\RunAsTI.cmd "%1"'
    'cmd /c C:\Windows\VantaModules\Scripts\RunAsTI.cmd "%1"'
)
$script:VantaMergeAdministratorLabel = 'Merge as administrator'
$script:VantaMergeAdministratorCommand = '"%SystemRoot%\System32\reg.exe" import "%1"'

function Get-VantaMergeRegistrySnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SubKey)

    $baseKey = $null
    $key = $null
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        $key = $baseKey.OpenSubKey($SubKey, $false)
        if ($null -eq $key) {
            return [pscustomobject]@{ Exists = $false; Values = @(); SubKeys = @() }
        }
        $values = @($key.GetValueNames() | ForEach-Object {
                $name = [string]$_
                [pscustomobject]@{
                    Name = $name
                    Kind = $key.GetValueKind($name).ToString()
                    Value = $key.GetValue(
                        $name,
                        $null,
                        [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
                    )
                }
            })
        return [pscustomobject]@{
            Exists = $true
            Values = $values
            SubKeys = @($key.GetSubKeyNames())
        }
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        if ($null -ne $baseKey) { $baseKey.Dispose() }
    }
}

function Set-VantaMergeRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SubKey,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][ValidateSet('String', 'ExpandString')][string]$Kind
    )

    $baseKey = $null
    $key = $null
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        $key = $baseKey.CreateSubKey($SubKey)
        if ($null -eq $key) { throw "Creating or opening 'HKLM\$SubKey' returned no registry key." }
        $registryKind = [Enum]::Parse([Microsoft.Win32.RegistryValueKind], $Kind, $false)
        $key.SetValue($Name, $Value, $registryKind)
        $key.Flush()
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        if ($null -ne $baseKey) { $baseKey.Dispose() }
    }
}

function Get-VantaMergeSnapshotValue {
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name
    )

    $matchingValues = @($Snapshot.Values | Where-Object { [string]$_.Name -ieq $Name })
    if ($matchingValues.Count -ne 1) { return $null }
    return $matchingValues[0]
}

function Test-VantaMergeSnapshotEqual {
    param(
        [Parameter(Mandatory = $true)]$Left,
        [Parameter(Mandatory = $true)]$Right
    )

    if ([bool]$Left.Exists -ne [bool]$Right.Exists) { return $false }
    if (-not $Left.Exists) { return $true }
    if (@($Left.Values).Count -ne @($Right.Values).Count -or
        @($Left.SubKeys).Count -ne @($Right.SubKeys).Count) { return $false }
    foreach ($value in @($Left.Values)) {
        $other = Get-VantaMergeSnapshotValue -Snapshot $Right -Name ([string]$value.Name)
        if ($null -eq $other -or [string]$other.Kind -cne [string]$value.Kind -or
            [string]$other.Value -cne [string]$value.Value) { return $false }
    }
    foreach ($subKey in @($Left.SubKeys)) {
        if (@($Right.SubKeys | Where-Object { [string]$_ -ieq [string]$subKey }).Count -ne 1) {
            return $false
        }
    }
    return $true
}

function Test-VantaMergeParentKnown {
    param(
        [Parameter(Mandatory = $true)]$Parent,
        [Parameter(Mandatory = $true)][bool]$CommandExists
    )

    if (-not $Parent.Exists) { return -not $CommandExists }
    $expectedSubKeyCount = if ($CommandExists) { 1 } else { 0 }
    if (@($Parent.SubKeys).Count -ne $expectedSubKeyCount -or
        ($CommandExists -and @($Parent.SubKeys | Where-Object { [string]$_ -ieq 'Command' }).Count -ne 1) -or
        @($Parent.Values).Count -gt 2) { return $false }

    foreach ($value in @($Parent.Values)) {
        if ([string]$value.Name -ceq '') {
            if ([string]$value.Kind -cne 'String' -or
                [string]$value.Value -cnotin @(
                    $script:VantaMergeLegacyLabel,
                    $script:VantaMergeAdministratorLabel
                )) { return $false }
        }
        elseif ([string]$value.Name -ceq 'HasLUAShield') {
            if ([string]$value.Kind -cne 'String' -or [string]$value.Value -cne '1') {
                return $false
            }
        }
        else { return $false }
    }
    return $true
}

function Test-VantaMergeCommandKnown {
    param([Parameter(Mandatory = $true)]$Command)

    if (-not $Command.Exists) { return $true }
    if (@($Command.SubKeys).Count -ne 0 -or @($Command.Values).Count -gt 1) { return $false }
    # A failed SetValue after CreateSubKey can leave this exact empty command key.
    # It contains no executable data and is a recoverable command-first checkpoint.
    if (@($Command.Values).Count -eq 0) { return $true }
    $value = Get-VantaMergeSnapshotValue -Snapshot $Command -Name ''
    if ($null -eq $value) { return $false }
    return ([string]$value.Kind -ceq 'String' -and
            $script:VantaMergeLegacyCommands -ccontains [string]$value.Value) -or
        ([string]$value.Kind -ceq 'ExpandString' -and
            [string]$value.Value -ceq $script:VantaMergeAdministratorCommand)
}

function Test-VantaMergeCanonical {
    param(
        [Parameter(Mandatory = $true)]$Parent,
        [Parameter(Mandatory = $true)]$Command
    )

    if (-not $Parent.Exists -or -not $Command.Exists -or
        @($Parent.Values).Count -ne 2 -or @($Parent.SubKeys).Count -ne 1 -or
        @($Command.Values).Count -ne 1 -or @($Command.SubKeys).Count -ne 0) { return $false }
    $label = Get-VantaMergeSnapshotValue -Snapshot $Parent -Name ''
    $shield = Get-VantaMergeSnapshotValue -Snapshot $Parent -Name 'HasLUAShield'
    $commandValue = Get-VantaMergeSnapshotValue -Snapshot $Command -Name ''
    return $null -ne $label -and $label.Kind -ceq 'String' -and
        $label.Value -ceq $script:VantaMergeAdministratorLabel -and
        $null -ne $shield -and $shield.Kind -ceq 'String' -and $shield.Value -ceq '1' -and
        @($Parent.SubKeys | Where-Object { [string]$_ -ieq 'Command' }).Count -eq 1 -and
        $null -ne $commandValue -and $commandValue.Kind -ceq 'ExpandString' -and
        $commandValue.Value -ceq $script:VantaMergeAdministratorCommand
}

function Invoke-VantaAdministratorMergeTransition {
    [CmdletBinding()]
    param(
        [scriptblock]$RegistryReader,
        [scriptblock]$RegistryWriter
    )

    if ($null -eq $RegistryReader) {
        $RegistryReader = { param($SubKey) Get-VantaMergeRegistrySnapshot -SubKey $SubKey }
    }
    if ($null -eq $RegistryWriter) {
        $RegistryWriter = {
            param($SubKey, $Name, $Value, $Kind)
            Set-VantaMergeRegistryValue -SubKey $SubKey -Name $Name -Value $Value -Kind $Kind
        }
    }

    $parent = & $RegistryReader $script:VantaMergeParentPath
    $command = & $RegistryReader $script:VantaMergeCommandPath
    if (-not (Test-VantaMergeParentKnown -Parent $parent -CommandExists ([bool]$command.Exists)) -or
        -not (Test-VantaMergeCommandKnown -Command $command)) {
        throw 'The registry-file RunAs verb is customized or ambiguous; Vanta will not overwrite it.'
    }
    if (Test-VantaMergeCanonical -Parent $parent -Command $command) { return }

    # Revalidate the entire recognised starting shape immediately before mutation.
    $freshParent = & $RegistryReader $script:VantaMergeParentPath
    $freshCommand = & $RegistryReader $script:VantaMergeCommandPath
    if (-not (Test-VantaMergeSnapshotEqual -Left $parent -Right $freshParent) -or
        -not (Test-VantaMergeSnapshotEqual -Left $command -Right $freshCommand)) {
        throw 'The registry-file RunAs verb changed after validation; Vanta will not overwrite it.'
    }

    # Commit the least-privilege executable command first. If interruption occurs,
    # the old TI command is gone before the user-visible label can change.
    [void](& $RegistryWriter $script:VantaMergeCommandPath '' `
            $script:VantaMergeAdministratorCommand 'ExpandString')
    $command = & $RegistryReader $script:VantaMergeCommandPath
    if (-not (Test-VantaMergeCommandKnown -Command $command)) {
        throw 'The Administrator registry-import command did not verify after publication.'
    }
    $commandValue = Get-VantaMergeSnapshotValue -Snapshot $command -Name ''
    if ($null -eq $commandValue -or $commandValue.Kind -cne 'ExpandString' -or
        $commandValue.Value -cne $script:VantaMergeAdministratorCommand) {
        throw 'The Administrator registry-import command did not verify after publication.'
    }

    $parent = & $RegistryReader $script:VantaMergeParentPath
    if (-not (Test-VantaMergeParentKnown -Parent $parent -CommandExists $true)) {
        throw 'The registry-file RunAs parent changed after command publication; Vanta will not overwrite it.'
    }
    [void](& $RegistryWriter $script:VantaMergeParentPath '' `
            $script:VantaMergeAdministratorLabel 'String')
    $parent = & $RegistryReader $script:VantaMergeParentPath
    $label = Get-VantaMergeSnapshotValue -Snapshot $parent -Name ''
    if (-not (Test-VantaMergeParentKnown -Parent $parent -CommandExists $true) -or
        $null -eq $label -or $label.Kind -cne 'String' -or
        $label.Value -cne $script:VantaMergeAdministratorLabel) {
        throw 'The Administrator registry-file label did not verify after publication.'
    }
    [void](& $RegistryWriter $script:VantaMergeParentPath 'HasLUAShield' '1' 'String')
    $parent = & $RegistryReader $script:VantaMergeParentPath
    $command = & $RegistryReader $script:VantaMergeCommandPath
    if (-not (Test-VantaMergeCanonical -Parent $parent -Command $command)) {
        throw 'The complete Administrator registry-file RunAs verb did not verify after publication.'
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    Invoke-VantaAdministratorMergeTransition
}
