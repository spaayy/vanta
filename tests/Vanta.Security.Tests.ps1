BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Registry\Vanta.Registry.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Security\Vanta.Security.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force

    $script:testRoot = 'HKCU:\Software\VantaRewriteTest'
    $script:deviceGuardPath = "$script:testRoot\DeviceGuard"
    $script:hvciPath = "$script:deviceGuardPath\Scenarios\HypervisorEnforcedCodeIntegrity"
    $script:policyPath = "$script:testRoot\Policies\DeviceGuard"

    $togglesRoot = Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules\Toggles'
    $script:ToggleDefender = Get-VantaToggleDefinition -Name ToggleDefender -TogglesRoot $togglesRoot
    $script:FixErrors2502and2503 = Get-VantaToggleDefinition -Name FixErrors2502and2503 -TogglesRoot $togglesRoot
    $script:VbsState = Get-VantaToggleDefinition -Name VbsState -TogglesRoot $togglesRoot
    $script:ShippedTogglesRoot = $togglesRoot
    $script:TweakPath = Join-Path $script:VantaTestScriptsRoot 'Tweaks\scripts\disable-core-isolation.psd1'

    function Set-TestDword {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][int]$Value
        )

        New-Item -Path $Path -Force | Out-Null
        Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type DWord
    }

    function Get-TestValueState {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string]$Name
        )

        if (-not (Test-Path -LiteralPath $Path)) {
            return $null
        }
        $key = Get-Item -LiteralPath $Path
        if (@($key.GetValueNames()) -notcontains $Name) {
            return $null
        }
        return [pscustomobject]@{
            Kind  = $key.GetValueKind($Name)
            Value = $key.GetValue($Name)
        }
    }

    function New-ToggleContext {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][string]$State,
            [bool]$Silent = $true
        )

        return [pscustomobject]@{
            Name           = $Name
            State          = $State
            StateValue     = $null
            Silent         = $Silent
            OperationsPath = Join-Path $TestDrive 'Operations'
        }
    }

    # Runs one companion function exactly as the engine does (dot-sourced into the
    # module scope under strict mode), so module-scoped mocks apply to it.
    function Invoke-CompanionFunction {
        param(
            [Parameter(Mandatory = $true)]$Definition,
            [Parameter(Mandatory = $true)][string]$FunctionName,
            [Parameter(Mandatory = $true)]$Toggle
        )

        InModuleScope Vanta.Toggles {
            Invoke-VantaToggleFunction -Definition $d -FunctionName $f -Toggle $t -Label 'test'
        } -Parameters @{ d = $Definition; f = $FunctionName; t = $Toggle }
    }
}

