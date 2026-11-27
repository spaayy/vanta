[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter',
    '',
    Justification = 'The servicing doubles declare the parameter surface of the commands they stand in for.'
)]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    . (Join-Path $script:VantaTestScriptsRoot 'Install\Tasks\Set-VantaDefenderChoice.ps1')

    # Servicing doubles: the task must never install, remove or register anything on the
    # PC that runs the tests. Each records into $script:Events in the order it ran.
    function Test-VantaCbsPackagesAvailable { $true }
    function Install-VantaCbsPackage {
        param($Packages, [switch]$NonInteractive)
        $script:Events.Add("Install:$(@($Packages) -join '+'):$([bool]$NonInteractive)")
    }
    function Uninstall-VantaCbsPackage {
        param($Packages)
        $script:Events.Add("Uninstall:$(@($Packages) -join '+')")
        return [pscustomobject]@{ RemovedPackages = @(); FailedPackages = @($script:UninstallFailed); UnmatchedPatterns = @() }
    }
    function Set-VantaDefenderCoreService {
        param($State)
        $script:Events.Add("CoreService:$State")
    }
    # Stands in for Vanta.Security's reader, so each test's mock answers instead of this PC.
    function Test-VantaDefenderCoreServiceRemoved { }
    function Write-VantaLog {
        param($Message, $Level = 'Info', $ErrorRecord)
        $script:Logs.Add([pscustomobject]@{ Level = $Level; Message = $Message })
    }
}

AfterAll {
    foreach ($name in @(
            'Test-VantaCbsPackagesAvailable', 'Install-VantaCbsPackage', 'Uninstall-VantaCbsPackage', 'Set-VantaDefenderCoreService', 'Write-VantaLog'
            'Test-VantaDefenderCoreServiceRemoved'
            'Get-VantaServicingPackageState', 'Test-VantaDefenderServicePresent', 'Set-VantaDefenderChoice'
        )) {
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath "Function:\$name" -ErrorAction SilentlyContinue
    }
}

