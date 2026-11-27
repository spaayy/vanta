BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $modulesRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\package\Executables\VantaModules\Scripts\Modules'
    Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Registry\Vanta.Registry.psd1') -Force
    Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Tweaks\Vanta.Tweaks.psd1') -Force

    $script:testRoot = 'HKCU:\Software\VantaRewriteTest'

    function New-TestContextMock {
        param(
            [bool]$IsArm64 = $false,
            [bool]$IsUpgrade = $false,
            [int]$WindowsBuild = 26100,
            [bool]$IsInstallStateBacked = $false,
            [string]$InteractiveUserSid = 'S-1-5-21-1-2-3-1001'
        )

        [pscustomobject]@{
            WinDir           = 'C:\Windows'
            VantaModulesPath = 'C:\Windows\VantaModules'
            FlagsPath        = 'C:\Windows\VantaModules\Flags'
            LogsPath         = Join-Path -Path $TestDrive -ChildPath 'Logs'
            IsArm64          = $IsArm64
            WindowsBuild     = $WindowsBuild
            IsUpgrade        = $IsUpgrade
            IsInstallStateBacked = $IsInstallStateBacked
            InteractiveUserSid = $InteractiveUserSid
        }
    }
}

AfterAll {
    Remove-Item -Path 'HKCU:\Software\VantaRewriteTest' -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Test-VantaTweakSchema' {
    It 'accepts a fully-populated valid tweak' {
        $companion = Join-Path -Path $TestDrive -ChildPath 'companion.ps1'
        Set-Content -Path $companion -Value 'Write-Output "companion"'

        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'valid.psd1'
        @'
@{
    Name           = 'Valid Tweak'
    Description    = 'A tweak exercising every schema key.'
    Option         = 'defender-disable'
    Arch           = 'X64'
    OnUpgrade      = 'Both'
    MinBuild       = 22000
    MaxBuild       = 26200
    Registry       = @(
        @{ Path = 'HKLM:\SOFTWARE\Test'; Name = 'Value'; Type = 'DWord'; Data = 1; AllowOsProtected = $true }
        @{ Path = 'HKCU\Software\Test'; Name = 'Old'; Operation = 'Delete'; IgnoreErrors = $true; AllowOsProtected = $false }
        @{ Path = 'HKLM:\SOFTWARE\TestKey'; Operation = 'AddKey'; Arch = 'ARM64' }
        @{ Path = 'HKLM:\SOFTWARE\Marker'; Name = 'Flag'; Type = 'None' }
    )
    PostUserRegistryRefresh = 'ExplorerRefresh'
    Services       = @(
        @{ Name = 'TestSvc'; StartupType = 4; IgnoreErrors = $false }
        @{ Name = 'TestSvc'; Operation = 'Stop' }
    )
    ScheduledTasks = @(
        @{ Path = '\Microsoft\Windows\Test\Task'; Operation = 'Disable'; IgnoreErrors = $false }
    )
    Run            = @(
        @{ Exe = 'C:\Windows\System32\whoami.exe'; Args = @('/all'); Wait = $true; IgnoreErrors = $false }
        @{ Exe = '{windir}\System32\dism.exe'; Args = @('/Online'); AllowedExitCodes = @(0, 3010) }
    )
    RemovePaths    = @(
        @{ Path = '{windir}\Test'; Arch = 'X64'; IgnoreErrors = $false }
    )
    Script         = 'companion.ps1'
}
'@ | Set-Content -Path $tweakFile

        $problems = @(Test-VantaTweakSchema -Path $tweakFile)
        $problems | Should -BeNullOrEmpty
    }

    It 'reports Oobe as an unknown top-level key' {
        $companion = Join-Path -Path $TestDrive -ChildPath 'oobe-companion.ps1'
        Set-Content -Path $companion -Value 'Write-Output "companion"'
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'oobe-gate.psd1'
        @'
@{
    Name   = 'Per-user companion'
    Oobe   = $false
    RunAs  = 'User'
    Script = 'oobe-companion.ps1'
}
'@ | Set-Content -Path $tweakFile

        $problems = @(Test-VantaTweakSchema -Path $tweakFile)
        @($problems | ForEach-Object { $_.Problem }) | Should -Be @("Unknown top-level key 'Oobe'.")
    }

    It 'reports problems for an invalid tweak' {
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'invalid.psd1'
        @'
@{
    Description = 'No name, bad option, broken entries.'
    Option      = 'not-a-real-option'
    Arch        = 'X86'
    OnUpgrade   = 'Sometimes'
    RunAs       = 'UserElevated'
    MinBuild    = 'notanumber'
    Bogus       = $true
    PostUserRegistryRefresh = 'explorerrefresh'
    Registry    = @(
        @{ Name = 'MissingPath'; Type = 'DWord'; Data = 1 }
        @{ Path = 'HKLM:\SOFTWARE\Test'; Name = 'BadType'; Type = 'SuperString' }
        @{ Path = 'HKLM:\SOFTWARE\Test'; Name = 'NoData'; Type = 'DWord' }
        @{ Path = 'HKU\S-1-5-21-1-2-3-1001\Software\X'; Name = 'Value'; Type = 'DWord'; Data = 1 }
        @{ Path = 'HKXX\Software\X'; Operation = 'AddKey' }
        @{ Path = 'HKLM:\SOFTWARE\Test'; Name = 'Value'; Type = 'DWord'; Data = 1; Sneaky = $true }
    )
    Services    = @(
        @{ StartupType = 9; IgnoreErrors = 'yes' }
    )
    ScheduledTasks = @(
        @{ Path = '\Microsoft\Windows\Test\Task'; IgnoreErrors = 'yes' }
    )
    Run         = @(
        @{ Exe = 'C:\Windows\System32\whoami.exe'; Args = '/all'; AllowedExitCodes = @('0', 1641); RunAs = 'UserElevated' }
        @{ Exe = 'tool.exe'; RunAs = 'User'; Wait = $false; IgnoreErrors = $true }
    )
    RemovePaths = @(
        @{ Path = 'C:\Test'; IgnoreErrors = 'yes' }
    )
    Script      = 'does-not-exist.ps1'
}
'@ | Set-Content -Path $tweakFile

        $problems = @(Test-VantaTweakSchema -Path $tweakFile)
        $problemText = @($problems | ForEach-Object { $_.Problem }) -join "`n"

        $problemText | Should -Match "Unknown top-level key 'Bogus'"
        $problemText | Should -Match "Missing or empty 'Name'"
        $problemText | Should -Match "Unknown 'Option'"
        $problemText | Should -Match "'Arch' must be"
        $problemText | Should -Match "'OnUpgrade' must be"
        $problemText | Should -Match "'MinBuild' must be an integer"
        $problemText | Should -Match "'RunAs' must be 'User'"
        $problemText | Should -Match "'PostUserRegistryRefresh' must be exactly one of"
        $problemText | Should -Match 'requires at least one ambient HKCU Registry entry'
        $problemText | Should -Match 'Registry entry is missing its Path'
        $problemText | Should -Match 'targets an explicit user hive'
        $problemText | Should -Match "Registry entry path 'HKXX\\Software\\X' does not resolve"
        $problemText | Should -Match "Registry entry has an unknown key 'Sneaky'"
        $problemText | Should -Match "needs a Type"
        $problemText | Should -Match "is missing its Data"
        $problemText | Should -Match 'Service entry is missing its Name'
        $problemText | Should -Match 'integer StartupType between 0 and 4'
        $problemText | Should -Match "Service entry 'IgnoreErrors' must be a boolean"
        $problemText | Should -Match "ScheduledTasks entry 'IgnoreErrors' must be a boolean"
        $problemText | Should -Match "Run entry 'Args' must be an array"
        $problemText | Should -Match "AllowedExitCodes.*unique integer exit-code set"
        $problemText | Should -Match "AllowedExitCodes.*only supported for the exact.*dism\.exe"
        $problemText | Should -Match "Run entry has an unknown key 'RunAs'"
        $problemText | Should -Match "Run entry 'Wait' can only be"
        $problemText | Should -Match "RemovePaths entry 'IgnoreErrors' must be a boolean"
        $problemText | Should -Match 'does not exist next to the tweak file'
    }

    It 'reports a file that does not parse as a data file' {
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'broken.psd1'
        Set-Content -Path $tweakFile -Value '@{ Name = "Broken"; Code = (Get-Date) }'

        $problems = @(Test-VantaTweakSchema -Path $tweakFile)
        @($problems).Count | Should -BeGreaterThan 0
        $problems[0].Problem | Should -Match 'does not load'
    }

    It 'validates a directory recursively and skips the manifest' {
        $tweaksDir = Join-Path -Path $TestDrive -ChildPath 'TweaksDir\sub'
        New-Item -Path $tweaksDir -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path -Path $tweaksDir -ChildPath 'bad.psd1') -Value '@{ Description = "no name" }'
        Set-Content -Path (Join-Path -Path $TestDrive -ChildPath 'TweaksDir\tweaks.manifest.psd1') -Value '@{ Categories = @() }'

        $problems = @(Test-VantaTweakSchema -Path (Join-Path -Path $TestDrive -ChildPath 'TweaksDir'))
        @($problems).Count | Should -Be 1
        $problems[0].Path | Should -Match 'bad\.psd1$'
    }
}