AfterAll {
    Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Set-VantaVbsConfiguration' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Security
        Mock Write-VantaSuccess -ModuleName Vanta.Security
        Mock Assert-VantaPrivilege -ModuleName Vanta.Security
        Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $script:testRoot -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'disables by writing only the two documented runtime values' {
        Set-VantaVbsConfiguration -State Disable `
            -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath

        $enabled = Get-TestValueState -Path $script:hvciPath -Name 'Enabled'
        $enabled.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::DWord)
        $enabled.Value | Should -Be 0
        $vbs = Get-TestValueState -Path $script:deviceGuardPath -Name 'EnableVirtualizationBasedSecurity'
        $vbs.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::DWord)
        $vbs.Value | Should -Be 0
        @((Get-Item -LiteralPath $script:deviceGuardPath).GetValueNames()) |
            Should -Be @('EnableVirtualizationBasedSecurity')
        @((Get-Item -LiteralPath $script:hvciPath).GetValueNames()) | Should -Be @('Enabled')
        Should -Invoke Assert-VantaPrivilege -ModuleName Vanta.Security -Times 1 -Exactly -ParameterFilter { $Administrator }
        Should -Invoke Write-VantaSuccess -ModuleName Vanta.Security -Times 1 -Exactly -ParameterFilter {
            $Text -like '*configured to disable*'
        }
    }

    It 'enables with platform security features and preserves existing lock values' {
        Set-TestDword -Path $script:deviceGuardPath -Name 'Locked' -Value 1

        Set-VantaVbsConfiguration -State Enable `
            -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath

        (Get-TestValueState -Path $script:deviceGuardPath -Name 'RequirePlatformSecurityFeatures').Value | Should -Be 1
        (Get-TestValueState -Path $script:deviceGuardPath -Name 'Locked').Value | Should -Be 1
        (Get-TestValueState -Path $script:deviceGuardPath -Name 'EnableVirtualizationBasedSecurity').Value | Should -Be 1
        (Get-TestValueState -Path $script:hvciPath -Name 'Locked').Value | Should -Be 0
        (Get-TestValueState -Path $script:hvciPath -Name 'Enabled').Value | Should -Be 1
        foreach ($name in @('RequirePlatformSecurityFeatures', 'Locked', 'EnableVirtualizationBasedSecurity')) {
            (Get-TestValueState -Path $script:deviceGuardPath -Name $name).Kind |
                Should -Be ([Microsoft.Win32.RegistryValueKind]::DWord) -Because $name
        }
    }

    It 'refuses to disable when a UEFI lock protects the current state' {
        Set-TestDword -Path $script:hvciPath -Name 'Locked' -Value 1

        { Set-VantaVbsConfiguration -State Disable `
                -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath } |
            Should -Throw '*UEFI lock*'

        Get-TestValueState -Path $script:hvciPath -Name 'Enabled' | Should -BeNullOrEmpty
        Test-Path -LiteralPath $script:deviceGuardPath | Should -BeTrue
        @((Get-Item -LiteralPath $script:deviceGuardPath).GetValueNames()) | Should -BeNullOrEmpty
    }

    It 'still enables under a UEFI lock and keeps the lock' {
        Set-TestDword -Path $script:hvciPath -Name 'Locked' -Value 1

        Set-VantaVbsConfiguration -State Enable `
            -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath

        (Get-TestValueState -Path $script:hvciPath -Name 'Locked').Value | Should -Be 1
        (Get-TestValueState -Path $script:hvciPath -Name 'Enabled').Value | Should -Be 1
    }

    It 'disables when policy already turns VBS off, as guides for disabling VBS leave it' {
        # The values such a guide leaves.
        Set-TestDword -Path $script:policyPath -Name 'EnableVirtualizationBasedSecurity' -Value 0
        Set-TestDword -Path $script:policyPath -Name 'HVCIMATRequired' -Value 0
        Set-TestDword -Path $script:policyPath -Name 'LsaCfgFlags' -Value 0

        Set-VantaVbsConfiguration -State Disable `
            -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath

        (Get-TestValueState -Path $script:deviceGuardPath -Name 'EnableVirtualizationBasedSecurity').Value | Should -Be 0
        (Get-TestValueState -Path $script:hvciPath -Name 'Enabled').Value | Should -Be 0
    }

    It 'refuses to <State> over policy value <Name> = <Value> and writes nothing' -TestCases @(
        @{ State = 'Disable'; Name = 'EnableVirtualizationBasedSecurity'; Value = 1 }
        @{ State = 'Disable'; Name = 'LsaCfgFlags'; Value = 2 }
        @{ State = 'Disable'; Name = 'ConfigureSystemGuardLaunch'; Value = 1 }
        @{ State = 'Disable'; Name = 'ConfigureKernelShadowStacksLaunch'; Value = 1 }
        @{ State = 'Disable'; Name = 'EnableVirtualizationBasedSecurity'; Value = 7 }
        @{ State = 'Enable'; Name = 'EnableVirtualizationBasedSecurity'; Value = 0 }
        @{ State = 'Enable'; Name = 'HypervisorEnforcedCodeIntegrity'; Value = 0 }
    ) {
        Set-TestDword -Path $script:policyPath -Name $Name -Value $Value

        { Set-VantaVbsConfiguration -State $State `
                -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath } |
            Should -Throw "*($Name = $Value)*"

        Test-Path -LiteralPath $script:deviceGuardPath | Should -BeFalse
    }

    It 'enables when policy only configures Credential Guard' {
        Set-TestDword -Path $script:policyPath -Name 'LsaCfgFlags' -Value 2

        Set-VantaVbsConfiguration -State Enable `
            -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath

        (Get-TestValueState -Path $script:hvciPath -Name 'Enabled').Value | Should -Be 1
    }

    It 'logs a warning and writes nothing over conflicting policy when asked to skip' {
        Set-TestDword -Path $script:policyPath -Name 'EnableVirtualizationBasedSecurity' -Value 1

        Set-VantaVbsConfiguration -State Disable -SkipWhenPolicyConflicts `
            -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath

        Test-Path -LiteralPath $script:deviceGuardPath | Should -BeFalse
        Should -Invoke Write-VantaLog -ModuleName Vanta.Security -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -like '*EnableVirtualizationBasedSecurity = 1*'
        }
    }

    It 'logs a warning and writes nothing under a UEFI lock when asked to skip, so a locked PC can still install' {
        Set-TestDword -Path $script:deviceGuardPath -Name 'Locked' -Value 1

        { Set-VantaVbsConfiguration -State Disable -SkipWhenPolicyConflicts `
                -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath } | Should -Not -Throw

        @((Get-Item -LiteralPath $script:deviceGuardPath).GetValueNames()) | Should -Be @('Locked')
        Test-Path -LiteralPath $script:hvciPath | Should -BeFalse
        Should -Invoke Write-VantaLog -ModuleName Vanta.Security -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -like '*not configured to disable*UEFI lock*'
        }
        Should -Invoke Write-VantaSuccess -ModuleName Vanta.Security -Times 0 -Exactly
    }

    It 'refuses a <Kind> lock value it cannot interpret before writing anything' -TestCases @(
        @{ Kind = 'DWord'; Value = 2; State = 'Enable'; Message = '*unsupported value*' }
        @{ Kind = 'String'; Value = '1'; State = 'Disable'; Message = '*not REG_DWORD*' }
    ) {
        New-Item -Path $script:deviceGuardPath -Force | Out-Null
        Set-ItemProperty -LiteralPath $script:deviceGuardPath -Name 'Locked' -Value $Value -Type $Kind

        { Set-VantaVbsConfiguration -State $State `
                -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath } |
            Should -Throw $Message

        Get-TestValueState -Path $script:deviceGuardPath -Name 'EnableVirtualizationBasedSecurity' |
            Should -BeNullOrEmpty
    }

    It 'requires Administrator rights before reading or writing anything' {
        Mock Assert-VantaPrivilege -ModuleName Vanta.Security { throw '[privilege] This operation requires Administrator rights.' }

        { Set-VantaVbsConfiguration -State Disable `
                -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath } |
            Should -Throw '*requires Administrator*'

        Test-Path -LiteralPath $script:deviceGuardPath | Should -BeFalse
    }
}

Describe 'Test-VantaVbsChange' {
    BeforeEach {
        Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $script:testRoot -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'allows <State> when nothing stands in the way' -ForEach @(
        @{ State = 'Enable' }
        @{ State = 'Disable' }
    ) {
        Test-VantaVbsChange -State $State -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath |
            Should -BeNullOrEmpty
    }

    It 'names the policy that controls VBS for <State> (<Name> = <Value>)' -ForEach @(
        @{ State = 'Disable'; Name = 'EnableVirtualizationBasedSecurity'; Value = 1 }
        @{ State = 'Disable'; Name = 'LsaCfgFlags'; Value = 2 }
        @{ State = 'Enable'; Name = 'EnableVirtualizationBasedSecurity'; Value = 0 }
        @{ State = 'Enable'; Name = 'HypervisorEnforcedCodeIntegrity'; Value = 0 }
    ) {
        Set-TestDword -Path $script:policyPath -Name $Name -Value $Value

        Test-VantaVbsChange -State $State -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath |
            Should -BeExactly "policy under '$script:policyPath' controls it ($Name = $Value)"
    }

    It 'refuses Disable under a UEFI lock on <Key>, but not Enable, which keeps the lock' -ForEach @(
        @{ Key = 'VBS'; Relative = '' }
        @{ Key = 'memory integrity'; Relative = 'Scenarios\HypervisorEnforcedCodeIntegrity' }
    ) {
        $lockPath = if ($Relative) { Join-Path $script:deviceGuardPath $Relative } else { $script:deviceGuardPath }
        Set-TestDword -Path $lockPath -Name 'Locked' -Value 1

        Test-VantaVbsChange -State Disable -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath |
            Should -BeExactly "a UEFI lock protects it, and a registry change can't turn it off"
        Test-VantaVbsChange -State Enable -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath |
            Should -BeNullOrEmpty
    }

    It 'gives a reason instead of failing when a lock value can''t be read safely' {
        Set-TestDword -Path $script:deviceGuardPath -Name 'Locked' -Value 2

        Test-VantaVbsChange -State Enable -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath |
            Should -BeLike "one of its settings can't be read safely (A VBS lock value has an unsupported value*)"
    }

    It 'names the policy first when a lock is set too, as the change itself does' {
        Set-TestDword -Path $script:policyPath -Name 'EnableVirtualizationBasedSecurity' -Value 1
        Set-TestDword -Path $script:deviceGuardPath -Name 'Locked' -Value 1

        Test-VantaVbsChange -State Disable -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath |
            Should -BeLike 'policy under*'
    }

    It 'only reads' {
        Test-VantaVbsChange -State Disable -DeviceGuardPath $script:deviceGuardPath -PolicyPath $script:policyPath | Out-Null

        Test-Path -LiteralPath $script:deviceGuardPath | Should -BeFalse
        Test-Path -LiteralPath $script:policyPath | Should -BeFalse
    }
}

Describe 'Get-VantaVbsConfiguration' {
    It 'reports the current provider state with readable names' {
        Mock Get-CimInstance -ModuleName Vanta.Security -MockWith {
            [pscustomobject]@{
                VirtualizationBasedSecurityStatus = 2
                SecurityServicesConfigured        = @(1, 2, 7)
                SecurityServicesRunning           = @(2)
                RequiredSecurityProperties        = @(0)
                AvailableSecurityProperties       = @(1, 2, 8, 99)
            }
        }

        $report = Get-VantaVbsConfiguration
        $report.VbsStatus | Should -BeExactly 'Enabled and running'
        @($report.ConfiguredServices) | Should -Be @(
            'Credential Guard'
            'Memory integrity (HVCI)'
            'Hypervisor-Enforced Paging Translation'
        )
        @($report.RunningServices) | Should -Be @('Memory integrity (HVCI)')
        @($report.RequiredProperties) | Should -Be @('None')
        @($report.AvailableProperties) | Should -Be @(
            'Base virtualization support'
            'Secure Boot'
            'APIC virtualization'
            'Unknown (99)'
        )
        Should -Invoke Get-CimInstance -ModuleName Vanta.Security -Times 1 -Exactly -ParameterFilter {
            $ClassName -ceq 'Win32_DeviceGuard' -and $Namespace -ceq 'root\Microsoft\Windows\DeviceGuard'
        }
    }

    It 'fails when the provider does not return exactly one instance' {
        Mock Get-CimInstance -ModuleName Vanta.Security -MockWith { @() }

        { Get-VantaVbsConfiguration } | Should -Throw '*exactly one Win32_DeviceGuard*'
    }
}

Describe 'Windows Defender state' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Security
        Mock Write-VantaStep -ModuleName Vanta.Security
        Mock Write-VantaNote -ModuleName Vanta.Security
        Mock Write-VantaWarning -ModuleName Vanta.Security
        Mock Wait-VantaContinue -ModuleName Vanta.Security
        Mock Get-VantaDefenderPackageInstaller -ModuleName Vanta.Security {
            [pscustomobject]@{ ScriptPath = 'C:\Windows\VantaModules\Scripts\Entry\Install-VantaPackage.ps1'; PowerShellPath = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' }
        }
        Mock Invoke-VantaDefenderPackageInstaller -ModuleName Vanta.Security { 0 }
        Mock Read-VantaDefenderMenuChoice -ModuleName Vanta.Security { throw 'the menu must not be shown' }
        Mock Get-VantaDefenderPackageNames -ModuleName Vanta.Security { @() }
        # The core service has its own tests; here it must never reach the PC.
        Mock Set-VantaDefenderCoreService -ModuleName Vanta.Security
    }

    It 'reports Enabled without the NoDefender package and Disabled with it' {
        Get-VantaDefenderState | Should -BeExactly 'Enabled'

        Mock Get-VantaDefenderPackageNames -ModuleName Vanta.Security { @('Z-Vanta-NoDefender-Package~amd64~~1.0.0.0') }
        Get-VantaDefenderState | Should -BeExactly 'Disabled'
    }

    It 'installs the NoDefender package silently to disable Defender' {
        Set-VantaDefenderState -State Disable -Silent

        Should -Invoke Invoke-VantaDefenderPackageInstaller -ModuleName Vanta.Security -Times 1 -Exactly -ParameterFilter {
            $Operation -ceq 'Install' -and $NoInteraction
        }
        Should -Invoke Wait-VantaContinue -ModuleName Vanta.Security -Times 0 -Exactly
        Should -Invoke Read-VantaDefenderMenuChoice -ModuleName Vanta.Security -Times 0 -Exactly
    }

    It 'confirms interactively and removes the package to enable Defender' {
        Mock Get-VantaDefenderPackageNames -ModuleName Vanta.Security { @('Z-Vanta-NoDefender-Package~amd64~~1.0.0.0') }

        Set-VantaDefenderState -State Enable

        Should -Invoke Wait-VantaContinue -ModuleName Vanta.Security -Times 1 -Exactly
        Should -Invoke Write-VantaWarning -ModuleName Vanta.Security -Times 0 -Exactly
        Should -Invoke Invoke-VantaDefenderPackageInstaller -ModuleName Vanta.Security -Times 1 -Exactly -ParameterFilter {
            $Operation -ceq 'Uninstall' -and -not $NoInteraction
        }
    }

    It 'shows the menu for the current state and the warning, then returns the choice without changing anything' {
        Mock Read-VantaDefenderMenuChoice -ModuleName Vanta.Security { 'Disable' }

        Read-VantaDefenderStateChoice | Should -BeExactly 'Disable'

        Should -Invoke Read-VantaDefenderMenuChoice -ModuleName Vanta.Security -Times 1 -Exactly -ParameterFilter {
            $CurrentState -ceq 'Enabled'
        }
        Should -Invoke Write-VantaWarning -ModuleName Vanta.Security -Times 1 -Exactly
        Should -Invoke Wait-VantaContinue -ModuleName Vanta.Security -Times 1 -Exactly
        Should -Invoke Invoke-VantaDefenderPackageInstaller -ModuleName Vanta.Security -Times 0 -Exactly
    }

    It 'changes nothing when Defender is already in the requested state' {
        Set-VantaDefenderState -State Enable -Silent

        Should -Invoke Invoke-VantaDefenderPackageInstaller -ModuleName Vanta.Security -Times 0 -Exactly
        Should -Invoke Write-VantaLog -ModuleName Vanta.Security -Times 1 -Exactly -ParameterFilter {
            $Message -like '*already enabled*'
        }
    }

    It 'propagates a failing package installer exit code' {
        Mock Invoke-VantaDefenderPackageInstaller -ModuleName Vanta.Security { 7 }

        { Set-VantaDefenderState -State Disable -Silent } | Should -Throw '*Package installation failed with exit code 7*'
        Should -Invoke Set-VantaDefenderCoreService -ModuleName Vanta.Security -Times 0 -Exactly
    }

    It 'turns the core service off only after the package removed Defender' {
        $script:defenderOrder = [Collections.Generic.List[string]]::new()
        Mock Invoke-VantaDefenderPackageInstaller -ModuleName Vanta.Security { $script:defenderOrder.Add("package:$Operation"); 0 }
        Mock Set-VantaDefenderCoreService -ModuleName Vanta.Security { $script:defenderOrder.Add("core:$State") }

        Set-VantaDefenderState -State Disable -Silent

        @($script:defenderOrder) | Should -Be @('package:Install', 'core:Removed')
    }

    It 'puts the core service back before the package comes off, while Defender is still removed' {
        $script:defenderOrder = [Collections.Generic.List[string]]::new()
        Mock Get-VantaDefenderPackageNames -ModuleName Vanta.Security { @('Z-Vanta-NoDefender-Package~amd64~~1.0.0.0') }
        Mock Invoke-VantaDefenderPackageInstaller -ModuleName Vanta.Security { $script:defenderOrder.Add("package:$Operation"); 0 }
        Mock Set-VantaDefenderCoreService -ModuleName Vanta.Security { $script:defenderOrder.Add("core:$State") }

        Set-VantaDefenderState -State Enable -Silent

        @($script:defenderOrder) | Should -Be @('core:Restored', 'package:Uninstall')
    }

    It 'leaves the core service alone when Defender is already in the requested state' {
        Set-VantaDefenderState -State Enable -Silent

        Should -Invoke Set-VantaDefenderCoreService -ModuleName Vanta.Security -Times 0 -Exactly
    }
}

Describe 'Set-VantaDefenderCoreService' {
    BeforeAll {
        $script:coreServicePath = "$script:testRoot\MDCoreSvc"
    }

    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Security
        # The New-ScheduledTask* constructors only build the task's objects; registering
        # it is the one call that would reach the scheduler.
        $script:registeredTasks = [Collections.Generic.List[object]]::new()
        Mock Register-ScheduledTask -ModuleName Vanta.Security {
            $script:registeredTasks.Add([pscustomobject]@{
                    TaskName = $TaskName; Principal = $Principal; Action = $Action; Trigger = $Trigger; Force = $Force
                })
        }
        Mock Remove-VantaScheduledTask -ModuleName Vanta.Security
        Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'defers MDCoreSvc disable to a SYSTEM task that records state before self-deleting' {
        Set-VantaDefenderCoreService -State Removed -ServicePath $script:coreServicePath

        @($script:registeredTasks).Count | Should -Be 1
        $script:registered = $script:registeredTasks[0]
        $script:registered.TaskName | Should -BeExactly 'VantaDisableMDCoreSvc'
        $script:registered.Force | Should -BeTrue
        $script:registered.Principal.UserId | Should -BeExactly 'SYSTEM'
        @($script:registered.Trigger)[0].CimClass.CimClassName | Should -BeExactly 'MSFT_TaskBootTrigger'
        $script:registered.Action.Execute | Should -BeExactly 'cmd'

        $argument = [string]$script:registered.Action.Arguments
        $regAddIndex = $argument.IndexOf(
            'reg add "HKLM\SYSTEM\CurrentControlSet\Services\MDCoreSvc"',
            [StringComparison]::Ordinal
        )
        $deleteIndex = $argument.IndexOf(
            "schtasks /delete /tn `"$($script:registered.TaskName)`"",
            [StringComparison]::Ordinal
        )
        $regAddIndex | Should -BeGreaterThan -1
        $deleteIndex | Should -BeGreaterThan $regAddIndex
        $argument.Substring($regAddIndex, $deleteIndex - $regAddIndex) | Should -Match '&&'
        Should -Invoke Remove-VantaScheduledTask -ModuleName Vanta.Security -Times 0 -Exactly
        Test-Path -LiteralPath $script:coreServicePath | Should -BeFalse
    }

    It 'drops a pending removal task and puts back the automatic start a removal turned off' {
        Set-TestDword -Path $script:coreServicePath -Name 'Start' -Value 4

        Set-VantaDefenderCoreService -State Restored -ServicePath $script:coreServicePath

        Should -Invoke Remove-VantaScheduledTask -ModuleName Vanta.Security -Times 1 -Exactly -ParameterFilter {
            $Path -ceq '\VantaDisableMDCoreSvc' -and $IgnoreMissing
        }
        $start = Get-TestValueState -Path $script:coreServicePath -Name 'Start'
        $start.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::DWord)
        $start.Value | Should -Be 2
        @($script:registeredTasks).Count | Should -Be 0
    }

    It 'leaves a start type that Vanta didn''t turn off: <Case>' -ForEach @(
        @{ Case = 'manual start'; Value = 3 }
        @{ Case = 'automatic start'; Value = 2 }
    ) {
        Set-TestDword -Path $script:coreServicePath -Name 'Start' -Value $Value

        Set-VantaDefenderCoreService -State Restored -ServicePath $script:coreServicePath

        (Get-TestValueState -Path $script:coreServicePath -Name 'Start').Value | Should -Be $Value
    }

    It 'changes nothing on a Windows without the core service' {
        { Set-VantaDefenderCoreService -State Restored -ServicePath $script:coreServicePath } | Should -Not -Throw

        Test-Path -LiteralPath $script:coreServicePath | Should -BeFalse
        Should -Invoke Remove-VantaScheduledTask -ModuleName Vanta.Security -Times 1 -Exactly
    }
}

