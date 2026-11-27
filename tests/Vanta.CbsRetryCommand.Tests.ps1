BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Import-Module -Name (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    $script:CbsRetryPath = Join-Path $script:VantaTestScriptsRoot 'Operations\CbsRetry.ps1'
    . $script:CbsRetryPath -LibraryOnly
}

Describe 'The CBS retry launcher arguments' {
    It 'needs exactly one of -Recover and -Discard' {
        { & $script:CbsRetryPath } | Should -Throw '*Specify -Recover or -Discard*'
        { & $script:CbsRetryPath -Recover -Discard } | Should -Throw '*Specify -Recover or -Discard*'
    }
}

Describe 'What the Safe Mode retry command says is left to do' {
    BeforeEach {
        $script:statePath = Join-Path $TestDrive 'Recovery\CbsRetry.json'
        $package = Join-Path $TestDrive 'package.cab'
        [void](Write-VantaCbsRetryState -Phase Armed -Packages $package -Path $script:statePath)
        $script:shown = @()
        Mock Invoke-WithVantaCbsRetryLock { & $Action }
        # Nothing here may change this PC's boot configuration or restart it.
        Mock Invoke-VantaCbsRetrySafeMode {}
        Mock Read-VantaYesNo { $false }
        Mock Test-VantaTrustedInstaller { $false }
        Mock Assert-VantaPrivilege {}
        Mock Get-CimInstance { [pscustomobject]@{ BootupState = 'Fail-safe boot' } }
        Mock Invoke-VantaTrustedInstaller { Clear-VantaCbsRetryState -Path $script:statePath }
        Mock Test-VantaCbsRetryInstallUnfinished { $false }
        foreach ($command in @('Set-VantaLogConsoleStyle', 'Write-VantaTitle', 'Write-VantaStep',
                'Write-VantaLog', 'Write-VantaNotApplied')) {
            Mock -CommandName $command -MockWith {}
        }
        Mock Write-VantaSuccess { $script:shown += $Text }
    }

    It 'says only that Windows starts normally when no install is waiting (<Mode>)' -ForEach @(
        @{ Mode = 'Recover'; Done = 'The packages are installed. Windows starts normally from the next restart.' }
        @{ Mode = 'Discard'; Done = 'The retry was given up. Windows starts normally from the next restart.' }
    ) {
        Invoke-VantaCbsRetryCommand -Mode $Mode -StatePath $script:statePath | Should -Be 0
        $script:shown | Should -Be @($Done)
    }

    It 'sends the user back to Vanta for the install that armed the retry (<Mode>)' -ForEach @(
        @{ Mode = 'Recover'; Next = '* After the restart, open Vanta to finish installing it.' }
        @{ Mode = 'Discard'; Next = '* After the restart, open Vanta to try installing again.' }
    ) {
        Mock Test-VantaCbsRetryInstallUnfinished { $true }
        Invoke-VantaCbsRetryCommand -Mode $Mode -StatePath $script:statePath | Should -Be 0
        $script:shown | Should -BeLike $Next
    }

    It 'offers the restart after giving up only where Safe Mode has no Start menu (<Boot>)' -ForEach @(
        @{ Boot = 'Fail-safe boot'; Asks = 1 }
        @{ Boot = 'Normal boot'; Asks = 0 }
    ) {
        Mock Get-CimInstance { [pscustomobject]@{ BootupState = $Boot } }
        Invoke-VantaCbsRetryCommand -Mode Discard -StatePath $script:statePath | Should -Be 0
        Should -Invoke Read-VantaYesNo -Times $Asks -Exactly -ParameterFilter { $Question -ceq 'Restart Windows now?' }
    }
}