Describe 'Included tweak definitions' {
    BeforeAll {
        $script:shippedTweaksRoot = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\package\Executables\VantaModules\Scripts\Tweaks')).Path
    }

    It 'every included tweak passes schema validation' {
        $problems = @(Test-VantaTweakSchema -Path $script:shippedTweaksRoot)
        $report = @($problems | ForEach-Object { "$($_.Path): $($_.Problem)" }) -join "`n"
        $report | Should -BeNullOrEmpty
    }

    # The schema checks only that a Toggle entry looks like a name and a state. A toggle
    # renamed or left without that state would fail the tweak's whole category during install,
    # and so would a state spelt in another case: the engine passes the tweak's spelling on,
    # and companions match it case-sensitively.
    It 'names an installed toggle state in every Toggle entry' {
        Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1')
        $togglesRoot = Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules\Toggles'
        $references = @(Get-ChildItem -LiteralPath $script:shippedTweaksRoot -Filter '*.psd1' -File -Recurse |
                Where-Object Name -cne 'tweaks.manifest.psd1' |
                ForEach-Object {
                    $slug = $_.FullName.Substring($script:shippedTweaksRoot.Length + 1) -replace '\\', '/' -replace '\.psd1$', ''
                    $tweak = Import-PowerShellDataFile -LiteralPath $_.FullName
                    foreach ($entry in @($tweak['Toggle'] | Where-Object { $null -ne $_ })) {
                        [pscustomobject]@{ Slug = $slug; Name = [string]$entry['Name']; State = [string]$entry['State'] }
                    }
                })

        $references.Count | Should -BeGreaterThan 0
        foreach ($reference in $references) {
            $because = "$($reference.Slug) applies toggle $($reference.Name) state $($reference.State)"
            try {
                $definition = Get-VantaToggleDefinition -Name $reference.Name -TogglesRoot $togglesRoot
            }
            catch {
                throw "$because, which has no installed definition: $($_.Exception.Message)"
            }
            [string]$definition['Name'] | Should -BeExactly $reference.Name -Because $because
            @($definition['States'].Keys) -ccontains $reference.State | Should -BeTrue -Because $because
        }
    }

    It 'disables and stops PCA before disabling the task its service re-enables' {
        $script:pcaOperations = New-Object 'Collections.Generic.List[string]'
        Mock -ModuleName Vanta.Tweaks Invoke-VantaRegistryEntries {}
        Mock -ModuleName Vanta.Tweaks Invoke-VantaServiceEntries {
            param($Entries)
            foreach ($entry in $Entries) {
                if ($entry.Operation -eq 'Stop') {
                    $script:pcaOperations.Add("Stop:$($entry.Name)")
                }
                else {
                    $script:pcaOperations.Add("Change:$($entry.Name):$($entry.StartupType)")
                }
            }
        }
        Mock -ModuleName Vanta.Tweaks Invoke-VantaScheduledTaskEntries {
            param($Entries)
            foreach ($entry in $Entries) { $script:pcaOperations.Add("Task:$($entry.Path)") }
        }
        Invoke-VantaTweak -Path (Join-Path $script:shippedTweaksRoot 'privacy\disable-pca.psd1') `
            -RegistryScope Machine -Context (New-TestContextMock)
        @($script:pcaOperations) | Should -Be @(
            'Change:PcaSvc:4', 'Stop:PcaSvc',
            'Task:\Microsoft\Windows\Application Experience\PcaPatchDbTask'
        )
    }

    It 'points the editable Windows 11 Start pin policy at the installed layout file' {
        $vantaModules = Join-Path -Path $script:shippedTweaksRoot -ChildPath '..\..'
        $definition = Import-PowerShellDataFile -LiteralPath (Join-Path $script:shippedTweaksRoot `
                'qol\config-start-menu.psd1')
        $policyEntries = @($definition.Registry | Where-Object {
                $_.Path -eq 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer' -and
                $_.Name -like 'ConfigureStartPins*'
            })

        $policyEntries.Count | Should -Be 2
        ($policyEntries | Where-Object Name -eq 'ConfigureStartPins').Data | Should -Be 1
        $pathEntry = $policyEntries | Where-Object Name -eq 'ConfigureStartPinsJSON'
        # Windows reads the path unexpanded from a plain String value.
        $pathEntry.Type | Should -BeExactly 'ExpandString'
        $pathEntry.Data | Should -Match '^%SystemRoot%\\VantaModules\\'
        $packaged = Join-Path $vantaModules ($pathEntry.Data -replace '^%SystemRoot%\\VantaModules\\', '')
        Test-Path -LiteralPath $packaged -PathType Leaf | Should -BeTrue -Because $pathEntry.Data
    }
}