Describe 'Test-VantaDefenderCoreServiceRemoved' {
    BeforeAll {
        $script:coreServicePath = "$script:testRoot\MDCoreSvc"
    }

    BeforeEach {
        $script:coreTaskState = 'Missing'
        Mock Get-VantaScheduledTaskState -ModuleName Vanta.Security { $script:coreTaskState }
        Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'has nothing to do on a Windows without the core service' {
        Test-VantaDefenderCoreServiceRemoved -ServicePath $script:coreServicePath | Should -BeTrue

        Should -Invoke Get-VantaScheduledTaskState -ModuleName Vanta.Security -Times 0 -Exactly
        Test-Path -LiteralPath $script:coreServicePath | Should -BeFalse
    }

    It 'has nothing to do once the service is off' {
        Set-TestDword -Path $script:coreServicePath -Name 'Start' -Value 4

        Test-VantaDefenderCoreServiceRemoved -ServicePath $script:coreServicePath | Should -BeTrue

        Should -Invoke Get-VantaScheduledTaskState -ModuleName Vanta.Security -Times 0 -Exactly
    }

    It 'gives <Expected> for a service that still starts (<Start>) while the task is <Task>' -ForEach @(
        @{ Start = 2; Task = 'Missing'; Expected = $false }
        @{ Start = 3; Task = 'Disabled'; Expected = $false }
        @{ Start = 2; Task = 'Enabled'; Expected = $true }
    ) {
        Set-TestDword -Path $script:coreServicePath -Name 'Start' -Value $Start
        $script:coreTaskState = $Task

        Test-VantaDefenderCoreServiceRemoved -ServicePath $script:coreServicePath | Should -Be $Expected

        Should -Invoke Get-VantaScheduledTaskState -ModuleName Vanta.Security -Times 1 -Exactly -ParameterFilter {
            $Path -ceq '\VantaDisableMDCoreSvc'
        }
        (Get-TestValueState -Path $script:coreServicePath -Name 'Start').Value | Should -Be $Start
    }
}

Describe 'Windows Defender package installer boundary' {
    It 'resolves the installer only beneath the Vanta modules root' {
        $script:defenderModulesRoot = Join-Path $TestDrive 'VantaModules'
        $entryRoot = New-Item -ItemType Directory -Path (Join-Path $script:defenderModulesRoot 'Scripts\Entry') -Force
        $expectedScript = Join-Path $entryRoot.FullName 'Install-VantaPackage.ps1'
        Mock Get-VantaContext -ModuleName Vanta.Security { [pscustomobject]@{ VantaModulesPath = $script:defenderModulesRoot } }

        { InModuleScope Vanta.Security { Get-VantaDefenderPackageInstaller } } | Should -Throw '*Install-VantaPackage.ps1*missing*'

        Set-Content -LiteralPath $expectedScript -Value '' -Encoding Ascii
        $installer = InModuleScope Vanta.Security { Get-VantaDefenderPackageInstaller }
        $installer.ScriptPath | Should -BeExactly $expectedScript
        [IO.File]::Exists($installer.PowerShellPath) | Should -BeTrue
    }

    It 'runs the installer through Windows PowerShell with the package pattern and returns its exit code' {
        $script:defenderCallRecord = Join-Path $TestDrive 'installer-call.txt'
        $fakeInstaller = Join-Path $TestDrive 'Install-VantaPackage.ps1'
        @"
param([string[]]`$InstallPackages, [string[]]`$UninstallPackages, [switch]`$NoInteraction)
Set-Content -LiteralPath '$script:defenderCallRecord' -Value @(
    "install=`$(`$InstallPackages -join '|')"
    "uninstall=`$(`$UninstallPackages -join '|')"
    "nointeraction=`$NoInteraction"
)
exit 3
"@ | Set-Content -LiteralPath $fakeInstaller -Encoding UTF8
        $installer = [pscustomobject]@{
            ScriptPath     = $fakeInstaller
            PowerShellPath = Join-Path $PSHOME 'powershell.exe'
        }

        $exitCode = InModuleScope Vanta.Security {
            Invoke-VantaDefenderPackageInstaller -Operation Uninstall -Installer $i -NoInteraction
        } -Parameters @{ i = $installer }

        $exitCode | Should -Be 3
        Get-Content -LiteralPath $script:defenderCallRecord | Should -Be @(
            'install='
            'uninstall=*Z-[AV]*-NoDefender-Package*'
            'nointeraction=True'
        )
    }

    It 'returns only the exit code of a silent installer that prints, and logs what it printed' {
        Mock Write-VantaLog -ModuleName Vanta.Security
        $fakeInstaller = Join-Path $TestDrive 'Install-VantaPackage-Printing.ps1'
        @(
            'param([string[]]$InstallPackages, [string[]]$UninstallPackages, [switch]$NoInteraction)'
            "Write-Host ''"
            "Write-Host 'The package change completed.'"
            "Write-Output 'pipeline line'"
            "[Console]::Error.WriteLine('stderr line')"
            'exit 0'
        ) | Set-Content -LiteralPath $fakeInstaller -Encoding UTF8
        $installer = [pscustomobject]@{ ScriptPath = $fakeInstaller; PowerShellPath = Join-Path $PSHOME 'powershell.exe' }

        # The toggle engine runs companions with Stop, under which redirected stderr throws.
        $exitCode = InModuleScope Vanta.Security {
            $ErrorActionPreference = 'Stop'
            Invoke-VantaDefenderPackageInstaller -Operation Install -Installer $i -NoInteraction
        } -Parameters @{ i = $installer }

        ($exitCode -is [int]) | Should -BeTrue
        $exitCode | Should -Be 0
        foreach ($line in @('The package change completed.', 'pipeline line', 'stderr line')) {
            Should -Invoke Write-VantaLog -ModuleName Vanta.Security -Times 1 -Exactly -ParameterFilter {
                $Message -ceq "Package installer: $line"
            }
        }
    }

    It 'completes a silent Defender change whose installer prints before it exits 0' {
        Mock Write-VantaLog -ModuleName Vanta.Security
        Mock Get-VantaDefenderPackageNames -ModuleName Vanta.Security { @() }
        Mock Set-VantaDefenderCoreService -ModuleName Vanta.Security
        $script:printingInstaller = Join-Path $TestDrive 'Install-VantaPackage-Done.ps1'
        @(
            'param([string[]]$InstallPackages, [string[]]$UninstallPackages, [switch]$NoInteraction)'
            "Write-Host ''"
            "Write-Host 'The package change completed.'"
            'exit 0'
        ) | Set-Content -LiteralPath $script:printingInstaller -Encoding UTF8
        Mock Get-VantaDefenderPackageInstaller -ModuleName Vanta.Security {
            [pscustomobject]@{ ScriptPath = $script:printingInstaller; PowerShellPath = Join-Path $PSHOME 'powershell.exe' }
        }

        { Set-VantaDefenderState -State Disable -Silent } | Should -Not -Throw
        Should -Invoke Write-VantaLog -ModuleName Vanta.Security -Times 1 -Exactly -ParameterFilter {
            $Message -like 'Windows Defender Disable requested*'
        }
    }

    It 'gives an interactive installer the console and returns its exit code' {
        $callRecord = Join-Path $TestDrive 'interactive-installer-call.txt'
        $fakeInstaller = Join-Path $TestDrive 'Install-VantaPackage-Interactive.ps1'
        # What it prints must reach the console, not join the returned exit code.
        @"
param([string[]]`$InstallPackages, [string[]]`$UninstallPackages, [switch]`$NoInteraction)
Set-Content -LiteralPath '$callRecord' -Value @(
    "install=`$(`$InstallPackages -join '|')"
    "nointeraction=`$NoInteraction"
)
Write-Host 'Restart now? ' -NoNewline
Write-Output 'pipeline line'
exit 5
"@ | Set-Content -LiteralPath $fakeInstaller -Encoding UTF8
        $installer = [pscustomobject]@{ ScriptPath = $fakeInstaller; PowerShellPath = Join-Path $PSHOME 'powershell.exe' }

        $exitCode = InModuleScope Vanta.Security {
            Invoke-VantaDefenderPackageInstaller -Operation Install -Installer $i
        } -Parameters @{ i = $installer }

        ($exitCode -is [int]) | Should -BeTrue
        $exitCode | Should -Be 5
        Get-Content -LiteralPath $callRecord | Should -Be @(
            'install=*Z-[AV]*-NoDefender-Package*'
            'nointeraction=False'
        )
    }
}

Describe 'Repair-VantaWindowsTempPermissions' {
    BeforeAll {
        # What each rule grants, not the SDDL text: on CI's runner, signed in as the
        # built-in Administrator, a descendant's inherited rule came back marked explicit
        # with the same access. A write that reached descendants would change the grants.
        function Get-AccessGrant([string]$Path) {
            @((Get-Acl -LiteralPath $Path).Access | ForEach-Object {
                    '{0}|{1}|{2}|{3}|{4}' -f $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value,
                    [int]$_.FileSystemRights, $_.AccessControlType, $_.InheritanceFlags, $_.PropagationFlags
                } | Sort-Object)
        }
    }

    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Security
    }

    AfterEach {
        # The default TEMP rule set grants the test user no read access; hand the
        # directory back to the current user so the test drive can be cleaned.
        if ($script:aclTarget -and (Test-Path -LiteralPath $script:aclTarget)) {
            $acl = Get-Acl -LiteralPath $script:aclTarget
            $acl.SetAccessRuleProtection($false, $false)
            foreach ($rule in @($acl.Access)) {
                [void]$acl.RemoveAccessRuleSpecific($rule)
            }
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
                        [Security.Principal.WindowsIdentity]::GetCurrent().User,
                        [Security.AccessControl.FileSystemRights]::FullControl,
                        ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),
                        [Security.AccessControl.PropagationFlags]::None,
                        [Security.AccessControl.AccessControlType]::Allow)))
            (New-Object IO.DirectoryInfo($script:aclTarget)).SetAccessControl($acl)
            $script:aclTarget = $null
        }
    }

    It 'replaces only the directory DACL, with exactly the four default TEMP rules' {
        $target = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'TempRoot') -Force
        $script:aclTarget = $target.FullName
        $subdirectory = New-Item -ItemType Directory -Path (Join-Path $target.FullName 'existing') -Force
        $descendants = @(
            (New-Item -ItemType File -Path (Join-Path $target.FullName 'existing.txt') -Force).FullName
            $subdirectory.FullName
            (New-Item -ItemType File -Path (Join-Path $subdirectory.FullName 'nested.txt') -Force).FullName
        )
        $descendantGrants = @($descendants | ForEach-Object { , (Get-AccessGrant $_) })

        InModuleScope Vanta.Security { Set-VantaWindowsTempRootAcl -Path $p } -Parameters @{ p = $target.FullName }

        $acl = Get-Acl -LiteralPath $target.FullName
        $acl.AreAccessRulesProtected | Should -BeTrue
        $rules = @($acl.Access)
        $rules.Count | Should -Be 4
        @($rules | ForEach-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } | Sort-Object) |
            Should -Be @('S-1-3-0', 'S-1-5-18', 'S-1-5-32-544', 'S-1-5-32-545')
        $users = $rules | Where-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -ceq 'S-1-5-32-545' }
        [int]$users.FileSystemRights | Should -Be ([int](
                [Security.AccessControl.FileSystemRights]::Synchronize -bor
                [Security.AccessControl.FileSystemRights]::WriteData -bor
                [Security.AccessControl.FileSystemRights]::AppendData -bor
                [Security.AccessControl.FileSystemRights]::ExecuteFile))
        $users.InheritanceFlags | Should -Be ([Security.AccessControl.InheritanceFlags]::ContainerInherit)
        $creatorOwner = $rules | Where-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -ceq 'S-1-3-0' }
        $creatorOwner.PropagationFlags | Should -Be ([Security.AccessControl.PropagationFlags]::InheritOnly)
        # Descendants keep their own DACLs: rewriting them would be the privileged walk of a
        # user-writable tree that the repair avoids. The repair is also idempotent.
        foreach ($index in 0..($descendants.Count - 1)) {
            Get-AccessGrant $descendants[$index] | Should -Be $descendantGrants[$index] -Because $descendants[$index]
        }
        { InModuleScope Vanta.Security { Set-VantaWindowsTempRootAcl -Path $p } -Parameters @{ p = $target.FullName } } |
            Should -Not -Throw
    }

    It 'keeps the Windows reason when the TEMP DACL cannot be written' {
        Initialize-VantaNativeType
        $security = New-Object Security.AccessControl.DirectorySecurity
        $security.SetAccessRuleProtection($true, $false)
        $missing = Join-Path $TestDrive 'missing\nested'

        { [Vanta.Native.DirectoryDacl]::SetProtected($missing, $security) } |
            Should -Throw "*Setting the DACL of '$([WildcardPattern]::Escape($missing))' failed: *(Win32 error 3).*"
    }

    It 'requires Administrator rights before touching the Windows TEMP directory' {
        Mock Assert-VantaPrivilege -ModuleName Vanta.Security { throw '[privilege] This operation requires Administrator rights.' }
        Mock Set-VantaWindowsTempRootAcl -ModuleName Vanta.Security

        { Repair-VantaWindowsTempPermissions } | Should -Throw '*requires Administrator*'

        Should -Invoke Set-VantaWindowsTempRootAcl -ModuleName Vanta.Security -Times 0 -Exactly
    }

    It 'repairs exactly the fixed Windows TEMP root' {
        Mock Assert-VantaPrivilege -ModuleName Vanta.Security
        Mock Set-VantaWindowsTempRootAcl -ModuleName Vanta.Security

        Repair-VantaWindowsTempPermissions

        $expected = Join-Path ([Environment]::GetFolderPath('Windows')) 'Temp'
        Should -Invoke Set-VantaWindowsTempRootAcl -ModuleName Vanta.Security -Times 1 -Exactly -ParameterFilter {
            $Path -eq $expected
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Security -Times 1 -Exactly
    }
}

