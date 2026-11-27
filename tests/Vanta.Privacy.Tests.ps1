[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidGlobalVars',
    '',
    Justification = 'Module-scoped mock bodies cannot see test-file variables, so shared fixture state is staged as global variables.'
)]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Add-Type -AssemblyName System.ServiceProcess
    Import-Module -Name (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module -Name (Join-Path $script:VantaTestModulesRoot 'Vanta.Privacy\Vanta.Privacy.psd1') -Force

    # Module-scoped mocks cannot see test-file functions, so the fake service
    # controller factory and the shared call log live in the global scope.
    function global:New-VantaPrivacyTestService {
        param([string]$Name, [string]$Status)

        $service = [pscustomobject]@{
            Name   = $Name
            Status = [System.ServiceProcess.ServiceControllerStatus]$Status
        }
        $service | Add-Member -MemberType ScriptMethod -Name Refresh -Value {}
        $service | Add-Member -MemberType ScriptMethod -Name Start -Value {
            $global:VantaPrivacyTestCalls.Add("$($this.Name):Start")
            $this.Status = [System.ServiceProcess.ServiceControllerStatus]::StartPending
        }
        $service | Add-Member -MemberType ScriptMethod -Name Stop -Value {
            $global:VantaPrivacyTestCalls.Add("$($this.Name):Stop")
            $this.Status = [System.ServiceProcess.ServiceControllerStatus]::StopPending
        }
        $service | Add-Member -MemberType ScriptMethod -Name WaitForStatus -Value {
            param($Desired, $Timeout)
            [void]$Timeout
            $global:VantaPrivacyTestCalls.Add("$($this.Name):Wait:$Desired")
            $this.Status = $Desired
        }
        $service | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
            $global:VantaPrivacyTestCalls.Add("$($this.Name):Dispose")
        }
        return $service
    }
}

