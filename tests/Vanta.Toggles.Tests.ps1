BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $script:repoRoot = $script:VantaTestRepoRoot
    $modulesRoot = $script:VantaTestModulesRoot

    Import-Module (Join-Path $modulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module (Join-Path $modulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force
    $script:ToolsHost = $script:VantaTestToolsHost

    $script:StateRoot = 'HKCU:\Software\VantaRewriteTest\Services'
    $script:ShippedTogglesRoot = Join-Path $script:repoRoot 'package\Executables\VantaModules\Toggles'

    # Writes a definition (and optional companion) into a scratch toggles tree.
    function New-TestToggle {
        param(
            [Parameter(Mandatory = $true)][string]$Root,
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][string]$Definition,
            [string]$Companion,
            [string]$Group = 'TestGroup'
        )

        $groupDirectory = Join-Path $Root $Group
        New-Item -Path $groupDirectory -ItemType Directory -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $groupDirectory "$Name.psd1"), $Definition, [Text.UTF8Encoding]::new($false))
        if ($PSBoundParameters.ContainsKey('Companion')) {
            [IO.File]::WriteAllText((Join-Path $groupDirectory "$Name.ps1"), $Companion, [Text.UTF8Encoding]::new($false))
        }
    }

    # Companion functions record what ran through marker files under $env:VantaToggleTestDir.
    $script:MarkerCompanion = @'
function Write-VantaTestMarker {
    param([string]$Name, [string]$Value)
    [IO.File]::WriteAllText((Join-Path $env:VantaToggleTestDir "$Name.txt"), $Value)
}

function Invoke-VantaTestContext {
    param($Toggle)
    Write-VantaTestMarker -Name 'context' -Value $Toggle.State
}

function Invoke-VantaTestLocal {
    param($Toggle)
    Write-VantaTestMarker -Name 'local' -Value "$($Toggle.Name):$($Toggle.State):$($Toggle.StateValue)"
}

function Invoke-VantaTestMachine {
    param($Toggle)
    Write-VantaTestMarker -Name 'machine' -Value "$($Toggle.Name):$($Toggle.State):$($Toggle.StateValue):silent=$($Toggle.Silent)"
}

function Invoke-VantaTestUser {
    param($Toggle)
    Write-VantaTestMarker -Name 'user' -Value "$($Toggle.Name):$($Toggle.State)"
}

function Invoke-VantaTestFailure {
    param($Toggle)
    throw 'deliberate failure'
}

function Invoke-VantaTestPowerShellError {
    param($Toggle)
    Write-Error 'ordinary action error'
}

function Invoke-VantaTestIgnoredError {
    param($Toggle)
    Write-Error 'intentionally ignored' -ErrorAction Ignore
    Write-VantaTestMarker -Name 'ignored-error' -Value 'continued'
}

function Invoke-VantaTestContextFailure {
    param($Toggle)
    throw 'deliberate context failure'
}

function Test-VantaTestReplayApplicable {
    param($Toggle)
    return [bool]$env:VantaToggleTestReplayApplicable
}
'@
}

AfterAll {
    # Only remove the Services subtree; other test files share the VantaRewriteTest root.
    Remove-Item -Path 'HKCU:\Software\VantaRewriteTest\Services' -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Binary toggle state contract' {
    It 'exposes Disable and Enable for every two-state public toggle' {
        foreach ($file in Get-ChildItem -LiteralPath $script:ShippedTogglesRoot -Recurse -Filter '*.psd1') {
            $definition = Import-PowerShellDataFile -LiteralPath $file.FullName
            $states = @($definition.States | Where-Object { -not $_.Internal })
            if ($states.Count -ne 2) { continue }

            @($states.Name | Sort-Object) | Should -Be @('Disable', 'Enable') -Because $definition.Name
            foreach ($state in $states) {
                if (-not $state.ContainsKey('StateValue')) { continue }
                $expectedValue = if ($state.Name -eq 'Disable') { 0 } else { 1 }
                $state.StateValue | Should -Be $expectedValue -Because $definition.Name
            }
        }
    }
}

Describe 'Toggle definition loading and validation' {
    BeforeAll {
        $script:TogglesRoot = Join-Path $TestDrive 'Toggles'

        New-TestToggle -Root $TogglesRoot -Name 'GoodToggle' -Definition @'
@{
    Name      = 'GoodToggle'
    Elevation = 'Admin'
    Script    = 'GoodToggle.ps1'
    States    = @(
        @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; MachineAction = 'Invoke-VantaTestMachine'; UserAction = 'Invoke-VantaTestUser' }
        @{ Name = 'Off'; StateValue = 0; Launcher = 'A\Off.cmd'; Registry = @( @{ Path = 'HKLM:\SOFTWARE\VantaRewriteTest'; Name = 'x'; Type = 'DWord'; Data = 0 } ) }
    )
}
'@ -Companion $script:MarkerCompanion

        New-TestToggle -Root $TogglesRoot -Name 'ScriptBlockToggle' -Definition @'
@{
    Name          = 'ScriptBlockToggle'
    Elevation     = 'None'
    NoStateRecord = $true
    States        = @( @{ Name = 'On'; Launcher = 'A\On.cmd'; Action = { param($Toggle) } } )
}
'@
        New-TestToggle -Root $TogglesRoot -Name 'MissingFunction' -Definition @'
@{
    Name      = 'MissingFunction'
    Elevation = 'Admin'
    Script    = 'MissingFunction.ps1'
    States    = @( @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; MachineAction = 'Invoke-VantaNotDefined' } )
}
'@ -Companion $script:MarkerCompanion
        New-TestToggle -Root $TogglesRoot -Name 'SideEffectCompanion' -Definition @'
@{
    Name      = 'SideEffectCompanion'
    Elevation = 'Admin'
    Script    = 'SideEffectCompanion.ps1'
    States    = @( @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; MachineAction = 'Invoke-VantaTestMachine' } )
}
'@ -Companion ("Set-Content -Path (Join-Path `$env:TEMP 'vanta-side-effect.txt') -Value 'ran'`n" + $script:MarkerCompanion)
        New-TestToggle -Root $TogglesRoot -Name 'ElevatedAction' -Definition @'
@{
    Name      = 'ElevatedAction'
    Elevation = 'Admin'
    Script    = 'ElevatedAction.ps1'
    States    = @( @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; Action = 'Invoke-VantaTestLocal' } )
}
'@ -Companion $script:MarkerCompanion
        New-TestToggle -Root $TogglesRoot -Name 'UnelevatedMachine' -Definition @'
@{
    Name          = 'UnelevatedMachine'
    Elevation     = 'None'
    NoStateRecord = $true
    States        = @( @{ Name = 'On'; Launcher = 'A\On.cmd'; Registry = @( @{ Path = 'HKLM:\SOFTWARE\X'; Name = 'y'; Type = 'DWord'; Data = 1 } ) } )
}
'@
        New-TestToggle -Root $TogglesRoot -Name 'UnelevatedRecord' -Definition @'
@{
    Name      = 'UnelevatedRecord'
    Elevation = 'None'
    Script    = 'UnelevatedRecord.ps1'
    States    = @( @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; Action = 'Invoke-VantaTestLocal' } )
}
'@ -Companion $script:MarkerCompanion
        New-TestToggle -Root $TogglesRoot -Name 'UserPolicy' -Definition @'
@{
    Name      = 'UserPolicy'
    Elevation = 'Admin'
    States    = @( @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; Registry = @( @{ Path = 'HKCU:\Software\Policies\Microsoft\Windows\X'; Name = 'y'; Type = 'DWord'; Data = 1 } ) } )
}
'@
        New-TestToggle -Root $TogglesRoot -Name 'DuplicateValue' -Definition @'
@{
    Name      = 'DuplicateValue'
    Elevation = 'Admin'
    States    = @(
        @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; Registry = @( @{ Path = 'HKLM:\SOFTWARE\X'; Name = 'y'; Type = 'DWord'; Data = 1 } ) }
        @{ Name = 'Off'; StateValue = 1; Launcher = 'A\Off.cmd'; Registry = @( @{ Path = 'HKLM:\SOFTWARE\X'; Name = 'y'; Type = 'DWord'; Data = 0 } ) }
    )
}
'@
        New-TestToggle -Root $TogglesRoot -Name 'WrongName' -Definition @'
@{
    Name      = 'SomethingElse'
    Elevation = 'Admin'
    States    = @( @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; Registry = @( @{ Path = 'HKLM:\SOFTWARE\X'; Name = 'y'; Type = 'DWord'; Data = 1 } ) } )
}
'@
        New-TestToggle -Root $TogglesRoot -Name 'UnknownKey' -Definition @'
@{
    Name      = 'UnknownKey'
    Elevation = 'Admin'
    Sideload  = $true
    States    = @( @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; Registry = @( @{ Path = 'HKLM:\SOFTWARE\X'; Name = 'y'; Type = 'DWord'; Data = 1 } ) } )
}
'@
    }

    It 'loads a well-formed definition as an ordered state dictionary with its companion functions' {
        $definition = Get-VantaToggleDefinition -Name 'GoodToggle' -TogglesRoot $TogglesRoot

        $definition.Name | Should -Be 'GoodToggle'
        @($definition.States.Keys) | Should -Be @('On', 'Off')
        $definition.States['On']['StateValue'] | Should -Be 1
        $definition.ScriptPath | Should -Be (Join-Path $TogglesRoot 'TestGroup\GoodToggle.ps1')
        $definition.Functions | Should -Contain 'Invoke-VantaTestMachine'
    }

    It 'classifies machine and user work from the declarations' {
        $definition = Get-VantaToggleDefinition -Name 'GoodToggle' -TogglesRoot $TogglesRoot

        $on = Get-VantaToggleStateWork -Definition $definition -StateEntry $definition.States['On']
        $on.Machine | Should -BeTrue
        $on.User | Should -BeTrue
        $on.Local | Should -BeFalse

        $off = Get-VantaToggleStateWork -Definition $definition -StateEntry $definition.States['Off']
        $off.Machine | Should -BeTrue
        $off.User | Should -BeFalse
    }

    It 'never executes definition code: a scriptblock in a data file is rejected' {
        { Get-VantaToggleDefinition -Name 'ScriptBlockToggle' -TogglesRoot $TogglesRoot } |
            Should -Throw "*'Action' must name a Verb-VantaNoun function*"
    }

    It 'rejects a definition that names a function its companion does not define' {
        { Get-VantaToggleDefinition -Name 'MissingFunction' -TogglesRoot $TogglesRoot } |
            Should -Throw "*Invoke-VantaNotDefined*does not define*"
    }

    It 'rejects a companion with top-level statements without running them' {
        Remove-Item -LiteralPath (Join-Path $env:TEMP 'vanta-side-effect.txt') -Force -ErrorAction SilentlyContinue

        { Get-VantaToggleDefinition -Name 'SideEffectCompanion' -TogglesRoot $TogglesRoot } |
            Should -Throw '*must contain only function definitions*'
        Join-Path $env:TEMP 'vanta-side-effect.txt' | Should -Not -Exist
    }

    It 'rejects the shape problems the schema forbids' -TestCases @(
        @{ Name = 'ElevatedAction'; Message = "*declares 'Action'; elevated toggles*" }
        @{ Name = 'UnelevatedMachine'; Message = '*machine registry paths without elevation*' }
        @{ Name = 'UnelevatedRecord'; Message = '*declare NoStateRecord*' }
        @{ Name = 'UserPolicy'; Message = '*protected HKCU policy path*' }
        @{ Name = 'DuplicateValue'; Message = '*reuses StateValue*' }
        @{ Name = 'WrongName'; Message = "*declares Name 'SomethingElse'*" }
        @{ Name = 'UnknownKey'; Message = "*unknown top-level key 'Sideload'*" }
    ) {
        { Get-VantaToggleDefinition -Name $Name -TogglesRoot $TogglesRoot } | Should -Throw $Message
    }

    It 'throws when no definition with the given name exists' {
        { Get-VantaToggleDefinition -Name 'Missing' -TogglesRoot $TogglesRoot } |
            Should -Throw "*No toggle definition named 'Missing'*"
    }

    It 'finds a definition by its name in other letter case, and loads it under its own' {
        $definition = Get-VantaToggleDefinition -Name 'goodtoggle' -TogglesRoot $TogglesRoot
        $definition.Name | Should -BeExactly 'GoodToggle'
    }

    It 'reports every problem of a tree through Test-VantaToggleDefinition' {
        $problems = @(Test-VantaToggleDefinition -Path $TogglesRoot)

        @($problems | Where-Object { $_.Path -like '*GoodToggle.psd1' }).Count | Should -Be 0
        @($problems | Where-Object { $_.Path -like '*UnknownKey.psd1' }).Count | Should -Be 1
        @($problems | Where-Object { $_.Path -like '*DuplicateValue.psd1' }).Count | Should -Be 1
    }
}

