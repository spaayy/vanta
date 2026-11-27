[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    '',
    Justification = 'Pester BeforeAll variables are consumed from child test scopes.'
)]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $script:ModulesRoot = Join-Path -Path $PSScriptRoot `
        -ChildPath '..\package\Executables\VantaModules\Scripts\Modules'
    Import-Module -Name (Join-Path $script:ModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module -Name (Join-Path $script:ModulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force

    & (Get-Module Vanta.Core) { Initialize-VantaNativeType }

    $script:ToggleRoot = Join-Path $TestDrive 'Toggles'
    $definitionRoot = Join-Path $script:ToggleRoot 'Privilege'
    New-Item -Path $definitionRoot -ItemType Directory -Force | Out-Null

    $script:EventPath = Join-Path $TestDrive 'privilege-events.txt'
    $env:VANTA_PRIVILEGE_TEST_EVENTS = $script:EventPath

    $companion = @'
function Write-VantaPrivilegeMachineEvent {
    param($Toggle)
    [IO.File]::AppendAllText($env:VANTA_PRIVILEGE_TEST_EVENTS, "machine`n")
}

function Write-VantaPrivilegeUserEvent {
    param($Toggle)
    [IO.File]::AppendAllText($env:VANTA_PRIVILEGE_TEST_EVENTS, "user`n")
}
'@
    $splitTemplate = @'
@{
    Name          = '__NAME__'
    Elevation     = '__ELEVATION__'
    Warning       = 'Confirm split action.'
    NoStateRecord = $true
    Script        = '__NAME__.ps1'
    States        = @(
        @{ Name = 'Enable'; Launcher = 'Privilege\__NAME__.cmd'; Reboot = 'None'; MachineAction = 'Write-VantaPrivilegeMachineEvent'; UserAction = 'Write-VantaPrivilegeUserEvent' }
    )
}
'@
    foreach ($definition in @(
            @{ Name = 'SplitAdmin'; Elevation = 'Admin' }
            @{ Name = 'SplitTrusted'; Elevation = 'TrustedInstaller' }
        )) {
        $content = $splitTemplate.Replace('__NAME__', $definition.Name).
            Replace('__ELEVATION__', $definition.Elevation)
        Set-Content -LiteralPath (Join-Path $definitionRoot "$($definition.Name).psd1") `
            -Value $content -Encoding Ascii
        Set-Content -LiteralPath (Join-Path $definitionRoot "$($definition.Name).ps1") `
            -Value $companion -Encoding Ascii
    }
}

AfterAll {
    Remove-Item Env:\VANTA_PRIVILEGE_TEST_EVENTS -ErrorAction SilentlyContinue
}