Describe 'The CBS retry command' {
    BeforeAll {
        # A copy of the script beside an empty trust bootstrap, so a run keeps the test
        # host's module setup and the Vanta.Core this file imported.
        $harnessScripts = Join-Path $TestDrive 'Scripts'
        $script:CbsRetryEntry = Join-Path $harnessScripts 'Operations\CbsRetry.ps1'
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $script:CbsRetryEntry))
        Copy-Item -LiteralPath $script:CbsRetryPath -Destination $script:CbsRetryEntry
        Set-Content -LiteralPath (Join-Path $harnessScripts 'Initialize-VantaPowerShell.ps1') -Value ''
    }

    BeforeEach {
        # The script runs these mocks from its own script scope, where $script: means the
        # script's variables, so they read the test's through the caller scopes instead.
        $cbsState = Join-Path $TestDrive 'Recovery\CbsRetry.json'
        $cbsPackage = Join-Path $TestDrive 'package.cab'
        if (Test-Path -LiteralPath $cbsState) {
            Remove-Item -LiteralPath $cbsState -Force
        }
        Set-Content -LiteralPath $cbsPackage -Value 'fixture'
        Mock Import-Module {} -ParameterFilter { $Name -like '*\Vanta.Core.psd1' }
        Mock Get-VantaCbsRetryStatePath { $cbsState }
        Mock Invoke-WithVantaCbsRetryLock { & $Action }
        Mock Invoke-VantaCbsRetrySafeMode {}
        Mock Test-VantaTrustedInstaller { $false }
        Mock Assert-VantaPrivilege {}
        Mock Get-CimInstance { [pscustomobject]@{ BootupState = 'Fail-safe boot' } }
        Mock Invoke-VantaTrustedInstaller {}
        Mock Test-VantaCbsRetryInstallUnfinished { $false }
        Mock Read-VantaYesNo { $false }
        Mock Start-VantaPhase {}
        Mock Stop-VantaPhase {}
        Mock Write-VantaLog {}
        Mock Get-VantaInstallLogPath {}
        foreach ($command in @('Set-VantaLogConsoleStyle', 'Write-VantaTitle', 'Write-VantaStep',
                'Write-VantaNote', 'Write-VantaSuccess', 'Write-VantaNotApplied')) {
            Mock -CommandName $command -MockWith {}
        }
    }

    It 'refuses a retry that was never armed and says how to give it up' {
        [void](Write-VantaCbsRetryState -Phase Pending -Packages $cbsPackage -Path $cbsState)
        $null = & $script:CbsRetryEntry -Recover
        $LASTEXITCODE | Should -Be 1
        Should -Invoke Write-VantaNotApplied -Times 1 -Exactly -ParameterFilter {
            $Reason -like '*Invoke-VantaCbsRetry.cmd" /discard*'
        }
        Should -Invoke Invoke-VantaTrustedInstaller -Times 0 -Exactly
    }

    It 'refuses to retry outside Safe Mode' {
        Mock Get-CimInstance { [pscustomobject]@{ BootupState = 'Normal boot' } }
        [void](Write-VantaCbsRetryState -Phase Armed -Packages $cbsPackage -Path $cbsState)
        $null = & $script:CbsRetryEntry -Recover
        $LASTEXITCODE | Should -Be 1
        Should -Invoke Write-VantaNotApplied -Times 1 -Exactly -ParameterFilter { $Reason -like 'The retry runs in Safe Mode.*' }
        Should -Invoke Invoke-VantaTrustedInstaller -Times 0 -Exactly
    }

    It 'hands an armed retry in Safe Mode to TrustedInstaller' {
        [void](Write-VantaCbsRetryState -Phase Armed -Packages $cbsPackage -Path $cbsState)
        $null = & $script:CbsRetryEntry -Recover
        $LASTEXITCODE | Should -Be 0
        Should -Invoke Assert-VantaPrivilege -Times 1 -Exactly -ParameterFilter { $Administrator }
        Should -Invoke Invoke-VantaTrustedInstaller -Times 1 -Exactly -ParameterFilter { $Operation -ceq 'CbsRetry' }
        Should -Invoke Write-VantaNotApplied -Times 0 -Exactly
    }

    It 'says what is left to do when the TrustedInstaller run fails with the retry <After>' -ForEach @(
        @{ After = 'Armed' }
        @{ After = 'Pending' }
    ) {
        [void](Write-VantaCbsRetryState -Phase Armed -Packages $cbsPackage -Path $cbsState)
        # A run that reached servicing has already left Safe Mode and marked the retry Pending.
        Mock Invoke-VantaTrustedInstaller {
            [void](Write-VantaCbsRetryState -Phase $After -Packages $cbsPackage -Path $cbsState)
            throw 'The broker failed.'
        }
        $expectedReason = "The packages didn't install: The broker failed. $(Get-VantaCbsRetryInstruction -Phase $After)"
        $null = & $script:CbsRetryEntry -Recover
        $LASTEXITCODE | Should -Be 1
        Should -Invoke Write-VantaNotApplied -Times 1 -Exactly -ParameterFilter { $Reason -ceq $expectedReason }
    }

    It 'runs the retry itself with a TrustedInstaller token and exits <ExitCode>' -ForEach @(
        @{ Fails = $false; ExitCode = 0 }
        @{ Fails = $true; ExitCode = 1 }
    ) {
        Mock Test-VantaTrustedInstaller { $true }
        Mock Invoke-VantaCbsRetryRecovery { if ($Fails) { throw 'Servicing failed.' } }
        $null = & $script:CbsRetryEntry -Recover
        $LASTEXITCODE | Should -Be $ExitCode
        Should -Invoke Invoke-VantaCbsRetryRecovery -Times 1 -Exactly
        Should -Invoke Start-VantaPhase -Times 1 -Exactly -ParameterFilter { $Phase -ceq 'CbsRetry' }
        Should -Invoke Stop-VantaPhase -Times 1 -Exactly -ParameterFilter { [bool]$Failed -eq $Fails }
        Should -Invoke Invoke-VantaTrustedInstaller -Times 0 -Exactly
    }

    It 'gives up with /discard whether or not a retry is waiting' {
        [void](Write-VantaCbsRetryState -Phase Armed -Packages $cbsPackage -Path $cbsState)
        $null = & $script:CbsRetryEntry -Discard
        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath $cbsState | Should -BeFalse
        Should -Invoke Invoke-VantaCbsRetrySafeMode -Times 1 -Exactly -ParameterFilter { $Mode -ceq 'Exit' }

        $null = & $script:CbsRetryEntry -Discard
        $LASTEXITCODE | Should -Be 0
        Should -Invoke Invoke-VantaCbsRetrySafeMode -Times 1 -Exactly
        Should -Invoke Write-VantaNote -Times 1 -Exactly
        Should -Invoke Test-VantaTrustedInstaller -Times 0 -Exactly
    }
}
