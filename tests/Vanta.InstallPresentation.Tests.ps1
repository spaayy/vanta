BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Import-Module (Join-Path $VantaTestModulesRoot 'Vanta.TasksProcs\Vanta.TasksProcs.psd1') -Force
    foreach ($source in @(
        @{ Path = 'Operations\Invoke-VantaUserShellRefresh.ps1'; Functions = @('Restore-VantaUserExplorer') }
        @{ Path = 'Operations\Remove-OneDriveCurrentUserData.ps1'; Functions = @('ConvertTo-VantaOneDriveUserSid', 'Register-VantaOneDrivePostBootCleanup') }
    )) {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $VantaTestScriptsRoot $source.Path), [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw ($errors -join '; ') }
        foreach ($name in $source.Functions) {
            $definition = $ast.Find({
                param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name
            }, $true)
            . ([scriptblock]::Create($definition.Extent.Text))
        }
    }
}

Describe 'Shell refresh preserves the installation window' {
    BeforeEach {
        Mock Start-Process {}
    }
    It 'does not launch a folder when Windows has restored the shell' {
        Mock Wait-VantaExplorerShellRecovery { [pscustomobject]@{ Id = 42; SessionId = 7 } }
        Restore-VantaUserExplorer -SessionId 7
        Should -Invoke Start-Process -Times 0 -Exactly
        Should -Invoke Wait-VantaExplorerShellRecovery -Times 1 -Exactly -ParameterFilter { $SessionId -eq 7 }
    }
    It 'recovers a missing shell once and verifies readiness in the same session' {
        Mock Wait-VantaExplorerShellRecovery {
            if ($TimeoutSeconds -eq 5) { throw 'shell is missing' }
            [pscustomobject]@{ Id = 42; SessionId = 7 }
        }
        Restore-VantaUserExplorer -SessionId 7
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*\explorer.exe' -and $WindowStyle -eq 'Hidden'
        }
        Should -Invoke Wait-VantaExplorerShellRecovery -Times 1 -Exactly -ParameterFilter {
            $SessionId -eq 7 -and $TimeoutSeconds -eq 15
        }
    }
    It 'reports failure when the recovery launch never produces a shell' {
        Mock Wait-VantaExplorerShellRecovery { throw 'shell is missing' }
        { Restore-VantaUserExplorer -SessionId 7 } | Should -Throw '*shell is missing*'
        Should -Invoke Start-Process -Times 1 -Exactly
    }
}

Describe 'Deferred cleanup preserves other startup registrations' {
    BeforeEach {
        $script:launcherFixture = Join-Path $TestDrive 'cleanup.vbs'
        [IO.File]::WriteAllText($script:launcherFixture, '')
        Mock Join-Path { $script:launcherFixture } -ParameterFilter {
            $ChildPath -like '*Invoke-OneDriveCleanupHidden.vbs'
        }
        Mock New-Item {}
        Mock New-ItemProperty {}
    }
    It 'does not recreate an existing startup key containing Vanta and other apps' {
        Mock Test-Path { $true }
        Register-VantaOneDrivePostBootCleanup -UserSid 'S-1-5-21-1000-2000-3000-1001' -BootUtcTicks 638925000000000000L
        Should -Invoke New-Item -Times 0 -Exactly
        Should -Invoke New-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'VantaOneDriveCleanup' -and $LiteralPath -eq 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        }
    }
    It 'creates a missing startup key before registering cleanup' {
        Mock Test-Path { $false }
        Register-VantaOneDrivePostBootCleanup -UserSid 'S-1-5-21-1000-2000-3000-1001' -BootUtcTicks 638925000000000000L
        Should -Invoke New-Item -Times 1 -Exactly
        Should -Invoke New-ItemProperty -Times 1 -Exactly
    }
}