Describe 'Included toggle definitions' {
    It 'all validate without running any toggle code' {
        $problems = @(Test-VantaToggleDefinition -Path $script:ShippedTogglesRoot)
        ($problems | ForEach-Object { "$($_.Path): $($_.Problem)" }) -join "`n" | Should -BeNullOrEmpty
    }

    It 'never hard-code the Windows directory' {
        # Windows is not always at C:\Windows; an ExpandString with %SystemRoot% follows it.
        $files = Get-ChildItem -LiteralPath $script:ShippedTogglesRoot -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psd1' }
        @($files | Select-String -Pattern "(?i)['""][a-z]:\\Windows\\" | ForEach-Object { "$($_.Path):$($_.LineNumber)" }) |
            Should -BeNullOrEmpty
    }

    It 'keep prompts and progress out of TrustedInstaller machine actions, which the broker runs silently' {
        $interactive = '^(Read-Vanta\w+|Wait-VantaContinue|Write-Vanta(Step|Note|Warning|Success|NextStep|ManualStep|Partial))$'
        $problems = foreach ($file in Get-ChildItem -LiteralPath $script:ShippedTogglesRoot -Recurse -Filter '*.psd1') {
            $definition = Import-PowerShellDataFile -LiteralPath $file.FullName
            if ($definition['Elevation'] -cne 'TrustedInstaller' -or -not $definition['Script']) { continue }
            $companion = [Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $file.DirectoryName $definition['Script']), [ref]$null, [ref]$null)
            foreach ($state in $definition['States']) {
                if (-not $state['MachineAction']) { continue }
                $function = $companion.Find({
                        param($node)
                        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $state['MachineAction']
                    }, $true)
                if (-not $function) {
                    "$($definition['Name']): $($state['MachineAction']) is not defined"
                    continue
                }
                foreach ($call in $function.Body.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true)) {
                    if ([string]$call.GetCommandName() -match $interactive) {
                        "$($definition['Name']): $($state['MachineAction']) calls $($call.GetCommandName())"
                    }
                }
            }
        }
        @($problems) | Should -BeNullOrEmpty
    }

    It 'never run a desktop launcher silently from an Explorer verb' {
        # Explorer starts verbs with the filtered token, and a silent run won't ask for administrator permission.
        $problems = foreach ($file in Get-ChildItem -LiteralPath $script:ShippedTogglesRoot -Recurse -Filter '*.psd1') {
            $definition = Import-PowerShellDataFile -LiteralPath $file.FullName
            foreach ($state in $definition['States']) {
                foreach ($entry in $state['Registry']) {
                    $data = [string]$entry['Data']
                    if ($data -match '(?i)\\VantaDesktop\\.+\.cmd' -and $data -match '(?i)\s/silent\b') {
                        "$($definition['Name']): $($entry['Path'])"
                    }
                }
            }
        }
        @($problems) | Should -BeNullOrEmpty
    }

    It 'reset exactly the closed service-defaults set to one (default) state each, in allowlist order' {
        InModuleScope Vanta.Toggles {
            $applied = [Collections.Generic.List[string]]::new()
            Mock Assert-VantaPrivilege
            Mock Get-VantaContext { [pscustomobject]@{ VantaModulesPath = $ModulesPath } }
            # Whether a default applies on this PC is covered in Vanta.ServiceDefaultsReset.Tests.ps1.
            Mock Test-VantaToggleReplayApplicable { $true }
            Mock Invoke-VantaToggleInProcess { $applied.Add("$($Definition['Name']):${StateName}:$([bool]$ResetServices)") }

            # The real guard compares the name-sorted files with the allowlist position by
            # position, so an allowlist out of file-name order fails the reset on every PC.
            Invoke-VantaServiceDefaultsReset

            $expected = @($script:VantaServiceDefaultResetStates.Keys | ForEach-Object {
                    "${_}:$($script:VantaServiceDefaultResetStates[$_]):True"
                })
            @($applied) | Should -Be $expected
        } -Parameters @{ ModulesPath = (Split-Path -Parent $script:ShippedTogglesRoot) }
    }
}

Describe 'Set-VantaToggleState / Get-VantaToggleState' {
    It 'writes state as REG_DWORD and never persists the legacy launcher path' {
        Remove-Item -LiteralPath (Join-Path $StateRoot 'KindCheck') -Recurse -Force -ErrorAction SilentlyContinue
        Get-VantaToggleState -Name 'KindCheck' -StateRoot $StateRoot | Should -BeNullOrEmpty

        Set-VantaToggleState -Name 'KindCheck' -State 2 -LauncherPath 'C:\Fake\Kind.cmd' -StateRoot $StateRoot

        $key = Get-Item -LiteralPath (Join-Path $StateRoot 'KindCheck')
        $key.GetValueKind('state') | Should -Be ([Microsoft.Win32.RegistryValueKind]::DWord)
        @($key.GetValueNames()) | Should -Not -Contain 'path'
        $recorded = Get-VantaToggleState -Name 'KindCheck' -StateRoot $StateRoot
        $recorded.State | Should -Be 2
        $recorded.PSObject.Properties.Name | Should -Not -Contain 'Path'
    }

    It 'overwrites state and scrubs a legacy raw path from an existing record' {
        $keyPath = Join-Path $StateRoot 'TestSetting'
        New-Item -Path $keyPath -Force | Out-Null
        New-ItemProperty -LiteralPath $keyPath -Name 'path' -Value 'C:\Attacker\payload.ps1' -PropertyType String -Force | Out-Null
        New-ItemProperty -LiteralPath $keyPath -Name 'days' -Value 14 -PropertyType DWord -Force | Out-Null

        Set-VantaToggleState -Name 'TestSetting' -State 0 -LauncherPath 'C:\Fake\Other.cmd' -StateRoot $StateRoot

        $recorded = Get-VantaToggleState -Name 'TestSetting' -StateRoot $StateRoot
        $recorded.State | Should -Be 0
        @(Get-Item -LiteralPath $keyPath).GetValueNames() | Should -Not -Contain 'path'
        (Get-ItemProperty -LiteralPath $keyPath -Name 'days').days | Should -Be 14
    }
}

Describe 'Initialize-VantaToggleStateStore' {
    It 'preserves the legacy verbose-message choice for <Launcher>' -ForEach @(
        @{ Launcher = 'Disable Verbose Messages (default).cmd'; State = 1; Expected = 0 }
        @{ Launcher = 'disable verbose messages (default).cmd'; State = 1; Expected = 0 }
        @{ Launcher = 'Disable Verbose Messages (default).cmd'; State = 0; Expected = 0 }
        @{ Launcher = 'Enable Verbose Messages.cmd'; State = 1; Expected = 1 }
        @{ Launcher = 'unknown.cmd'; State = 1; Expected = 1 }
    ) {
        $keyPath = Join-Path $StateRoot 'VerboseMessages'
        New-Item -Path $keyPath -Force | Out-Null
        New-ItemProperty -LiteralPath $keyPath -Name state -Value $State -PropertyType DWord -Force | Out-Null
        New-ItemProperty -LiteralPath $keyPath -Name path -Value ("C:\Windows\VantaDesktop\$Launcher") -PropertyType String -Force | Out-Null

        Initialize-VantaToggleStateStore -StateRoot $StateRoot

        (Get-VantaToggleState -Name VerboseMessages -StateRoot $StateRoot).State | Should -Be $Expected
        @((Get-Item -LiteralPath $keyPath).GetValueNames()) | Should -Not -Contain 'path'
        Initialize-VantaToggleStateStore -StateRoot $StateRoot
        (Get-VantaToggleState -Name VerboseMessages -StateRoot $StateRoot).State | Should -Be $Expected
        Remove-Item -LiteralPath $keyPath -Recurse -Force
    }

    It 'preserves the actual legacy context-menu choice for <Launcher>' -ForEach @(
        @{ Launcher = 'Old Context Menu (default).cmd'; Expected = 1 }
        @{ Launcher = 'New Context Menu.cmd'; Expected = 0 }
        @{ Launcher = 'unknown.cmd'; Expected = 0 }
    ) {
        # No observable user, so the classic-menu fallback applies whatever this PC's own
        # install state and menu are.
        Mock Get-VantaLegacyToggleObservedState -ModuleName Vanta.Toggles { $null }
        $keyPath = Join-Path $StateRoot 'OldContextMenu'
        New-Item -Path $keyPath -Force | Out-Null
        New-ItemProperty -LiteralPath $keyPath -Name state -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -LiteralPath $keyPath -Name path -Value ("C:\Windows\VantaDesktop\$Launcher") -PropertyType String -Force | Out-Null

        Initialize-VantaToggleStateStore -StateRoot $StateRoot

        (Get-VantaToggleState -Name OldContextMenu -StateRoot $StateRoot).State | Should -Be $Expected
        @((Get-Item -LiteralPath $keyPath).GetValueNames()) | Should -Not -Contain 'path'
        Initialize-VantaToggleStateStore -StateRoot $StateRoot
        (Get-VantaToggleState -Name OldContextMenu -StateRoot $StateRoot).State | Should -Be $Expected
        Remove-Item -LiteralPath $keyPath -Recurse -Force
    }

    It 'removes legacy executable paths while preserving non-replay product metadata' {
        $keyPath = Join-Path $StateRoot 'PauseUpdates'
        New-Item -Path $keyPath -Force | Out-Null
        New-ItemProperty -LiteralPath $keyPath -Name 'state' -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -LiteralPath $keyPath -Name 'path' -Value 'C:\Attacker\payload.ps1' -PropertyType String -Force | Out-Null
        New-ItemProperty -LiteralPath $keyPath -Name 'days' -Value 356000 -PropertyType DWord -Force | Out-Null

        Initialize-VantaToggleStateStore -StateRoot $StateRoot

        $key = Get-Item -LiteralPath $keyPath
        @($key.GetValueNames()) | Should -Not -Contain 'path'
        (Get-ItemProperty -LiteralPath $keyPath -Name 'days').days | Should -Be 356000
    }

}

Describe 'Vanta toggle production state ACL' {
    It 'uses a protected DACL with writes limited to privileged Windows principals' {
        InModuleScope Vanta.Toggles {
            $acl = New-VantaToggleStateAcl
            $acl.AreAccessRulesProtected | Should -BeTrue
            $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be 'S-1-5-32-544'

            $rules = @($acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]))
            $fullControlSids = @($rules | Where-Object {
                    ($_.RegistryRights -band [System.Security.AccessControl.RegistryRights]::FullControl) -eq
                    [System.Security.AccessControl.RegistryRights]::FullControl
                } | ForEach-Object { $_.IdentityReference.Value })

            $fullControlSids | Should -Contain 'S-1-5-18'
            $fullControlSids | Should -Contain 'S-1-5-32-544'
            $fullControlSids | Should -Contain 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
            $fullControlSids | Should -Not -Contain 'S-1-5-32-545'

            $usersRule = @($rules | Where-Object { $_.IdentityReference.Value -eq 'S-1-5-32-545' })
            $usersRule.Count | Should -Be 1
            $usersRule[0].RegistryRights | Should -Be ([System.Security.AccessControl.RegistryRights]::ReadKey)
        }
    }

    It 'protects the production root before migrating its existing children' {
        InModuleScope Vanta.Toggles {
            $productionRoot = 'HKLM:\SOFTWARE\Vanta\Services'
            $childPath = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Vanta\Services\Example'
            $script:aclTargets = @()

            Mock Test-Path { $true }
            Mock Get-ChildItem { @([pscustomobject]@{ PSPath = $childPath }) }
            Mock Set-Acl { $script:aclTargets += $LiteralPath }

            Protect-VantaToggleStateRoot -StateRoot $productionRoot -IncludeChildren

            $script:aclTargets | Should -Be @($productionRoot, $childPath)
        }
    }
}