Describe 'Set-VantaDefenderChoice' {
    BeforeEach {
        $script:Events = [Collections.Generic.List[string]]::new()
        $script:Logs = [Collections.Generic.List[pscustomobject]]::new()
        $script:UninstallFailed = @()
        $script:PackageStates = @{}
        $script:DefenderPresent = $true
        # MDCoreSvc already off, or Vanta's task waiting to turn it off.
        $script:CoreServiceRemoved = $true
        Mock Get-VantaServicingPackageState { $script:PackageStates[$Name] }
        Mock Test-VantaDefenderServicePresent { $script:DefenderPresent }
        Mock Test-VantaDefenderCoreServiceRemoved { $script:CoreServiceRemoved }
    }

    Context 'choosing again on an update' {
        It 'removes a Defender that is present: NoTelemetry <Telemetry>' -ForEach @(
            @{ Telemetry = 'missing'; TelemetryState = $null; Install = 'Install:*Z-[AV]*-NoDefender-Package*+*Z-[AV]*-NoTelemetry-Package*:True' }
            @{ Telemetry = 'installed'; TelemetryState = 'Installed'; Install = 'Install:*Z-[AV]*-NoDefender-Package*:True' }
            @{ Telemetry = 'waiting for the restart'; TelemetryState = 'InstallPending'; Install = 'Install:*Z-[AV]*-NoDefender-Package*:True' }
        ) {
            $script:PackageStates['Z-Vanta-NoTelemetry-Package'] = $TelemetryState

            Set-VantaDefenderChoice -State Disable | Should -BeTrue

            @($script:Events) | Should -Be @($Install, 'CoreService:Removed')
        }

        It 'brings back a Defender Vanta removed, putting its core service back first: NoTelemetry <Telemetry>' -ForEach @(
            @{ Telemetry = 'missing'; TelemetryState = $null; Expected = @('CoreService:Restored', 'Uninstall:*Z-[AV]*-NoDefender-Package*', 'Install:*Z-[AV]*-NoTelemetry-Package*:True') }
            @{ Telemetry = 'installed'; TelemetryState = 'Installed'; Expected = @('CoreService:Restored', 'Uninstall:*Z-[AV]*-NoDefender-Package*') }
        ) {
            $script:PackageStates['Z-Vanta-NoDefender-Package'] = 'Installed'
            $script:PackageStates['Z-Vanta-NoTelemetry-Package'] = $TelemetryState

            Set-VantaDefenderChoice -State Enable | Should -BeTrue

            @($script:Events) | Should -Be $Expected
        }

        It 'fails when Vanta''s package can''t be taken off, so the install never reports a Defender it lacks' {
            $script:PackageStates['Z-Vanta-NoDefender-Package'] = 'Installed'
            $script:PackageStates['Z-Vanta-NoTelemetry-Package'] = 'Installed'
            $script:UninstallFailed = @('Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~5.0.0.0')

            { Set-VantaDefenderChoice -State Enable } |
                Should -Throw "Microsoft Defender couldn't be restored: Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~5.0.0.0"
        }

        It 'changes nothing when the PC already matches: <Case>' -ForEach @(
            @{ Case = 'Defender removed by Vanta, Remove chosen'; State = 'Disable'; Defender = 'Installed' }
            @{ Case = 'removal waiting for the restart, Remove chosen'; State = 'Disable'; Defender = 'InstallPending' }
            @{ Case = 'Defender present, Keep chosen'; State = 'Enable'; Defender = $null }
            @{ Case = 'restore waiting for the restart, Keep chosen'; State = 'Enable'; Defender = 'UninstallPending' }
        ) {
            $script:PackageStates['Z-Vanta-NoDefender-Package'] = $Defender

            Set-VantaDefenderChoice -State $State | Should -BeFalse

            $script:Events | Should -BeNullOrEmpty
            @($script:Logs | Where-Object Level -eq 'Warning') | Should -BeNullOrEmpty
        }

        It 'turns the core service off when Defender was removed but the service never was: <Defender>' -ForEach @(
            @{ Defender = 'Installed' }
            @{ Defender = 'InstallPending' }
        ) {
            # A run that stopped after the package went on, or an earlier Vanta that never
            # turned the service off.
            $script:PackageStates['Z-Vanta-NoDefender-Package'] = $Defender
            $script:CoreServiceRemoved = $false

            Set-VantaDefenderChoice -State Disable | Should -BeFalse

            @($script:Events) | Should -Be @('CoreService:Removed')
        }

        It 'warns, and changes nothing, when Defender is missing and no Vanta package removed it' {
            $script:DefenderPresent = $false

            Set-VantaDefenderChoice -State Enable | Should -BeFalse

            $script:Events | Should -BeNullOrEmpty
            @($script:Logs | Where-Object Level -eq 'Warning' | ForEach-Object Message) |
                Should -Be @("Microsoft Defender isn't on this PC and no Vanta package removed it, so Vanta can't bring it back.")
        }

        It 'fails, and changes nothing, when Keep is chosen while Vanta''s removal still waits for a restart' {
            $script:PackageStates['Z-Vanta-NoDefender-Package'] = 'InstallPending'

            { Set-VantaDefenderChoice -State Enable } |
                Should -Throw "Microsoft Defender couldn't be restored: Vanta's NoDefender package is still waiting for a restart to finish installing.*"

            $script:Events | Should -BeNullOrEmpty
        }

        It 'warns, and changes nothing, when Remove is chosen while Vanta''s restore still waits for a restart: -Fresh <Fresh>' -ForEach @(
            @{ Fresh = $false }
            @{ Fresh = $true }
        ) {
            $script:PackageStates['Z-Vanta-NoDefender-Package'] = 'UninstallPending'
            $script:PackageStates['Z-Vanta-NoTelemetry-Package'] = 'Installed'
            $script:CoreServiceRemoved = $false

            Set-VantaDefenderChoice -State Disable -Fresh:$Fresh | Should -BeFalse

            $script:Events | Should -BeNullOrEmpty
            @($script:Logs | Where-Object Level -eq 'Warning' | ForEach-Object Message) |
                Should -BeLike "Vanta's NoDefender package is still waiting for a restart to come off*Toggle Defender*"
        }

        It 'redoes nothing on a second run once the first has removed Defender' {
            Set-VantaDefenderChoice -State Disable | Should -BeTrue
            $script:PackageStates['Z-Vanta-NoDefender-Package'] = 'InstallPending'
            $script:PackageStates['Z-Vanta-NoTelemetry-Package'] = 'InstallPending'
            $script:Events.Clear()

            Set-VantaDefenderChoice -State Disable | Should -BeFalse

            $script:Events | Should -BeNullOrEmpty
        }
    }

    Context 'a first installation (-Fresh)' {
        It 'puts NoTelemetry on with Keep chosen and nothing else to do' {
            Set-VantaDefenderChoice -State Enable -Fresh | Should -BeFalse

            @($script:Events) | Should -Be @('Install:*Z-[AV]*-NoTelemetry-Package*:True')
        }

        It 'sets the core service up for removal even when Defender was already removed: <Defender>' -ForEach @(
            @{ Defender = 'Installed' }
            @{ Defender = 'InstallPending' }
        ) {
            $script:PackageStates['Z-Vanta-NoDefender-Package'] = $Defender

            Set-VantaDefenderChoice -State Disable -Fresh | Should -BeFalse

            @($script:Events) | Should -Be @('CoreService:Removed', 'Install:*Z-[AV]*-NoTelemetry-Package*:True')
            # As the first installation always has, whatever the service reads.
            Should -Invoke Test-VantaDefenderCoreServiceRemoved -Times 0 -Exactly
        }

        It 'installs NoTelemetry once when it goes on with the Defender change' {
            Set-VantaDefenderChoice -State Disable -Fresh | Should -BeTrue

            @($script:Events) | Should -Be @(
                'Install:*Z-[AV]*-NoDefender-Package*+*Z-[AV]*-NoTelemetry-Package*:True'
                'CoreService:Removed'
            )
        }

        It 'never installs NoTelemetry again when it is already installed' {
            $script:PackageStates['Z-Vanta-NoTelemetry-Package'] = 'Installed'

            Set-VantaDefenderChoice -State Enable -Fresh | Should -BeFalse

            $script:Events | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-VantaServicingPackageState' {
    BeforeAll {
        $script:CbsPath = 'Software\VantaRewriteTest\Cbs\Packages'

        function Set-TestPackage {
            param([string]$Key, $CurrentState, [Microsoft.Win32.RegistryValueKind]$Kind = 'DWord')
            $package = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$script:CbsPath\$Key")
            try { $package.SetValue('CurrentState', $CurrentState, $Kind) }
            finally { $package.Dispose() }
        }

        function Get-TestPackageState {
            Get-VantaServicingPackageState -Name 'Z-Vanta-NoDefender-Package' `
                -BaseKey ([Microsoft.Win32.Registry]::CurrentUser) -PackagesPath $script:CbsPath
        }
    }

    BeforeEach {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\VantaRewriteTest\Cbs', $false)
    }

    AfterAll {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\VantaRewriteTest\Cbs', $false)
    }

    It 'reads CurrentState <Value> as <Expected>' -ForEach @(
        @{ Value = 112; Expected = 'Installed' }
        @{ Value = 96; Expected = 'InstallPending' }
        @{ Value = 5; Expected = 'UninstallPending' }
        @{ Value = 64; Expected = $null }
        @{ Value = 0; Expected = $null }
    ) {
        Set-TestPackage -Key 'Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~5.0.0.0' -CurrentState $Value

        Get-TestPackageState | Should -Be $Expected
    }

    It 'gives the strongest state of several versions' {
        Set-TestPackage -Key 'Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~1.0.0.0' -CurrentState 5
        Set-TestPackage -Key 'Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~5.0.0.0' -CurrentState 96
        Get-TestPackageState | Should -BeExactly 'InstallPending'

        Set-TestPackage -Key 'Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~6.0.0.0' -CurrentState 112
        Get-TestPackageState | Should -BeExactly 'Installed'
    }

    It 'ignores other packages and a CurrentState that isn''t a DWORD' {
        Set-TestPackage -Key 'Z-Vanta-NoTelemetry-Package~31bf3856ad364e35~amd64~~5.0.0.0' -CurrentState 112
        Set-TestPackage -Key 'Z-Vanta-NoDefender-PackageExtra~31bf3856ad364e35~amd64~~5.0.0.0' -CurrentState 112
        Set-TestPackage -Key 'Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~5.0.0.0' -CurrentState '112' -Kind String

        Get-TestPackageState | Should -BeNullOrEmpty
    }

    It 'still sees the package an older build installed under its Z-Atlas-* name' {
        Set-TestPackage -Key 'Z-Atlas-NoDefender-Package~31bf3856ad364e35~amd64~~5.0.0.0' -CurrentState 112
        Get-TestPackageState | Should -BeExactly 'Installed'
    }
    It 'reads no packages at all as absent' {
        Get-TestPackageState | Should -BeNullOrEmpty
    }
}
