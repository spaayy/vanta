BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $modulesRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\package\Executables\VantaModules\Scripts\Modules'
    Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Registry\Vanta.Registry.psd1') -Force

    $script:testRoot = 'HKCU:\Software\VantaRewriteTest'
    $script:testSubPath = 'Software\VantaRewriteTest'
}

AfterAll {
    Remove-Item -Path 'HKCU:\Software\VantaRewriteTest' -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-VantaRegistryTarget identity boundary' {
    BeforeEach {
        InModuleScope Vanta.Registry {
            $script:VantaRegistryIdentityContext = $null
        }
    }

    It 'fails closed instead of redirecting privileged HKCU to a live user hive' {
        Mock -CommandName Test-VantaSystem -ModuleName Vanta.Registry -MockWith { $true }

        {
            InModuleScope Vanta.Registry {
                Resolve-VantaRegistryTarget -Path 'HKCU:\Software\X'
            }
        } | Should -Throw '*live-user HKU redirection is forbidden*'
    }

    It 'uses ambient HKCU only after proving the non-System current token' {
        Mock -CommandName Test-VantaSystem -ModuleName Vanta.Registry -MockWith { $false }
        Mock -CommandName Get-VantaRegistryCurrentTokenSid -ModuleName Vanta.Registry -MockWith {
            'S-1-5-21-1-2-3-1001'
        }

        $result = InModuleScope Vanta.Registry {
            Resolve-VantaRegistryTarget -Path 'HKCU:\Software\X'
        }

        $result.Primary | Should -Be 'Registry::HKEY_CURRENT_USER\Software\X'
        $result.PSObject.Properties.Match('Mirror').Count | Should -Be 0
        $result.HkcuSubPath | Should -BeNullOrEmpty
        Should -Invoke -CommandName Test-VantaSystem -ModuleName Vanta.Registry -Times 1 -Exactly
        Should -Invoke -CommandName Get-VantaRegistryCurrentTokenSid -ModuleName Vanta.Registry -Times 1 -Exactly
    }

    It 'binds an exact current-token helper context and rejects a changed token' {
        Mock -CommandName Test-VantaSystem -ModuleName Vanta.Registry -MockWith { $false }
        Mock -CommandName Get-VantaRegistryCurrentTokenSid -ModuleName Vanta.Registry -MockWith {
            'S-1-5-21-1-2-3-1001'
        }

        Initialize-VantaRegistryIdentityContext -CurrentToken `
            -ExpectedUserSid 'S-1-5-21-1-2-3-1001' | Out-Null
        $result = InModuleScope Vanta.Registry {
            Resolve-VantaRegistryTarget -Path 'HKCU:\Software\X'
        }
        $result.Primary | Should -Be 'Registry::HKEY_CURRENT_USER\Software\X'

        Mock -CommandName Get-VantaRegistryCurrentTokenSid -ModuleName Vanta.Registry -MockWith {
            'S-1-5-21-1-2-3-2002'
        }
        {
            InModuleScope Vanta.Registry {
                Resolve-VantaRegistryTarget -Path 'HKCU:\Software\X'
            }
        } | Should -Throw '*token changed*'
    }

    It 'binds strict TrustedInstaller only to the fixed default-user hive and transaction' {
        Mock -CommandName Test-VantaSystem -ModuleName Vanta.Registry -MockWith { $true }
        Mock -CommandName Test-VantaTrustedInstaller -ModuleName Vanta.Registry -MockWith { $true }
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Registry -MockWith {
            [pscustomobject]@{
                IsInstallStateBacked = $true
                TransactionId        = '11111111-2222-3333-4444-555555555555'
            }
        }
        Mock -CommandName Test-VantaDefaultUserHiveLoaded -ModuleName Vanta.Registry -MockWith { $true }

        Initialize-VantaRegistryIdentityContext -DefaultUserOnly `
            -TransactionId '11111111-2222-3333-4444-555555555555' | Out-Null
        $result = InModuleScope Vanta.Registry {
            Resolve-VantaRegistryTarget -Path 'HKCU:\Software\X'
        }

        $result.Primary | Should -Be 'Registry::HKEY_USERS\Vanta_DefaultUser\Software\X'
        $result.PSObject.Properties.Match('Mirror').Count | Should -Be 0
        $result.HkcuSubPath | Should -Be 'Software\X'
        Should -Invoke -CommandName Get-VantaContext `
            -ModuleName Vanta.Registry -Times 1 -Exactly
    }

    It 'binds the protected policy writer to the active transaction and exact installing user' {
        Mock -CommandName Test-VantaSystem -ModuleName Vanta.Registry -MockWith { $true }
        Mock -CommandName Test-VantaTrustedInstaller -ModuleName Vanta.Registry -MockWith { $true }
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Registry -MockWith {
            [pscustomobject]@{
                IsInstallStateBacked = $true
                TransactionId        = '11111111-2222-3333-4444-555555555555'
                InteractiveUserSid   = 'S-1-5-21-1-2-3-1001'
            }
        }

        Initialize-VantaRegistryIdentityContext -InstallingUserPoliciesOnly `
            -InstallingUserSid 'S-1-5-21-1-2-3-1001' `
            -TransactionId '11111111-2222-3333-4444-555555555555' | Out-Null
        $result = InModuleScope Vanta.Registry {
            Resolve-VantaRegistryTarget `
                -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
        }

        $result.Primary | Should -Be 'Registry::HKEY_USERS\S-1-5-21-1-2-3-1001\Software\Policies\Microsoft\Windows\Explorer'
    }

    It 'refuses arbitrary HKCU paths from the protected policy writer' {
        Mock -CommandName Test-VantaSystem -ModuleName Vanta.Registry -MockWith { $true }
        Mock -CommandName Test-VantaTrustedInstaller -ModuleName Vanta.Registry -MockWith { $true }
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Registry -MockWith {
            [pscustomobject]@{
                IsInstallStateBacked = $true
                TransactionId        = '11111111-2222-3333-4444-555555555555'
                InteractiveUserSid   = 'S-1-5-21-1-2-3-1001'
            }
        }

        Initialize-VantaRegistryIdentityContext -InstallingUserPoliciesOnly `
            -InstallingUserSid 'S-1-5-21-1-2-3-1001' `
            -TransactionId '11111111-2222-3333-4444-555555555555' | Out-Null

        {
            InModuleScope Vanta.Registry {
                Resolve-VantaRegistryTarget -Path 'HKCU:\Software\Vanta\Arbitrary'
            }
        } | Should -Throw '*cannot target HKCU path*'
    }

    It 'rejects a protected policy writer whose SID differs from install state' {
        Mock -CommandName Test-VantaTrustedInstaller -ModuleName Vanta.Registry -MockWith { $true }
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Registry -MockWith {
            [pscustomobject]@{
                IsInstallStateBacked = $true
                TransactionId        = '11111111-2222-3333-4444-555555555555'
                InteractiveUserSid   = 'S-1-5-21-1-2-3-2002'
            }
        }

        {
            Initialize-VantaRegistryIdentityContext -InstallingUserPoliciesOnly `
                -InstallingUserSid 'S-1-5-21-1-2-3-1001' `
                -TransactionId '11111111-2222-3333-4444-555555555555'
        } | Should -Throw '*does not match expected SID*'
    }

    It 'rejects every privileged explicit live-user HKEY_USERS target' {
        Mock -CommandName Test-VantaSystem -ModuleName Vanta.Registry -MockWith { $true }

        {
            InModuleScope Vanta.Registry {
                Resolve-VantaRegistryTarget `
                    -Path 'HKU\S-1-5-21-1-2-3-1001\Software\X'
            }
        } | Should -Throw '*may target only the fixed*'
    }

}

Describe 'Resolve-VantaRegistryPath' {
    It 'normalizes <Path> to the Registry provider' -TestCases @(
        @{ Path = 'HKCU:\Software\X'; Primary = 'Registry::HKEY_CURRENT_USER\Software\X'; IsHkcu = $true }
        @{ Path = 'HKCU\Software\X'; Primary = 'Registry::HKEY_CURRENT_USER\Software\X'; IsHkcu = $true }
        @{ Path = 'HKLM:\SOFTWARE\Test'; Primary = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Test'; IsHkcu = $false }
        @{ Path = 'HKU\S-1-5-18\Software'; Primary = 'Registry::HKEY_USERS\S-1-5-18\Software'; IsHkcu = $false }
        @{ Path = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Test'; Primary = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Test'; IsHkcu = $false }
    ) {
        $result = Resolve-VantaRegistryPath -Path $Path
        $result.Primary | Should -BeExactly $Primary
        $result.IsHkcu | Should -Be $IsHkcu
        $result.PSObject.Properties.Match('Mirror').Count | Should -Be 0
        $result.HkcuSubPath | Should -BeNullOrEmpty
    }

    It 'throws on an unsupported root' {
        { Resolve-VantaRegistryPath -Path 'HKXX:\Software' } | Should -Throw '*Unsupported registry root*'
    }
}

Describe 'Get-VantaRegistryEntryTargetScope' {
    It 'classifies machine, current-user, protected, default-user and explicit hive paths' {
        Get-VantaRegistryEntryTargetScope -Path 'HKLM\SOFTWARE\X' | Should -Be 'Machine'
        Get-VantaRegistryEntryTargetScope -Path 'HKCU:\Software\X' | Should -Be 'CurrentUser'
        Get-VantaRegistryEntryTargetScope -Path 'HKCU\Software\Policies\X' |
            Should -Be 'ProtectedCurrentUser'
        Get-VantaRegistryEntryTargetScope -Path 'HKU\Vanta_DefaultUser\Software\X' |
            Should -Be 'DefaultUser'
        Get-VantaRegistryEntryTargetScope -Path 'HKU\S-1-5-21-1-2-3-1001\Software\X' |
            Should -Be 'ExplicitUserHive'
    }
}

Describe 'Test-VantaArchMatch' {
    It 'matches optional architecture gates against the machine architecture' {
        Test-VantaArchMatch -Arch '' -IsArm64 $false | Should -BeTrue
        Test-VantaArchMatch -Arch 'X64' -IsArm64 $false | Should -BeTrue
        Test-VantaArchMatch -Arch 'X64' -IsArm64 $true | Should -BeFalse
        Test-VantaArchMatch -Arch 'ARM64' -IsArm64 $true | Should -BeTrue
        { Test-VantaArchMatch -Arch 'X86' -IsArm64 $false } |
            Should -Throw '*Unknown architecture gate*'
    }
}

Describe 'Set-VantaRegistryValue and Remove-VantaRegistryValue' {
    BeforeAll {
        $script:valuesKeyPath = "$script:testRoot\Values"
    }

    It 'writes a <Kind> value as <Expected>' -TestCases @(
        @{ Name = 'String'; Type = 'String'; Data = 'hello'; Expected = 'hello'; Kind = 'String' }
        @{ Name = 'Expand'; Type = 'ExpandString'; Data = '%windir%\test'; Expected = '%windir%\test'; Kind = 'ExpandString' }
        @{ Name = 'Dword'; Type = 'DWord'; Data = 1; Expected = 1; Kind = 'DWord' }
        # RegistryKey.SetValue accepts only Int32 for a DWord.
        @{ Name = 'DwordMax'; Type = 'DWord'; Data = 4294967295; Expected = -1; Kind = 'DWord' }
        @{ Name = 'Qword'; Type = 'QWord'; Data = 8589934592; Expected = 8589934592; Kind = 'QWord' }
        @{ Name = 'Binary'; Type = 'Binary'; Data = @(1, 2, 3); Expected = @(1, 2, 3); Kind = 'Binary' }
        @{ Name = 'Multi'; Type = 'MultiString'; Data = @('one', 'two'); Expected = @('one', 'two'); Kind = 'MultiString' }
        @{ Name = 'None'; Type = 'None'; Data = $null; Expected = @(); Kind = 'None' }
    ) {
        Set-VantaRegistryValue -Path $script:valuesKeyPath -Name $Name -Type $Type -Data $Data
        $key = Get-Item -Path $script:valuesKeyPath
        $value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        @($value) -join '|' | Should -BeExactly (@($Expected) -join '|')
        $key.GetValueKind($Name) | Should -Be ([Microsoft.Win32.RegistryValueKind]$Kind)
    }

    It 'creates missing intermediate keys' {
        Set-VantaRegistryValue -Path "$script:testRoot\Deep\Nested\Key" -Name 'Value' -Type DWord -Data 7
        (Get-Item -Path "$script:testRoot\Deep\Nested\Key").GetValue('Value') | Should -Be 7
    }

    It 'writes the default value when Name is empty (old-context-menu contract)' {
        # The OldContextMenu toggle requires setting a key's DEFAULT value to ''.
        Set-VantaRegistryValue -Path "$script:testRoot\DefaultValue" -Name '' -Type String -Data ''
        $key = Get-Item -Path "$script:testRoot\DefaultValue"
        $key.GetValue('') | Should -Be ''
        $key.GetValueKind('') | Should -Be ([Microsoft.Win32.RegistryValueKind]::String)
    }

    It 'throws when a data-carrying type has no data' {
        { Set-VantaRegistryValue -Path $script:valuesKeyPath -Name 'NoData' -Type DWord } | Should -Throw '*no data*'
    }

    It 'removes the existing value named ''<Name>''' -TestCases @(
        @{ Name = 'ToRemove' }
        @{ Name = '' }
    ) {
        Set-VantaRegistryValue -Path $script:valuesKeyPath -Name $Name -Type String -Data 'x'
        Remove-VantaRegistryValue -Path $script:valuesKeyPath -Name $Name
        (Get-Item -Path $script:valuesKeyPath).GetValue($Name, $null) | Should -BeNullOrEmpty
    }

    It 'does not throw when the value or its key is missing' {
        { Remove-VantaRegistryValue -Path $script:valuesKeyPath -Name 'NeverExisted' } | Should -Not -Throw
        { Remove-VantaRegistryValue -Path "$script:testRoot\NoSuchKey" -Name 'Value' } | Should -Not -Throw
    }
}

Describe 'New-VantaRegistryKey and Remove-VantaRegistryKey' {
    It 'creates a key with missing parents, and again when it exists' {
        New-VantaRegistryKey -Path "$script:testRoot\Keys\Child"
        Test-Path -Path "$script:testRoot\Keys\Child" | Should -BeTrue
        { New-VantaRegistryKey -Path "$script:testRoot\Keys\Child" } | Should -Not -Throw
    }

    It 'removes a key tree recursively, and again when it is gone' {
        New-VantaRegistryKey -Path "$script:testRoot\Keys\Tree\Deeper"
        Remove-VantaRegistryKey -Path "$script:testRoot\Keys\Tree"
        Test-Path -Path "$script:testRoot\Keys\Tree" | Should -BeFalse
        { Remove-VantaRegistryKey -Path "$script:testRoot\Keys\Tree" } | Should -Not -Throw
    }

    It 'refuses to delete the HKCU root' {
        { Remove-VantaRegistryKey -Path 'HKCU:\' } | Should -Throw '*Refusing to delete the registry root*'
    }
}

Describe 'Local machine Group Policy application' {
    BeforeEach {
        Mock Test-VantaAdmin -ModuleName Vanta.Registry { $true }
        Mock Set-VantaMachineDwordPolicyNative -ModuleName Vanta.Registry
        Mock Invoke-VantaHiddenProcess -ModuleName Vanta.Registry
        Mock Test-VantaRegistryEntries -ModuleName Vanta.Registry { @() }
        Mock Write-VantaLog -ModuleName Vanta.Registry
        Mock Set-VantaRegistryValue -ModuleName Vanta.Registry
    }

    It 'persists, refreshes, and verifies a declared machine policy without a direct write' {
        Invoke-VantaRegistryEntries -IsArm64 $false -Entries @(
            @{ Path = 'HKLM:\Software\Policies\Test'; Name = 'Policy'; Type = 'DWord'; Data = 0; UseGroupPolicy = $true }
        )
        Should -Invoke Set-VantaMachineDwordPolicyNative -ModuleName Vanta.Registry -Times 1 -Exactly -ParameterFilter {
            $SubKey -eq 'Software\Policies\Test' -and $Name -eq 'Policy' -and $Data -eq 0
        }
        Should -Invoke Invoke-VantaHiddenProcess -ModuleName Vanta.Registry -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*\gpupdate.exe' -and $ArgumentList -contains '/target:computer' -and $Wait
        }
        Should -Invoke Test-VantaRegistryEntries -ModuleName Vanta.Registry -Times 1 -Exactly -ParameterFilter {
            $Scope -eq 'Machine' -and $Entries[0].Data -eq 0
        }
        Should -Not -Invoke Set-VantaRegistryValue -ModuleName Vanta.Registry
    }

    It 'reports drift even after successful policy save and refresh' {
        Mock Test-VantaRegistryEntries -ModuleName Vanta.Registry { [pscustomobject]@{ Reason = 'value missing' } }
        { Set-VantaMachineDwordPolicy -Path 'HKLM:\Software\Policies\Test' -Name Policy -Data 0 } |
            Should -Throw '*Group Policy did not apply*value missing*'
    }

    It 'does not report success when policy refresh fails' {
        Mock Invoke-VantaHiddenProcess -ModuleName Vanta.Registry { throw 'gpupdate failed' }
        { Set-VantaMachineDwordPolicy -Path 'HKLM:\Software\Policies\Test' -Name Policy -Data 0 } |
            Should -Throw '*gpupdate failed*'
        Should -Not -Invoke Test-VantaRegistryEntries -ModuleName Vanta.Registry
    }

    It 'rejects user and non-policy paths before calling the native editor' {
        foreach ($path in @('HKCU:\Software\Policies\Test', 'HKLM:\Software\Test')) {
            { Set-VantaMachineDwordPolicy -Path $path -Name Policy -Data 0 } | Should -Throw '*HKLM Software*Policies*'
        }
        Should -Not -Invoke Set-VantaMachineDwordPolicyNative -ModuleName Vanta.Registry
    }

    It 'rejects malformed declarations before any mutation' {
        foreach ($entry in @(
                @{ Path = 'HKLM:\Software\Policies\Test'; Name = 'Policy'; Type = 'DWord'; Data = 0; UseGroupPolicy = 'false' }
                @{ Path = 'HKLM:\Software\Policies\Test'; Name = 'Policy'; Operation = 'Delete'; UseGroupPolicy = $true }
            )) {
            { Invoke-VantaRegistryEntries -IsArm64 $false -Entries @($entry) } | Should -Throw '*UseGroupPolicy*'
        }
        Should -Not -Invoke Set-VantaMachineDwordPolicyNative -ModuleName Vanta.Registry
        Should -Not -Invoke Set-VantaRegistryValue -ModuleName Vanta.Registry
    }
}

Describe 'Invoke-VantaRegistryEntries' {
    BeforeEach {
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Registry -MockWith {
            [pscustomobject]@{
                IsArm64  = $false
                LogsPath = Join-Path -Path $TestDrive -ChildPath 'Logs'
            }
        }
        Mock -CommandName Write-VantaLog -ModuleName Vanta.Registry
    }

    It 'applies entries and skips those gated to the other architecture on <Machine>' -TestCases @(
        @{ Machine = 'x64'; IsArm64 = $false; Applied = 'X64Only'; AppliedData = 2; Skipped = 'Arm64Only' }
        @{ Machine = 'arm64'; IsArm64 = $true; Applied = 'Arm64Only'; AppliedData = 3; Skipped = 'X64Only' }
    ) {
        $script:entriesIsArm64 = $IsArm64
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Registry -MockWith {
            [pscustomobject]@{ IsArm64 = $script:entriesIsArm64; LogsPath = Join-Path -Path $TestDrive -ChildPath 'Logs' }
        }
        $path = "$script:testRoot\Entries-$Machine"

        Invoke-VantaRegistryEntries -Entries @(
            @{ Path = $path; Name = 'Ungated'; Type = 'DWord'; Data = 1 }
            @{ Path = $path; Name = 'X64Only'; Type = 'DWord'; Data = 2; Arch = 'X64' }
            @{ Path = $path; Name = 'Arm64Only'; Type = 'DWord'; Data = 3; Arch = 'ARM64' }
        )

        $key = Get-Item -Path $path
        $key.GetValue('Ungated') | Should -Be 1
        $key.GetValue($Applied, $null) | Should -Be $AppliedData
        $key.GetValue($Skipped, $null) | Should -BeNullOrEmpty
    }

    It 'separates protected policy entries from ordinary current-user entries' {
        Mock -CommandName Set-VantaRegistryValue -ModuleName Vanta.Registry
        $entries = @(
            @{ Path = 'HKCU:\Software\Vanta\Preference'; Name = 'Value'; Type = 'DWord'; Data = 1 }
            @{ Path = 'HKCU:\Software\Policies\Vanta\Policy'; Name = 'Value'; Type = 'DWord'; Data = 1 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'Value'; Type = 'DWord'; Data = 1 }
        )

        Invoke-VantaRegistryEntries -Entries $entries -Scope CurrentUser -IsArm64:$false
        Should -Invoke Set-VantaRegistryValue -ModuleName Vanta.Registry -Times 1 -Exactly `
            -ParameterFilter { $Path -eq 'HKCU:\Software\Vanta\Preference' }

        Invoke-VantaRegistryEntries -Entries $entries -Scope ProtectedCurrentUser -IsArm64:$false
        Should -Invoke Set-VantaRegistryValue -ModuleName Vanta.Registry -Times 2 -Exactly `
            -ParameterFilter { $Path -like 'HKCU:*Policies*' }
    }

    It 'supports Delete, AddKey and DeleteKey operations' {
        Set-VantaRegistryValue -Path "$script:testRoot\EntryOps" -Name 'DeleteMe' -Type String -Data 'x'
        New-VantaRegistryKey -Path "$script:testRoot\EntryOps\DeleteThisKey"

        Invoke-VantaRegistryEntries -Entries @(
            @{ Path = "$script:testRoot\EntryOps"; Name = 'DeleteMe'; Operation = 'Delete' }
            @{ Path = "$script:testRoot\EntryOps\DeleteThisKey"; Operation = 'DeleteKey' }
            @{ Path = "$script:testRoot\EntryOps\AddedKey"; Operation = 'AddKey' }
        )

        (Get-Item -Path "$script:testRoot\EntryOps").GetValue('DeleteMe', $null) | Should -BeNullOrEmpty
        Test-Path -Path "$script:testRoot\EntryOps\DeleteThisKey" | Should -BeFalse
        Test-Path -Path "$script:testRoot\EntryOps\AddedKey" | Should -BeTrue
    }

    It 'fails a malformed entry by default' {
        $err = {
            Invoke-VantaRegistryEntries -Entries @(
                @{ Path = "$script:testRoot\EntryFail"; Name = 'Broken' } # Set without a Type
            )
        } | Should -Throw "*Failed to apply registry Set of '$script:testRoot\EntryFail\Broken'*" `
            -ErrorId 'VantaRegistryEntryFailed*' -PassThru
        # The binder's own message is localised, so check the parameter it rejected instead.
        $err.Exception.InnerException | Should -BeOfType ([System.Management.Automation.ParameterBindingException])
        $err.Exception.InnerException.ParameterName | Should -BeExactly 'Type'
    }

    It 'logs and continues when IgnoreErrors is explicit' {
        Invoke-VantaRegistryEntries -Entries @(
            @{ Path = "$script:testRoot\EntryFail"; Name = 'Broken'; IgnoreErrors = $true } # Set without a Type
            @{ Path = "$script:testRoot\EntryFail"; Name = 'After'; Type = 'DWord'; Data = 1 }
        )

        Should -Invoke -CommandName Write-VantaLog -ModuleName Vanta.Registry -Times 1 -Exactly `
            -ParameterFilter { $Level -eq 'Warning' -and $Message -like 'Ignoring failure of registry Set of*Broken*' }
        (Get-Item -Path "$script:testRoot\EntryFail").GetValue('After') | Should -Be 1
    }
}

Describe 'Import-VantaRegFile' {
    It 'imports a .reg file' {
        $regFile = Join-Path -Path $TestDrive -ChildPath 'test.reg'
        @'
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\VantaRewriteTest\RegImport]
"Imported"=dword:00000005
'@ | Set-Content -Path $regFile -Encoding ASCII

        Import-VantaRegFile -Path $regFile
        (Get-Item -Path "$script:testRoot\RegImport").GetValue('Imported') | Should -Be 5
    }

    It 'rejects HKCU imports under LocalSystem because they cannot target the installing user safely' {
        $regFile = Join-Path -Path $TestDrive -ChildPath 'unsafe-hkcu.reg'
        @'
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\VantaRewriteTest\UnsafeImport]
"Imported"=dword:00000005
'@ | Set-Content -Path $regFile -Encoding ASCII

        Mock -CommandName Test-VantaSystem -ModuleName Vanta.Registry -MockWith { $true }

        { Import-VantaRegFile -Path $regFile } | Should -Throw '*cannot select an interactive user*'
        Test-Path -Path "$script:testRoot\UnsafeImport" | Should -BeFalse
        Should -Invoke -CommandName Test-VantaSystem -ModuleName Vanta.Registry -Times 1 -Exactly
    }
}

Describe 'Values Windows itself refuses' {
    BeforeAll {
        $script:RefusedRecord = InModuleScope Vanta.Registry {
            New-VantaRegistryValueRefusedRecord -ProviderPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\X' `
                -Name 'Policy' -Cause (New-Object System.UnauthorizedAccessException('refused'))
        }
    }

    It 'marks a refused value write so callers can tell it apart from an Vanta defect' {
        $record = InModuleScope Vanta.Registry {
            New-VantaRegistryValueRefusedRecord -ProviderPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\X' `
                -Name 'Protected' -Cause (New-Object System.UnauthorizedAccessException('kernel said no'))
        }
        $record.FullyQualifiedErrorId | Should -Be 'VantaRegistryValueWriteRefused'
        $record.Exception | Should -BeOfType [System.UnauthorizedAccessException]
        $record.Exception.Message | Should -Match "value operation for 'Protected'"
        $record.Exception.Message | Should -Match 'cause of the access denial is not established'
        $record.Exception.InnerException.Message | Should -Be 'kernel said no'
        InModuleScope Vanta.Registry -Parameters @{ record = $record } {
            Test-VantaRegistryValueRefused -ErrorRecord $record
        } | Should -BeTrue

        $default = InModuleScope Vanta.Registry {
            New-VantaRegistryValueRefusedRecord -ProviderPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\X' `
                -Name '' -Cause (New-Object System.UnauthorizedAccessException('no'))
        }
        $default.Exception.Message | Should -Match '\(default\)'
    }

    It 'does not mark an ordinary failure as a refusal' {
        $ordinary = try { throw 'something else' } catch { $_ }
        InModuleScope Vanta.Registry -Parameters @{ ordinary = $ordinary } {
            Test-VantaRegistryValueRefused -ErrorRecord $ordinary
        } | Should -BeFalse
    }

    It 'continues past a refused write only when the caller allows it' {
        Mock -CommandName Set-VantaRegistryValueCore -ModuleName Vanta.Registry -MockWith {
            throw $script:RefusedRecord
        }
        Mock -CommandName Write-VantaLog -ModuleName Vanta.Registry -MockWith { }

        { Set-VantaRegistryValue -Path "$script:testRoot\Refused" -Name 'Policy' -Type DWord -Data 1 } |
            Should -Throw '*cause of the access denial is not established*'

        { Set-VantaRegistryValue -Path "$script:testRoot\Refused" -Name 'Policy' -Type DWord -Data 1 -AllowOsProtected } |
            Should -Not -Throw
        Should -Invoke -CommandName Write-VantaLog -ModuleName Vanta.Registry -Times 1 -Exactly `
            -ParameterFilter { $Level -eq 'Warning' -and $Message -match 'Continuing without it' }
    }

    It 'still fails on an ordinary error when the caller allows refusals' {
        Mock -CommandName Set-VantaRegistryValueCore -ModuleName Vanta.Registry -MockWith { throw 'disk is on fire' }

        { Set-VantaRegistryValue -Path "$script:testRoot\Refused" -Name 'Policy' -Type DWord -Data 1 -AllowOsProtected } |
            Should -Throw '*disk is on fire*'
    }

    It 'continues past a refused delete only when the caller allows it' {
        Mock -CommandName Write-VantaLog -ModuleName Vanta.Registry -MockWith { }
        # RegistryKey.DeleteValue returns normally when Windows refuses the delete; the
        # value is simply still there afterwards.
        Mock -CommandName Split-VantaRegistryProviderPath -ModuleName Vanta.Registry -MockWith {
            $key = New-Object -TypeName psobject
            $key | Add-Member -MemberType ScriptMethod -Name DeleteValue -Value { }
            $key | Add-Member -MemberType ScriptMethod -Name GetValueNames -Value { , [string[]]@('Policy') }
            $key | Add-Member -MemberType ScriptMethod -Name Close -Value { }
            $baseKey = New-Object -TypeName psobject
            $baseKey | Add-Member -MemberType NoteProperty -Name Key -Value $key
            $baseKey | Add-Member -MemberType ScriptMethod -Name OpenSubKey -Value { $this.Key }
            [pscustomobject]@{ BaseKey = $baseKey; SubPath = 'Software\VantaRewriteTest\Delete' }
        }

        { Remove-VantaRegistryValue -Path "$script:testRoot\Delete" -Name 'Policy' } |
            Should -Throw -ErrorId 'VantaRegistryValueWriteRefused'
        { Remove-VantaRegistryValue -Path "$script:testRoot\Delete" -Name 'Policy' -AllowOsProtected } |
            Should -Not -Throw
        Should -Invoke -CommandName Write-VantaLog -ModuleName Vanta.Registry -Times 1 -Exactly `
            -ParameterFilter { $Level -eq 'Warning' -and $Message -match 'Continuing without removing it' }
    }

    It 'continues when the reported background-app preference is refused but still applies the main preference' {
        $definition = Import-PowerShellDataFile (Join-Path $script:VantaTestScriptsRoot 'Tweaks\performance\disable-background-apps.psd1')
        $entries = $definition.Registry
        foreach ($entry in $entries) { $entry.Path = "$script:testRoot\BackgroundApps" }
        Mock Set-VantaRegistryValueCore -ModuleName Vanta.Registry {
            if ($Name -eq 'BackgroundAppGlobalToggle') { throw $script:RefusedRecord }
        }
        Mock Write-VantaLog -ModuleName Vanta.Registry {}
        { Invoke-VantaRegistryEntries -Entries $entries -IsArm64 $false } | Should -Not -Throw
        Should -Invoke Set-VantaRegistryValueCore -ModuleName Vanta.Registry -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'GlobalUserDisabled' -and $Data -eq 1
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Registry -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -match 'Continuing without it'
        }
    }

    It 'reports a refused value as drift so nothing is lost silently' {
        New-Item -Path "$script:testRoot\Drift" -Force | Out-Null
        $entries = @(
            @{ Path = "$script:testRoot\Drift"; Name = 'Policy'; Type = 'DWord'; Data = 1; AllowOsProtected = $true }
        )
        @(Test-VantaRegistryEntries -Entries $entries -IsArm64 $false).Reason | Should -Be 'value is missing'
    }
}