Describe 'Security toggle companions' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Toggles
        Mock Write-VantaNote -ModuleName Vanta.Toggles
        Mock Write-VantaStep -ModuleName Vanta.Toggles
        Mock Import-VantaModule -ModuleName Vanta.Toggles
    }

    It 'ToggleDefender asks for the state only in an interactive administrator window' {
        Mock Set-VantaDefenderState -ModuleName Vanta.Toggles
        Mock Read-VantaDefenderStateChoice -ModuleName Vanta.Toggles { 'Disable' }

        Invoke-CompanionFunction -Definition $script:ToggleDefender -FunctionName 'Select-VantaDefenderToggleState' `
            -Toggle (New-ToggleContext -Name 'ToggleDefender' -State 'Run' -Silent $false) | Should -BeExactly 'Disable'
        { Invoke-CompanionFunction -Definition $script:ToggleDefender -FunctionName 'Select-VantaDefenderToggleState' `
                -Toggle (New-ToggleContext -Name 'ToggleDefender' -State 'Run' -Silent $true) } |
            Should -Throw '*interactive window*'
        Should -Invoke Set-VantaDefenderState -ModuleName Vanta.Toggles -Times 0 -Exactly
    }

    It 'ToggleDefender applies the chosen <Chosen> state silently inside the broker, then records <Option>' -TestCases @(
        @{ Chosen = 'Disable'; Companion = 'Disable-VantaDefenderToggle'; Option = 'defender-disable' }
        @{ Chosen = 'Enable'; Companion = 'Enable-VantaDefenderToggle'; Option = 'defender-enable' }
    ) {
        $script:defenderOrder = [Collections.Generic.List[string]]::new()
        Mock Set-VantaDefenderState -ModuleName Vanta.Toggles { $script:defenderOrder.Add('state') }
        Mock Set-VantaStateChoice -ModuleName Vanta.Toggles { $script:defenderOrder.Add("choice:$Option") }
        $script:defenderState = $Chosen

        Invoke-CompanionFunction -Definition $script:ToggleDefender -FunctionName $Companion `
            -Toggle (New-ToggleContext -Name 'ToggleDefender' -State $Chosen -Silent $true)
        Should -Invoke Set-VantaDefenderState -ModuleName Vanta.Toggles -Times 1 -Exactly
        Should -Invoke Set-VantaDefenderState -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Silent -and $State -ceq $script:defenderState
        }
        @($script:defenderOrder) | Should -Be @('state', "choice:$Option")
        Should -Invoke Set-VantaStateChoice -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter { -not $Absent }
    }

    It 'ToggleDefender records nothing when the package change fails' {
        Mock Set-VantaDefenderState -ModuleName Vanta.Toggles { throw 'Package installation failed with exit code 7.' }
        Mock Set-VantaStateChoice -ModuleName Vanta.Toggles

        { Invoke-CompanionFunction -Definition $script:ToggleDefender -FunctionName 'Disable-VantaDefenderToggle' `
                -Toggle (New-ToggleContext -Name 'ToggleDefender' -State 'Disable' -Silent $true) } |
            Should -Throw '*exit code 7*'
        Should -Invoke Set-VantaStateChoice -ModuleName Vanta.Toggles -Times 0 -Exactly
    }

    It 'ToggleDefender still succeeds, with a warning, when Defender changed but the record can''t be written' {
        Mock Set-VantaDefenderState -ModuleName Vanta.Toggles
        Mock Set-VantaStateChoice -ModuleName Vanta.Toggles { throw 'Timed out waiting for the Vanta state-document lock.' }

        { Invoke-CompanionFunction -Definition $script:ToggleDefender -FunctionName 'Enable-VantaDefenderToggle' `
                -Toggle (New-ToggleContext -Name 'ToggleDefender' -State 'Enable' -Silent $true) } |
            Should -Not -Throw
        Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -like "Couldn't record 'defender-enable'*lock*"
        }
    }

    It 'VbsState replays <State> only while <Case>' -ForEach @(
        @{ State = 'Disable'; Case = 'nothing on the PC refuses it'; Reason = $null; Expected = $true; Log = $null }
        @{ State = 'Disable'; Case = 'policy controls VBS'; Reason = "policy under 'HKLM:\x' controls it (EnableVirtualizationBasedSecurity = 1)"; Expected = $false
            Log = "VBS can't be turned off: policy under 'HKLM:\x' controls it (EnableVirtualizationBasedSecurity = 1)." }
        @{ State = 'Enable'; Case = 'policy controls VBS'; Reason = "policy under 'HKLM:\x' controls it (EnableVirtualizationBasedSecurity = 0)"; Expected = $false
            Log = "VBS can't be turned on: policy under 'HKLM:\x' controls it (EnableVirtualizationBasedSecurity = 0)." }
    ) {
        $script:vbsReason = $Reason
        $script:vbsRequested = $State
        $script:vbsLog = $Log
        Mock Test-VantaVbsChange -ModuleName Vanta.Toggles { $script:vbsReason }

        Invoke-CompanionFunction -Definition $script:VbsState -FunctionName 'Test-VantaVbsStateReplayApplicable' `
            -Toggle (New-ToggleContext -Name 'VbsState' -State $State) | Should -Be $Expected
        Should -Invoke Test-VantaVbsChange -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter { $State -ceq $script:vbsRequested }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times ([int](-not $Expected)) -Exactly -ParameterFilter {
            $Message -ceq $script:vbsLog
        }
    }

    It 'VbsState declares the replay check for both of its states' {
        foreach ($stateName in @('Disable', 'Enable')) {
            [string]$script:VbsState['States'][$stateName]['ReplayApplicable'] |
                Should -BeExactly 'Test-VantaVbsStateReplayApplicable' -Because $stateName
        }
    }

    Context 'an update replaying a recorded VbsState choice' {
        BeforeAll {
            $script:vbsReplayRoot = "$script:testRoot\VbsReplay\Services"
        }

        BeforeEach {
            Mock Assert-VantaPrivilege -ModuleName Vanta.Toggles
            Mock Set-VantaVbsConfiguration -ModuleName Vanta.Toggles
            Remove-Item -Path "$script:testRoot\VbsReplay" -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -Path "$script:vbsReplayRoot\VbsState" -Force | Out-Null
            New-ItemProperty -LiteralPath "$script:vbsReplayRoot\VbsState" -Name 'state' -Value 0 -PropertyType DWord | Out-Null
        }

        AfterEach {
            Remove-Item -Path "$script:testRoot\VbsReplay" -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'clears a record that a UEFI lock now refuses, instead of failing the update' {
            Mock Test-VantaVbsChange -ModuleName Vanta.Toggles { "a UEFI lock protects it, and a registry change can't turn it off" }

            { Invoke-VantaToggleReapply -StateRoot $script:vbsReplayRoot -TogglesRoot $script:ShippedTogglesRoot } | Should -Not -Throw

            Should -Invoke Set-VantaVbsConfiguration -ModuleName Vanta.Toggles -Times 0 -Exactly
            Get-VantaToggleState -Name VbsState -StateRoot $script:vbsReplayRoot | Should -BeNullOrEmpty
            Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
                $Message -like "Toggle 'VbsState' state 'Disable' is no longer applicable.*"
            }
        }

        It 'replays and keeps a record nothing refuses' {
            Mock Test-VantaVbsChange -ModuleName Vanta.Toggles { $null }

            Invoke-VantaToggleReapply -StateRoot $script:vbsReplayRoot -TogglesRoot $script:ShippedTogglesRoot

            Should -Invoke Set-VantaVbsConfiguration -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
                $State -ceq 'Disable' -and -not $SkipWhenPolicyConflicts
            }
            (Get-VantaToggleState -Name VbsState -StateRoot $script:vbsReplayRoot).State | Should -Be 0
        }
    }

    It 'ToggleDefender refuses a silent request for its public state, which has no choice to apply' {
        Mock Set-VantaDefenderState -ModuleName Vanta.Toggles

        { Invoke-CompanionFunction -Definition $script:ToggleDefender -FunctionName 'Invoke-VantaDefenderToggle' `
                -Toggle (New-ToggleContext -Name 'ToggleDefender' -State 'Run' -Silent $true) } |
            Should -Throw '*interactive window*'
        Should -Invoke Set-VantaDefenderState -ModuleName Vanta.Toggles -Times 0 -Exactly
    }

    It 'FixErrors2502and2503 explains the repair in the administrator window before the silent broker runs' {
        $selector = [string]$script:FixErrors2502and2503['States']['Run']['InteractiveState']
        $selector | Should -BeExactly 'Show-VantaWindowsTempRepairNote' `
            -Because 'the repair runs in the silent TrustedInstaller broker, so only an InteractiveState can show the note'
        Invoke-CompanionFunction -Definition $script:FixErrors2502and2503 -FunctionName $selector `
            -Toggle (New-ToggleContext -Name 'FixErrors2502and2503' -State 'Run' -Silent $false) | Should -BeExactly 'Run'
        Should -Invoke Write-VantaNote -ModuleName Vanta.Toggles -Times 1 -Exactly
        { Invoke-CompanionFunction -Definition $script:FixErrors2502and2503 -FunctionName $selector `
                -Toggle (New-ToggleContext -Name 'FixErrors2502and2503' -State 'Run' -Silent $true) } |
            Should -Throw '*interactive window*'
    }
}