Describe 'Vanta process privilege decisions' {
    It 'reads enabled and deny-only groups without duplicating the token' {
        $nativeType = [Vanta.Native.TrustedInstallerProcess]
        $openToken = $nativeType.GetMethod('OpenProcessToken', [Reflection.BindingFlags]'Static,NonPublic')
        $hasGroup = $nativeType.GetMethod('HasEnabledGroup', [Reflection.BindingFlags]'Static,NonPublic')
        $closeHandle = $nativeType.GetMethod('CloseHandle', [Reflection.BindingFlags]'Static,NonPublic')
        $openArguments = [object[]]@([Diagnostics.Process]::GetCurrentProcess().Handle, [uint32]8, [IntPtr]::Zero)
        $openToken.Invoke($null, $openArguments) | Should -BeTrue
        $token = $openArguments[2]
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        try {
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            foreach ($sid in @('S-1-5-32-545', 'S-1-5-32-544', 'S-1-5-32-9999')) {
                $expected = $principal.IsInRole([Security.Principal.SecurityIdentifier]::new($sid))
                $hasGroup.Invoke($null, @($token, $sid)) | Should -Be $expected
            }
        }
        finally {
            $identity.Dispose()
            [void]$closeHandle.Invoke($null, @($token))
        }
    }

    It 'reads fixed-size elevation and session values from the real current token' {
        $nativeType = [Vanta.Native.TrustedInstallerProcess]
        $informationClass = $nativeType.GetNestedType('TOKEN_INFORMATION_CLASS', [Reflection.BindingFlags]'NonPublic')
        $readScalar = $nativeType.GetMethod('ReadTokenInt32', [Reflection.BindingFlags]'Static,NonPublic')
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        try {
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            $expectedElevation = [int]$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            $readScalar.Invoke($null, @($identity.Token, [Enum]::Parse($informationClass, 'TokenElevation'))) |
                Should -Be $expectedElevation
            $readScalar.Invoke($null, @($identity.Token, [Enum]::Parse($informationClass, 'TokenSessionId'))) |
                Should -Be ([Diagnostics.Process]::GetCurrentProcess().SessionId)
        }
        finally { $identity.Dispose() }
    }

    It 'does not accept the real current token as TrustedInstaller' {
        Test-VantaTrustedInstaller | Should -BeFalse
        { Assert-VantaPrivilege -TrustedInstaller } | Should -Throw '*TrustedInstaller service token*'
    }

    It 'accepts only the strict TrustedInstaller token shape' -TestCases @(
        @{ Sid = 'S-1-5-18'; Present = $true; Attributes = [uint32]0x4; Integrity = 0x4000; Expected = $true }
        @{ Sid = 'S-1-5-21-1-2-3-1001'; Present = $true; Attributes = [uint32]0x4; Integrity = 0x4000; Expected = $false }
        @{ Sid = 'S-1-5-18'; Present = $false; Attributes = [uint32]0x0; Integrity = 0x4000; Expected = $false }
        @{ Sid = 'S-1-5-18'; Present = $true; Attributes = [uint32]0x14; Integrity = 0x4000; Expected = $false }
        @{ Sid = 'S-1-5-18'; Present = $true; Attributes = [uint32]0x4; Integrity = 0x3000; Expected = $false }
    ) {
        param($Sid, $Present, $Attributes, $Integrity, $Expected)

        [Vanta.Native.TrustedInstallerProcess]::IsStrictTrustedInstallerEvidence(
            $Sid,
            [bool]$Present,
            [uint32]$Attributes,
            [int]$Integrity
        ) | Should -Be $Expected
    }
}

