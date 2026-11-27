param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    # The public adapter imports Vanta.Core for Test-VantaAdmin; load the real module
    # once so the adapter tests can mock that command.
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    $script:repoRoot = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
    $script:scriptsRoot = Join-Path -Path $script:repoRoot `
        -ChildPath 'package\Executables\VantaModules\Scripts'
    $script:internalResetPath = Join-Path -Path $script:scriptsRoot `
        -ChildPath 'Entry\Restore-VantaServiceDefaults.ps1'
    $script:publicResetPath = Join-Path -Path $script:scriptsRoot `
        -ChildPath 'Entry\Invoke-VantaResetServices.ps1'
    $script:hostExecutable = (Get-Process -Id $PID).Path

    function Invoke-VantaTrustedInstaller {
        [CmdletBinding()]
        param(
            [string]$Operation,
            [string]$RestoreSource
        )

        $null = $Operation, $RestoreSource
    }

    function Write-TestFile {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string]$Content
        )

        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
        Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
    }

    function Initialize-VantaResetFixture {
        param([Parameter(Mandatory = $true)][string]$Root)

        $vantaModules = Join-Path -Path $Root -ChildPath 'VantaModules'
        $scripts = Join-Path -Path $vantaModules -ChildPath 'Scripts'
        $modules = Join-Path -Path $scripts -ChildPath 'Modules'
        $internal = Join-Path -Path $scripts -ChildPath 'Entry\Restore-VantaServiceDefaults.ps1'
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $internal) -Force
        Copy-Item -LiteralPath $script:internalResetPath -Destination $internal -Force
        Copy-Item -LiteralPath (Join-Path $script:VantaTestScriptsRoot 'Initialize-VantaPowerShell.ps1') -Destination $scripts

        Write-TestFile -Path (Join-Path $modules 'Vanta.Core\Vanta.Core.psd1') -Content @'
@{ RootModule = 'Vanta.Core.psm1'; ModuleVersion = '1.0.0'; FunctionsToExport = @('Assert-VantaPrivilege', 'Get-VantaContext', 'Write-VantaLog') }
'@
        Write-TestFile -Path (Join-Path $modules 'Vanta.Core\Vanta.Core.psm1') -Content @'
function Write-ResetEvent { param([string]$Message) Add-Content -LiteralPath $env:VANTA_RESET_TEST_LOG -Value $Message -Encoding UTF8 }
function Assert-VantaPrivilege {
    [CmdletBinding()] param([switch]$TrustedInstaller)
    Write-ResetEvent "Privilege:$([bool]$TrustedInstaller)"
    if (-not $TrustedInstaller) { throw 'simulated privilege failure' }
}
function Get-VantaContext { [pscustomobject]@{ VantaModulesPath = $env:VANTA_RESET_TEST_ROOT } }
function Write-VantaLog { param([string]$Message, [string]$Level, $ErrorRecord) Write-ResetEvent "Log:${Level}:$Message" }
Export-ModuleMember -Function Assert-VantaPrivilege, Get-VantaContext, Write-VantaLog
'@
        Write-TestFile -Path (Join-Path $modules 'Vanta.Services\Vanta.Services.psd1') -Content @'
@{ RootModule = 'Vanta.Services.psm1'; ModuleVersion = '1.0.0'; FunctionsToExport = @('Restore-VantaServicesBackup') }
'@
        Write-TestFile -Path (Join-Path $modules 'Vanta.Services\Vanta.Services.psm1') -Content @'
function Write-ResetEvent { param([string]$Message) Add-Content -LiteralPath $env:VANTA_RESET_TEST_LOG -Value $Message -Encoding UTF8 }
function Restore-VantaServicesBackup {
    param([string]$FilePath)
    Write-ResetEvent "Restore:$([IO.Path]::GetFullPath($FilePath))"
}
Export-ModuleMember -Function Restore-VantaServicesBackup
'@
        # The reset enters the module and calls this private function directly.
        Write-TestFile -Path (Join-Path $modules 'Vanta.Toggles\Vanta.Toggles.psd1') -Content @'
@{ RootModule = 'Vanta.Toggles.psm1'; ModuleVersion = '1.0.0'; FunctionsToExport = @() }
'@
        Write-TestFile -Path (Join-Path $modules 'Vanta.Toggles\Vanta.Toggles.psm1') -Content @'
function Write-ResetEvent { param([string]$Message) Add-Content -LiteralPath $env:VANTA_RESET_TEST_LOG -Value $Message -Encoding UTF8 }
function Invoke-VantaServiceDefaultsReset {
    Write-ResetEvent 'ResetDefaults'
    if ($env:VANTA_RESET_TEST_FAIL -ceq 'ResetDefaults') { throw 'simulated service reset failure' }
}
'@

        return [pscustomobject]@{
            VantaModules = $vantaModules
            Internal     = $internal
            Log          = Join-Path -Path $Root -ChildPath 'events.log'
        }
    }

    function Invoke-VantaResetFixture {
        param(
            [Parameter(Mandatory = $true)]$Fixture,
            [string]$RestoreSource = 'ToggleDefaults',
            [string]$FailAt
        )

        Remove-Item -LiteralPath $Fixture.Log -Force -ErrorAction SilentlyContinue
        $oldLog = $env:VANTA_RESET_TEST_LOG
        $oldRoot = $env:VANTA_RESET_TEST_ROOT
        $oldFail = $env:VANTA_RESET_TEST_FAIL
        $oldErrorActionPreference = $ErrorActionPreference
        try {
            $env:VANTA_RESET_TEST_LOG = $Fixture.Log
            $env:VANTA_RESET_TEST_ROOT = $Fixture.VantaModules
            $env:VANTA_RESET_TEST_FAIL = $FailAt
            # A nonzero child is the behavior under test. Windows PowerShell reports
            # redirected native stderr as an ErrorRecord when the caller prefers Stop.
            $ErrorActionPreference = 'Continue'
            $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File')
            $output = @(& $script:hostExecutable @arguments $Fixture.Internal -RestoreSource $RestoreSource 2>&1)
            $exitCode = $LASTEXITCODE
        }
        finally {
            $env:VANTA_RESET_TEST_LOG = $oldLog
            $env:VANTA_RESET_TEST_ROOT = $oldRoot
            $env:VANTA_RESET_TEST_FAIL = $oldFail
            $ErrorActionPreference = $oldErrorActionPreference
        }

        $events = if (Test-Path -LiteralPath $Fixture.Log -PathType Leaf) {
            @(Get-Content -LiteralPath $Fixture.Log)
        }
        else {
            @()
        }
        return [pscustomobject]@{ ExitCode = $exitCode; Events = $events; Output = $output }
    }
}

Describe 'Reset Services privileged adapter behavior' {
    BeforeEach {
        $script:fixture = Initialize-VantaResetFixture -Root $TestDrive
    }

    It 'applies closed service defaults before restoring the fixed typed snapshot and fails stop' {
        $result = Invoke-VantaResetFixture -Fixture $script:fixture -RestoreSource WindowsBackup
        $expectedRestore = Join-Path -Path $script:fixture.VantaModules `
            -ChildPath 'Other\winServices.reg'

        $result.ExitCode | Should -Be 0
        $result.Events | Should -Be @('Privilege:True', 'ResetDefaults', "Restore:$expectedRestore")

        $failed = Invoke-VantaResetFixture -Fixture $script:fixture -RestoreSource WindowsBackup -FailAt ResetDefaults
        $failed.ExitCode | Should -Be 1
        $failed.Events | Should -Be @(
            'Privilege:True', 'ResetDefaults'
            'Log:Error:Resetting services to defaults (WindowsBackup) failed: simulated service reset failure'
        )
    }
}