Describe 'Replay of recorded states' {
    It 'replays disabling verbose messages from the incorrectly enabled legacy record' {
        $keyPath = Join-Path $StateRoot 'VerboseMessages'
        New-Item -Path $keyPath -Force | Out-Null
        New-ItemProperty -LiteralPath $keyPath -Name state -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -LiteralPath $keyPath -Name path -Value 'C:\Windows\VantaDesktop\Disable Verbose Messages (default).cmd' -PropertyType String -Force | Out-Null

        Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ShippedTogglesRoot

        (Get-VantaToggleState -Name VerboseMessages -StateRoot $StateRoot).State | Should -Be 0
        @((Get-Item -LiteralPath $keyPath).GetValueNames()) | Should -Not -Contain 'path'
        Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Re-applying toggle 'VerboseMessages' machine state 'Disable'."
        }
        Should -Invoke Invoke-VantaRegistryEntries -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            @($Entries).Count -eq 1 -and $Entries[0].Name -eq 'verbosestatus' -and $Entries[0].Operation -eq 'Delete'
        }
    }

    It 'migrates the legacy classic menu before resolving the upgrade replay state' {
        Mock Get-VantaLegacyToggleObservedState -ModuleName Vanta.Toggles { $null }
        $keyPath = Join-Path $StateRoot 'OldContextMenu'
        New-Item -Path $keyPath -Force | Out-Null
        New-ItemProperty -LiteralPath $keyPath -Name state -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -LiteralPath $keyPath -Name path -Value 'C:\Windows\VantaDesktop\Old Context Menu (default).cmd' -PropertyType String -Force | Out-Null

        Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ShippedTogglesRoot

        (Get-VantaToggleState -Name OldContextMenu -StateRoot $StateRoot).State | Should -Be 1
        @((Get-Item -LiteralPath $keyPath).GetValueNames()) | Should -Not -Contain 'path'
        Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Toggle 'OldContextMenu' state 'Enable' has no machine work to re-apply."
        }
        Remove-Item -LiteralPath $keyPath -Recurse -Force
    }

    BeforeAll {
        $script:ReplayRoot = Join-Path $TestDrive 'ReplayToggles'
        $script:ReplayWork = Join-Path $TestDrive 'ReplayWork'
        New-Item -Path $script:ReplayWork -ItemType Directory -Force | Out-Null

        $cpuIdleRoot = Join-Path $script:ShippedTogglesRoot 'General'
        New-TestToggle -Root $script:ReplayRoot -Name 'CpuIdle' `
            -Definition (Get-Content -LiteralPath (Join-Path $cpuIdleRoot 'CpuIdle.psd1') -Raw) `
            -Companion (Get-Content -LiteralPath (Join-Path $cpuIdleRoot 'CpuIdle.ps1') -Raw)
        New-TestToggle -Root $script:ReplayRoot -Name 'Copilot' `
            -Definition (Get-Content -LiteralPath (Join-Path $cpuIdleRoot 'Copilot.psd1') -Raw) `
            -Companion (Get-Content -LiteralPath (Join-Path $cpuIdleRoot 'Copilot.ps1') -Raw)

        New-TestToggle -Root $script:ReplayRoot -Name 'SplitToggle' -Definition @'
@{
    Name      = 'SplitToggle'
    Elevation = 'Admin'
    Script    = 'SplitToggle.ps1'
    States    = @(
        @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; MachineAction = 'Invoke-VantaTestMachine'; UserAction = 'Invoke-VantaTestUser' }
        @{ Name = 'Off'; StateValue = 0; Launcher = 'A\Off.cmd'; MachineAction = 'Invoke-VantaTestMachine'; UserAction = 'Invoke-VantaTestUser' }
    )
}
'@ -Companion $script:MarkerCompanion
        New-TestToggle -Root $script:ReplayRoot -Name 'UserOnlyToggle' -Definition @'
@{
    Name      = 'UserOnlyToggle'
    Elevation = 'Admin'
    Script    = 'UserOnlyToggle.ps1'
    States    = @( @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; UserAction = 'Invoke-VantaTestUser' } )
}
'@ -Companion $script:MarkerCompanion
        New-TestToggle -Root $script:ReplayRoot -Name 'ApplicableToggle' -Definition @'
@{
    Name      = 'ApplicableToggle'
    Elevation = 'Admin'
    Script    = 'ApplicableToggle.ps1'
    States    = @( @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; MachineAction = 'Invoke-VantaTestMachine'; ReplayApplicable = 'Test-VantaTestReplayApplicable' } )
}
'@ -Companion $script:MarkerCompanion
        New-TestToggle -Root $script:ReplayRoot -Name 'NoRecordToggle' -Definition @'
@{
    Name          = 'NoRecordToggle'
    Elevation     = 'Admin'
    NoStateRecord = $true
    Script        = 'NoRecordToggle.ps1'
    States        = @( @{ Name = 'Run'; Launcher = 'A\Run.cmd'; MachineAction = 'Invoke-VantaTestMachine' } )
}
'@ -Companion $script:MarkerCompanion
        New-TestToggle -Root $script:ReplayRoot -Name 'FailingToggle' -Definition @'