Describe 'Test-VantaTweakApplicable' {
    BeforeEach {
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Tweaks -MockWith { New-TestContextMock }
        Mock -CommandName Test-VantaOption -ModuleName Vanta.Tweaks -MockWith { $true }
    }

    It 'gates on the selected option' {
        Test-VantaTweakApplicable -Tweak @{ Name = 'T'; Option = 'defender-disable' } | Should -BeTrue

        Mock -CommandName Test-VantaOption -ModuleName Vanta.Tweaks -MockWith { $false }
        Test-VantaTweakApplicable -Tweak @{ Name = 'T'; Option = 'defender-disable' } | Should -BeFalse
    }

    It 'gates on architecture' {
        Test-VantaTweakApplicable -Tweak @{ Name = 'T'; Arch = 'X64' } | Should -BeTrue
        Test-VantaTweakApplicable -Tweak @{ Name = 'T'; Arch = 'ARM64' } | Should -BeFalse

        Mock -CommandName Get-VantaContext -ModuleName Vanta.Tweaks -MockWith { New-TestContextMock -IsArm64 $true }
        Test-VantaTweakApplicable -Tweak @{ Name = 'T'; Arch = 'ARM64' } | Should -BeTrue
        Test-VantaTweakApplicable -Tweak @{ Name = 'T'; Arch = 'X64' } | Should -BeFalse
    }

    # A missing OnUpgrade means Both.
    It 'gates OnUpgrade <Label>: fresh <Fresh>, upgrade <Upgrade>, Rebase <Rebase>' -ForEach @(
        @{ Label = 'missing'; Gates = @{}; Fresh = $true; Upgrade = $true; Rebase = $true }
        @{ Label = 'Both'; Gates = @{ OnUpgrade = 'Both' }; Fresh = $true; Upgrade = $true; Rebase = $true }
        @{ Label = 'Skip'; Gates = @{ OnUpgrade = 'Skip' }; Fresh = $true; Upgrade = $false; Rebase = $false }
        @{ Label = 'Skip with OnRebase Run'; Gates = @{ OnUpgrade = 'Skip'; OnRebase = 'Run' }; Fresh = $true; Upgrade = $false; Rebase = $true }
        @{ Label = 'Only'; Gates = @{ OnUpgrade = 'Only' }; Fresh = $false; Upgrade = $true; Rebase = $true }
    ) {
        $tweak = @{ Name = 'T' } + $Gates
        $rebaseContext = New-TestContextMock -IsUpgrade $true
        $rebaseContext | Add-Member -NotePropertyName IsRebase -NotePropertyValue $true

        Test-VantaTweakApplicable -Tweak $tweak -Context (New-TestContextMock) | Should -Be $Fresh
        Test-VantaTweakApplicable -Tweak $tweak -Context (New-TestContextMock -IsUpgrade $true) | Should -Be $Upgrade
        Test-VantaTweakApplicable -Tweak $tweak -Context $rebaseContext | Should -Be $Rebase
    }

    It 'gates on MinBuild inclusively (legacy builds: [>=N])' {
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Tweaks -MockWith { New-TestContextMock -WindowsBuild 22621 }
        Test-VantaTweakApplicable -Tweak @{ Name = 'T'; MinBuild = 22000 } | Should -BeTrue
        Test-VantaTweakApplicable -Tweak @{ Name = 'T'; MinBuild = 26200 } | Should -BeFalse

        Mock -CommandName Get-VantaContext -ModuleName Vanta.Tweaks -MockWith { New-TestContextMock -WindowsBuild 22000 }
        Test-VantaTweakApplicable -Tweak @{ Name = 'T'; MinBuild = 22000 } | Should -BeTrue

        Mock -CommandName Get-VantaContext -ModuleName Vanta.Tweaks -MockWith { New-TestContextMock -WindowsBuild 19045 }
        Test-VantaTweakApplicable -Tweak @{ Name = 'T'; MinBuild = 22000 } | Should -BeFalse
    }

    It 'gates on MaxBuild inclusively (legacy builds: [<N] / [<=N])' {
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Tweaks -MockWith { New-TestContextMock -WindowsBuild 19045 }
        Test-VantaTweakApplicable -Tweak @{ Name = 'T'; MaxBuild = 21999 } | Should -BeTrue

        Mock -CommandName Get-VantaContext -ModuleName Vanta.Tweaks -MockWith { New-TestContextMock -WindowsBuild 21999 }
        Test-VantaTweakApplicable -Tweak @{ Name = 'T'; MaxBuild = 21999 } | Should -BeTrue

        Mock -CommandName Get-VantaContext -ModuleName Vanta.Tweaks -MockWith { New-TestContextMock -WindowsBuild 22621 }
        Test-VantaTweakApplicable -Tweak @{ Name = 'T'; MaxBuild = 21999 } | Should -BeFalse
    }

    It 'does not enforce build gates when the build could not be read (WindowsBuild = 0)' {
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Tweaks -MockWith { New-TestContextMock -WindowsBuild 0 }
        Test-VantaTweakApplicable -Tweak @{ Name = 'T'; MinBuild = 22000 } | Should -BeTrue
        Test-VantaTweakApplicable -Tweak @{ Name = 'T'; MaxBuild = 19999 } | Should -BeTrue
    }
}