Describe 'Reset Services public adapter behavior' {
    BeforeEach {
        # The script dot-sources the Vanta bootstrap, which replaces PSModulePath for the
        # whole process.
        $script:savedModulePath = $env:PSModulePath
        Mock -CommandName Import-Module -ParameterFilter { $Name -like '*Vanta.Core*' } -MockWith {}
        Mock -CommandName Test-VantaAdmin -MockWith { $true }
        Mock -CommandName Invoke-VantaTrustedInstaller
        Mock -CommandName Write-VantaLog
    }

    AfterEach {
        $env:PSModulePath = $script:savedModulePath
    }

    It 'uses the typed broker default and reports the required restart' {
        $output = & $script:publicResetPath -Silent

        $output | Should -BeExactly `
            'Vanta service defaults were restored. A restart is required to apply every change.'
        Should -Invoke -CommandName Invoke-VantaTrustedInstaller -Times 1 -Exactly `
            -ParameterFilter { $Operation -ceq 'ResetServices' -and $RestoreSource -ceq 'ToggleDefaults' }
    }

    It 'reports a checked broker or target failure without claiming success' {
        Mock -CommandName Invoke-VantaTrustedInstaller -MockWith {
            throw 'TrustedInstaller broker exited with disallowed code 5: target failed.'
        }
        { & $script:publicResetPath -Silent } | Should -Throw '*disallowed code 5*target failed*'
        Should -Invoke -CommandName Write-VantaLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Error' -and $Message -like 'Resetting services failed: *disallowed code 5*'
        }
    }
}
