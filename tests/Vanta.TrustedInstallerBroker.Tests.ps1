BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $script:BrokerFixture = Join-Path $TestDrive 'VantaModules\Scripts\Entry\Invoke-VantaTrustedInstallerBroker.ps1'
    $fixtureModules = Join-Path $TestDrive 'VantaModules\Scripts\Modules'
    New-Item -ItemType Directory -Path (Split-Path $script:BrokerFixture),
        (Join-Path $fixtureModules 'Vanta.Core'), (Join-Path $fixtureModules 'Vanta.Toggles') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:VantaTestScriptsRoot 'Entry\Invoke-VantaTrustedInstallerBroker.ps1') `
        -Destination $script:BrokerFixture
    Copy-Item -LiteralPath (Join-Path $script:VantaTestScriptsRoot 'Initialize-VantaPowerShell.ps1') `
        -Destination (Join-Path $TestDrive 'VantaModules\Scripts')

    # Exercise the real broker in a separate process, with a private native boundary
    # that records requests instead of creating privileged processes.
    Set-Content -LiteralPath (Join-Path $fixtureModules 'Vanta.Core\Vanta.Core.psm1') -Encoding UTF8 -Value @'
function Assert-VantaPrivilege {
    param([switch]$Administrator)
    if ($Administrator -and $env:VANTA_BROKER_TEST_DENY_ADMIN) { throw '[privilege] fixture refusal' }
}
function Invoke-VantaTrustedInstallerNativeOperation {
    param($Operation, $TimeoutMilliseconds, $Name, $State, $Silent, $JustContext,
        $NoExplorerRestart, $MachineOnly, $RestoreSource, $InstallPhase, $PackageRoot)
    $PSBoundParameters | ConvertTo-Json | Set-Content -LiteralPath $env:VANTA_BROKER_TEST_RESULT
    [pscustomobject]@{ ExitCodeUInt32 = [uint32]$env:VANTA_BROKER_TEST_EXIT }
}
Export-ModuleMember -Function Assert-VantaPrivilege
'@
    Set-Content -LiteralPath (Join-Path $fixtureModules 'Vanta.Core\Vanta.Core.psd1') -Encoding UTF8 -Value @'
@{ RootModule = 'Vanta.Core.psm1'; ModuleVersion = '1.0.0'; FunctionsToExport = @('Assert-VantaPrivilege') }
'@
    Set-Content -LiteralPath (Join-Path $fixtureModules 'Vanta.Toggles\Vanta.Toggles.psm1') -Encoding UTF8 -Value @'
function Get-VantaToggleDefinition {
    param($Name)
    @{ Name = $Name; Elevation = 'TrustedInstaller'; States = @{ Minimal = @{} } }
}
Export-ModuleMember -Function Get-VantaToggleDefinition
'@
    Set-Content -LiteralPath (Join-Path $fixtureModules 'Vanta.Toggles\Vanta.Toggles.psd1') -Encoding UTF8 -Value @'
@{ RootModule = 'Vanta.Toggles.psm1'; ModuleVersion = '1.0.0'; FunctionsToExport = @('Get-VantaToggleDefinition') }
'@
    $script:BrokerPowerShell = Join-Path $PSHOME 'powershell.exe'
    $script:PreviousBrokerResult = $env:VANTA_BROKER_TEST_RESULT
    $script:PreviousBrokerExit = $env:VANTA_BROKER_TEST_EXIT
    $script:PreviousBrokerDenyAdmin = $env:VANTA_BROKER_TEST_DENY_ADMIN
}

AfterAll {
    $env:VANTA_BROKER_TEST_RESULT = $script:PreviousBrokerResult
    $env:VANTA_BROKER_TEST_EXIT = $script:PreviousBrokerExit
    $env:VANTA_BROKER_TEST_DENY_ADMIN = $script:PreviousBrokerDenyAdmin
}