Describe 'Invoke-VantaTweak' {
    BeforeEach {
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Tweaks -MockWith { New-TestContextMock }
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Registry -MockWith { New-TestContextMock }
        Mock -CommandName Test-VantaOption -ModuleName Vanta.Tweaks -MockWith { $true }
        Mock -CommandName Write-VantaLog -ModuleName Vanta.Tweaks
        Mock -CommandName Write-VantaLog -ModuleName Vanta.Registry
    }

    It 'records the explicit keyboard choice on fresh installs and upgrades: <Choice>, upgrade=<Upgrade>' -ForEach @(
        @{ Choice = 'keyboard-shortcuts'; Expected = 'Enable'; Upgrade = $false }
        @{ Choice = 'keyboard-selector'; Expected = 'Disable'; Upgrade = $false }
        @{ Choice = 'keyboard-single'; Expected = 'Disable'; Upgrade = $false }
        @{ Choice = 'keyboard-shortcuts'; Expected = 'Enable'; Upgrade = $true }
        @{ Choice = 'keyboard-selector'; Expected = 'Disable'; Upgrade = $true }
        @{ Choice = 'keyboard-single'; Expected = 'Disable'; Upgrade = $true }
    ) {
        Mock Get-VantaContext -ModuleName Vanta.Tweaks {
            $context = New-TestContextMock -IsUpgrade $Upgrade
            $context | Add-Member -NotePropertyName Options -NotePropertyValue @($Choice)
            $context
        }
        Mock Import-VantaModule -ModuleName Vanta.Tweaks
        Mock Get-VantaToggleState -ModuleName Vanta.Tweaks { $null }
        Mock Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks

        Invoke-VantaTweak -Path (Join-Path $PSScriptRoot '..\package\Executables\VantaModules\Scripts\Tweaks\qol\set-keyboard-switching.psd1')

        Should -Invoke Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks -Times 1 -Exactly `
            -ParameterFilter { $Name -ceq 'KeyboardShortcuts' -and $State -ceq $Expected }
    }

    It 'keeps a keyboard choice recorded since the install on an update, but not on a fresh install: upgrade=<Upgrade>' -ForEach @(
        @{ Upgrade = $true; Expected = 'Enable' }
        @{ Upgrade = $false; Expected = 'Disable' }
    ) {
        Mock Get-VantaContext -ModuleName Vanta.Tweaks {
            $context = New-TestContextMock -IsUpgrade $Upgrade
            $context | Add-Member -NotePropertyName Options -NotePropertyValue @('keyboard-single')
            $context
        }
        Mock Import-VantaModule -ModuleName Vanta.Tweaks
        # Enable Language Shortcuts.cmd was run after installing with one layout.
        Mock Get-VantaToggleState -ModuleName Vanta.Tweaks { [pscustomobject]@{ Name = 'KeyboardShortcuts'; State = 1 } }
        Mock Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks

        Invoke-VantaTweak -Path (Join-Path $PSScriptRoot '..\package\Executables\VantaModules\Scripts\Tweaks\qol\set-keyboard-switching.psd1')

        Should -Invoke Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks -Times 1 -Exactly `
            -ParameterFilter { $Name -ceq 'KeyboardShortcuts' -and $State -ceq $Expected }
    }

    It 'keeps a mitigations choice recorded since the install on an update, but not on a fresh install: upgrade=<Upgrade>' -ForEach @(
        @{ Upgrade = $true; Expected = 'WindowsDefault' }
        @{ Upgrade = $false; Expected = 'Disable' }
    ) {
        Mock Get-VantaContext -ModuleName Vanta.Tweaks {
            $context = New-TestContextMock -IsUpgrade $Upgrade
            $context | Add-Member -NotePropertyName Options -NotePropertyValue @('mitigations-disable')
            $context
        }
        Mock Get-VantaContext -ModuleName Vanta.Toggles {
            [pscustomobject]@{ VantaModulesPath = Join-Path $script:VantaTestScriptsRoot '..' }
        }
        # Set Windows Default Mitigations.cmd was run after installing with mitigations off.
        Mock Get-VantaToggleState -ModuleName Vanta.Tweaks { [pscustomobject]@{ Name = 'Mitigations'; State = 1 } }
        Mock Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks
        Mock Invoke-VantaHiddenProcess -ModuleName Vanta.Tweaks

        Invoke-VantaTweak -Path (Join-Path $PSScriptRoot '..\package\Executables\VantaModules\Scripts\Tweaks\scripts\disable-mitigations.psd1')

        Should -Invoke Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks -Times 1 -Exactly `
            -ParameterFilter { $Name -ceq 'Mitigations' -and $State -ceq $Expected }
        Should -Invoke Invoke-VantaHiddenProcess -ModuleName Vanta.Tweaks -Times 0 -Exactly
    }

    It 'keeps existing keyboard settings when an older options snapshot has no keyboard choice' {
        Mock Get-VantaContext -ModuleName Vanta.Tweaks {
            $context = New-TestContextMock
            $context | Add-Member -NotePropertyName Options -NotePropertyValue @('defender-enable')
            $context
        }
        Mock Import-VantaModule -ModuleName Vanta.Tweaks
        Mock Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks

        Invoke-VantaTweak -Path (Join-Path $PSScriptRoot '..\package\Executables\VantaModules\Scripts\Tweaks\qol\set-keyboard-switching.psd1')

        Should -Invoke Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks -Times 0 -Exactly
    }

    It 'rejects conflicting keyboard choices before recording any changes' {
        Mock Get-VantaContext -ModuleName Vanta.Tweaks {
            $context = New-TestContextMock
            $context | Add-Member -NotePropertyName Options -NotePropertyValue @('keyboard-shortcuts', 'keyboard-single')
            $context
        }
        Mock Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks

        { Invoke-VantaTweak -Path (Join-Path $PSScriptRoot '..\package\Executables\VantaModules\Scripts\Tweaks\qol\set-keyboard-switching.psd1') } |
            Should -Throw '*exactly one keyboard*'

        Should -Invoke Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks -Times 0 -Exactly
    }

    It 'applies a registry-only tweak through the ambient HKCU path when unelevated' {
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'registry-tweak.psd1'
        @'
@{
    Name     = 'Registry Tweak'
    Registry = @(
        @{ Path = 'HKCU:\Software\VantaRewriteTest\Tweak'; Name = 'Applied'; Type = 'DWord'; Data = 1 }
        @{ Path = 'HKCU:\Software\VantaRewriteTest\Tweak'; Name = 'ArmOnly'; Type = 'DWord'; Data = 2; Arch = 'ARM64' }
    )
}
'@ | Set-Content -Path $tweakFile

        Invoke-VantaTweak -Path $tweakFile

        $key = Get-Item -Path "$script:testRoot\Tweak"
        $key.GetValue('Applied') | Should -Be 1
        $key.GetValue('ArmOnly', $null) | Should -BeNullOrEmpty
    }

    It 'uses the passed option snapshot without rereading machine install state in the user pass' {
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Tweaks -MockWith {
            throw 'The exact-user registry pass must not reread machine install state.'
        }
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Registry -MockWith {
            throw 'Vanta.Registry must receive architecture explicitly in the exact-user pass.'
        }
        Mock -CommandName Test-VantaOption -ModuleName Vanta.Tweaks -MockWith {
            throw 'Option gates must use the injected protected snapshot.'
        }

        $marker = Join-Path -Path $TestDrive -ChildPath 'registry-only-script.txt'
        $companion = Join-Path -Path $TestDrive -ChildPath 'registry-only.ps1'
        "Set-Content -LiteralPath '$marker' -Value 'unexpected'" | Set-Content -Path $companion
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'explicit-context.psd1'
        @'
@{
    Name     = 'Explicit Context Tweak'
    Option   = 'selected-option'
    Registry = @(
        @{ Path = 'HKCU:\Software\VantaRewriteTest\ExplicitContext'; Name = 'Applied'; Type = 'DWord'; Data = 1 }
    )
    Script   = 'registry-only.ps1'
}
'@ | Set-Content -Path $tweakFile

        $explicitContext = [pscustomobject]@{
            WinDir = 'C:\Windows'; VantaModulesPath = 'C:\Windows\VantaModules'
            IsArm64 = $false; WindowsBuild = 26100; IsUpgrade = $false
            IsInstallStateBacked = $true; Options = @('selected-option')
        }
        Invoke-VantaTweak -Path $tweakFile -RegistryScope CurrentUser `
            -RegistryOnly -Context $explicitContext

        (Get-Item "$script:testRoot\ExplicitContext").GetValue('Applied') | Should -Be 1
        Test-Path -LiteralPath $marker | Should -BeFalse
        Should -Invoke Get-VantaContext -ModuleName Vanta.Tweaks -Times 0 -Exactly
        Should -Invoke Get-VantaContext -ModuleName Vanta.Registry -Times 0 -Exactly
        Should -Invoke Test-VantaOption -ModuleName Vanta.Tweaks -Times 0 -Exactly
    }

    It 'runs a RunAs=User companion script via Invoke-VantaAsUser instead of in-process' {
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Tweaks -MockWith {
            New-TestContextMock -IsInstallStateBacked $true
        }
        Mock -CommandName Invoke-VantaAsUser -ModuleName Vanta.Tweaks -MockWith { 0 }
        $marker = Join-Path -Path $TestDrive -ChildPath 'runas-should-not-run.txt'
        $companion = Join-Path -Path $TestDrive -ChildPath 'runas.ps1'
        "New-Item -Path '$($marker -replace "'", "''")' -Force | Out-Null" | Set-Content -Path $companion
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'runas-tweak.psd1'
        @'
@{
    Name   = 'RunAs Tweak'
    RunAs  = 'User'
    Script = 'runas.ps1'
}
'@ | Set-Content -Path $tweakFile

        Invoke-VantaTweak -Path $tweakFile

        # The engine must delegate to Invoke-VantaAsUser (mocked) and NOT dot-source the
        # companion into the current process.
        Should -Invoke -CommandName Invoke-VantaAsUser -ModuleName Vanta.Tweaks -Times 1 `
            -ParameterFilter {
                $Arguments -match '-ExpectedUserSid S-1-5-21-1-2-3-1001$'
            }
        Test-Path -LiteralPath $marker | Should -BeFalse

        Mock -CommandName Invoke-VantaAsUser -ModuleName Vanta.Tweaks -MockWith { 9 }
        { Invoke-VantaTweak -Path $tweakFile } | Should -Throw '*exited with code 9*'
    }

    It 'runs a companion without RunAs in-process' {
        Mock -CommandName Invoke-VantaAsUser -ModuleName Vanta.Tweaks -MockWith { 0 }
        $marker = Join-Path -Path $TestDrive -ChildPath 'inproc.txt'
        $companion = Join-Path -Path $TestDrive -ChildPath 'inproc.ps1'
        "New-Item -Path '$marker' -Force | Out-Null" | Set-Content -Path $companion
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'inproc-tweak.psd1'
        @'
@{
    Name   = 'In-Process Tweak'
    Script = 'inproc.ps1'
}
'@ | Set-Content -Path $tweakFile

        Invoke-VantaTweak -Path $tweakFile

        Should -Invoke -CommandName Invoke-VantaAsUser -ModuleName Vanta.Tweaks -Times 0
        Test-Path $marker | Should -BeTrue

        "throw 'companion failure marker'" | Set-Content -Path $companion
        { Invoke-VantaTweak -Path $tweakFile } | Should -Throw '*companion failure marker*'

        "@{ Name = 'Bad authority'; RunAs = 'UserElevated'; Script = 'inproc.ps1' }" |
            Set-Content -Path $tweakFile
        { Invoke-VantaTweak -Path $tweakFile } | Should -Throw '*unsupported companion RunAs*'
    }

    It 'expands {windir} independently in exact Run entry argv elements' {
        [AppDomain]::CurrentDomain.SetData('VantaTweaksExpandedRun', $null)
        Mock -CommandName Invoke-VantaHiddenProcess -ModuleName Vanta.Tweaks -MockWith {
            [AppDomain]::CurrentDomain.SetData('VantaTweaksExpandedRun', [pscustomobject]@{
                FilePath        = $FilePath
                ArgumentList    = [string[]]$ArgumentList
                AllowedExitCode = [int[]]$AllowedExitCode
            })
        }
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'run-tweak.psd1'
        @'
@{
    Name = 'Run Tweak'
    Run  = @(
        @{ Exe = '{windir}\System32\example.exe'; Args = @('{windir}\path with spaces\', 'embedded"quote', '') }
    )
}
'@ | Set-Content -Path $tweakFile

        # Unlike the real Windows directory, so the expansion must come from the context.
        $context = New-TestContextMock
        $context.WinDir = 'X:\VantaWin'
        Invoke-VantaTweak -Path $tweakFile -Context $context

        $captured = [AppDomain]::CurrentDomain.GetData('VantaTweaksExpandedRun')
        $captured.FilePath | Should -BeExactly 'X:\VantaWin\System32\example.exe'
        @($captured.ArgumentList) | Should -BeExactly @('X:\VantaWin\path with spaces\', 'embedded"quote', '')
        @($captured.AllowedExitCode) | Should -Be @(0)
    }

    It 'passes the narrowly declared reboot-required exit contract only to DISM' {
        Mock -CommandName Invoke-VantaHiddenProcess -ModuleName Vanta.Tweaks
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'dism-exit-contract.psd1'
        @'
@{
    Name = 'DISM exit contract'
    Run = @(
        @{ Exe = '{windir}\System32\dism.exe'; Args = @('/Online'); AllowedExitCodes = @(0, 3010) }
    )
}
'@ | Set-Content -Path $tweakFile

        Invoke-VantaTweak -Path $tweakFile

        Should -Invoke -CommandName Invoke-VantaHiddenProcess -ModuleName Vanta.Tweaks `
            -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'C:\Windows\System32\dism.exe' -and
                @($AllowedExitCode).Count -eq 2 -and
                $AllowedExitCode -contains 0 -and
                $AllowedExitCode -contains 3010
            }

        $wrongExeFile = Join-Path -Path $TestDrive -ChildPath 'wrong-exe-exit-contract.psd1'
        "@{ Name = 'Wrong executable'; Run = @( @{ Exe = 'C:\Windows\System32\whoami.exe'; AllowedExitCodes = @(0, 3010) } ) }" |
            Set-Content -Path $wrongExeFile
        { Invoke-VantaTweak -Path $wrongExeFile } |
            Should -Throw '*AllowedExitCodes is restricted*'
    }

    It 'propagates a required machine Run failure by default' {
        Mock -CommandName Invoke-VantaHiddenProcess -ModuleName Vanta.Tweaks -MockWith {
            throw "'C:\Windows\System32\failure.exe' exited with disallowed code 17."
        }
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'failed-machine-run.psd1'
        @'
@{
    Name = 'Failed Machine Run'
    Run = @(
        @{ Exe = 'C:\Windows\System32\failure.exe'; Wait = $true }
    )
}
'@ | Set-Content -Path $tweakFile

        { Invoke-VantaTweak -Path $tweakFile } |
            Should -Throw '*disallowed code 17*'
    }

    It 'retains explicit IgnoreErrors for a reviewed optional machine Run' {
        Mock -CommandName Invoke-VantaHiddenProcess -ModuleName Vanta.Tweaks -MockWith {
            throw "'C:\Windows\System32\optional.exe' exited with disallowed code 17."
        }
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'optional-machine-run.psd1'
        @'
@{
    Name = 'Optional Machine Run'
    Run = @(
        @{ Exe = 'C:\Windows\System32\optional.exe'; Wait = $true; IgnoreErrors = $true }
    )
}
'@ | Set-Content -Path $tweakFile

        { Invoke-VantaTweak -Path $tweakFile } | Should -Not -Throw
        Should -Invoke -CommandName Write-VantaLog -ModuleName Vanta.Tweaks -Times 1 -Exactly `
            -ParameterFilter {
                $Level -eq 'Warning' -and
                $Message -like "Ignored Run entry failure (executable: 'C:\Windows\System32\optional.exe'):*disallowed code 17*"
            }
    }

    It 'routes scheduled task entries through the missing-task-tolerant Vanta.TasksProcs helpers' {
        Mock -CommandName Disable-VantaScheduledTask -ModuleName Vanta.TasksProcs
        Mock -CommandName Enable-VantaScheduledTask -ModuleName Vanta.TasksProcs
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'scheduled-task-routing.psd1'
        @'
@{
    Name = 'Scheduled Task Routing'
    ScheduledTasks = @(
        @{ Path = '\Microsoft\Windows\Test\UnwantedTask' }
        @{ Path = '\Microsoft\Windows\Test\WantedTask'; Operation = 'Enable' }
    )
}
'@ | Set-Content -Path $tweakFile

        Invoke-VantaTweak -Path $tweakFile

        Should -Invoke -CommandName Disable-VantaScheduledTask -ModuleName Vanta.TasksProcs `
            -Times 1 -Exactly -ParameterFilter {
                $Path -eq '\Microsoft\Windows\Test\UnwantedTask'
            }
        Should -Invoke -CommandName Enable-VantaScheduledTask -ModuleName Vanta.TasksProcs `
            -Times 1 -Exactly -ParameterFilter {
                $Path -eq '\Microsoft\Windows\Test\WantedTask'
            }
    }

    It 'routes service startup changes through the checked Vanta.Services helper' {
        Mock -CommandName Set-VantaServiceStartup -ModuleName Vanta.Services
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'service-startup.psd1'
        @'
@{
    Name = 'Service Startup'
    Services = @(
        @{ Name = 'TestSvc'; StartupType = 4 }
        @{ Name = 'OptionalDrv'; StartupType = 3; AllowMissing = $true }
    )
}
'@ | Set-Content -Path $tweakFile

        Invoke-VantaTweak -Path $tweakFile

        Should -Invoke -CommandName Set-VantaServiceStartup -ModuleName Vanta.Services `
            -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'TestSvc' -and $StartupType -eq 4 -and -not $AllowMissing
            }
        Should -Invoke -CommandName Set-VantaServiceStartup -ModuleName Vanta.Services `
            -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'OptionalDrv' -and $StartupType -eq 3 -and $AllowMissing
            }

        Mock -CommandName Set-VantaServiceStartup -ModuleName Vanta.Services -MockWith {
            throw "Service or driver 'TestSvc' did not retain startup type '4'."
        }
        { Invoke-VantaTweak -Path $tweakFile } | Should -Throw '*did not retain startup type*'
    }

    It 'applies a Toggle entry through the toggle engine machine state with the declared name and state' {
        Mock -CommandName Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'toggle-routing.psd1'
        @'
@{
    Name = 'Toggle Routing'
    Toggle = @(
        @{ Name = 'FileSharing'; State = 'Disable' }
        @{ Name = 'Indexing'; State = 'Minimal' }
    )
}
'@ | Set-Content -Path $tweakFile

        Invoke-VantaTweak -Path $tweakFile

        Should -Invoke -CommandName Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks `
            -Times 2 -Exactly
        Should -Invoke -CommandName Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks `
            -Times 1 -Exactly -ParameterFilter {
                $Name -ceq 'FileSharing' -and $State -ceq 'Disable'
            }
        Should -Invoke -CommandName Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks `
            -Times 1 -Exactly -ParameterFilter {
                $Name -ceq 'Indexing' -and $State -ceq 'Minimal'
            }

        Mock -CommandName Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks -MockWith {
            throw "Toggle 'FileSharing' machine state failed."
        }
        { Invoke-VantaTweak -Path $tweakFile } | Should -Throw '*machine state failed*'
        # Invocation counts accumulate across both runs: the failing run reached the
        # first entry again and must not have continued to the second.
        Should -Invoke -CommandName Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks `
            -Times 2 -Exactly -ParameterFilter { $Name -ceq 'FileSharing' }
        Should -Invoke -CommandName Invoke-VantaToggleMachineState -ModuleName Vanta.Tweaks `
            -Times 1 -Exactly -ParameterFilter { $Name -ceq 'Indexing' }
    }

    It 'limits RemovePaths to the Windows directory and propagates required removal failures' {
        $targetPath = Join-Path -Path $TestDrive -ChildPath 'protected-removal'
        New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
        Mock -CommandName Remove-Item -ModuleName Vanta.Tweaks -MockWith {
            throw 'path access denied'
        } -ParameterFilter { $LiteralPath -eq $targetPath }
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'failed-removal.psd1'
        @'
@{
    Name = 'Failed RemovePaths'
    RemovePaths = @(
        @{ Path = '{windir}\protected-removal' }
    )
}
'@ | Set-Content -Path $tweakFile

        $context = New-TestContextMock
        $context.WinDir = $TestDrive
        { Invoke-VantaTweak -Path $tweakFile -Context $context } |
            Should -Throw '*path access denied*'

        $outsideTweak = Join-Path -Path $TestDrive -ChildPath 'outside-removal.psd1'
        @'
@{
    Name = 'Outside RemovePaths'
    RemovePaths = @(
        @{ Path = '{windir}\..\outside' }
    )
}
'@ | Set-Content -Path $outsideTweak

        { Invoke-VantaTweak -Path $outsideTweak -Context $context } |
            Should -Throw '*resolves outside the Windows directory*'
    }

    It 'skips a tweak whose option is not selected' {
        Mock -CommandName Test-VantaOption -ModuleName Vanta.Tweaks -MockWith { $false }

        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'gated-tweak.psd1'
        @'
@{
    Name     = 'Gated Tweak'
    Option   = 'defender-disable'
    Registry = @(
        @{ Path = 'HKCU:\Software\VantaRewriteTest\Gated'; Name = 'Applied'; Type = 'DWord'; Data = 1 }
    )
}
'@ | Set-Content -Path $tweakFile

        Invoke-VantaTweak -Path $tweakFile

        Test-Path -Path "$script:testRoot\Gated" | Should -BeFalse
        Should -Invoke -CommandName Write-VantaLog -ModuleName Vanta.Tweaks -Times 1 -Exactly -ParameterFilter { $Message -like "Skipping tweak 'Gated Tweak'*" }
    }

    It 'throws on a missing tweak file' {
        { Invoke-VantaTweak -Path (Join-Path -Path $TestDrive -ChildPath 'missing.psd1') } | Should -Throw '*not found*'
    }

    It 'throws on a tweak without a Name' {
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'nameless.psd1'
        Set-Content -Path $tweakFile -Value '@{ Description = "nameless" }'
        { Invoke-VantaTweak -Path $tweakFile } | Should -Throw "*no 'Name' key*"
    }
}

