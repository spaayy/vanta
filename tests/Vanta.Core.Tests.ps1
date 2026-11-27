BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $modulesRoot = $script:VantaTestModulesRoot
    Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Core\Vanta.Core.psd1') -Force
    $coreModule = Get-Module -Name Vanta.Core
    & $coreModule { Initialize-VantaNativeType }
}

Describe 'Get-VantaContext install state' {
    BeforeEach {
        & $coreModule { $script:VantaContext = $null }
    }

    It 'maps the active install state and selected options into the shared context' {
        $windowsPath = Join-Path -Path $TestDrive -ChildPath 'Windows'
        [void][IO.Directory]::CreateDirectory($windowsPath)
        $transactionId = '31f30158-28ea-4e0c-86b5-d8f3e33b81f5'
        # Install states that older Vanta releases wrote also carry isOobe, which the
        # context ignores.
        $state = [pscustomobject]@{
            mode          = 'Upgrade'
            isOobe        = $true
            targetVersion = '0.5.1'
            userSid       = 'S-1-5-21-1-2-3-1001'
            userSessionId = 7
            transactionId = $transactionId
            options       = @('defender-disable', 'browser-brave')
        }
        $observedPaths = [Collections.Generic.List[string]]::new()
        $stateReader = {
            param($path)
            [void]$observedPaths.Add($path)
            return $state
        }.GetNewClosure()

        $context = Get-VantaContext -Refresh -WindowsPath $windowsPath `
            -StateReader $stateReader -WindowsBuildReader { 26100 }

        $observedPaths | Should -HaveCount 1
        $observedPaths[0] | Should -BeExactly (
            Join-Path -Path $windowsPath -ChildPath 'VantaOS\Install\active.json'
        )
        $context.IsInstallStateBacked | Should -BeTrue
        $context.Mode | Should -BeExactly 'Upgrade'
        $context.IsUpgrade | Should -BeTrue
        $context.PSObject.Properties['IsOobe'] | Should -BeNullOrEmpty
        $context.TargetVersion | Should -BeExactly '0.5.1'
        $context.InteractiveUserSid | Should -BeExactly 'S-1-5-21-1-2-3-1001'
        $context.InteractiveUserSessionId | Should -Be 7
        $context.TransactionId | Should -BeExactly $transactionId
        $context.Options | Should -Be @('defender-disable', 'browser-brave')
        Test-VantaOption -Name 'defender-disable' | Should -BeTrue
        Test-VantaOption -Name 'browser-firefox' | Should -BeFalse
    }

    It 'keeps the orchestrator install-state commands loaded while reading active state' {
        $stateManifest = Join-Path -Path $modulesRoot `
            -ChildPath 'Vanta.InstallState\Vanta.InstallState.psd1'
        $windowsPath = Join-Path -Path $TestDrive -ChildPath 'ModuleLifetimeWindows'
        $statePath = Join-Path -Path $windowsPath -ChildPath 'VantaOS\Install\active.json'
        try {
            Import-Module -Name $stateManifest -Force -DisableNameChecking
            $started = Start-VantaInstallState -TargetVersion '0.6.0' -Mode Fresh `
                -StatePath $statePath
            $before = Get-Module -Name Vanta.InstallState

            $context = Get-VantaContext -Refresh -WindowsPath $windowsPath `
                -WindowsBuildReader { 26200 }

            $context.IsInstallStateBacked | Should -BeTrue
            $context.TransactionId | Should -BeExactly ([string]$started.transactionId)
            # Command lookup would autoload a torn-down module again from PSModulePath,
            # so check the function table and the module instance directly.
            Test-Path -LiteralPath Function:\Invoke-VantaInstallStep | Should -BeTrue
            [object]::ReferenceEquals($before, (Get-Module -Name Vanta.InstallState)) | Should -BeTrue
        }
        finally {
            Remove-Module -Name Vanta.InstallState -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reads the update path from the install state: <Choices> on <Mode>' -TestCases @(
        @{ Mode = 'Upgrade'; Choices = 'ChooseAgain'; Expected = 'ChooseAgain'; ChoosingAgain = $true }
        @{ Mode = 'Reapply'; Choices = 'ChooseAgain'; Expected = 'ChooseAgain'; ChoosingAgain = $true }
        @{ Mode = 'Reapply'; Choices = 'Keep'; Expected = 'Keep'; ChoosingAgain = $false }
        # A first installation applies every choice and a Rebase keeps them, whatever is stored.
        @{ Mode = 'Fresh'; Choices = 'ChooseAgain'; Expected = 'ChooseAgain'; ChoosingAgain = $false }
        @{ Mode = 'Rebase'; Choices = 'ChooseAgain'; Expected = 'ChooseAgain'; ChoosingAgain = $false }
        # An install state written before the path existed.
        @{ Mode = 'Upgrade'; Choices = $null; Expected = 'Keep'; ChoosingAgain = $false }
    ) {
        param($Mode, $Choices, $Expected, $ChoosingAgain)
        $state = [ordered]@{
            mode = $Mode; targetVersion = '0.6.0'; userSid = $null; userSessionId = $null
            transactionId = '31f30158-28ea-4e0c-86b5-d8f3e33b81f5'; options = @()
        }
        if ($null -ne $Choices) { $state.choices = $Choices }
        $state = [pscustomobject]$state
        $context = Get-VantaContext -Refresh -WindowsPath (Join-Path $TestDrive 'Windows') `
            -StateReader { $state }.GetNewClosure() -WindowsBuildReader { 26200 }
        $context.Choices | Should -BeExactly $Expected
        $context.IsChoosingAgain | Should -Be $ChoosingAgain
    }

    It 'refuses an update path it doesn''t know' {
        $state = [pscustomobject]@{ mode = 'Upgrade'; targetVersion = '0.6.0'; userSid = $null; userSessionId = $null; transactionId = 'x'; options = @(); choices = 'Sometimes' }
        $reader = { $state }.GetNewClosure()
        { Get-VantaContext -Refresh -WindowsPath (Join-Path $TestDrive 'Windows') -StateReader $reader -WindowsBuildReader { 26200 } } |
            Should -Throw "*choices value 'Sometimes' is invalid*"
    }

    It 'never chooses again outside an install' {
        $document = [pscustomobject]@{ installedVersion = '0.6.0'; mode = 'Reapply'; options = @(); history = @() }
        $context = Get-VantaContext -Refresh -WindowsPath (Join-Path $TestDrive 'Windows') -StateReader { $null } `
            -DocumentReader { $document }.GetNewClosure() -WindowsBuildReader { 26200 }
        $context.Choices | Should -BeExactly 'Keep'
        $context.IsChoosingAgain | Should -BeFalse
    }

    It 'uses published completion flags after active state is archived' {
        $windowsPath = Join-Path -Path $TestDrive -ChildPath 'FlagBackedWindows'
        $flagsPath = Join-Path -Path $windowsPath -ChildPath 'VantaModules\Flags'
        [void][IO.Directory]::CreateDirectory($flagsPath)
        [IO.File]::WriteAllText((Join-Path $flagsPath 'Upgrade.flag'), '')
        [IO.File]::WriteAllText((Join-Path $flagsPath 'option-browser-firefox.flag'), '')

        $context = Get-VantaContext -Refresh -WindowsPath $windowsPath `
            -StateReader { $null } -DocumentReader { $null } -WindowsBuildReader { 19045 }

        $context.IsInstallStateBacked | Should -BeFalse
        $context.IsStateDocumentBacked | Should -BeFalse
        $context.Mode | Should -BeExactly 'Legacy'
        $context.IsUpgrade | Should -BeTrue
        $context.TargetVersion | Should -BeNullOrEmpty
        $context.InteractiveUserSid | Should -BeNullOrEmpty
        $context.InteractiveUserSessionId | Should -BeNullOrEmpty
        $context.TransactionId | Should -BeNullOrEmpty
        $context.Options | Should -BeNullOrEmpty
        Test-VantaOption -Name 'browser-firefox' | Should -BeTrue
        Test-VantaOption -Name 'browser-brave' | Should -BeFalse
    }
}

Describe 'Write-VantaLog fallback' {
    It 'routes unelevated diagnostics away from the protected machine log' {
        Mock Test-VantaAdmin { $false } -ModuleName Vanta.Core
        Mock Get-VantaContext { throw 'Unelevated logging must not resolve the machine log' } -ModuleName Vanta.Core
        Mock Test-Path { $true } -ModuleName Vanta.Core

        $expected = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Vanta\Logs\install\vanta-install.log'
        Get-VantaInstallLogPath | Should -BeExactly $expected
    }

    It 'keeps elevated diagnostics in the protected machine log without reading install state' {
        & $coreModule { $script:VantaContext = $null }
        Mock Test-VantaAdmin { $true } -ModuleName Vanta.Core
        Mock Get-VantaContext { throw 'Elevated logging must not read the install-state documents' } -ModuleName Vanta.Core
        Mock Test-Path { $true } -ModuleName Vanta.Core

        $expected = Join-Path ([Environment]::GetFolderPath('Windows')) 'VantaModules\Logs\install\vanta-install.log'
        Get-VantaInstallLogPath | Should -BeExactly $expected
    }

    It 'keeps elevated diagnostics in the log folder of a context that is already loaded' {
        # Elevated entry scripts load the context before anything logs.
        $windowsPath = Join-Path -Path $TestDrive -ChildPath 'LoadedContextWindows'
        [void][IO.Directory]::CreateDirectory($windowsPath)
        Get-VantaContext -Refresh -WindowsPath $windowsPath -StateReader { $null } `
            -DocumentReader { $null } -WindowsBuildReader { 26100 } | Out-Null
        try {
            Mock Test-VantaAdmin { $true } -ModuleName Vanta.Core
            Mock Get-VantaContext { throw 'Elevated logging must not reload the context' } -ModuleName Vanta.Core
            Mock Test-Path { $true } -ModuleName Vanta.Core

            $expected = Join-Path $windowsPath 'VantaModules\Logs\install\vanta-install.log'
            Get-VantaInstallLogPath | Should -BeExactly $expected
        }
        finally {
            & $coreModule { $script:VantaContext = $null }
        }
    }

    It 'returns no log path instead of throwing when the log folder is unavailable' {
        Mock Test-VantaAdmin { $false } -ModuleName Vanta.Core
        Mock Test-Path { $false } -ModuleName Vanta.Core
        Mock New-Item { throw 'simulated access denial' } -ModuleName Vanta.Core

        Get-VantaInstallLogPath | Should -BeNullOrEmpty
    }

    It 'does not turn a log access failure into a terminating error under strict callers' {
        Mock Write-VantaLogFile { throw 'simulated log access denial' } -ModuleName Vanta.Core

        {
            $ErrorActionPreference = 'Stop'
            Write-VantaLog -Message 'best-effort diagnostic'
        } | Should -Not -Throw

        Should -Invoke Write-VantaLogFile -ModuleName Vanta.Core -Times 1
    }
}

Describe 'Get-VantaUserProcessCommandLine' {
    It 'quotes the executable and appends the raw arguments after one space: <Expected>' -TestCases @(
        @{ FilePath = 'C:\Program Files\x.exe'; Arguments = ''; Expected = '"C:\Program Files\x.exe"' }
        @{ FilePath = 'C:\x.exe'; Arguments = '-Flag "va lue"'; Expected = '"C:\x.exe" -Flag "va lue"' }
    ) {
        Get-VantaUserProcessCommandLine -FilePath $FilePath -Arguments $Arguments |
            Should -BeExactly $Expected
    }
}

Describe 'Get-VantaUserSessionHelperStage' {
    It 'names the stage for session-helper exit code <ExitCode>' -TestCases @(
        @{ ExitCode = 10; Expected = 'bootstrap' }
        @{ ExitCode = 12; Expected = 'process stop' }
        @{ ExitCode = 17; Expected = 'operation selection' }
    ) {
        Get-VantaUserSessionHelperStage -ExitCode $ExitCode | Should -BeExactly $Expected
    }

    It 'returns $null for an exit code the session helper never uses' {
        $null -eq (Get-VantaUserSessionHelperStage -ExitCode 1) | Should -BeTrue
    }
}

Describe 'Invoke-VantaAsUser' {
    # Mocks only: the CreateProcessAsUser path must never launch anything from a test.
    It 'throws when the caller is not SYSTEM' {
        Mock Test-VantaSystem { $false } -ModuleName Vanta.Core

        { Invoke-VantaAsUser -FilePath 'C:\Windows\System32\cmd.exe' } |
            Should -Throw -ExpectedMessage '*must run as SYSTEM*'
    }
}

Describe 'Invoke-VantaTrustedInstaller' {
    BeforeEach {
        Mock Assert-VantaPrivilege -ModuleName Vanta.Core
        Mock Get-VantaContext {
            [pscustomobject]@{
                WinDir = [Environment]::GetFolderPath('Windows')
                VantaModulesPath = 'C:\Windows\VantaModules'
            }
        } -ModuleName Vanta.Core
        Mock Invoke-VantaHiddenProcess {
            [pscustomobject]@{ ExitCode = 0; StandardOutput = ''; StandardError = '' }
        } -ModuleName Vanta.Core
    }

    It 'exports only the closed operation API and takes no raw command parameters' {
        $command = Get-Command Invoke-VantaTrustedInstaller
        $command.Parameters.Keys | Should -Contain 'Operation'
        foreach ($forbidden in @(
                'CommandLine', 'Command', 'Executable', 'ScriptPath', 'ArgumentList',
                'Arguments', 'InputPath'
            )) {
            $command.Parameters.Keys | Should -Not -Contain $forbidden
        }
        $commonParameters = @(
            'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
            'ProgressAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable',
            'OutVariable', 'OutBuffer', 'PipelineVariable'
        )
        $operationParameters = @($command.Parameters.Keys |
            Where-Object { $_ -cnotin $commonParameters } |
            Sort-Object)
        $expectedParameters = @(
            'Operation', 'Name', 'State', 'Silent', 'JustContext', 'NoExplorerRestart', 'MachineOnly',
            'RestoreSource', 'InstallPhase', 'PackageRoot', 'TimeoutSeconds'
        ) | Sort-Object
        $operationParameters | Should -Be $expectedParameters
    }

    It 'rejects incomplete typed operations before asking for elevation' {
        { Invoke-VantaTrustedInstaller -Operation Toggle } |
            Should -Throw -ExpectedMessage '*requires typed -Name and -State*'
        { Invoke-VantaTrustedInstaller -Operation ResetServices } |
            Should -Throw -ExpectedMessage '*requires a typed -RestoreSource*'
        { Invoke-VantaTrustedInstaller -Operation RegistryImport } | Should -Throw
        Should -Invoke Assert-VantaPrivilege -ModuleName Vanta.Core -Times 0 -Exactly
    }

    It 'rejects every operation input outside the selected operation schema' {
        { Invoke-VantaTrustedInstaller -Operation Toggle -Name Test -State Enable `
                -RestoreSource ToggleDefaults } |
            Should -Throw -ExpectedMessage "*Toggle does not accept*'-RestoreSource'*"
        { Invoke-VantaTrustedInstaller -Operation ResetServices -RestoreSource ToggleDefaults `
                -Name Test } |
            Should -Throw -ExpectedMessage "*ResetServices does not accept*'-Name'*"
        { Invoke-VantaTrustedInstaller -Operation ResetServices -RestoreSource ToggleDefaults `
                -MachineOnly } |
            Should -Throw -ExpectedMessage "*ResetServices does not accept*'-MachineOnly'*"
        { Invoke-VantaTrustedInstaller -Operation Install -Name Test -InstallPhase Run `
                -PackageRoot 'C:\Windows\VantaOS\Staging\candidate\Executables' } |
            Should -Throw -ExpectedMessage "*Install does not accept*'-Name'*"
        { Invoke-VantaTrustedInstaller -Operation Toggle -Name Test -State Enable -InstallPhase Run } |
            Should -Throw -ExpectedMessage "*Toggle does not accept*'-InstallPhase'*"
    }

    It 'passes only typed operation arguments to the fixed checked broker' {
        Invoke-VantaTrustedInstaller -Operation Toggle -Name TestToggle -State Enable `
            -JustContext -TimeoutSeconds 42 | Out-Null

        Should -Invoke Invoke-VantaHiddenProcess -ModuleName Vanta.Core -Times 1 -Exactly `
            -ParameterFilter {
                $FilePath -like '*\System32\WindowsPowerShell\v1.0\powershell.exe' -and
                @($ArgumentList | Where-Object {
                        $_ -like '*\Scripts\Entry\Invoke-VantaTrustedInstallerBroker.ps1'
                    }).Count -eq 1 -and
                $ArgumentList -contains 'TestToggle' -and
                $ArgumentList -contains 'Enable' -and
                $ArgumentList -contains '-JustContext' -and
                $TimeoutSeconds -eq 57 -and
                $Wait -and $CaptureOutput -and
                $null -eq $AllowedExitCode
            }
    }

    It 'uses the candidate broker for fresh install <Phase>' -TestCases @(
        @{ Phase = 'Capture' }
        @{ Phase = 'Run' }
    ) {
        $staged = Join-Path ([Environment]::GetFolderPath('Windows')) 'VantaOS\Staging\candidate\Executables'
        $broker = Join-Path $staged 'VantaModules\Scripts\Entry\Invoke-VantaTrustedInstallerBroker.ps1'

        Invoke-VantaTrustedInstaller -Operation Install -InstallPhase $Phase -PackageRoot $staged | Out-Null

        Should -Invoke Invoke-VantaHiddenProcess -ModuleName Vanta.Core -Times 1 -Exactly `
            -ParameterFilter {
                $arguments = @($ArgumentList)
                $arguments[[array]::IndexOf($arguments, '-File') + 1] -eq $broker -and
                $arguments[[array]::IndexOf($arguments, '-Operation') + 1] -ceq 'Install' -and
                $arguments[[array]::IndexOf($arguments, '-InstallPhase') + 1] -ceq $Phase -and
                $arguments[[array]::IndexOf($arguments, '-PackageRoot') + 1] -eq $staged
            }
    }

    It 'rejects install roots outside staging before starting a broker' {
        foreach ($staged in @('relative', 'C:\Users\Public\staged',
                'C:\Windows\VantaOS\Staging-other\staged', 'C:\Windows\VantaOS\Staging\..\staged')) {
            { Invoke-VantaTrustedInstaller -Operation Install -InstallPhase Capture -PackageRoot $staged } | Should -Throw
        }
        Should -Not -Invoke Invoke-VantaHiddenProcess -ModuleName Vanta.Core
    }

    It 'runs the input-free CbsRetry operation through the installed broker' {
        Invoke-VantaTrustedInstaller -Operation CbsRetry -TimeoutSeconds 3600 | Out-Null

        Should -Invoke Invoke-VantaHiddenProcess -ModuleName Vanta.Core -Times 1 -Exactly `
            -ParameterFilter {
                $arguments = @($ArgumentList)
                $fileIndex = [array]::IndexOf($arguments, '-File')
                $arguments[$fileIndex + 1] -eq 'C:\Windows\VantaModules\Scripts\Entry\Invoke-VantaTrustedInstallerBroker.ps1' -and
                ($arguments[($fileIndex + 2)..($arguments.Count - 1)] -join ' ') -ceq '-Operation CbsRetry -TimeoutSeconds 3600' -and
                $TimeoutSeconds -eq 3615
            }
    }

    It 'rejects every operation input for CbsRetry' {
        { Invoke-VantaTrustedInstaller -Operation CbsRetry -Name Test } |
            Should -Throw -ExpectedMessage "*CbsRetry does not accept*'-Name'*"
        { Invoke-VantaTrustedInstaller -Operation CbsRetry -RestoreSource ToggleDefaults } |
            Should -Throw -ExpectedMessage "*CbsRetry does not accept*'-RestoreSource'*"
        { Invoke-VantaTrustedInstaller -Operation CbsRetry -InstallPhase Run } |
            Should -Throw -ExpectedMessage "*CbsRetry does not accept*'-InstallPhase'*"
        Should -Not -Invoke Invoke-VantaHiddenProcess -ModuleName Vanta.Core
    }
}

Describe 'Vanta privilege identity split' {
    It 'distinguishes LocalSystem from strict TrustedInstaller evidence' {
        Mock Get-VantaCurrentUserSid { 'S-1-5-18' } -ModuleName Vanta.Core
        Mock Get-VantaCurrentTokenEvidence {
            [pscustomobject]@{ IsSystem = $true; IsTrustedInstaller = $false }
        } -ModuleName Vanta.Core

        Test-VantaSystem | Should -BeTrue
        Test-VantaTrustedInstaller | Should -BeFalse
    }

    It 'fails closed when token evidence cannot be resolved' {
        Mock Get-VantaCurrentUserSid { throw 'identity failed' } -ModuleName Vanta.Core
        Mock Get-VantaCurrentTokenEvidence { throw 'translation failed' } -ModuleName Vanta.Core

        Test-VantaSystem | Should -BeFalse
        Test-VantaTrustedInstaller | Should -BeFalse
    }
}

Describe 'Assert-VantaPrivilege' {
    # Mocked probes take both branches of every guard whether or not Pester runs elevated.
    It 'allows -<Switch> when <Probe> confirms it' -TestCases @(
        @{ Switch = 'Administrator'; Probe = 'Test-VantaAdmin' }
        @{ Switch = 'System'; Probe = 'Test-VantaSystem' }
        @{ Switch = 'TrustedInstaller'; Probe = 'Test-VantaTrustedInstaller' }
    ) {
        param($Switch, $Probe)
        Mock -CommandName $Probe -ModuleName Vanta.Core -MockWith { $true }
        $privilege = @{ $Switch = $true }

        { Assert-VantaPrivilege @privilege } | Should -Not -Throw
        Should -Invoke -CommandName $Probe -ModuleName Vanta.Core -Times 1 -Exactly
    }

    It 'rejects -<Switch> when <Probe> denies it' -TestCases @(
        @{ Switch = 'Administrator'; Probe = 'Test-VantaAdmin'; Message = '*requires Administrator rights*' }
        @{ Switch = 'System'; Probe = 'Test-VantaSystem'; Message = '*requires LocalSystem*' }
        @{
            Switch = 'TrustedInstaller'; Probe = 'Test-VantaTrustedInstaller'
            Message = '*requires a TrustedInstaller service token*'
        }
    ) {
        param($Switch, $Probe, $Message)
        Mock -CommandName $Probe -ModuleName Vanta.Core -MockWith { $false }
        $privilege = @{ $Switch = $true }

        { Assert-VantaPrivilege @privilege } | Should -Throw -ExpectedMessage $Message
    }
}

Describe 'Import-VantaModule' {
    It 'imports a sibling module from inside another module scope so its commands reach the caller' {
        # Companion functions run inside Vanta.Toggles and import Vanta.Appx or
        # Vanta.Download this way; the import must land in the caller-visible session.
        Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Toggles\Vanta.Toggles.psd1') -Force
        Remove-Module -Name Vanta.Download -Force -ErrorAction SilentlyContinue

        & (Get-Module -Name Vanta.Toggles) { Import-VantaModule -Name Vanta.Download }

        # Command lookup would autoload Vanta.Download from PSModulePath even if
        # nothing was imported, so check the session's modules and functions.
        $imported = @(Get-Module -Name Vanta.Download)
        $imported | Should -HaveCount 1
        $imported[0].ModuleBase | Should -Be (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Download')
        Test-Path -LiteralPath Function:\Get-VantaTrustedWingetPath | Should -BeTrue
    }

    It 'rejects a name outside the Vanta module family and a missing manifest' {
        { Import-VantaModule -Name 'Pester' } | Should -Throw
        { Import-VantaModule -Name 'Vanta.DoesNotExist' } | Should -Throw '*manifest*is missing*'
    }
}

Describe 'Get-VantaContext machine state document' {
    BeforeEach {
        & $coreModule { $script:VantaContext = $null }
    }

    It 'reads installed version, mode and options from the state document after an install' {
        $windowsPath = Join-Path -Path $TestDrive -ChildPath 'Windows'
        [void][IO.Directory]::CreateDirectory($windowsPath)
        $document = [pscustomobject]@{
            installedVersion = '0.6.0'; mode = 'Upgrade'; isOobe = $false; isInteractive = $true
            options = @('defender-enable')
        }

        $context = Get-VantaContext -WindowsPath $windowsPath -StateReader { $null } `
            -DocumentReader { $document } -WindowsBuildReader { 26100 }

        $context.IsInstallStateBacked | Should -BeFalse
        $context.IsStateDocumentBacked | Should -BeTrue
        $context.InstalledVersion | Should -Be '0.6.0'
        $context.Mode | Should -BeExactly 'Upgrade'
        $context.IsUpgrade | Should -BeTrue
        $context.PSObject.Properties['IsOobe'] | Should -BeNullOrEmpty
        @($context.Options) | Should -Be @('defender-enable')
        $context.StateDocumentPath | Should -Be (Join-Path $windowsPath 'VantaOS\state.json')
    }

    It 'stays Legacy when the state document has no recorded mode' {
        $windowsPath = Join-Path -Path $TestDrive -ChildPath 'Windows'
        [void][IO.Directory]::CreateDirectory($windowsPath)
        $document = [pscustomobject]@{
            installedVersion = $null; mode = $null; isOobe = $false; isInteractive = $false; options = @()
        }

        $context = Get-VantaContext -WindowsPath $windowsPath -StateReader { $null } `
            -DocumentReader { $document } -WindowsBuildReader { 26100 }

        $context.IsStateDocumentBacked | Should -BeTrue
        $context.Mode | Should -BeExactly 'Legacy'
    }

    It 'still counts as an update after a Reapply of an updated install, but not of a fresh one' -TestCases @(
        @{ First = 'Upgrade'; Expected = $true }
        @{ First = 'Rebase'; Expected = $true }
        @{ First = 'Fresh'; Expected = $false }
    ) {
        param($First, $Expected)
        $windowsPath = Join-Path -Path $TestDrive -ChildPath 'Windows'
        [void][IO.Directory]::CreateDirectory($windowsPath)
        $document = [pscustomobject]@{
            installedVersion = '0.6.0'; mode = 'Reapply'; isOobe = $false; isInteractive = $true; options = @()
            history = @(
                [pscustomobject]@{ version = '0.6.0'; mode = $First; completedAt = '2026-10-01T00:00:00Z'; transactionId = 'a' }
                [pscustomobject]@{ version = '0.6.0'; mode = 'Reapply'; completedAt = '2026-10-02T00:00:00Z'; transactionId = 'b' }
            )
        }

        $context = Get-VantaContext -WindowsPath $windowsPath -StateReader { $null } `
            -DocumentReader { $document } -WindowsBuildReader { 26100 }

        $context.IsUpgrade | Should -Be $Expected
    }
}

Describe 'Native assembly loader seam' {
    It 'rejects an absent or unsigned prebuilt Vanta.Native.dll' {
        InModuleScope Vanta.Core {
            Test-VantaNativeAssembly -Path (Join-Path $TestDrive 'absent.dll') | Should -BeFalse
            $unsigned = Join-Path $TestDrive 'Vanta.Native.dll'
            [IO.File]::WriteAllBytes($unsigned, [byte[]](0x4D, 0x5A, 0, 0))
            Test-VantaNativeAssembly -Path $unsigned | Should -BeFalse
        }
    }

    It 'rejects a symbolic link to a validly signed file' {
        $signed = Join-Path -Path ([Environment]::SystemDirectory) -ChildPath 'kernel32.dll'
        $link = Join-Path $TestDrive 'Linked\Vanta.Native.dll'
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $link))
        # Windows PowerShell's New-Item needs Administrator rights for a symbolic link;
        # mklink also works unelevated in Developer Mode.
        $null = cmd.exe /d /c mklink "$link" "$signed"
        if (-not (Test-Path -LiteralPath $link -PathType Leaf)) {
            Set-ItResult -Skipped -Because 'this host cannot create file symbolic links'
            return
        }

        InModuleScope Vanta.Core -Parameters @{ Signed = $signed; Link = $link } {
            param($Signed, $Link)
            Test-VantaNativeAssembly -Path $Signed | Should -BeTrue
            Test-VantaNativeAssembly -Path $Link | Should -BeFalse
        }
    }
}