Describe 'Registry entry failure reporting' {
    It 'names the entry that failed instead of only the registry error' {
        Mock -CommandName Set-VantaRegistryValue -ModuleName Vanta.Registry -MockWith { throw 'raw registry error' }

        {
            Invoke-VantaRegistryEntries -IsArm64 $false -Entries @(
                @{ Path = "$script:testRoot\Entry"; Name = 'Broken'; Type = 'DWord'; Data = 1 }
            )
        } | Should -Throw "*registry Set of 'HKCU:\Software\VantaRewriteTest\Entry\Broken'*raw registry error*"
    }

    It 'passes an entry AllowOsProtected declaration to the value writer' {
        Mock -CommandName Set-VantaRegistryValue -ModuleName Vanta.Registry -MockWith { }
        Mock -CommandName Remove-VantaRegistryValue -ModuleName Vanta.Registry -MockWith { }

        Invoke-VantaRegistryEntries -IsArm64 $false -Entries @(
            @{ Path = "$script:testRoot\Entry"; Name = 'Policy'; Type = 'DWord'; Data = 1; AllowOsProtected = $true }
            @{ Path = "$script:testRoot\Entry"; Name = 'Plain'; Type = 'DWord'; Data = 1 }
            @{ Path = "$script:testRoot\Entry"; Name = 'Gone'; Operation = 'Delete'; AllowOsProtected = $true }
        )

        Should -Invoke -CommandName Set-VantaRegistryValue -ModuleName Vanta.Registry -Times 1 -Exactly `
            -ParameterFilter { $Name -eq 'Policy' -and $AllowOsProtected }
        Should -Invoke -CommandName Set-VantaRegistryValue -ModuleName Vanta.Registry -Times 1 -Exactly `
            -ParameterFilter { $Name -eq 'Plain' -and -not $AllowOsProtected }
        Should -Invoke -CommandName Remove-VantaRegistryValue -ModuleName Vanta.Registry -Times 1 -Exactly `
            -ParameterFilter { $Name -eq 'Gone' -and $AllowOsProtected }
    }
}