AfterAll {
    Remove-Item -Path 'Function:\global:New-VantaPrivacyTestService' -ErrorAction SilentlyContinue
    Remove-Variable -Name VantaPrivacyTestCalls, VantaPrivacyTestStatus, VantaPrivacyTestFailing, VantaPrivacyTestPackage `
        -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Set-VantaLocationMachineState' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Privacy
        Mock Test-VantaTrustedInstaller -ModuleName Vanta.Privacy { $false }
        Mock Assert-VantaPrivilege -ModuleName Vanta.Privacy {}
        $global:VantaPrivacyTestCalls = New-Object 'System.Collections.Generic.List[string]'
        $global:VantaPrivacyTestStatus = @{ lfsvc = 'Running'; MapsBroker = 'Running' }
        Mock Set-VantaServiceStartup -ModuleName Vanta.Privacy { throw 'Location must configure SCM before a runtime transition.' }
        Mock Set-Service -ModuleName Vanta.Privacy {
            $global:VantaPrivacyTestCalls.Add("$($Name):Start=$StartupType")
        }
        Mock Get-VantaLocationServiceController -ModuleName Vanta.Privacy {
            New-VantaPrivacyTestService -Name $Name -Status $global:VantaPrivacyTestStatus[$Name]
        }
        Mock Set-VantaRegistryValue -ModuleName Vanta.Privacy {
            $global:VantaPrivacyTestCalls.Add("registry:$Name=$Data")
        }
        Mock Set-VantaLocationSettingsPageVisibility -ModuleName Vanta.Privacy {
            $global:VantaPrivacyTestCalls.Add("settings:$($Operation):$Page")
        }
    }

    It 'disables both services, locks Find My Device and hides both settings pages in order' {
        Set-VantaLocationMachineState -State Disable

        @($global:VantaPrivacyTestCalls) | Should -Be @(
            'lfsvc:Start=Disabled'
            'lfsvc:Stop'
            'lfsvc:Wait:Stopped'
            'lfsvc:Dispose'
            'MapsBroker:Start=Disabled'
            'MapsBroker:Stop'
            'MapsBroker:Wait:Stopped'
            'MapsBroker:Dispose'
            'registry:AllowFindMyDevice=0'
            'registry:LocationSyncEnabled=0'
            'settings:hide:privacy-location'
            'settings:hide:findmydevice'
        )
        Should -Invoke Set-VantaRegistryValue -ModuleName Vanta.Privacy -Times 2 -Exactly -ParameterFilter {
            $Path -eq 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice' -and $Type -eq 'DWord'
        }
    }

    It 'enables both services and reveals only the location page, leaving Find My Device locked' {
        $global:VantaPrivacyTestStatus = @{ lfsvc = 'Stopped'; MapsBroker = 'Stopped' }

        Set-VantaLocationMachineState -State Enable

        @($global:VantaPrivacyTestCalls) | Should -Be @(
            'lfsvc:Start=Manual'
            'lfsvc:Start'
            'lfsvc:Wait:Running'
            'lfsvc:Dispose'
            'MapsBroker:Start=Automatic'
            'MapsBroker:Start'
            'MapsBroker:Wait:Running'
            'MapsBroker:Dispose'
            'settings:unhide:privacy-location'
        )
        Should -Invoke Set-VantaRegistryValue -ModuleName Vanta.Privacy -Times 0
    }

    It 'leaves a service alone when it already has the requested status' {
        $global:VantaPrivacyTestStatus = @{ lfsvc = 'Stopped'; MapsBroker = 'Running' }

        Set-VantaLocationMachineState -State Disable

        @($global:VantaPrivacyTestCalls | Where-Object { $_ -like 'lfsvc:*' }) | Should -Be @(
            'lfsvc:Start=Disabled'
            'lfsvc:Dispose'
        )
        @($global:VantaPrivacyTestCalls) | Should -Contain 'MapsBroker:Stop'
    }

    It 'stops before touching <Failing>, the registry or the settings pages when SCM rejects its <State> change' -TestCases @(
        @{ State = 'Enable'; Failing = 'lfsvc' }
        @{ State = 'Disable'; Failing = 'MapsBroker' }
    ) {
        $global:VantaPrivacyTestFailing = $Failing
        Mock Set-Service -ModuleName Vanta.Privacy {
            if ($Name -eq $global:VantaPrivacyTestFailing) { throw 'SCM configuration denied' }
            $global:VantaPrivacyTestCalls.Add("$($Name):Start=$StartupType")
        }

        { Set-VantaLocationMachineState -State $State } | Should -Throw '*SCM configuration denied*'
        Should -Invoke Set-Service -ModuleName Vanta.Privacy -Times 1 -Exactly -ParameterFilter {
            $Name -eq $global:VantaPrivacyTestFailing -and $ErrorAction -eq 'Stop'
        }
        Should -Invoke Get-VantaLocationServiceController -ModuleName Vanta.Privacy -Times 0 -ParameterFilter {
            $Name -eq $global:VantaPrivacyTestFailing
        }
        Should -Invoke Set-VantaRegistryValue -ModuleName Vanta.Privacy -Times 0
        Should -Invoke Set-VantaLocationSettingsPageVisibility -ModuleName Vanta.Privacy -Times 0
    }

    It 'asserts TrustedInstaller when running as TrustedInstaller and Administrator otherwise' {
        Set-VantaLocationMachineState -State Enable
        Should -Invoke Assert-VantaPrivilege -ModuleName Vanta.Privacy -Times 1 -Exactly -ParameterFilter { $Administrator }

        Mock Test-VantaTrustedInstaller -ModuleName Vanta.Privacy { $true }
        Set-VantaLocationMachineState -State Enable
        Should -Invoke Assert-VantaPrivilege -ModuleName Vanta.Privacy -Times 1 -Exactly -ParameterFilter { $TrustedInstaller }
    }
}

Describe 'Clear-VantaTelemetryLogFiles' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Privacy
        Mock Assert-VantaPrivilege -ModuleName Vanta.Privacy {}
        Mock Get-VantaContext -ModuleName Vanta.Privacy {
            [pscustomobject]@{ IsInstallStateBacked = $true }
        }

        $script:programData = Join-Path $TestDrive 'ProgramData'
        $script:etlRoot = Join-Path $script:programData 'Microsoft\Diagnosis\ETLLogs'
        New-Item -Path (Join-Path $script:etlRoot 'AutoLogger') -ItemType Directory -Force | Out-Null
        foreach ($name in @('DiagTrack-Listener.etl', 'DiagTrack-Listener.etl.000', 'Other.etl')) {
            Set-Content -LiteralPath (Join-Path $script:etlRoot "AutoLogger\$name") -Value 'x' -Encoding ASCII
        }
    }

    It 'removes only DiagTrack files from the two fixed log directories' {
        New-Item -Path (Join-Path $script:etlRoot 'ShutdownLogger') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:etlRoot 'ShutdownLogger\DiagTrack-Shutdown.etl') -Value 'x' -Encoding ASCII
        New-Item -Path (Join-Path $script:etlRoot 'Unrelated') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:etlRoot 'Unrelated\DiagTrack-Keep.etl') -Value 'x' -Encoding ASCII

        Clear-VantaTelemetryLogFiles -ProgramDataPath $script:programData

        @((Get-ChildItem -LiteralPath (Join-Path $script:etlRoot 'AutoLogger')).Name) | Should -Be @('Other.etl')
        @(Get-ChildItem -LiteralPath (Join-Path $script:etlRoot 'ShutdownLogger')).Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:etlRoot 'Unrelated\DiagTrack-Keep.etl') | Should -BeTrue
        Should -Invoke Assert-VantaPrivilege -ModuleName Vanta.Privacy -Times 1 -Exactly -ParameterFilter { $TrustedInstaller }
    }

    It 'tolerates a missing log directory' {
        Remove-Item -LiteralPath (Join-Path $script:etlRoot 'AutoLogger') -Recurse -Force

        { Clear-VantaTelemetryLogFiles -ProgramDataPath $script:programData } | Should -Not -Throw
    }

    It 'requires active install state and a rooted common application-data directory' {
        Mock Get-VantaContext -ModuleName Vanta.Privacy {
            [pscustomobject]@{ IsInstallStateBacked = $false }
        }
        { Clear-VantaTelemetryLogFiles -ProgramDataPath $script:programData } |
            Should -Throw '*requires active Vanta install state*'

        Mock Get-VantaContext -ModuleName Vanta.Privacy {
            [pscustomobject]@{ IsInstallStateBacked = $true }
        }
        { Clear-VantaTelemetryLogFiles -ProgramDataPath 'relative\ProgramData' } |
            Should -Throw '*rooted common application-data directory*'
        Test-Path -LiteralPath (Join-Path $script:etlRoot 'AutoLogger\DiagTrack-Listener.etl') | Should -BeTrue
    }

    It 'refuses a reparse-point log directory' {
        $target = Join-Path $TestDrive 'Elsewhere'
        New-Item -Path $target -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $target 'DiagTrack-Linked.etl') -Value 'x' -Encoding ASCII
        $junction = Join-Path $script:etlRoot 'ShutdownLogger'
        try {
            New-Item -Path $junction -ItemType Junction -Value $target -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because 'this host cannot create a directory junction'
            return
        }

        try {
            { Clear-VantaTelemetryLogFiles -ProgramDataPath $script:programData } |
                Should -Throw '*is a reparse point*'
            Test-Path -LiteralPath (Join-Path $target 'DiagTrack-Linked.etl') | Should -BeTrue
        }
        finally {
            [IO.Directory]::Delete($junction)
        }
    }
}

Describe 'NoTelemetry package choice and state' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Privacy
        Mock Write-VantaNote -ModuleName Vanta.Privacy
        Mock Write-VantaStep -ModuleName Vanta.Privacy
        Mock Write-Host -ModuleName Vanta.Privacy
        $global:VantaPrivacyTestCalls = New-Object 'System.Collections.Generic.List[string]'
        Mock Read-VantaChoice -ModuleName Vanta.Privacy { throw 'the menu was shown without a scripted answer' }
        Mock Invoke-VantaTelemetryPackageOperation -ModuleName Vanta.Privacy {
            $global:VantaPrivacyTestCalls.Add("package:${Action}:$([bool]$NoInteraction)")
        }
    }

    It 'marks the current choice and returns the other one when the package is <Presence>' -TestCases @(
        @{ Presence = 'absent'; Installed = $false; Current = 2; Choice = 1; Expected = 'Add' }
        @{ Presence = 'present'; Installed = $true; Current = 1; Choice = 2; Expected = 'Remove' }
    ) {
        $global:VantaPrivacyTestPackage = @{ Installed = $Installed; Current = $Current; Choice = $Choice }
        Mock Get-VantaTelemetryPackageInstalled -ModuleName Vanta.Privacy { $global:VantaPrivacyTestPackage.Installed }
        Mock Read-VantaChoice -ModuleName Vanta.Privacy { $global:VantaPrivacyTestPackage.Choice } -ParameterFilter {
            $CurrentIndex -eq $global:VantaPrivacyTestPackage.Current
        }

        Read-VantaTelemetryPackageChoice | Should -BeExactly $Expected

        # Choosing changes nothing: the toggle applies the choice in a separate step.
        @($global:VantaPrivacyTestCalls).Count | Should -Be 0
        Should -Invoke Read-VantaChoice -ModuleName Vanta.Privacy -Times 1 -Exactly
    }

    It 'applies a chosen state silently without the installer restart prompt' {
        Set-VantaTelemetryPackageState -State Installed -Silent
        Set-VantaTelemetryPackageState -State Removed -Silent

        @($global:VantaPrivacyTestCalls) | Should -Be @('package:Install:True', 'package:Uninstall:True')
        Should -Invoke Read-VantaChoice -ModuleName Vanta.Privacy -Times 0 -Exactly
    }

    It 'detects the NoTelemetry package by name and wraps enumeration failures' {
        Mock Get-WindowsPackage -ModuleName Vanta.Privacy {
            @(
                [pscustomobject]@{ PackageName = 'Microsoft-Windows-Something' }
                [pscustomobject]@{ PackageName = 'Z-Vanta-NoTelemetry-Package~31bf3856ad364e35~amd64~~10.0.0.0' }
            )
        }
        InModuleScope Vanta.Privacy { Get-VantaTelemetryPackageInstalled } | Should -BeTrue

        Mock Get-WindowsPackage -ModuleName Vanta.Privacy { @([pscustomobject]@{ PackageName = 'Other' }) }
        InModuleScope Vanta.Privacy { Get-VantaTelemetryPackageInstalled } | Should -BeFalse

        Mock Get-WindowsPackage -ModuleName Vanta.Privacy { throw 'DISM offline' }
        { InModuleScope Vanta.Privacy { Get-VantaTelemetryPackageInstalled } } | Should -Throw '*Failed to get packages! DISM offline*'
    }
}