Describe 'Get-VantaTweakManifest and Invoke-VantaTweakCategory' {
    BeforeEach {
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Tweaks -MockWith { New-TestContextMock }
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Registry -MockWith { New-TestContextMock }
        Mock -CommandName Write-VantaLog -ModuleName Vanta.Tweaks
        Mock -CommandName Write-VantaLog -ModuleName Vanta.Registry

        $script:tweaksRoot = Join-Path -Path $TestDrive -ChildPath 'Tweaks'
        $categoryDir = Join-Path -Path $script:tweaksRoot -ChildPath 'testing\sub'
        New-Item -Path $categoryDir -ItemType Directory -Force | Out-Null

        @'
@{
    Categories = @(
        @{
            Name   = 'testing'
            Tweaks = @(
                'first-tweak'
                'sub/second-tweak'
                'missing-tweak'
            )
        }
    )
}
'@ | Set-Content -Path (Join-Path -Path $script:tweaksRoot -ChildPath 'tweaks.manifest.psd1')

        @'
@{
    Name     = 'First Tweak'
    Registry = @(
        @{ Path = 'HKCU:\Software\VantaRewriteTest\Category'; Name = 'First'; Type = 'DWord'; Data = 1 }
    )
}
'@ | Set-Content -Path (Join-Path -Path $script:tweaksRoot -ChildPath 'testing\first-tweak.psd1')

        @'
@{
    Name     = 'Second Tweak'
    Registry = @(
        @{ Path = 'HKCU:\Software\VantaRewriteTest\Category'; Name = 'Second'; Type = 'DWord'; Data = 2 }
    )
}
'@ | Set-Content -Path (Join-Path -Path $script:tweaksRoot -ChildPath 'testing\sub\second-tweak.psd1')
    }

    It 'resolves only applicable post-user-registry refreshes in declaration order without duplicates' {
        @'
@{
    Categories = @(
        @{
            Name = 'testing'
            Tweaks = @('first-tweak', 'sub/second-tweak', 'third-tweak')
        }
    )
}
'@ | Set-Content -Path (Join-Path $script:tweaksRoot 'tweaks.manifest.psd1')

        '@{ Name = ''First''; PostUserRegistryRefresh = ''ExplorerRefresh'' }' |
            Set-Content -Path (Join-Path $script:tweaksRoot 'testing\first-tweak.psd1')
        '@{ Name = ''Upgrade''; OnUpgrade = ''Only''; PostUserRegistryRefresh = ''SearchShellRefresh'' }' |
            Set-Content -Path (Join-Path $script:tweaksRoot 'testing\sub\second-tweak.psd1')
        '@{ Name = ''Duplicate''; PostUserRegistryRefresh = ''ExplorerRefresh'' }' |
            Set-Content -Path (Join-Path $script:tweaksRoot 'testing\third-tweak.psd1')

        $fresh = @(Get-VantaTweakCategoryPostUserRegistryRefresh -Name testing `
                -TweaksRoot $script:tweaksRoot -Context (New-TestContextMock))
        $upgrade = @(Get-VantaTweakCategoryPostUserRegistryRefresh -Name testing `
                -TweaksRoot $script:tweaksRoot -Context (New-TestContextMock -IsUpgrade $true))

        $fresh | Should -Be @('ExplorerRefresh')
        $upgrade | Should -Be @('ExplorerRefresh', 'SearchShellRefresh')
    }

    It 'throws on a missing manifest' {
        { Get-VantaTweakManifest -Path (Join-Path -Path $TestDrive -ChildPath 'nope.psd1') } | Should -Throw '*not found*'
    }

    It 'applies a category in order and fails when a manifest-listed tweak is missing' {
        { Invoke-VantaTweakCategory -Name 'testing' -TweaksRoot $script:tweaksRoot } |
            Should -Throw '*Tweak file not found*missing-tweak.psd1*'

        $key = Get-Item -Path "$script:testRoot\Category"
        $key.GetValue('First') | Should -Be 1
        $key.GetValue('Second') | Should -Be 2
    }

    It 'throws on an unknown category' {
        { Invoke-VantaTweakCategory -Name 'nope' -TweaksRoot $script:tweaksRoot } | Should -Throw '*not defined*'
    }

}