Describe 'disable-core-isolation install tweak' {
    It 'runs only when the user chose it' {
        (Import-PowerShellDataFile -LiteralPath $script:TweakPath).Option | Should -BeExactly 'disable-core-isolation' `
            -Because 'without the option gate every install would turn off VBS and memory integrity'
    }

    It 'finishes without changes when policy keeps VBS on' {
        Mock Assert-VantaPrivilege -ModuleName Vanta.Security
        Mock Write-VantaLog -ModuleName Vanta.Security
        Mock Import-VantaModule {}
        Mock Get-VantaContext { [pscustomobject]@{ IsUpgrade = $false } }
        Mock Get-VantaVbsDwordState -ModuleName Vanta.Security -ParameterFilter { $Name -eq 'EnableVirtualizationBasedSecurity' } {
            [pscustomobject]@{ Exists = $Path -like '*Policies*'; Value = 1 }
        }
        Mock Set-VantaRegistryValue -ModuleName Vanta.Security { throw 'The tweak wrote a value.' }

        & ($script:TweakPath -replace '\.psd1$', '.ps1')

        Should -Invoke Write-VantaLog -ModuleName Vanta.Security -ParameterFilter { $Level -eq 'Warning' }
    }

    It 'keeps a VBS choice recorded since the install on an update, but not on a fresh install: upgrade=<Upgrade>' -ForEach @(
        @{ Upgrade = $true; Expected = 0; ExpectedLog = 1 }
        @{ Upgrade = $false; Expected = 1; ExpectedLog = 0 }
    ) {
        Mock Import-VantaModule {}
        Mock Get-VantaContext { [pscustomobject]@{ IsUpgrade = $Upgrade } }
        # Enable VBS.cmd was run after installing with VBS off. Only the VbsState record
        # exists, so a lookup under any other name finds nothing.
        Mock Get-VantaToggleState { $null }
        Mock Get-VantaToggleState -ParameterFilter { $Name -ceq 'VbsState' } {
            [pscustomobject]@{ Name = 'VbsState'; State = 1 }
        }
        Mock Write-VantaLog {}
        Mock Set-VantaVbsConfiguration {}

        & ($script:TweakPath -replace '\.psd1$', '.ps1')

        Should -Invoke Set-VantaVbsConfiguration -Times $Expected -Exactly
        Should -Invoke Set-VantaVbsConfiguration -Times $Expected -Exactly -ParameterFilter {
            $State -ceq 'Disable' -and $SkipWhenPolicyConflicts
        }
        Should -Invoke Write-VantaLog -Times $ExpectedLog -Exactly -ParameterFilter {
            $Message -like '*recorded VbsState choice*'
        }
    }

    It 'disables VBS on an update when no VbsState choice is recorded' {
        Mock Import-VantaModule {}
        Mock Get-VantaContext { [pscustomobject]@{ IsUpgrade = $true } }
        Mock Get-VantaToggleState { $null }
        Mock Set-VantaVbsConfiguration {}

        & ($script:TweakPath -replace '\.psd1$', '.ps1')

        Should -Invoke Set-VantaVbsConfiguration -Times 1 -Exactly -ParameterFilter {
            $State -ceq 'Disable' -and $SkipWhenPolicyConflicts
        }
    }
}
