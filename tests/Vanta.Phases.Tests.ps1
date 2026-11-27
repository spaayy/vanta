[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter',
    '',
    Justification = 'The software-phase harness parameters are consumed through its isolated child-scope command stubs.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidOverwritingBuiltInCmdlets',
    '',
    Justification = 'The isolated software-phase harness shadows Import-Module only while executing the phase under test.'
)]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $script:vantaModulesRoot = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\package\Executables\VantaModules')).Path
    $script:phasesRoot = Join-Path -Path $script:vantaModulesRoot -ChildPath 'Scripts\Install\Phases'

    function Get-VantaPhaseAst {
        param([Parameter(Mandatory = $true)][string]$Path)

        $tokens = $null
        $errors = $null
        return [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    }

    function Get-VantaPrivilegeSwitch {
        param([Parameter(Mandatory = $true)]$Ast)

        $commands = $Ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Assert-VantaPrivilege'
            }, $true)

        $switches = foreach ($command in $commands) {
            foreach ($element in $command.CommandElements) {
                if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                    $element.ParameterName
                }
            }
        }

        return @($switches)
    }

    function Invoke-VantaSoftwarePhaseForTest {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)]$Context,
            [Parameter(Mandatory = $true)][hashtable]$Options,
            [Parameter(Mandatory = $true)][hashtable]$ComponentOutcomes,
            [Parameter(Mandatory = $true)]$Attempts,
            [Parameter(Mandatory = $true)]$Logs,
            [Parameter(Mandatory = $true)]$UserIntegrationState,
            [int]$UserIntegrationExitCode = 0
        )

        & {
            function Assert-VantaPrivilege {
                [CmdletBinding()]
                param([switch]$TrustedInstaller)
                [void]$TrustedInstaller
            }

            function Import-Module {
                [CmdletBinding()]
                param([string]$Name, [switch]$Force)
                [void]$Name
                [void]$Force
            }

            function Get-VantaContext {
                return $Context
            }

            function Test-VantaOption {
                param([Parameter(Mandatory = $true)][string]$Name)
                return $Options.ContainsKey($Name) -and [bool]$Options[$Name]
            }

            function Install-VantaSoftware {
                param([Parameter(Mandatory = $true)][string[]]$Component)
                $name = [string]$Component[0]
                [void]$Attempts.Add($name)
                if (-not $ComponentOutcomes.ContainsKey($name)) {
                    return $true
                }
                $outcome = $ComponentOutcomes[$name]
                if ($outcome -is [Exception]) {
                    throw $outcome
                }
                return [bool]$outcome
            }

            function Invoke-VantaAsUser {
                param(
                    [Parameter(Mandatory = $true)][string]$FilePath,
                    [Parameter(Mandatory = $true)][string]$Arguments
                )
                [void]$FilePath
                [void]$Arguments
                $UserIntegrationState.Count++
                return $UserIntegrationExitCode
            }

            function Write-VantaLog {
                param(
                    [string]$Level = 'Information',
                    [Parameter(Mandatory = $true)][string]$Message
                )
                [void]$Logs.Add([pscustomobject]@{ Level = $Level; Message = $Message })
            }

            . $Path
        }
    }
}