Describe 'Test-VantaTweakSchema AllowOsProtected' {
    It 'rejects a non-boolean declaration and key operations' {
        $tweakFile = Join-Path -Path $TestDrive -ChildPath 'os-protected.psd1'
        @'
@{
    Name     = 'Protected'
    Registry = @(
        @{ Path = 'HKLM:\SOFTWARE\Test'; Name = 'V'; Type = 'DWord'; Data = 1; AllowOsProtected = 'yes' }
        @{ Path = 'HKLM:\SOFTWARE\TestKey'; Operation = 'AddKey'; AllowOsProtected = $true }
    )
}
'@ | Set-Content -Path $tweakFile

        $problemText = @(Test-VantaTweakSchema -Path $tweakFile | ForEach-Object { $_.Problem }) -join "`n"
        $problemText | Should -Match "'AllowOsProtected' must be a boolean"
        $problemText | Should -Match "applies only to 'Set' and 'Delete'"
    }
}

Describe 'Local Group Policy declaration schema' {
    It 'accepts only explicit machine DWORD policy writes' -TestCases @(
        @{ Path = 'HKLM\Software\Policies\Test'; Type = 'DWord'; Flag = '$true'; Valid = $true }
        @{ Path = 'HKCU\Software\Policies\Test'; Type = 'DWord'; Flag = '$true'; Valid = $false }
        @{ Path = 'HKLM\Software\Test'; Type = 'DWord'; Flag = '$true'; Valid = $false }
        @{ Path = 'HKLM\Software\Policies\Test'; Type = 'String'; Flag = '$true'; Valid = $false }
        @{ Path = 'HKLM\Software\Policies\Test'; Type = 'DWord'; Flag = "'false'"; Valid = $false }
    ) {
        param($Path, $Type, $Flag, $Valid)
        $file = Join-Path $TestDrive 'policy.psd1'
        Set-Content -LiteralPath $file -Value "@{ Name = 'Policy'; Registry = @(@{ Path = '$Path'; Name = 'Policy'; Type = '$Type'; Data = 0; UseGroupPolicy = $Flag }) }"
        $problems = @(Test-VantaTweakSchema -Path $file)
        if ($Valid) { $problems.Count | Should -Be 0 }
        else { ($problems.Problem -join '; ') | Should -Match 'UseGroupPolicy' }
    }
}