Describe 'Vanta toggle privilege routing' {
    BeforeEach {
        Remove-Item -LiteralPath $script:EventPath -Force -ErrorAction SilentlyContinue

        Mock -CommandName Test-VantaAdmin -ModuleName Vanta.Toggles -MockWith { $false }
        Mock -CommandName Test-VantaSystem -ModuleName Vanta.Toggles -MockWith { $false }
        Mock -CommandName Test-VantaTrustedInstaller -ModuleName Vanta.Toggles -MockWith { $false }
        Mock -CommandName Wait-VantaContinue -ModuleName Vanta.Toggles
        Mock -CommandName Wait-VantaExit -ModuleName Vanta.Toggles
        Mock -CommandName Write-VantaTitle -ModuleName Vanta.Toggles
        Mock -CommandName Write-VantaCompletion -ModuleName Vanta.Toggles
        Mock -CommandName Write-VantaLog -ModuleName Vanta.Toggles
        Mock -CommandName Get-VantaContext -ModuleName Vanta.Toggles -MockWith {
            [pscustomobject]@{
                WinDir           = [Environment]::GetFolderPath('Windows')
                VantaModulesPath = 'C:\VantaModules'
                WindowsBuild     = 26100
            }
        }
        Mock -CommandName Start-VantaToggleAdminRelaunch -ModuleName Vanta.Toggles -MockWith {
            [pscustomobject]@{ ExitCode = 0 }
        }
        Mock -CommandName Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles -MockWith {
            [pscustomobject]@{ ExitCode = 0 }
        }
    }

    It 'runs the machine child before the user action when SID and session remain exact' {
        $script:CallerBindings = [Collections.Generic.Queue[object]]::new()
        foreach ($unused in 1..2) {
            $script:CallerBindings.Enqueue([pscustomobject]@{
                    Sid       = 'S-1-5-21-111-222-333-1001'
                    SessionId = 7
                })
        }
        Mock -CommandName Get-VantaToggleUserCallerBinding -ModuleName Vanta.Toggles -MockWith {
            $script:CallerBindings.Dequeue()
        }
        Mock -CommandName Start-VantaToggleAdminRelaunch -ModuleName Vanta.Toggles -MockWith {
            [IO.File]::AppendAllText($script:EventPath, "machine-child`n")
            [pscustomobject]@{ ExitCode = 0 }
        }

        Invoke-VantaToggle -Name SplitAdmin -State Enable -NoExplorerRestart `
            -TogglesRoot $script:ToggleRoot

        Get-Content -LiteralPath $script:EventPath | Should -Be @('machine-child', 'user')
        Should -Invoke -CommandName Start-VantaToggleAdminRelaunch -ModuleName Vanta.Toggles `
            -Times 1 -Exactly -ParameterFilter { $ArgumentList -contains '-MachineOnly' }
        Should -Not -Invoke -CommandName Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles
        Should -Invoke -CommandName Wait-VantaContinue -ModuleName Vanta.Toggles -Times 1 -Exactly
    }

    It 'routes a normal split TrustedInstaller caller through Administrator and the TI broker before the bound user action' {
        $script:CallerBindings = [Collections.Generic.Queue[object]]::new()
        foreach ($unused in 1..2) {
            $script:CallerBindings.Enqueue([pscustomobject]@{
                    Sid       = 'S-1-5-21-111-222-333-1001'
                    SessionId = 7
                })
        }
        $script:InElevatedChild = $false
        Mock -CommandName Get-VantaToggleUserCallerBinding -ModuleName Vanta.Toggles -MockWith {
            $script:CallerBindings.Dequeue()
        }
        Mock -CommandName Test-VantaAdmin -ModuleName Vanta.Toggles -MockWith {
            $script:InElevatedChild
        }
        Mock -CommandName Start-VantaToggleAdminRelaunch -ModuleName Vanta.Toggles -MockWith {
            [IO.File]::AppendAllText($script:EventPath, "admin-child`n")
            $script:InElevatedChild = $true
            try {
                Invoke-VantaToggle -Name SplitTrusted -State Enable -Silent -MachineOnly `
                    -TogglesRoot $script:ToggleRoot
            }
            finally {
                $script:InElevatedChild = $false
            }
            [pscustomobject]@{ ExitCode = 0 }
        }
        Mock -CommandName Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles -MockWith {
            [IO.File]::AppendAllText($script:EventPath, "ti-broker`n")
            [pscustomobject]@{ ExitCode = 0 }
        }

        Invoke-VantaToggle -Name SplitTrusted -State Enable -NoExplorerRestart `
            -TogglesRoot $script:ToggleRoot

        Get-Content -LiteralPath $script:EventPath | Should -Be @(
            'admin-child'
            'ti-broker'
            'user'
        )
        Should -Invoke -CommandName Start-VantaToggleAdminRelaunch -ModuleName Vanta.Toggles `
            -Times 1 -Exactly -ParameterFilter { $ArgumentList -contains '-MachineOnly' }
        Should -Invoke -CommandName Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles `
            -Times 1 -Exactly -ParameterFilter {
                $Operation -ceq 'Toggle' -and
                    $Name -ceq 'SplitTrusted' -and
                    $State -ceq 'Enable' -and
                    $Silent -and
                    $NoExplorerRestart -and
                    $MachineOnly
            }
        Should -Invoke -CommandName Wait-VantaContinue -ModuleName Vanta.Toggles -Times 1 -Exactly
    }

    It 'lets a strict TrustedInstaller child run only the declared machine action' {
        Mock -CommandName Test-VantaTrustedInstaller -ModuleName Vanta.Toggles -MockWith { $true }

        Invoke-VantaToggle -Name SplitTrusted -State Enable -Silent -MachineOnly `
            -TogglesRoot $script:ToggleRoot

        Get-Content -LiteralPath $script:EventPath | Should -Be @('machine')
        Should -Not -Invoke -CommandName Invoke-VantaTrustedInstaller -ModuleName Vanta.Toggles
    }
}
