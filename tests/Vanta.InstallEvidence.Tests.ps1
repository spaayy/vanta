BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $script:PowerShell51 = Join-Path $PSHOME 'powershell.exe'
    $broker = Join-Path $script:VantaTestScriptsRoot 'Entry\Invoke-VantaTrustedInstallerBroker.ps1'
    $ast = [Management.Automation.Language.Parser]::ParseFile($broker, [ref]$null, [ref]$null)
    $reader = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-VantaInstallFailureDetail' }, $true)
    . ([scriptblock]::Create($reader.Extent.Text))
}

Describe 'Early TrustedInstaller install evidence' {
    It 'retains install-plan host output and warnings and preserves its exit code' {
        $scripts = Join-Path $TestDrive 'run\VantaModules\Scripts'
        foreach ($directory in @('Install', 'Entry', 'Modules\Vanta.Core', 'Modules\Vanta.InstallState')) {
            New-Item -ItemType Directory -Path (Join-Path $scripts $directory) -Force | Out-Null
        }
        $entry = Join-Path $scripts 'Install\Invoke-VantaInstallSession.ps1'
        Copy-Item (Join-Path $script:VantaTestScriptsRoot 'Install\Invoke-VantaInstallSession.ps1') $entry
        Copy-Item (Join-Path $script:VantaTestScriptsRoot 'Initialize-VantaPowerShell.ps1') $scripts
        foreach ($name in @('Vanta.Core', 'Vanta.InstallState')) {
            Set-Content (Join-Path $scripts "Modules\$name\$name.psd1") "@{ RootModule = '$name.psm1'; ModuleVersion = '1.0.0' }"
            Set-Content (Join-Path $scripts "Modules\$name\$name.psm1") 'function Assert-VantaPrivilege { param([switch]$TrustedInstaller) }'
        }
        # The commit binds a user marker from this PC's loaded hives. This test is about
        # the plan's evidence, so the copy commits nothing.
        $session = [IO.File]::ReadAllText($entry)
        $commit = [regex]::new('(?m)^(\s*)Invoke-VantaInstallCommit\s*$')
        $commit.Matches($session).Count | Should -Be 1
        [IO.File]::WriteAllText($entry, $commit.Replace($session, '$1Write-Output ''Vanta install state committed.'''), [Text.UTF8Encoding]::new($false))
        Set-Content (Join-Path $scripts 'Entry\Invoke-VantaInstall.ps1') @'
param([switch]$Run)
Write-Host 'Visual C++ Runtime fixture failed with exit code 1638.'
Write-Warning 'fixture warning'
exit 37
'@
        & $script:PowerShell51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry -Phase Run
        $LASTEXITCODE | Should -Be 37
        $detail = Get-VantaInstallFailureDetail -PackageRoot (Join-Path $TestDrive 'run') -Phase Run
        $detail | Should -Match 'Visual C\+\+ Runtime fixture failed with exit code 1638'
        $detail | Should -Match 'fixture warning'
        $detail | Should -Match 'Install plan exited with code 37'
    }

    It 'persists <Failure> errors without inherited output and exposes them to the broker' -TestCases @(
        @{ Failure = 'bootstrap' }
        @{ Failure = 'module' }
    ) {
        param($Failure)
        $staged = Join-Path $TestDrive $Failure
        $scripts = Join-Path $staged 'VantaModules\Scripts'
        $install = Join-Path $scripts 'Install'
        New-Item -ItemType Directory -Path $install -Force | Out-Null
        $entry = Join-Path $install 'Invoke-VantaInstallSession.ps1'
        Copy-Item (Join-Path $script:VantaTestScriptsRoot 'Install\Invoke-VantaInstallSession.ps1') $entry
        if ($Failure -eq 'module') {
            Copy-Item (Join-Path $script:VantaTestScriptsRoot 'Initialize-VantaPowerShell.ps1') $scripts
            $core = Join-Path $scripts 'Modules\Vanta.Core'
            New-Item -ItemType Directory -Path $core -Force | Out-Null
            Set-Content (Join-Path $core 'Vanta.Core.psd1') "@{ RootModule = 'Vanta.Core.psm1'; ModuleVersion = '1.0.0' }"
            Set-Content (Join-Path $core 'Vanta.Core.psm1') "throw 'fixture module import failed'"
        }
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $script:PowerShell51
        $start.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $entry + '" -Phase Capture'
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $process = [Diagnostics.Process]::Start($start)
        try {
            $process.WaitForExit(30000) | Should -BeTrue
            $process.ExitCode | Should -Be 1
        }
        finally { $process.Dispose() }
        $detail = Get-VantaInstallFailureDetail -PackageRoot $staged -Phase Capture
        $detail | Should -Match 'Starting install phase Capture'
        $detail | Should -Match 'ERROR:'
        if ($Failure -eq 'module') { $detail | Should -Match 'fixture module import failed' }
        else { $detail | Should -Match 'PowerShell bootstrap is missing' }
        $detail | Should -Match 'Invoke-VantaInstallSession.ps1'
    }

    It 'limits failure output while retaining the final exception' {
        $staged = Join-Path $TestDrive 'limited'
        $logs = Join-Path $staged 'VantaModules\Logs'
        New-Item -ItemType Directory -Path $logs -Force | Out-Null
        $path = Join-Path $logs 'install-capture.log'
        [IO.File]::WriteAllText($path, ('x' * 20000) + 'final exception')
        $detail = Get-VantaInstallFailureDetail -PackageRoot $staged -Phase Capture
        $detail.Length | Should -Be 16384
        $detail | Should -Match 'final exception$'
    }
}