Describe 'Registry verification exclusions in tweak schemas' {
    It 'requires a non-empty reason string' -TestCases @(
        @{ Value = "'Windows recreates this cache.'"; Valid = $true }
        @{ Value = '$true'; Valid = $false }
        @{ Value = "''"; Valid = $false }
        @{ Value = "' '"; Valid = $false }
    ) {
        param($Value, $Valid)
        $path = Join-Path $TestDrive 'verification.psd1'
        Set-Content -LiteralPath $path -Value "@{ Name = 'Transient'; Registry = @(@{ Path = 'HKCU\Software\Test'; Operation = 'DeleteKey'; SkipVerification = $Value }) }"
        $problems = @(Test-VantaTweakSchema -Path $path)
        if ($Valid) { $problems.Count | Should -Be 0 }
        else { ($problems.Problem -join '; ') | Should -Match 'non-empty reason string' }
    }
}

Describe 'Configure Time Servers' {
    # PCs tweaked beyond Vanta can have Windows Time disabled; the tweak must still finish.
    It 'never stops the install when Windows Time can''t start or reload' {
        $path = Join-Path $PSScriptRoot '..\package\Executables\VantaModules\Scripts\Tweaks\misc\config-time.psd1'
        @(Test-VantaTweakSchema -Path $path).Count | Should -Be 0
        $tweak = Import-PowerShellDataFile -LiteralPath $path
        @($tweak.Services | Where-Object { -not $_.IgnoreErrors }).Count | Should -Be 0
        @($tweak.Run | Where-Object { -not $_.IgnoreErrors }).Count | Should -Be 0
        # The servers themselves are registry values, which need no running service.
        @($tweak.Registry | Where-Object Name -eq 'NtpServer').Count | Should -Be 1
    }
}