Describe 'TrustedInstaller broker private native dispatch' {
    BeforeEach {
        $env:VANTA_BROKER_TEST_RESULT = Join-Path $TestDrive ([guid]::NewGuid().ToString() + '.json')
        $env:VANTA_BROKER_TEST_EXIT = '0'
        $env:VANTA_BROKER_TEST_DENY_ADMIN = $null
    }

    It 'dispatches a validated toggle through the private module function' {
        & $script:BrokerPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:BrokerFixture `
            -Operation Toggle -Name Indexing -State Minimal -TimeoutSeconds 42
        $LASTEXITCODE | Should -Be 0
        $request = Get-Content -LiteralPath $env:VANTA_BROKER_TEST_RESULT -Raw | ConvertFrom-Json
        $request.Operation | Should -Be 'Toggle'
        $request.Name | Should -Be 'Indexing'
        $request.State | Should -Be 'Minimal'
        $request.TimeoutMilliseconds | Should -Be 42000
        $request.Silent | Should -BeTrue
    }

    It 'dispatches service reset through the same private boundary' {
        & $script:BrokerPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:BrokerFixture `
            -Operation ResetServices -RestoreSource ToggleDefaults
        $LASTEXITCODE | Should -Be 0
        $request = Get-Content -LiteralPath $env:VANTA_BROKER_TEST_RESULT -Raw | ConvertFrom-Json
        $request.RestoreSource | Should -Be 'ToggleDefaults'
    }

    It 'dispatches an install request without writing to the real staging directory' {
        $stagedRoot = Join-Path ([Environment]::GetFolderPath('Windows')) 'VantaOS\Staging\BrokerTest\Executables'
        & $script:BrokerPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:BrokerFixture `
            -Operation Install -InstallPhase Capture -PackageRoot $stagedRoot
        $LASTEXITCODE | Should -Be 0
        $request = Get-Content -LiteralPath $env:VANTA_BROKER_TEST_RESULT -Raw | ConvertFrom-Json
        $request.InstallPhase | Should -Be 'Capture'
        $request.PackageRoot | Should -Be $stagedRoot
    }

    It 'rejects an undeclared toggle state before native dispatch' {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & $script:BrokerPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:BrokerFixture `
                -Operation Toggle -Name Indexing -State Unknown 2>&1
        }
        finally { $ErrorActionPreference = $previousPreference }
        $LASTEXITCODE | Should -Be 1
        ($output | Out-String) | Should -Match 'does not declare exact state'
        Test-Path -LiteralPath $env:VANTA_BROKER_TEST_RESULT | Should -BeFalse
    }

    It 'preserves a nonzero native child exit code' {
        $env:VANTA_BROKER_TEST_EXIT = '37'
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & $script:BrokerPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:BrokerFixture `
                -Operation ResetServices -RestoreSource ToggleDefaults 2>&1
        }
        finally { $ErrorActionPreference = $previousPreference }
        $LASTEXITCODE | Should -Be 37
        ($output | Out-String) | Should -Match 'child exited with code 37'
    }

    It 'preserves an install failure when the child could not write a session log' {
        $env:VANTA_BROKER_TEST_EXIT = '37'
        $stagedRoot = Join-Path ([Environment]::GetFolderPath('Windows')) ('VantaOS\Staging\' + [guid]::NewGuid().ToString('N') + '\Executables')
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & $script:BrokerPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:BrokerFixture `
                -Operation Install -InstallPhase Capture -PackageRoot $stagedRoot 2>&1
        }
        finally { $ErrorActionPreference = $previousPreference }
        $LASTEXITCODE | Should -Be 37
        ($output | Out-String) | Should -Match 'error details unavailable'
        ($output | Out-String) | Should -Match 'child exited with code 37'
    }

    It 'dispatches the Safe Mode CBS retry with no operation inputs' {
        & $script:BrokerPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:BrokerFixture `
            -Operation CbsRetry -TimeoutSeconds 3600
        $LASTEXITCODE | Should -Be 0
        $request = Get-Content -LiteralPath $env:VANTA_BROKER_TEST_RESULT -Raw | ConvertFrom-Json
        # The retry reads its packages from its own state file, so only the deadline crosses.
        @($request.PSObject.Properties.Name | Sort-Object) | Should -Be @('Operation', 'TimeoutMilliseconds')
        $request.Operation | Should -Be 'CbsRetry'
        $request.TimeoutMilliseconds | Should -Be 3600000
    }

    It 'rejects a CBS retry given -<Parameter> before native dispatch' -TestCases @(
        @{ Parameter = 'Name'; Arguments = @('-Name', 'Indexing') }
        @{ Parameter = 'RestoreSource'; Arguments = @('-RestoreSource', 'ToggleDefaults') }
        @{ Parameter = 'PackageRoot'; Arguments = @('-PackageRoot', 'C:\x') }
    ) {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & $script:BrokerPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:BrokerFixture `
                -Operation CbsRetry @Arguments 2>&1
        }
        finally { $ErrorActionPreference = $previousPreference }
        $LASTEXITCODE | Should -Be 1
        ($output | Out-String) | Should -Match "CbsRetry does not accept '-$Parameter'"
        Test-Path -LiteralPath $env:VANTA_BROKER_TEST_RESULT | Should -BeFalse
    }

    It 'refuses an install copy outside the protected staging root: <Label>' -TestCases @(
        @{ Label = 'a folder elsewhere'; Relative = $null }
        @{ Label = 'a sibling that shares its prefix'; Relative = 'VantaOS\Staging-other\x' }
        @{ Label = 'a path that climbs out of it'; Relative = 'VantaOS\Staging\..\x' }
    ) {
        # $TestDrive doesn't exist during discovery, so the first case builds its path here.
        $stagedRoot = if ($Relative) {
            Join-Path ([Environment]::GetFolderPath('Windows')) $Relative
        }
        else {
            Join-Path $TestDrive 'not-staging'
        }
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & $script:BrokerPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:BrokerFixture `
                -Operation Install -InstallPhase Capture -PackageRoot $stagedRoot 2>&1
        }
        finally { $ErrorActionPreference = $previousPreference }
        $LASTEXITCODE | Should -Be 1
        ($output | Out-String) | Should -Match 'protected staging root'
        Test-Path -LiteralPath $env:VANTA_BROKER_TEST_RESULT | Should -BeFalse
    }

    It 'refuses a caller without Administrator rights before native dispatch' {
        # The fixture's Vanta.Core refuses on request, so this holds on elevated hosts too.
        $env:VANTA_BROKER_TEST_DENY_ADMIN = '1'
        $stagedRoot = Join-Path ([Environment]::GetFolderPath('Windows')) 'VantaOS\Staging\BrokerTest\Executables'
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & $script:BrokerPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:BrokerFixture `
                -Operation Install -InstallPhase Capture -PackageRoot $stagedRoot 2>&1
        }
        finally { $ErrorActionPreference = $previousPreference }
        $LASTEXITCODE | Should -Be 1
        ($output | Out-String) | Should -Match '\[privilege\]'
        Test-Path -LiteralPath $env:VANTA_BROKER_TEST_RESULT | Should -BeFalse
    }
}