@{
    Name      = 'FailingToggle'
    Elevation = 'Admin'
    Script    = 'FailingToggle.ps1'
    States    = @( @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; MachineAction = 'Invoke-VantaTestFailure' } )
}
'@ -Companion $script:MarkerCompanion
    }

    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Toggles
        Mock Assert-VantaPrivilege -ModuleName Vanta.Toggles
        Mock Invoke-VantaRegistryEntries -ModuleName Vanta.Toggles
        Remove-Item -Path $StateRoot -Recurse -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $script:ReplayWork -Filter '*.txt' | Remove-Item -Force
        $env:VantaToggleTestDir = $script:ReplayWork
        $env:VantaToggleTestReplayApplicable = '1'
    }

    AfterAll {
        Remove-Item Env:\VantaToggleTestDir -ErrorAction SilentlyContinue
        Remove-Item Env:\VantaToggleTestReplayApplicable -ErrorAction SilentlyContinue
    }

    It 'replays only the machine part of a recorded state, silently, and keeps the record' {
        Set-VantaToggleState -Name 'SplitToggle' -State 0 -StateRoot $StateRoot
        $recordPath = Join-Path $StateRoot 'SplitToggle'
        New-ItemProperty -LiteralPath $recordPath -Name 'path' -Value 'C:\Attacker\payload.ps1' -PropertyType String -Force | Out-Null

        Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot

        Get-Content (Join-Path $script:ReplayWork 'machine.txt') | Should -Be 'SplitToggle:Off:0:silent=True'
        Join-Path $script:ReplayWork 'user.txt' | Should -Not -Exist
        @((Get-Item -LiteralPath $recordPath).GetValueNames()) | Should -Not -Contain 'path'
        (Get-VantaToggleState -Name 'SplitToggle' -StateRoot $StateRoot).State | Should -Be 0
    }

    It 'replays a record named in other letter case as its toggle''s choice, not as a stale one' {
        Set-VantaToggleState -Name 'splittoggle' -State 1 -StateRoot $StateRoot

        Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot

        Get-Content (Join-Path $script:ReplayWork 'machine.txt') | Should -Be 'SplitToggle:On:1:silent=True'
        (Get-VantaToggleState -Name 'SplitToggle' -StateRoot $StateRoot).State | Should -Be 1
    }

    It 'skips an old CPU idle disable choice on SMT and continues replaying other choices' {
        Mock Get-CimInstance -ModuleName Vanta.Toggles {
            @(
                [pscustomobject]@{ NumberOfCores = 4; NumberOfLogicalProcessors = 4 }
                [pscustomobject]@{ NumberOfCores = 8; NumberOfLogicalProcessors = 16 }
            )
        } -ParameterFilter { $ClassName -eq 'Win32_Processor' }
        Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles
        Set-VantaToggleState -Name CpuIdle -State 0 -StateRoot $StateRoot
        Set-VantaToggleState -Name SplitToggle -State 1 -StateRoot $StateRoot

        Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot

        (Get-VantaToggleState -Name CpuIdle -StateRoot $StateRoot).State | Should -BeNullOrEmpty
        Get-Content (Join-Path $script:ReplayWork 'machine.txt') | Should -Be 'SplitToggle:On:1:silent=True'
        Should -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles -Times 0 -Exactly
    }

    It 'drops a Copilot enable choice that Vanta 0.5.0 recorded on a PC without Edge' {
        Mock Test-Path -ModuleName Vanta.Toggles { $false } -ParameterFilter { $LiteralPath -like '*\msedge.exe' }
        Set-VantaToggleState -Name Copilot -State 1 -StateRoot $StateRoot
        Set-VantaToggleState -Name SplitToggle -State 1 -StateRoot $StateRoot

        { Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot } | Should -Not -Throw

        (Get-VantaToggleState -Name Copilot -StateRoot $StateRoot).State | Should -BeNullOrEmpty
        Get-Content (Join-Path $script:ReplayWork 'machine.txt') | Should -Be 'SplitToggle:On:1:silent=True'
    }

    It 'keeps and replays an old CPU idle disable choice when SMT is absent' {
        Mock Get-CimInstance -ModuleName Vanta.Toggles {
            [pscustomobject]@{ NumberOfCores = 8; NumberOfLogicalProcessors = 8 }
        } -ParameterFilter { $ClassName -eq 'Win32_Processor' }
        Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles
        Set-VantaToggleState -Name CpuIdle -State 0 -StateRoot $StateRoot

        Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot

        (Get-VantaToggleState -Name CpuIdle -StateRoot $StateRoot).State | Should -Be 0
        Should -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles -Times 1 -Exactly `
            -ParameterFilter { $ArgumentList[0] -eq '/setacvalueindex' -and $ArgumentList[4] -eq '1' }
        Should -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles -Times 1 -Exactly `
            -ParameterFilter { $ArgumentList[0] -eq '/setactive' }
    }

    It 'always replays enabling CPU idle without requiring the processor query' {
        Mock Get-CimInstance -ModuleName Vanta.Toggles { throw 'Processor query should not be needed.' } `
            -ParameterFilter { $ClassName -eq 'Win32_Processor' }
        Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles
        Set-VantaToggleState -Name CpuIdle -State 1 -StateRoot $StateRoot

        Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot

        (Get-VantaToggleState -Name CpuIdle -StateRoot $StateRoot).State | Should -Be 1
        Should -Invoke Get-CimInstance -ModuleName Vanta.Toggles -Times 0 -Exactly
        Should -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles -Times 1 -Exactly `
            -ParameterFilter { $ArgumentList[0] -eq '/setacvalueindex' -and $ArgumentList[4] -eq '0' }
    }

    It 'still rejects a manual CPU idle disable request on SMT without recording it' {
        Mock Get-CimInstance -ModuleName Vanta.Toggles {
            [pscustomobject]@{ NumberOfCores = 8; NumberOfLogicalProcessors = 16 }
        } -ParameterFilter { $ClassName -eq 'Win32_Processor' }
        Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles
        Set-VantaToggleState -Name CpuIdle -State 1 -StateRoot $StateRoot
        $definition = Get-VantaToggleDefinition -Name CpuIdle -TogglesRoot $script:ReplayRoot

        { InModuleScope Vanta.Toggles -Parameters @{ Definition = $definition; Root = $StateRoot } {
                param($Definition, $Root)
                Invoke-VantaToggleInProcess -Definition $Definition -StateName Disable -Scope Machine `
                    -Silent -NoExplorerRestart -SkipPreamble -StateRoot $Root
            } } |
            Should -Throw '*Hyper-Threading or SMT*Nothing was changed*'

        (Get-VantaToggleState -Name CpuIdle -StateRoot $StateRoot).State | Should -Be 1
        Should -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles -Times 0 -Exactly
    }

    It 'preserves the old CPU idle choice if processor detection fails' {
        Mock Get-CimInstance -ModuleName Vanta.Toggles { throw 'CIM unavailable' } `
            -ParameterFilter { $ClassName -eq 'Win32_Processor' }
        Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles
        Set-VantaToggleState -Name CpuIdle -State 0 -StateRoot $StateRoot

        { Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot } |
            Should -Throw '*failed for 1 toggle(s)*CpuIdle*CIM unavailable*'

        (Get-VantaToggleState -Name CpuIdle -StateRoot $StateRoot).State | Should -Be 0
        Should -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles -Times 0 -Exactly
    }

    It 'leaves a record that has only user work for first sign-in replay' {
        Set-VantaToggleState -Name 'UserOnlyToggle' -State 1 -StateRoot $StateRoot

        Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot

        Join-Path $script:ReplayWork 'user.txt' | Should -Not -Exist
        (Get-VantaToggleState -Name 'UserOnlyToggle' -StateRoot $StateRoot).State | Should -Be 1
    }

    It 'removes a recorded state whose ReplayApplicable check fails without running it' {
        Set-VantaToggleState -Name 'ApplicableToggle' -State 1 -StateRoot $StateRoot
        $env:VantaToggleTestReplayApplicable = ''

        Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot

        Join-Path $script:ReplayWork 'machine.txt' | Should -Not -Exist
        Test-Path -LiteralPath (Join-Path $StateRoot 'ApplicableToggle') | Should -BeFalse
    }

    It 'scrubs stale records: no definition, NoStateRecord, unknown value, wrong value kind' {
        Set-VantaToggleState -Name 'Vanished' -State 1 -StateRoot $StateRoot
        Set-VantaToggleState -Name 'NoRecordToggle' -State 1 -StateRoot $StateRoot
        Set-VantaToggleState -Name 'SplitToggle' -State 9 -StateRoot $StateRoot
        $wrongKind = Join-Path $StateRoot 'ApplicableToggle'
        New-Item -Path $wrongKind -Force | Out-Null
        New-ItemProperty -LiteralPath $wrongKind -Name 'state' -Value '1' -PropertyType String -Force | Out-Null

        Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot

        foreach ($name in 'Vanished', 'NoRecordToggle', 'SplitToggle', 'ApplicableToggle') {
            Test-Path -LiteralPath (Join-Path $StateRoot $name) | Should -BeFalse -Because $name
        }
        Join-Path $script:ReplayWork 'machine.txt' | Should -Not -Exist
        # Records an older Vanta left are expected after an update; clearing them is no warning.
        Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times 0 -Exactly -ParameterFilter { $Level -eq 'Warning' }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -ParameterFilter { $Message -like "Toggle 'SplitToggle' state '9' does not map*Cleared its old record; the PC itself is unchanged." }
    }

    It 'preserves metadata-only keys without warning or replay in either scope' {
        Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $false }
        Mock Test-VantaSystem -ModuleName Vanta.Toggles { $false }
        $metadataPath = Join-Path $StateRoot 'PowerSaving'
        $previousScheme = '381b4222-f694-41f0-9685-ff5bb260df2e'
        New-Item -Path $metadataPath -Force | Out-Null
        New-ItemProperty -LiteralPath $metadataPath -Name PreviousPowerSchemeGuid `
            -Value $previousScheme -PropertyType String -Force | Out-Null

        Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot
        Invoke-VantaToggleUserReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot

        (Get-ItemProperty -LiteralPath $metadataPath).PreviousPowerSchemeGuid | Should -Be $previousScheme
        (Get-VantaToggleState -Name PowerSaving -StateRoot $StateRoot).State | Should -BeNullOrEmpty
        Join-Path $script:ReplayWork 'machine.txt' | Should -Not -Exist
        Join-Path $script:ReplayWork 'user.txt' | Should -Not -Exist
        Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times 0 -Exactly -ParameterFilter { $Level -eq 'Warning' }
    }

    It 'removes stale replay values without deleting unrelated metadata or child keys' {
        Set-VantaToggleState -Name 'SplitToggle' -State 9 -StateRoot $StateRoot
        $recordPath = Join-Path $StateRoot 'SplitToggle'
        New-ItemProperty -LiteralPath $recordPath -Name PreviousPowerSchemeGuid `
            -Value '381b4222-f694-41f0-9685-ff5bb260df2e' -PropertyType String -Force | Out-Null
        New-ItemProperty -LiteralPath $recordPath -Name path -Value 'C:\Old\Launcher.cmd' -PropertyType String -Force | Out-Null
        New-Item -Path (Join-Path $recordPath 'Metadata') -Force | Out-Null

        Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot

        $key = Get-Item -LiteralPath $recordPath
        @($key.GetValueNames()) | Should -Be @('PreviousPowerSchemeGuid')
        $key.GetValue('PreviousPowerSchemeGuid') | Should -Be '381b4222-f694-41f0-9685-ff5bb260df2e'
        Test-Path -LiteralPath (Join-Path $recordPath 'Metadata') | Should -BeTrue
        Join-Path $script:ReplayWork 'machine.txt' | Should -Not -Exist
    }

    It 'continues past a failing replay, preserves its record, then throws one aggregate' {
        Set-VantaToggleState -Name 'FailingToggle' -State 1 -StateRoot $StateRoot
        Set-VantaToggleState -Name 'SplitToggle' -State 1 -StateRoot $StateRoot

        { Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot } |
            Should -Throw '*failed for 1 toggle(s)*FailingToggle*deliberate failure*'

        (Get-VantaToggleState -Name 'FailingToggle' -StateRoot $StateRoot).State | Should -Be 1
        Get-Content (Join-Path $script:ReplayWork 'machine.txt') | Should -Be 'SplitToggle:On:1:silent=True'
    }

    It 'asserts strict TrustedInstaller before touching the replay tree' {
        Mock Assert-VantaPrivilege -ModuleName Vanta.Toggles { throw '[privilege] TrustedInstaller required' }

        { Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot } |
            Should -Throw '*TrustedInstaller required*'
    }

    It 'replays only the user part of recorded states for the non-elevated account' {
        Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $false }
        Mock Test-VantaSystem -ModuleName Vanta.Toggles { $false }
        Set-VantaToggleState -Name 'SplitToggle' -State 1 -StateRoot $StateRoot
        Set-VantaToggleState -Name 'ApplicableToggle' -State 1 -StateRoot $StateRoot

        Invoke-VantaToggleUserReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot

        Get-Content (Join-Path $script:ReplayWork 'user.txt') | Should -Be 'SplitToggle:On'
        Join-Path $script:ReplayWork 'machine.txt' | Should -Not -Exist
    }

    It 'refuses per-user replay from an elevated process' {
        Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $true }

        { Invoke-VantaToggleUserReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot } |
            Should -Throw '*non-elevated*'
    }

    It 'replays the power plan before the per-plan choices it would otherwise reset' {
        $script:replayed = [Collections.Generic.List[string]]::new()
        Mock Invoke-VantaToggleFunction -ModuleName Vanta.Toggles {
            if ($Label -eq 'machine action') { $script:replayed.Add([string]$Toggle.Name) }
            $true
        }
        foreach ($name in 'CpuIdle', 'PowerSaving', 'Sleep') {
            Set-VantaToggleState -Name $name -State 0 -StateRoot $StateRoot
        }

        Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ShippedTogglesRoot

        $script:replayed | Should -Be @('PowerSaving', 'CpuIdle', 'Sleep')
    }

    It 'leaves out the toggles -Exclude names, keeping their records for the state document' {
        Mock Sync-VantaToggleStateDocument -ModuleName Vanta.Toggles
        Set-VantaToggleState -Name 'FailingToggle' -State 1 -StateRoot $StateRoot
        Set-VantaToggleState -Name 'SplitToggle' -State 1 -StateRoot $StateRoot

        { Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot -Exclude 'failingtoggle' } |
            Should -Not -Throw

        (Get-VantaToggleState -Name 'FailingToggle' -StateRoot $StateRoot).State | Should -Be 1
        Get-Content (Join-Path $script:ReplayWork 'machine.txt') | Should -Be 'SplitToggle:On:1:silent=True'
        Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Message -eq "Toggle 'FailingToggle' was applied by this installation's choices, so it isn't replayed."
        }
        Should -Invoke Sync-VantaToggleStateDocument -ModuleName Vanta.Toggles -Times 1 -Exactly
    }

    It 'doesn''t claim an excluded key that holds only metadata was applied' {
        $metadataPath = Join-Path $StateRoot 'PowerSaving'
        New-Item -Path $metadataPath -Force | Out-Null
        New-ItemProperty -LiteralPath $metadataPath -Name PreviousPowerSchemeGuid `
            -Value '381b4222-f694-41f0-9685-ff5bb260df2e' -PropertyType String -Force | Out-Null

        Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ReplayRoot -Exclude 'PowerSaving'

        (Get-ItemProperty -LiteralPath $metadataPath).PreviousPowerSchemeGuid | Should -Be '381b4222-f694-41f0-9685-ff5bb260df2e'
        Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times 0 -Exactly -ParameterFilter {
            $Message -like '*was applied by this installation*'
        }
    }

    It 'replays e9d7a85f''s records when keeping choices, and leaves out only what the Choices step set when choosing again: <Case>' -ForEach @(
        # All processor protections on and automatic updates on, while the options said
        # to turn both off.
        @{ Case = 'keeping them'; Mitigations = 2; AutomaticUpdates = 1; Exclude = @(); Replayed = @('CpuIdle=Enable', 'Mitigations=Enable'); AutoUpdatesReplays = 1 }
        # The Choices step set both to Disable and recorded that it did.
        @{ Case = 'choosing again'; Mitigations = 0; AutomaticUpdates = 0; Exclude = @('Mitigations', 'AutomaticUpdates'); Replayed = @('CpuIdle=Enable'); AutoUpdatesReplays = 0 }
        # Windows default chosen over all on matches, so the Choices step left it to the
        # replay, which keeps every protection on.
        @{ Case = 'choosing again with processor protections left all on'; Mitigations = 2; AutomaticUpdates = 0; Exclude = @('AutomaticUpdates'); Replayed = @('CpuIdle=Enable', 'Mitigations=Enable'); AutoUpdatesReplays = 0 }
    ) {
        $script:replayed = [Collections.Generic.List[string]]::new()
        Mock Invoke-VantaToggleFunction -ModuleName Vanta.Toggles {
            if ($Label -eq 'machine action') { $script:replayed.Add("$($Toggle.Name)=$($Toggle.State)") }
            $true
        }
        # CpuIdle is no install choice and replays either way.
        Set-VantaToggleState -Name Mitigations -State $Mitigations -StateRoot $StateRoot
        Set-VantaToggleState -Name AutomaticUpdates -State $AutomaticUpdates -StateRoot $StateRoot
        Set-VantaToggleState -Name CpuIdle -State 1 -StateRoot $StateRoot

        Invoke-VantaToggleReapply -StateRoot $StateRoot -TogglesRoot $script:ShippedTogglesRoot -Exclude $Exclude

        @($script:replayed | Sort-Object) | Should -Be $Replayed
        Should -Invoke Invoke-VantaRegistryEntries -ModuleName Vanta.Toggles -Times $AutoUpdatesReplays -Exactly -ParameterFilter {
            @($Entries | Where-Object { $_.Name -eq 'AUOptions' }).Count -gt 0
        }
        (Get-VantaToggleState -Name Mitigations -StateRoot $StateRoot).State | Should -Be $Mitigations
        (Get-VantaToggleState -Name AutomaticUpdates -StateRoot $StateRoot).State | Should -Be $AutomaticUpdates
    }
}

Describe 'Invoke-VantaToggle' {
    BeforeAll {
        $script:TogglesRoot = Join-Path $TestDrive 'EngineToggles'
        $script:WorkDir = Join-Path $TestDrive 'EngineWork'
        New-Item -Path $script:WorkDir -ItemType Directory -Force | Out-Null
        function script:Get-Marker {
            param([string]$Name)
            $path = Join-Path $script:WorkDir "$Name.txt"
            if (Test-Path -LiteralPath $path) { return [IO.File]::ReadAllText($path) }
            return $null
        }

        New-TestToggle -Root $script:TogglesRoot -Name 'LocalToggle' -Definition @'
@{
    Name          = 'LocalToggle'
    Elevation     = 'None'
    NoStateRecord = $true
    Script        = 'LocalToggle.ps1'
    States        = @(
        @{ Name = 'On'; Launcher = 'A\On.cmd'; Reboot = 'None'; ContextAction = 'Invoke-VantaTestContext'; Action = 'Invoke-VantaTestLocal' }
        @{ Name = 'Failing'; Launcher = 'A\Failing.cmd'; Reboot = 'None'; Action = 'Invoke-VantaTestFailure' }
        @{ Name = 'PowerShellError'; Launcher = 'A\PowerShellError.cmd'; Reboot = 'None'; Action = 'Invoke-VantaTestPowerShellError' }
        @{ Name = 'IgnoredError'; Launcher = 'A\IgnoredError.cmd'; Reboot = 'None'; Action = 'Invoke-VantaTestIgnoredError' }
        @{ Name = 'ContextFailure'; Launcher = 'A\ContextFailure.cmd'; Reboot = 'None'; ContextAction = 'Invoke-VantaTestContextFailure'; Action = 'Invoke-VantaTestLocal' }
    )
}
'@ -Companion $script:MarkerCompanion
        New-TestToggle -Root $script:TogglesRoot -Name 'MachineToggle' -Definition @'
@{
    Name      = 'MachineToggle'
    Elevation = 'Admin'
    Script    = 'MachineToggle.ps1'
    States    = @(
        @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; Reboot = 'None'; Registry = @( @{ Path = 'HKLM:\SOFTWARE\VantaRewriteTest'; Name = 'on'; Type = 'DWord'; Data = 1 } ); Services = @( @{ Name = 'FakeSvc'; StartupType = 4 } ); MachineAction = 'Invoke-VantaTestMachine' }
        @{ Name = 'Failing'; StateValue = 2; Launcher = 'A\Failing.cmd'; Reboot = 'None'; MachineAction = 'Invoke-VantaTestFailure' }
    )
}
'@ -Companion $script:MarkerCompanion
        New-TestToggle -Root $script:TogglesRoot -Name 'SplitToggle' -Definition @'
@{
    Name      = 'SplitToggle'
    Elevation = 'Admin'
    Script    = 'SplitToggle.ps1'
    States    = @(
        @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; Reboot = 'None'; Registry = @( @{ Path = 'HKLM:\SOFTWARE\VantaRewriteTest'; Name = 'm'; Type = 'DWord'; Data = 1 }; @{ Path = 'HKCU:\Software\VantaRewriteTest\ToggleUser'; Name = 'u'; Type = 'DWord'; Data = 1 } ); MachineAction = 'Invoke-VantaTestMachine'; UserAction = 'Invoke-VantaTestUser' }
    )
}
'@ -Companion $script:MarkerCompanion
        New-TestToggle -Root $script:TogglesRoot -Name 'SplitBrokerToggle' -Definition @'
@{
    Name          = 'SplitBrokerToggle'
    Elevation     = 'TrustedInstaller'
    NoStateRecord = $true
    Script        = 'SplitBrokerToggle.ps1'
    States        = @(
        @{ Name = 'On'; Launcher = 'A\On.cmd'; Reboot = 'None'; MachineAction = 'Invoke-VantaTestMachine'; UserAction = 'Invoke-VantaTestUser' }
    )
}
'@ -Companion $script:MarkerCompanion
        New-TestToggle -Root $script:TogglesRoot -Name 'UserOnlyToggle' -Definition @'
@{
    Name      = 'UserOnlyToggle'
    Elevation = 'Admin'
    Script    = 'UserOnlyToggle.ps1'
    States    = @(
        @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; Reboot = 'None'; UserAction = 'Invoke-VantaTestUser' }
        @{ Name = 'Failing'; StateValue = 2; Launcher = 'A\Failing.cmd'; Reboot = 'None'; UserAction = 'Invoke-VantaTestFailure' }
    )
}
'@ -Companion $script:MarkerCompanion
        New-TestToggle -Root $script:TogglesRoot -Name 'BrokerToggle' -Definition @'
@{
    Name          = 'BrokerToggle'
    Elevation     = 'TrustedInstaller'
    Warning       = 'Confirm privileged action.'
    NoStateRecord = $true
    Script        = 'BrokerToggle.ps1'
    States        = @( @{ Name = 'Run'; Launcher = 'A\Run.cmd'; Reboot = 'Recommend'; MachineAction = 'Invoke-VantaTestMachine' } )
}
'@ -Companion $script:MarkerCompanion
        New-TestToggle -Root $script:TogglesRoot -Name 'ExplorerToggle' -Definition @'
@{
    Name      = 'ExplorerToggle'
    Elevation = 'Admin'
    Script    = 'ExplorerToggle.ps1'
    States    = @( @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; Reboot = 'RestartExplorer'; MachineAction = 'Invoke-VantaTestMachine' } )
}
'@ -Companion $script:MarkerCompanion
        New-TestToggle -Root $script:TogglesRoot -Name 'MenuToggle' -Definition @'
@{
    Name          = 'MenuToggle'
    Elevation     = 'Admin'
    Menu          = $true
    Launcher      = 'A\Menu.cmd'
    SilentDefault = 'Enable'
    Script        = 'MenuToggle.ps1'
    States        = @(
        @{ Name = 'Disable'; StateValue = 0; MenuLabel = 'Disable it'; Reboot = 'None'; MachineAction = 'Invoke-VantaTestMachine' }
        @{ Name = 'Enable'; StateValue = 1; MenuLabel = 'Enable it'; Reboot = 'None'; MachineAction = 'Invoke-VantaTestMachine' }
    )
}
'@ -Companion $script:MarkerCompanion
    }

    AfterAll {
        Remove-Item Env:\VantaToggleTestDir -ErrorAction SilentlyContinue
        Remove-Item Env:\VANTA_USER_CONTEXT -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $env:VantaToggleTestDir = $script:WorkDir
        Remove-Item Env:\VANTA_USER_CONTEXT -ErrorAction SilentlyContinue
        Get-ChildItem -Path $script:WorkDir -Filter '*.txt' | Remove-Item -Force
        Remove-Item -Path $StateRoot -Recurse -Force -ErrorAction SilentlyContinue
        Mock Write-VantaLog -ModuleName Vanta.Toggles
        Mock Write-VantaTitle -ModuleName Vanta.Toggles
        Mock Wait-VantaContinue -ModuleName Vanta.Toggles
        Mock Wait-VantaExit -ModuleName Vanta.Toggles
        Mock Write-VantaCompletion -ModuleName Vanta.Toggles
        Mock Invoke-VantaRegistryEntries -ModuleName Vanta.Toggles
        Mock Invoke-VantaServiceEntries -ModuleName Vanta.Toggles
        Mock Test-VantaTrustedInstaller -ModuleName Vanta.Toggles { $false }
        Mock Test-VantaSystem -ModuleName Vanta.Toggles { $false }
        Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $false }
        $script:launcher = Join-Path $script:WorkDir 'fake-launcher.cmd'
    }

    Context 'unelevated (Elevation None) toggles' {
        It 'runs ContextAction then Action in-process and records nothing' {
            Invoke-VantaToggle -Name 'LocalToggle' -State 'On' -Silent -LauncherPath $script:launcher `
                -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot

            Get-Marker 'context' | Should -Be 'On'
            Get-Marker 'local' | Should -Be 'LocalToggle:On:'
            Get-VantaToggleState -Name 'LocalToggle' -StateRoot $StateRoot | Should -BeNullOrEmpty
            Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -ParameterFilter { $Message -like "*LocalToggle*applied local state 'On'*" }
        }

        It 'stops after ContextAction with -JustContext' {
            Invoke-VantaToggle -Name 'LocalToggle' -State 'On' -Silent -JustContext -LauncherPath $script:launcher `
                -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot

            Get-Marker 'context' | Should -Be 'On'
            Get-Marker 'local' | Should -BeNullOrEmpty
        }

        It 'propagates failures and logs them' -TestCases @(
            @{ State = 'Failing'; Message = '*deliberate failure*'; Label = 'action' }
            @{ State = 'PowerShellError'; Message = '*ordinary action error*'; Label = 'action' }
            @{ State = 'ContextFailure'; Message = '*deliberate context failure*'; Label = 'context action' }
        ) {
            { Invoke-VantaToggle -Name 'LocalToggle' -State $State -Silent -LauncherPath $script:launcher `
                    -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot } | Should -Throw $Message

            Get-Marker 'local' | Should -BeNullOrEmpty
            Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
                $Level -eq 'Warning' -and $Message -like "*Toggle 'LocalToggle' $Label*failed*"
            }
        }

        It 'honors an explicit error override inside a companion function' {
            Invoke-VantaToggle -Name 'LocalToggle' -State 'IgnoredError' -Silent -LauncherPath $script:launcher `
                -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot

            Get-Marker 'ignored-error' | Should -Be 'continued'
        }

        It 'throws on an unknown state and on a missing state for a non-menu toggle' {
            { Invoke-VantaToggle -Name 'LocalToggle' -State 'Bogus' -Silent -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot } |
                Should -Throw "*Unknown state 'Bogus'*"
            { Invoke-VantaToggle -Name 'LocalToggle' -Silent -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot } |
                Should -Throw '*without a -State*'
        }
    }

    Context 'machine-only elevated toggles' {
        It 'reports a failed caller-side Explorer restart as partly done once the elevated child applied the change' {
            Mock Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles
            Mock Write-VantaStep -ModuleName Vanta.Toggles
            Mock Write-VantaPartial -ModuleName Vanta.Toggles { Set-VantaRunOutcome -Outcome Partial }
            Mock Invoke-VantaToggleCurrentSessionShellRefresh -ModuleName Vanta.Toggles {
                throw 'Current-session toggle shell refresh exited with code 14.'
            }

            { Invoke-VantaToggle -Name 'ExplorerToggle' -State 'On' -LauncherPath $script:launcher `
                    -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot } | Should -Not -Throw

            InModuleScope Vanta.Toggles { Get-VantaRunOutcome } | Should -BeExactly 'Partial'
            Should -Invoke Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
                @($ArgumentList) -contains '/noaction'
            }
            Should -Invoke Write-VantaPartial -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
                "$Text" -like "*File Explorer couldn't be restarted*"
            }
            Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
                $Level -ceq 'Warning' -and $Message -like '*exited with code 14*'
            }
            Should -Invoke Wait-VantaExit -ModuleName Vanta.Toggles -Times 1 -Exactly
        }

        It 'applies registry, services and the machine function in order, then records the state' {
            Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $true }
            $script:order = @()
            Mock Invoke-VantaRegistryEntries -ModuleName Vanta.Toggles { $script:order += "registry:${Scope}:$($Entries.Count)" }
            Mock Invoke-VantaServiceEntries -ModuleName Vanta.Toggles { $script:order += "services:$($Entries[0].Name)" }

            Invoke-VantaToggle -Name 'MachineToggle' -State 'On' -Silent -LauncherPath $script:launcher `
                -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot

            $script:order | Should -Be @('registry:Machine:1', 'services:FakeSvc')
            Get-Marker 'machine' | Should -Be 'MachineToggle:On:1:silent=True'
            (Get-VantaToggleState -Name 'MachineToggle' -StateRoot $StateRoot).State | Should -Be 1
        }

        It 'does not record a state whose machine function failed' {
            Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $true }

            { Invoke-VantaToggle -Name 'MachineToggle' -State 'Failing' -Silent -LauncherPath $script:launcher `
                    -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot } | Should -Throw '*deliberate failure*'

            Get-VantaToggleState -Name 'MachineToggle' -StateRoot $StateRoot | Should -BeNullOrEmpty
        }

        It 'refuses to prompt for elevation in silent mode' {
            { Invoke-VantaToggle -Name 'MachineToggle' -State 'On' -Silent -LauncherPath $script:launcher `
                    -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot } | Should -Throw '*requires Administrator rights*'
            Get-Marker 'machine' | Should -BeNullOrEmpty
        }

        It 'relaunches through UAC when interactive and unelevated, without running the work locally' {
            Mock Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles

            Invoke-VantaToggle -Name 'MachineToggle' -State 'On' -LauncherPath $script:launcher `
                -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot

            Should -Invoke Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'MachineToggle' -and ($ArgumentList -join ' ') -like '*-State On*' -and
                    ($ArgumentList -join ' ') -notlike '*-MachineOnly*' -and
                    @($ArgumentList | Where-Object { $_ -match '^[/-](silent|quiet)$' }).Count -eq 0
            }
            Get-Marker 'machine' | Should -BeNullOrEmpty
        }

        It 'preserves the elevated child exit code for the command-line entry point' {
            Mock Start-VantaToggleAdminRelaunch -ModuleName Vanta.Toggles { [pscustomobject]@{ ExitCode = 5 } }

            $failure = $null
            try {
                Invoke-VantaToggle -Name 'MachineToggle' -State 'On' -LauncherPath $script:launcher `
                    -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot
            }
            catch {
                $failure = $_.Exception
            }

            $failure | Should -Not -BeNullOrEmpty
            $failure.Data['Vanta.Toggle.AdminChildExitCode'] | Should -Be 5
        }

        It 'replays nothing at first sign-in because it has no per-user work' {
            $env:VANTA_USER_CONTEXT = '1'

            Invoke-VantaToggle -Name 'MachineToggle' -State 'On' -Silent -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot

            Get-Marker 'machine' | Should -BeNullOrEmpty
            Get-VantaToggleState -Name 'MachineToggle' -StateRoot $StateRoot | Should -BeNullOrEmpty
        }

        Context 'menu resolution' {
            BeforeEach { Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $true } }

            It 'prefers an explicit -State over the recorded state and SilentDefault in silent mode' {
                Set-VantaToggleState -Name 'MenuToggle' -State 1 -StateRoot $StateRoot
                Invoke-VantaToggle -Name 'MenuToggle' -State 'Disable' -Silent -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot
                Get-Marker 'machine' | Should -Be 'MenuToggle:Disable:0:silent=True'
            }

            It 'accepts an explicit -State interactively without showing the menu' {
                # The elevated child of a menu choice gets -State without /silent.
                Mock Read-VantaChoice -ModuleName Vanta.Toggles { throw 'menu shown' }

                Invoke-VantaToggle -Name 'MenuToggle' -State 'Disable' -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot

                Get-Marker 'machine' | Should -Be 'MenuToggle:Disable:0:silent=False'
                Should -Invoke Read-VantaChoice -ModuleName Vanta.Toggles -Times 0 -Exactly
                Should -Invoke Write-VantaTitle -ModuleName Vanta.Toggles -Times 1 -Exactly
            }

            It 'silently re-applies the recorded state when -State is omitted' {
                Set-VantaToggleState -Name 'MenuToggle' -State 0 -StateRoot $StateRoot
                Invoke-VantaToggle -Name 'MenuToggle' -Silent -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot
                Get-Marker 'machine' | Should -Be 'MenuToggle:Disable:0:silent=True'
            }

            It 'falls back to SilentDefault when nothing is recorded' {
                Invoke-VantaToggle -Name 'MenuToggle' -Silent -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot
                Get-Marker 'machine' | Should -Be 'MenuToggle:Enable:1:silent=True'
            }
        }
    }

    Context 'toggles with machine and user work' {
        BeforeEach {
            Mock Get-VantaToggleUserCallerBinding -ModuleName Vanta.Toggles { [pscustomobject]@{ Sid = 'S-1-5-21-1-2-3-1001'; SessionId = 1 } }
        }

        It 'plans both brokered phase orders without applying or recording anything' {
            $common = @{ State = 'On'; Phase = 'Plan'; TogglesRoot = $script:TogglesRoot; StateRoot = $StateRoot }
            Invoke-VantaToggle -Name UserOnlyToggle @common | Should -BeExactly 'User,Machine'
            Invoke-VantaToggle -Name SplitToggle @common | Should -BeExactly 'Machine,User'
            Test-Path (Join-Path $StateRoot 'UserOnlyToggle') | Should -BeFalse
            Test-Path (Join-Path $env:VantaToggleTestDir 'user.txt') | Should -BeFalse
        }

        It 'plans every shipped elevated state that declares per-user work' {
            $catalog = Get-Content -Raw -LiteralPath (Join-Path $script:ShippedTogglesRoot 'catalog.json') | ConvertFrom-Json
            $planned = 0
            foreach ($toggle in $catalog.toggles) {
                foreach ($state in $toggle.states) {
                    if ($toggle.elevation -eq 'None' -or -not $state.work.user) { continue }
                    $order = Invoke-VantaToggle -Name $toggle.name -State $state.name -Phase Plan `
                        -TogglesRoot $script:ShippedTogglesRoot -StateRoot $StateRoot
                    @('User,Machine', 'Machine,User') | Should -Contain $order
                    $planned++
                }
            }
            $planned | Should -BeGreaterThan 0
        }

        It 'runs only the requested silent phase and leaves recording to the elevated caller' {
            $common = @{ Name = 'SplitToggle'; State = 'On'; TogglesRoot = $script:TogglesRoot; StateRoot = $StateRoot }
            Mock Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles { throw 'unexpected UAC' }
            { Invoke-VantaToggle @common -Phase Machine } | Should -Throw '*Administrator token*'
            Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $true }
            { Invoke-VantaToggle @common -Phase User } | Should -Throw '*non-elevated user*'
            Invoke-VantaToggle @common -Phase Machine
            Get-Marker 'machine' | Should -Match '^SplitToggle:On:1:silent=True'
            Test-Path (Join-Path $env:VantaToggleTestDir 'user.txt') | Should -BeFalse
            Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $false }
            Invoke-VantaToggle @common -Phase User
            Get-Marker 'user' | Should -Be 'SplitToggle:On'
            (Get-VantaToggleState -Name SplitToggle -StateRoot $StateRoot).State | Should -Be 1
        }

        It 'does not dispatch a state record when a user-only action fails' {
            Set-VantaToggleState -Name 'UserOnlyToggle' -State 0 -StateRoot $StateRoot
            Mock Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles
            Mock Invoke-VantaTogglePostAction -ModuleName Vanta.Toggles

            { Invoke-VantaToggle -Name 'UserOnlyToggle' -State 'Failing' -LauncherPath $script:launcher `
                    -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot } | Should -Throw '*deliberate failure*'

            Should -Not -Invoke Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles
            Should -Not -Invoke Invoke-VantaTogglePostAction -ModuleName Vanta.Toggles
            (Get-VantaToggleState -Name 'UserOnlyToggle' -StateRoot $StateRoot).State | Should -Be 0
        }

        It 'finishes user-only work before its existing privileged recording child and final follow-up' {
            Mock Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles {
                [IO.File]::ReadAllText((Join-Path $env:VantaToggleTestDir 'user.txt')) | Should -Be 'UserOnlyToggle:On'
                [IO.File]::WriteAllText((Join-Path $env:VantaToggleTestDir 'record-dispatched.txt'), 'yes')
            }
            Mock Invoke-VantaTogglePostAction -ModuleName Vanta.Toggles {
                Test-Path -LiteralPath (Join-Path $env:VantaToggleTestDir 'record-dispatched.txt') | Should -BeTrue
            }
            Mock Write-VantaTitle -ModuleName Vanta.Toggles

            Invoke-VantaToggle -Name 'UserOnlyToggle' -State 'On' -LauncherPath $script:launcher `
                -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot

            Should -Invoke Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter { $UserWorkApplied }
            Should -Invoke Invoke-VantaTogglePostAction -ModuleName Vanta.Toggles -Times 1 -Exactly
            Should -Invoke Write-VantaTitle -ModuleName Vanta.Toggles -Times 1 -Exactly
            Get-Marker 'user' | Should -Be 'UserOnlyToggle:On'
        }

        It 'records the Visual Effects choice before it offers to sign out' {
            $script:events = [Collections.Generic.List[string]]::new()
            Mock Invoke-VantaRegistryEntries -ModuleName Vanta.Toggles { $script:events.Add("registry:$Scope") }
            Mock Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles { $script:events.Add("record:$UserWorkApplied") }
            Mock Write-VantaRestartNotice -ModuleName Vanta.Toggles
            Mock Write-VantaStep -ModuleName Vanta.Toggles
            Mock Read-VantaYesNo -ModuleName Vanta.Toggles { $script:events.Add("ask:$Question"); $true }
            Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles {
                $script:events.Add("native:$([IO.Path]::GetFileName($FilePath))")
            }

            Invoke-VantaToggle -Name 'Animation' -State 'Enable' -TogglesRoot $script:ShippedTogglesRoot -StateRoot $StateRoot

            $script:events | Should -Be @('registry:CurrentUser', 'record:True', 'ask:Sign out now?', 'native:logoff.exe')
        }

        It 'defers completion and the heading for a nested user choice while retaining its recording child' {
            Mock Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles {
                [IO.File]::ReadAllText((Join-Path $env:VantaToggleTestDir 'user.txt')) | Should -Be 'UserOnlyToggle:On'
            }
            Mock Invoke-VantaTogglePostAction -ModuleName Vanta.Toggles
            Mock Write-VantaTitle -ModuleName Vanta.Toggles

            Invoke-VantaToggle -Name 'UserOnlyToggle' -State 'On' -DeferPostAction `
                -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot

            Should -Invoke Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles -Times 1 -Exactly
            Should -Not -Invoke Invoke-VantaTogglePostAction -ModuleName Vanta.Toggles
            Should -Not -Invoke Write-VantaTitle -ModuleName Vanta.Toggles -Because 'the enclosing run owns the heading and window title'
            Get-Marker 'user' | Should -Be 'UserOnlyToggle:On'
        }

        It 'rejects deferred completion for machine work before dispatching it' {
            Mock Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles
            { Invoke-VantaToggle -Name 'SplitToggle' -State 'On' -DeferPostAction `
                -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot } | Should -Throw '*user-only choice*'
            Should -Not -Invoke Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles
            Get-Marker 'user' | Should -BeNullOrEmpty
        }

        It 'reports a failed recording of a successful user-only action and skips the follow-up (<Mode>)' -ForEach @(
            @{ Mode = 'standalone'; Deferred = $false }
            @{ Mode = 'nested choice'; Deferred = $true }
        ) {
            Mock Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles { throw 'recording cancelled' }
            Mock Invoke-VantaTogglePostAction -ModuleName Vanta.Toggles
            $extra = if ($Deferred) { @{ DeferPostAction = $true } } else { @{ LauncherPath = $script:launcher } }

            { Invoke-VantaToggle -Name 'UserOnlyToggle' -State 'On' @extra `
                    -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot } | Should -Throw '*recording cancelled*'

            Get-Marker 'user' | Should -Be 'UserOnlyToggle:On'
            Should -Not -Invoke Invoke-VantaTogglePostAction -ModuleName Vanta.Toggles
        }

        It 'reports a declined recording prompt after user-only work as partly done (<Mode>)' -ForEach @(
            @{ Mode = 'standalone'; Deferred = $false }
            @{ Mode = 'nested choice'; Deferred = $true }
        ) {
            Mock Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles {
                $cancelled = [InvalidOperationException]::new('prompt cancelled')
                $cancelled.Data['Vanta.Toggle.ElevationCancelledAfterUserWork'] = $true
                throw $cancelled
            }
            Mock Invoke-VantaTogglePostAction -ModuleName Vanta.Toggles
            Mock Write-VantaPartial -ModuleName Vanta.Toggles { Set-VantaRunOutcome -Outcome Partial }
            InModuleScope Vanta.Toggles { Reset-VantaRunOutcome }
            $extra = if ($Deferred) { @{ DeferPostAction = $true } } else { @{ LauncherPath = $script:launcher } }

            { Invoke-VantaToggle -Name 'UserOnlyToggle' -State 'On' @extra `
                    -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot } | Should -Not -Throw

            Get-Marker 'user' | Should -Be 'UserOnlyToggle:On'
            InModuleScope Vanta.Toggles { Get-VantaRunOutcome } | Should -BeExactly 'Partial'
            Should -Invoke Write-VantaPartial -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
                "$Text" -like "*didn't save this choice*an Vanta update can change it back*"
            }
            Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
                $Level -ceq 'Warning' -and $Message -ceq 'prompt cancelled'
            }
            Should -Invoke Invoke-VantaTogglePostAction -ModuleName Vanta.Toggles -Times $(if ($Deferred) { 0 } else { 1 }) -Exactly
        }

        It 'preserves interactive prerequisites in the Administrator child, then runs user work locally' {
            $script:scopes = @()
            Mock Invoke-VantaRegistryEntries -ModuleName Vanta.Toggles { $script:scopes += $Scope }
            Mock Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles

            Invoke-VantaToggle -Name 'SplitToggle' -State 'On' -LauncherPath $script:launcher `
                -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot

            Should -Invoke Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -like '*-MachineOnly*' -and ($ArgumentList -join ' ') -notlike '*/silent*' -and
                    -not $UserWorkApplied
            }
            Get-Marker 'machine' | Should -BeNullOrEmpty
            Get-Marker 'user' | Should -Be 'SplitToggle:On'
            $script:scopes | Should -Be @('CurrentUser')
            Get-VantaToggleState -Name 'SplitToggle' -StateRoot $StateRoot | Should -BeNullOrEmpty
        }

        It 'as the interactive -MachineOnly child applies and records only the machine part without a final pause' {
            Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $true }
            $script:scopes = @()
            Mock Invoke-VantaRegistryEntries -ModuleName Vanta.Toggles { $script:scopes += $Scope }

            Invoke-VantaToggle -Name 'SplitToggle' -State 'On' -MachineOnly -LauncherPath $script:launcher `
                -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot

            Get-Marker 'machine' | Should -Be 'SplitToggle:On:1:silent=False'
            Get-Marker 'user' | Should -BeNullOrEmpty
            $script:scopes | Should -Be @('Machine')
            (Get-VantaToggleState -Name 'SplitToggle' -StateRoot $StateRoot).State | Should -Be 1
            Should -Invoke Wait-VantaExit -ModuleName Vanta.Toggles -Times 0 -Exactly
            Should -Invoke Write-VantaCompletion -ModuleName Vanta.Toggles -Times 0 -Exactly
        }

        It 'refuses to start <Name> from an elevated process so user work cannot inherit the token' -TestCases @(
            @{ Name = 'SplitToggle' }
            @{ Name = 'SplitBrokerToggle' }
        ) {
            Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $true }
            Mock Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles
            Mock Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles

            { Invoke-VantaToggle -Name $Name -State 'On' -LauncherPath $script:launcher `
                    -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot } | Should -Throw '*non-elevated user process*'
            Should -Not -Invoke Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles
            Should -Not -Invoke Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles
            Should -Not -Invoke Wait-VantaContinue -ModuleName Vanta.Toggles
            Get-Marker 'machine' | Should -BeNullOrEmpty
            Get-Marker 'user' | Should -BeNullOrEmpty
        }

        It 'refuses the caller when its <Change> changes across the privileged child' -TestCases @(
            @{ Change = 'identity'; Sid = 'S-1-5-21-1-2-3-1002'; SessionId = 1 }
            @{ Change = 'Windows session'; Sid = 'S-1-5-21-1-2-3-1001'; SessionId = 2 }
        ) {
            Mock Invoke-VantaToggleElevatedChild -ModuleName Vanta.Toggles
            $script:callerBindings = [Collections.Generic.Queue[object]]::new()
            $script:callerBindings.Enqueue([pscustomobject]@{ Sid = 'S-1-5-21-1-2-3-1001'; SessionId = 1 })
            $script:callerBindings.Enqueue([pscustomobject]@{ Sid = $Sid; SessionId = $SessionId })
            Mock Get-VantaToggleUserCallerBinding -ModuleName Vanta.Toggles { $script:callerBindings.Dequeue() }

            { Invoke-VantaToggle -Name 'SplitToggle' -State 'On' -LauncherPath $script:launcher `
                    -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot } | Should -Throw '*identity or Windows session changed*'
            Get-Marker 'user' | Should -BeNullOrEmpty
        }

        It 'replays only the user part at first sign-in without recording' {
            $env:VANTA_USER_CONTEXT = '1'
            $script:scopes = @()
            Mock Invoke-VantaRegistryEntries -ModuleName Vanta.Toggles { $script:scopes += $Scope }

            Invoke-VantaToggle -Name 'SplitToggle' -State 'On' -Silent -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot

            Get-Marker 'user' | Should -Be 'SplitToggle:On'
            Get-Marker 'machine' | Should -BeNullOrEmpty
            $script:scopes | Should -Be @('CurrentUser')
            Get-VantaToggleState -Name 'SplitToggle' -StateRoot $StateRoot | Should -BeNullOrEmpty
        }
    }

    Context 'TrustedInstaller toggles' {
        BeforeEach {
            Mock Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles { [pscustomobject]@{ ExitCode = 0 } }
        }

        It 'routes an Administrator caller through the typed broker only, confirming first' {
            Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $true }
            $script:events = @()
            Mock Wait-VantaContinue -ModuleName Vanta.Toggles { $script:events += 'confirm' }
            Mock Write-VantaStep -ModuleName Vanta.Toggles { $script:events += 'step' }
            Mock Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles {
                $script:events += 'broker'
                [pscustomobject]@{ ExitCode = 0 }
            }

            Invoke-VantaToggle -Name 'BrokerToggle' -State 'Run' -NoExplorerRestart -LauncherPath $script:launcher `
                -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot

            $script:events | Should -Be @('confirm', 'step', 'broker')
            Should -Invoke Write-VantaStep -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
                $Text -like 'Applying the change as TrustedInstaller*'
            }
            Should -Invoke Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
                $Operation -eq 'Toggle' -and $Name -eq 'BrokerToggle' -and $State -eq 'Run' -and $Silent -eq $true
            }
            Get-Marker 'machine' | Should -BeNullOrEmpty
        }

        It 'prints no broker progress step in a <Mode> run' -ForEach @(
            @{ Mode = 'silent'; Extra = @{ Silent = $true } }
            @{ Mode = 'context-only'; Extra = @{ JustContext = $true } }
        ) {
            Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $true }
            Mock Write-VantaStep -ModuleName Vanta.Toggles

            Invoke-VantaToggle -Name 'BrokerToggle' -State 'Run' @Extra -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot

            Should -Invoke Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles -Times 1 -Exactly
            Should -Not -Invoke Write-VantaStep -ModuleName Vanta.Toggles
        }

        It 'runs in-process only with strict TrustedInstaller evidence' {
            Mock Test-VantaTrustedInstaller -ModuleName Vanta.Toggles { $true }

            Invoke-VantaToggle -Name 'BrokerToggle' -State 'Run' -Silent -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot

            Get-Marker 'machine' | Should -Be 'BrokerToggle:Run::silent=True'
            Should -Invoke Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles -Times 0
        }

        It 'rejects LocalSystem without TrustedInstaller evidence before the broker' {
            # A real LocalSystem token is also in Administrators.
            Mock Test-VantaSystem -ModuleName Vanta.Toggles { $true }
            Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $true }

            { Invoke-VantaToggle -Name 'BrokerToggle' -State 'Run' -Silent -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot } |
                Should -Throw '*LocalSystem without strict TrustedInstaller*'
            Should -Not -Invoke Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles
        }

        It 'rejects a non-TrustedInstaller definition inside a TrustedInstaller process' {
            Mock Test-VantaTrustedInstaller -ModuleName Vanta.Toggles { $true }

            { Invoke-VantaToggle -Name 'MachineToggle' -State 'On' -Silent -TogglesRoot $script:TogglesRoot -StateRoot $StateRoot } |
                Should -Throw '*does not declare exact TrustedInstaller elevation*'
        }
    }
}

Describe 'Invoke-VantaToggleMachineState' {
    BeforeAll {
        $script:DependencyRoot = Join-Path $TestDrive 'DependencyToggles'
        $script:DependencyWork = Join-Path $TestDrive 'DependencyWork'
        New-Item -Path $script:DependencyWork -ItemType Directory -Force | Out-Null
        New-TestToggle -Root $script:DependencyRoot -Name 'Dependency' -Definition @'
@{
    Name      = 'Dependency'
    Elevation = 'Admin'
    Script    = 'Dependency.ps1'
    States    = @( @{ Name = 'On'; StateValue = 1; Launcher = 'A\On.cmd'; MachineAction = 'Invoke-VantaTestMachine'; UserAction = 'Invoke-VantaTestUser' } )
}
'@ -Companion $script:MarkerCompanion
        New-TestToggle -Root $script:DependencyRoot -Name 'Local' -Definition @'
@{
    Name          = 'Local'
    Elevation     = 'None'
    NoStateRecord = $true
    Script        = 'Local.ps1'
    States        = @( @{ Name = 'On'; Launcher = 'A\On.cmd'; Action = 'Invoke-VantaTestLocal' } )
}
'@ -Companion $script:MarkerCompanion
    }

    BeforeEach {
        $env:VantaToggleTestDir = $script:DependencyWork
        Get-ChildItem -Path $script:DependencyWork -Filter '*.txt' | Remove-Item -Force
        Remove-Item -Path $StateRoot -Recurse -Force -ErrorAction SilentlyContinue
        Mock Write-VantaLog -ModuleName Vanta.Toggles
        Mock Assert-VantaPrivilege -ModuleName Vanta.Toggles
    }

    AfterAll {
        Remove-Item Env:\VantaToggleTestDir -ErrorAction SilentlyContinue
    }

    It 'applies and records only the machine part from a privileged caller' {
        Invoke-VantaToggleMachineState -Name 'Dependency' -State 'On' -StateRoot $StateRoot -TogglesRoot $script:DependencyRoot

        Should -Invoke Assert-VantaPrivilege -ModuleName Vanta.Toggles -ParameterFilter { $Administrator }
        [IO.File]::ReadAllText((Join-Path $script:DependencyWork 'machine.txt')) | Should -Be 'Dependency:On:1:silent=True'
        Join-Path $script:DependencyWork 'user.txt' | Should -Not -Exist
        (Get-VantaToggleState -Name 'Dependency' -StateRoot $StateRoot).State | Should -Be 1
    }

    It 'rejects an unelevated toggle and an unknown state' {
        { Invoke-VantaToggleMachineState -Name 'Local' -State 'On' -StateRoot $StateRoot -TogglesRoot $script:DependencyRoot } |
            Should -Throw '*does not declare Admin or TrustedInstaller*'
        { Invoke-VantaToggleMachineState -Name 'Dependency' -State 'Off' -StateRoot $StateRoot -TogglesRoot $script:DependencyRoot } |
            Should -Throw "*does not define exact state 'Off'*"
    }
}

Describe 'Invoke-VantaTogglePostAction' {
    BeforeEach {
        $script:events = [Collections.Generic.List[string]]::new()
        Mock Write-VantaCompletion -ModuleName Vanta.Toggles { $script:events.Add('completion') }
        Mock Write-VantaRestartNotice -ModuleName Vanta.Toggles { $script:events.Add("notice:$Kind") }
        Mock Write-VantaStep -ModuleName Vanta.Toggles
        Mock Wait-VantaExit -ModuleName Vanta.Toggles { $script:events.Add('exit') }
        Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles {
            $script:events.Add("native:$([IO.Path]::GetFileName($FilePath))")
        }
    }

    It 'offers the declared sign-out after the closing line and signs out on yes' {
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { $script:events.Add("ask:$Question"); $true }

        InModuleScope Vanta.Toggles {
            Invoke-VantaTogglePostAction -ToggleName 'Animation' -StateEntry @{ Reboot = 'SignOut' } `
                -Context ([pscustomobject]@{ WinDir = 'C:\Windows' })
        }

        $script:events | Should -Be @('completion', 'notice:SignOut', 'ask:Sign out now?', 'native:logoff.exe', 'exit')
        Should -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'C:\Windows\System32\logoff.exe' -and @($ArgumentList).Count -eq 0 -and
                (@($AllowedExitCodes) -join ',') -eq '0'
        }
    }

    It 'keeps the session on no and asks nothing in a silent run' {
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { $false }

        InModuleScope Vanta.Toggles {
            $entry = @{ Reboot = 'SignOut' }
            $context = [pscustomobject]@{ WinDir = 'C:\Windows' }
            Invoke-VantaTogglePostAction -ToggleName 'Animation' -StateEntry $entry -Context $context
            Invoke-VantaTogglePostAction -ToggleName 'Animation' -StateEntry $entry -Context $context -Silent
        }

        Should -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles -Times 1 -Exactly
        Should -Not -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles
    }

    It 'reports a failed Explorer restart as partly done, and fails a silent run' {
        Mock Test-VantaSystem -ModuleName Vanta.Toggles { $false }
        Mock Write-VantaLog -ModuleName Vanta.Toggles
        Mock Write-VantaPartial -ModuleName Vanta.Toggles { $script:events.Add('partial') }
        Mock Invoke-VantaToggleCurrentSessionShellRefresh -ModuleName Vanta.Toggles {
            throw 'Current-session toggle shell refresh exited with code 14.'
        }

        InModuleScope Vanta.Toggles {
            Invoke-VantaTogglePostAction -ToggleName 'Explorer' -StateEntry @{ Reboot = 'RestartExplorer' } `
                -Context ([pscustomobject]@{ WinDir = 'C:\Windows' })
        }
        $script:events | Should -Be @('partial', 'completion', 'exit')
        Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Level -ceq 'Warning' -and $Message -like '*exited with code 14*'
        }

        {
            InModuleScope Vanta.Toggles {
                Invoke-VantaTogglePostAction -ToggleName 'Explorer' -StateEntry @{ Reboot = 'RestartExplorer' } `
                    -Context ([pscustomobject]@{ WinDir = 'C:\Windows' }) -Silent
            }
        } | Should -Throw '*exited with code 14*'
    }
}