Describe 'Install phase scripts' {
    BeforeDiscovery {
        $phasesRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\package\Executables\VantaModules\Scripts\Install\Phases'
        $script:phaseFiles = Get-ChildItem -Path $phasesRoot -Filter 'Invoke-*Phase.ps1' -File
    }

    It '<Name> returns or throws without exiting the install dispatcher host' -ForEach (
        $phaseFiles | ForEach-Object { @{ Name = $_.Name; FullName = $_.FullName } }
    ) {
        $ast = Get-VantaPhaseAst -Path $FullName
        $exitStatements = @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.ExitStatementAst]
                }, $true))

        $exitStatements | Should -BeNullOrEmpty `
            -Because "$Name must return or throw so Invoke-VantaInstall can record its phase as complete or failed"
    }

    # Every phase runs as TrustedInstaller; user work goes through the exact-user
    # launcher inside it.
    It '<Name> asserts TrustedInstaller privilege' -ForEach (
        $phaseFiles | ForEach-Object { @{ Name = $_.Name; FullName = $_.FullName } }
    ) {
        Get-VantaPrivilegeSwitch -Ast (Get-VantaPhaseAst -Path $FullName) | Should -Contain 'TrustedInstaller'
    }
}

Describe 'Software phase outcome aggregation' {
    BeforeEach {
        $script:softwarePhasePath = Join-Path -Path $script:phasesRoot `
            -ChildPath 'Invoke-SoftwarePhase.ps1'
        $script:softwareAttempts = New-Object 'Collections.Generic.List[string]'
        $script:softwareLogs = New-Object 'Collections.Generic.List[object]'
        $script:userIntegrationState = [pscustomobject]@{ Count = 0 }
    }

    It 'continues after optional app failures on fresh and upgrade installs' -ForEach @(
        @{ IsUpgrade = $false; ThrowFailures = $false }
        @{ IsUpgrade = $false; ThrowFailures = $true }
        @{ IsUpgrade = $true; ThrowFailures = $false }
        @{ IsUpgrade = $true; ThrowFailures = $true }
    ) {
        $context = [pscustomobject]@{
            IsUpgrade = $IsUpgrade
            InteractiveUserSid = 'S-1-5-21-1000-1001-1002-1003'
        }
        $outcome = if ($ThrowFailures) {
            [InvalidOperationException]::new('simulated optional app failure')
        } else { $false }

        {
            Invoke-VantaSoftwarePhaseForTest `
                -Path $script:softwarePhasePath `
                -Context $context `
                -Options @{ 'install-eclean' = $true; 'browser-chrome' = $true } `
                -ComponentOutcomes @{ Eclean = $outcome } `
                -Attempts $script:softwareAttempts `
                -Logs $script:softwareLogs `
                -UserIntegrationState $script:userIntegrationState
        } | Should -Not -Throw

        $expected = if ($IsUpgrade) { @('Eclean', 'Chrome') } else {
            @('VCRedist', 'SevenZip', 'DirectX', 'Eclean', 'Chrome')
        }
        @($script:softwareAttempts) | Should -Be $expected
        $script:softwareLogs.Count | Should -Be 1
        foreach ($entry in $script:softwareLogs) {
            $entry.Level | Should -Be 'Warning'
            $entry.Message | Should -Match 'Vanta setup will continue'
            $entry.Message | Should -Match 'You can install it later from https://'
        }
    }

    It 'attempts every selected component before throwing one aggregate for false and thrown outcomes' {
        $context = [pscustomobject]@{
            IsUpgrade = $false
            InteractiveUserSid = 'S-1-5-21-1000-1001-1002-1003'
        }
        $options = @{
            'install-eclean' = $true
            'browser-brave' = $true
            'browser-firefox' = $true
            'browser-librewolf' = $true
            'browser-chrome' = $true
        }
        $outcomes = @{
            SevenZip = $false
            DirectX = $false
            Eclean = [InvalidOperationException]::new('simulated eclean failure')
            Firefox = [InvalidOperationException]::new('simulated Firefox failure')
        }

        $failure = $null
        try {
            Invoke-VantaSoftwarePhaseForTest `
                -Path $script:softwarePhasePath `
                -Context $context `
                -Options $options `
                -ComponentOutcomes $outcomes `
                -Attempts $script:softwareAttempts `
                -Logs $script:softwareLogs `
                -UserIntegrationState $script:userIntegrationState
        }
        catch {
            $failure = $_
        }

        $failure | Should -Not -BeNullOrEmpty
        $failure.Exception.Message | Should -BeExactly `
            'Software phase failed for components: SevenZip, Firefox.'
        @($script:softwareAttempts) | Should -Be @(
            'VCRedist', 'SevenZip', 'DirectX', 'Eclean',
            'Brave', 'Firefox', 'LibreWolf', 'Chrome'
        )
        $script:userIntegrationState.Count | Should -Be 1
        $script:softwareLogs.Count | Should -Be 4
        @($script:softwareLogs | Where-Object {
                $_.Message -match 'Optional legacy DirectX runtime was not installed; continuing'
            }).Count | Should -Be 1
    }

    It 'counts failed exact-user LibreWolf integration and still attempts later browsers' {
        $context = [pscustomobject]@{
            IsUpgrade = $true
            InteractiveUserSid = 'S-1-5-21-1000-1001-1002-1003'
        }
        $options = @{
            'browser-librewolf' = $true
            'browser-chrome' = $true
        }

        $failure = $null
        try {
            Invoke-VantaSoftwarePhaseForTest `
                -Path $script:softwarePhasePath `
                -Context $context `
                -Options $options `
                -ComponentOutcomes @{} `
                -Attempts $script:softwareAttempts `
                -Logs $script:softwareLogs `
                -UserIntegrationState $script:userIntegrationState `
                -UserIntegrationExitCode 37
        }
        catch {
            $failure = $_
        }

        $failure | Should -Not -BeNullOrEmpty
        $failure.Exception.Message | Should -BeExactly `
            'Software phase failed for components: LibreWolf.'
        @($script:softwareAttempts) | Should -Be @('LibreWolf', 'Chrome')
        $script:userIntegrationState.Count | Should -Be 1
        $script:softwareLogs.Count | Should -Be 1
        $script:softwareLogs[0].Message | Should -Match `
            'Exact-user LibreWolf integration failed with exit code 37'
    }
}

Describe 'Services phase feature defaults' {
    BeforeAll {
        $script:servicesPhasePath = Join-Path -Path $script:phasesRoot `
            -ChildPath 'Invoke-ServicesPhase.ps1'

        # Runs the phase with its module commands stubbed. Each stub records its call, and
        # the recorded-state table decides what the verification read-back returns. A
        # toggle listed in AppliedStates records that state when the phase applies it.
        function Invoke-VantaServicesPhaseForTest {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)][string]$Path,
                [Parameter(Mandatory = $true)]$Calls,
                [Parameter(Mandatory = $true)][hashtable]$RecordedStates,
                [Parameter(Mandatory = $true)][hashtable]$Definitions,
                [hashtable]$AppliedStates = @{},
                [switch]$IsRebase,
                [switch]$BackupFails
            )

            & {
                function Get-VantaContext {
                    return [pscustomobject]@{ IsRebase = [bool]$IsRebase }
                }

                function Assert-VantaPrivilege {
                    [CmdletBinding()]
                    param([switch]$TrustedInstaller)
                    if ($TrustedInstaller) { [void]$Calls.Add('Privilege:TrustedInstaller') }
                }

                function Import-Module {
                    [CmdletBinding()]
                    param([string]$Name, [switch]$Force)
                    [void]$Force
                    [void]$Calls.Add("Import:$Name")
                }

                function Export-VantaServicesBackup {
                    param([Parameter(Mandatory = $true)][string]$FilePath)
                    [void]$Calls.Add("Backup:$FilePath")
                    if ($BackupFails) { throw 'simulated backup failure' }
                }

                function Invoke-VantaToggleMachineState {
                    param(
                        [Parameter(Mandatory = $true)][string]$Name,
                        [Parameter(Mandatory = $true)][string]$State
                    )
                    [void]$Calls.Add("Toggle:$Name=$State")
                    if ($AppliedStates.ContainsKey($Name)) {
                        $RecordedStates[$Name] = $AppliedStates[$Name]
                    }
                }

                function Get-VantaToggleDefinition {
                    param([Parameter(Mandatory = $true)][string]$Name)
                    return $Definitions[$Name]
                }

                function Get-VantaToggleState {
                    param([Parameter(Mandatory = $true)][string]$Name)
                    if (-not $RecordedStates.ContainsKey($Name)) {
                        return $null
                    }
                    return [pscustomobject]@{ State = $RecordedStates[$Name] }
                }

                function Write-VantaLog {
                    param(
                        [string]$Level = 'Information',
                        [Parameter(Mandatory = $true)][string]$Message
                    )
                    [void]$Level
                    [void]$Calls.Add("Log:$Message")
                }

                . $Path
            }
        }
    }

    BeforeEach {
        $script:servicesCalls = New-Object 'Collections.Generic.List[string]'
        $script:toggleDefinitions = @{
            FileSharing = @{ Name = 'FileSharing'; States = @{ Disable = @{ StateValue = 0 }; Enable = @{ StateValue = 1 } } }
            Location    = @{ Name = 'Location'; States = @{ Disable = @{ StateValue = 0 }; Enable = @{ StateValue = 1 } } }
            Indexing    = @{ Name = 'Indexing'; States = @{ Disable = @{ StateValue = 0 }; Minimal = @{ StateValue = 1 }; Full = @{ StateValue = 2 } } }
        }
    }

    It 'asserts TrustedInstaller, then backs up services before applying the three defaults in order' {
        $recorded = @{ FileSharing = 0; Location = 0; Indexing = 1 }

        Invoke-VantaServicesPhaseForTest -Path $script:servicesPhasePath `
            -Calls $script:servicesCalls -RecordedStates $recorded `
            -Definitions $script:toggleDefinitions

        $script:servicesCalls[0] | Should -BeExactly 'Privilege:TrustedInstaller'
        $imports = @($script:servicesCalls | Where-Object { $_ -like 'Import:*' })
        $imports.Count | Should -BeGreaterThan 0
        foreach ($import in $imports) {
            $import.Substring('Import:'.Length) | Should -Exist -Because 'the phase must find its modules in the installed layout'
        }
        $machineWork = @($script:servicesCalls | Where-Object { $_ -like 'Backup:*' -or $_ -like 'Toggle:*' })
        $machineWork[0] | Should -BeLike 'Backup:*\VantaModules\Other\winServices.reg'
        @($machineWork | Select-Object -Skip 1) | Should -Be @(
            'Toggle:FileSharing=Disable', 'Toggle:Location=Disable', 'Toggle:Indexing=Minimal'
        )
    }

    It 'makes no machine change when the services backup fails' {
        {
            Invoke-VantaServicesPhaseForTest -Path $script:servicesPhasePath `
                -Calls $script:servicesCalls -RecordedStates @{} `
                -Definitions $script:toggleDefinitions -BackupFails
        } | Should -Throw '*simulated backup failure*'

        @($script:servicesCalls | Where-Object { $_ -like 'Toggle:*' }) | Should -BeNullOrEmpty `
            -Because 'the backup is the only way back to the original services'
    }

    It 'fails when a default does not record its expected state and stops before later defaults' -TestCases @(
        @{ Recorded = @{ FileSharing = 0; Location = 1; Indexing = 1 }; Failing = 'Location'; State = 'Disable' }
        @{ Recorded = @{ FileSharing = 0; Location = 0 }; Failing = 'Indexing'; State = 'Minimal' }
    ) {
        {
            Invoke-VantaServicesPhaseForTest -Path $script:servicesPhasePath `
                -Calls $script:servicesCalls -RecordedStates $Recorded `
                -Definitions $script:toggleDefinitions
        } | Should -Throw "*Services phase toggle '$Failing' did not record state '$State'*"

        $toggleCalls = @($script:servicesCalls | Where-Object { $_ -like 'Toggle:*' })
        $toggleCalls[-1] | Should -BeExactly "Toggle:$Failing=$State"
    }

    It 'keeps a recorded choice on a Rebase and applies only the defaults nothing recorded' {
        $recorded = @{ FileSharing = 1 }

        Invoke-VantaServicesPhaseForTest -Path $script:servicesPhasePath `
            -Calls $script:servicesCalls -RecordedStates $recorded `
            -AppliedStates @{ Location = 0; Indexing = 1 } `
            -Definitions $script:toggleDefinitions -IsRebase

        $machineWork = @($script:servicesCalls | Where-Object { $_ -like 'Backup:*' -or $_ -like 'Toggle:*' })
        $machineWork[0] | Should -BeLike 'Backup:*\VantaModules\Other\winServices.reg'
        @($machineWork | Select-Object -Skip 1) | Should -Be @(
            'Toggle:Location=Disable', 'Toggle:Indexing=Minimal'
        )
        $recorded.FileSharing | Should -Be 1
        @($script:servicesCalls | Where-Object { $_ -like "Log:Kept the recorded 'FileSharing' choice*" }).Count |
            Should -Be 1
    }
}