Describe 'Generated launchers' {
    BeforeAll {
        $script:GeneratorScript = Join-Path $script:repoRoot 'tools\dev\New-ToggleLaunchers.ps1'
        $script:LauncherBody = Join-Path $script:repoRoot 'package\Executables\VantaModules\Scripts\Entry\Invoke-VantaToggleLauncher.cmd'
    }

    It 'match their definitions exactly' {
        # Repository tooling runs under PowerShell 7, like the build.
        $output = & $script:ToolsHost -NoProfile -File $script:GeneratorScript -Validate 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }

    It 'canonicalizes only the supported launcher flags before reaching PowerShell' {
        $bodyLines = @(Get-Content -LiteralPath $script:LauncherBody)
        $parserStart = [array]::IndexOf($bodyLines, 'set "VantaLauncherSilent="')
        $parserEnd = [array]::IndexOf($bodyLines, ':run')
        $parserStart | Should -BeGreaterThan -1
        $parserEnd | Should -BeGreaterThan $parserStart

        $probePath = Join-Path -Path $TestDrive -ChildPath 'launcher-argument-probe.cmd'
        $probeLines = @(
            '@echo off'
            'setlocal EnableExtensions DisableDelayedExpansion'
        ) + @($bodyLines[$parserStart..$parserEnd]) + @(
            'echo SINK silent=%VantaLauncherSilent% justcontext=%VantaLauncherJustContext% noaction=%VantaLauncherNoAction%'
            'exit /b 0'
        )
        [IO.File]::WriteAllText($probePath, (($probeLines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

        $commandHost = [IO.Path]::Combine([Environment]::GetFolderPath('System'), 'cmd.exe')
        $allowed = & $commandHost /d /e:on /v:off /c "call `"$probePath`" /quiet -justcontext /noaction" 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($allowed -join "`n")
        ($allowed -join "`n") | Should -Match '(?m)^SINK silent=/silent justcontext=/justcontext noaction=/noaction$'

        $rejected = & $commandHost /d /e:on /v:off /c "call `"$probePath`" /silent /unsupported" 2>&1
        $LASTEXITCODE | Should -Be 87 -Because ($rejected -join "`n")
        $rejected | Should -Not -Match '^SINK '
    }

    It 'keeps the toggle''s exit code when the body is run directly rather than called: <Code>' -TestCases @(
        @{ Code = 0; Expected = 0 }
        @{ Code = 3; Expected = 3 }
        @{ Code = -1; Expected = 1 }
    ) {
        param($Code, $Expected)
        # Vanta Manager and the Toolbox start the body with cmd /c, not through a stub's call.
        $bodyLines = @(Get-Content -LiteralPath $script:LauncherBody)
        $tailStart = [array]::FindIndex($bodyLines, [Predicate[string]] { param($line) $line -like '"%VantaNativePowerShell%"*' }) + 1
        $tailStart | Should -BeGreaterThan 0
        $probePath = Join-Path -Path $TestDrive -ChildPath 'launcher-exit-probe.cmd'
        $probeLines = @('@echo off', "cmd /d /c exit $Code") + @($bodyLines[$tailStart..($bodyLines.Count - 1)])
        [IO.File]::WriteAllText($probePath, (($probeLines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

        $commandHost = [IO.Path]::Combine([Environment]::GetFolderPath('System'), 'cmd.exe')
        $null = & $commandHost /d /s /c "`"$probePath`""
        $LASTEXITCODE | Should -Be $Expected
    }

    It 'pass the toggle name, state and their own path to the shared body and keep its exit code' {
        # The real stubs, with their body swapped for one that echoes what it received and
        # exits with the first extra argument.
        $body = Join-Path $TestDrive 'body.cmd'
        [IO.File]::WriteAllText($body, "@echo off`r`necho %~1^|%~2^|%~3`r`nexit /b %~4`r`n", [Text.Encoding]::ASCII)
        $stub = Join-Path $TestDrive 'stub.cmd'
        $commandHost = [IO.Path]::Combine([Environment]::GetFolderPath('System'), 'cmd.exe')
        # %__APPDIR__% is System32, so the call must resolve inside the installed VantaModules.
        $installedModules = '%__APPDIR__%..\VantaModules\'
        $cases = @(
            @{ Path = '2. Drivers\Run Update Drivers.cmd'; Name = 'UpdateDrivers'; State = 'Run' }
            @{ Path = '6. Advanced Configuration\Toggle Windows Updates\Toggle Windows Updates.cmd'; Name = 'ToggleWindowsUpdates'; State = '-' }
        )

        foreach ($case in $cases) {
            $shipped = @(Get-Content -LiteralPath (Join-Path $script:repoRoot "package\Executables\VantaDesktop\$($case.Path)"))
            $shipped.Count | Should -Be 2
            $call = [regex]::Match($shipped[1], '^call "([^"]+)" ')
            $call.Success | Should -BeTrue -Because $shipped[1]
            $target = $call.Groups[1].Value
            $target.StartsWith($installedModules, [StringComparison]::Ordinal) | Should -BeTrue -Because $target
            (Join-Path $script:repoRoot "package\Executables\VantaModules\$($target.Substring($installedModules.Length))") |
                Should -Be $script:LauncherBody
            [IO.File]::WriteAllText($stub, (($shipped[0], ($shipped[1] -replace '^call "[^"]+"', "call `"$body`"")) -join "`r`n") + "`r`n", [Text.Encoding]::ASCII)

            foreach ($code in 0, 37, -1) {
                $received = & $commandHost /d /c "`"$stub`" $code"
                $LASTEXITCODE | Should -Be $code
                $received | Should -BeExactly "$($case.Name)|$($case.State)|$stub"
            }
        }
    }
}

Describe 'Toggle elevation relaunch' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Toggles
        Mock Get-VantaContext -ModuleName Vanta.Toggles {
            [pscustomobject]@{
                WinDir           = [Environment]::GetFolderPath('Windows')
                VantaModulesPath = 'C:\Windows\VantaModules'
            }
        }
    }

    It 'builds plain argv for the relaunch' {
        InModuleScope Vanta.Toggles {
            Get-VantaToggleRelaunchArgumentList -Name 'MyToggle' -State 'On' -LauncherPath 'C:\Program Files\x.cmd' -MachineOnly |
                Should -Be @(
                    '-NoProfile', '-NoLogo', '-ExecutionPolicy', 'Bypass'
                    '-File', 'C:\Windows\VantaModules\Scripts\Entry\Invoke-Toggle.ps1'
                    '-Name', 'MyToggle', '-State', 'On', '-LauncherPath', 'C:\Program Files\x.cmd', '-MachineOnly'
                )
        }
    }

    It 'serializes the argv with the shared Windows quoting and keeps the shell''s Win32 error' {
        Mock ConvertTo-VantaWindowsArgumentString -ModuleName Vanta.Toggles { 'serialized' }
        $missing = Join-Path $TestDrive 'missing.exe'

        # A missing file fails ShellExecuteEx before any elevation prompt.
        $failure = { InModuleScope Vanta.Toggles -Parameters @{ Path = $missing } {
                param($Path)
                Start-VantaToggleAdminRelaunch -FilePath $Path -ArgumentList @('-Name', 'My Toggle')
            } } | Should -Throw -ExceptionType ([ComponentModel.Win32Exception]) -PassThru

        $failure.Exception.NativeErrorCode | Should -Be 2
        Should -Invoke ConvertTo-VantaWindowsArgumentString -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            (@($ArgumentList) -join '|') -eq '-Name|My Toggle'
        }
    }

    It 'reports a declined prompt as cancelled and says whether the user work already ran (<Case>)' -ForEach @(
        @{ Case = 'nothing applied yet'; Applied = $false; Expected = "*prompt for 'MyToggle' was cancelled, so nothing was changed." }
        @{ Case = 'user work applied'; Applied = $true; Expected = "*prompt for 'MyToggle' was cancelled, so the change was made but Vanta didn't record it." }
    ) {
        Mock Start-VantaToggleAdminRelaunch -ModuleName Vanta.Toggles { throw [ComponentModel.Win32Exception]::new(1223) }

        $failure = { InModuleScope Vanta.Toggles -Parameters @{ Applied = $Applied } {
                param($Applied)
                Invoke-VantaToggleElevatedChild -Name 'MyToggle' -ArgumentList @('-Name', 'MyToggle') -Silent `
                    -UserWorkApplied:$Applied
            } } | Should -Throw $Expected -PassThru

        # The engine reports the applied case as partly done by this key, not the text.
        $failure.Exception.Data.Contains('Vanta.Toggle.ElevationCancelledAfterUserWork') | Should -Be $Applied
    }
}

Describe 'Operating-system protected toggle values' {
    It 'accepts AllowOsProtected on a state registry entry' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-TestToggle -Root $root -Name 'Protected' -Definition @'
@{
    Name      = 'Protected'
    Elevation = 'Admin'
    States    = @(
        @{
            Name       = 'Disable'
            StateValue = 0
            Launcher   = 'Group\Disable.cmd'
            Registry   = @(
                @{ Path = 'HKLM:\SOFTWARE\Policies\Test'; Name = 'Policy'; Type = 'DWord'; Data = 1; AllowOsProtected = $true }
            )
        }
    )
}
'@
        @(Test-VantaToggleDefinition -Path $root).Count | Should -Be 0
    }

    It 'allows denial only for the legacy Search background preference in both toggle directions' {
        $definition = Get-VantaToggleDefinition -Name 'BackgroundApps' -TogglesRoot $script:ShippedTogglesRoot
        foreach ($state in @('Enable', 'Disable')) {
            $entries = @($definition['States'][$state]['Registry'])
            $optional = @($entries | Where-Object { $_['AllowOsProtected'] })
            $optional.Count | Should -Be 1
            $optional[0].Name | Should -Be 'BackgroundAppGlobalToggle'
        }
    }
}

Describe 'Local Group Policy declarations in toggle schemas' {
    It 'rejects user policy and non-boolean declarations' -TestCases @(
        @{ Path = 'HKLM:\Software\Policies\Test'; Flag = '$true'; Valid = $true }
        @{ Path = 'HKCU:\Software\Policies\Test'; Flag = '$true'; Valid = $false }
        @{ Path = 'HKLM:\Software\Policies\Test'; Flag = "'false'"; Valid = $false }
    ) {
        param($Path, $Flag, $Valid)
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-TestToggle -Root $root -Name 'Policy' -Definition @"
@{
    Name = 'Policy'
    Elevation = 'Admin'
    States = @(@{
        Name = 'Disable'; StateValue = 0; Launcher = 'Group\Disable.cmd'
        Registry = @(@{ Path = '$Path'; Name = 'Policy'; Type = 'DWord'; Data = 0; UseGroupPolicy = $Flag })
    })
}
"@
        $problems = @(Test-VantaToggleDefinition -Path $root)
        if ($Valid) { $problems.Count | Should -Be 0 }
        else { ($problems.Problem -join '; ') | Should -Match 'UseGroupPolicy' }
    }
}

Describe 'Power-plan verification' {
    It 'reports Balanced instead of the recorded Vanta plan through the normal health check' {
        Mock Get-VantaPowerPlanValue -ModuleName Vanta.Toggles { '381b4222-f694-41f0-9685-ff5bb260df2e' }
        Mock Get-VantaPowerPlanValue -ModuleName Vanta.Toggles { '11111111-1111-1111-1111-111111111111' } -ParameterFilter { $Name -eq 'VantaPowerSchemeGuid' }   # o GUID que o Vanta registrou
        $root = 'HKCU:\Software\VantaRewriteTest\PowerPlanHealth'
        try {
            Set-VantaToggleState -Name PowerSaving -State 0 -StateRoot $root
            $drift = @(Test-VantaToggleDrift -Scope Machine -StateRoot $root -TogglesRoot $script:ShippedTogglesRoot)
            $drift | Should -HaveCount 1
            $drift[0].Kind | Should -Be PowerPlan
            $drift[0].Reason | Should -BeLike '*not active*'
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reports the active Vanta plan beside a stale Enable record' {
        Mock Get-VantaPowerPlanValue -ModuleName Vanta.Toggles { '11111111-1111-1111-1111-111111111111' }
        $drift = @(& (Get-Module Vanta.Toggles) { Test-VantaPowerPlanDrift -StateName Enable })
        $drift | Should -HaveCount 1
        $drift[0].Reason | Should -BeLike '*recorded as enabled*'
    }

    It 'accepts the active Vanta plan only when its four AC values match' {
        Mock Get-VantaPowerPlanValue -ModuleName Vanta.Toggles { 0 }
        Mock Get-VantaPowerPlanValue -ModuleName Vanta.Toggles { '11111111-1111-1111-1111-111111111111' } -ParameterFilter { $Name -eq 'ActivePowerScheme' }
        Mock Get-VantaPowerPlanValue -ModuleName Vanta.Toggles { 200 } -ParameterFilter { $Path -like '*4d2b0152-7d5c-498b-88e2-34345392a2c5' }
        Mock Get-VantaPowerPlanValue -ModuleName Vanta.Toggles { '11111111-1111-1111-1111-111111111111' } -ParameterFilter { $Name -eq 'VantaPowerSchemeGuid' }   # o GUID que o Vanta registrou
        @(& (Get-Module Vanta.Toggles) { Test-VantaPowerPlanDrift -StateName Disable }) | Should -HaveCount 0
    }

    It 'reports an incorrect AC value even when the Vanta plan is active' {
        Mock Get-VantaPowerPlanValue -ModuleName Vanta.Toggles { 0 }
        Mock Get-VantaPowerPlanValue -ModuleName Vanta.Toggles { '11111111-1111-1111-1111-111111111111' } -ParameterFilter { $Name -eq 'ActivePowerScheme' }
        Mock Get-VantaPowerPlanValue -ModuleName Vanta.Toggles { '11111111-1111-1111-1111-111111111111' } -ParameterFilter { $Name -eq 'VantaPowerSchemeGuid' }   # o GUID que o Vanta registrou
        $drift = @(& (Get-Module Vanta.Toggles) { Test-VantaPowerPlanDrift -StateName Disable })
        $drift | Should -HaveCount 1
        $drift[0].Target | Should -BeLike '*4d2b0152-7d5c-498b-88e2-34345392a2c5'
    }

    It 'reports an unreadable plan instead of declaring it healthy' {
        Mock Get-VantaPowerPlanValue -ModuleName Vanta.Toggles { throw 'access denied' }
        $drift = @(& (Get-Module Vanta.Toggles) { Test-VantaPowerPlanDrift -StateName Disable })
        $drift | Should -HaveCount 1
        $drift[0].Reason | Should -BeLike '*verification failed*access denied*'
    }

    It 'does not require Balanced when power saving is enabled on a custom plan' {
        Mock Get-VantaPowerPlanValue -ModuleName Vanta.Toggles { 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
        Mock Get-VantaPowerPlanValue -ModuleName Vanta.Toggles { throw 'no Vanta plan recorded' } -ParameterFilter { $Name -eq 'VantaPowerSchemeGuid' }
        @(& (Get-Module Vanta.Toggles) { Test-VantaPowerPlanDrift -StateName Enable }) | Should -HaveCount 0
    }
}

Describe 'Registry verification exclusions in toggle schemas' {
    It 'requires a non-empty reason string' -TestCases @(
        @{ Value = "'Windows recreates this cache.'"; Valid = $true }
        @{ Value = '$true'; Valid = $false }
        @{ Value = "''"; Valid = $false }
        @{ Value = "' '"; Valid = $false }
    ) {
        param($Value, $Valid)
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-TestToggle -Root $root -Name 'Transient' -Definition @"
@{
    Name = 'Transient'
    Elevation = 'Admin'
    States = @(
        @{
            Name = 'Disable'; StateValue = 0; Launcher = 'Group\Disable.cmd'
            Registry = @(@{ Path = 'HKCU:\Software\Test'; Operation = 'DeleteKey'; SkipVerification = $Value })
        }
    )
}
"@
        $problems = @(Test-VantaToggleDefinition -Path $root)
        if ($Valid) { $problems.Count | Should -Be 0 }
        else { ($problems.Problem -join '; ') | Should -Match 'non-empty reason string' }
    }
}
