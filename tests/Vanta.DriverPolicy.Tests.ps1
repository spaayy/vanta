BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $script:policyFiles = Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaDesktop\2. Drivers\Drivers from Windows Update'
    $script:isolatedKey = 'Software\VantaRewriteTest\DriverPolicy\' + [guid]::NewGuid().ToString('N')
    function Import-IsolatedDriverPolicy([string]$Mode) {
        # Exercise the included .reg pair without changing any host driver policy.
        $text = [IO.File]::ReadAllText((Join-Path $script:policyFiles "$Mode Drivers from Windows Update.reg"))
        $text = $text.Replace('HKEY_LOCAL_MACHINE\', ('HKEY_CURRENT_USER\' + $script:isolatedKey + '\'))
        $file = Join-Path $TestDrive "$Mode.reg"
        [IO.File]::WriteAllText($file, $text, [Text.Encoding]::Unicode)
        & "$env:WINDIR\System32\reg.exe" import $file | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not import isolated driver policy.' }
    }
}
Describe 'Manual and automatic driver policy' {
    AfterAll {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\VantaRewriteTest', $false)
    }
    It 'blocks both update drivers and new-device online searches, then reverses both' {
        Import-IsolatedDriverPolicy Disable
        $base = 'HKCU:\' + $script:isolatedKey + '\SOFTWARE\'
        (Get-ItemProperty ($base + 'Policies\Microsoft\Windows\WindowsUpdate')).ExcludeWUDriversInQualityUpdate | Should -Be 1
        (Get-ItemProperty ($base + 'Policies\Microsoft\Windows\DriverSearching')).SearchOrderConfig | Should -Be 0
        (Get-ItemProperty ($base + 'Microsoft\Windows\CurrentVersion\DriverSearching')).SearchOrderConfig | Should -Be 0
        Import-IsolatedDriverPolicy Enable
        (Get-ItemProperty ($base + 'Policies\Microsoft\Windows\WindowsUpdate')).PSObject.Properties['ExcludeWUDriversInQualityUpdate'] | Should -BeNullOrEmpty
        (Get-ItemProperty ($base + 'Policies\Microsoft\Windows\DriverSearching')).PSObject.Properties['SearchOrderConfig'] | Should -BeNullOrEmpty
        (Get-ItemProperty ($base + 'Microsoft\Windows\CurrentVersion\DriverSearching')).SearchOrderConfig | Should -Be 1
    }
}

Describe 'Applying the drivers choice' {
    BeforeAll {
        . (Join-Path $script:VantaTestScriptsRoot 'Preparation\RegistryFile.ps1')
        $script:registryLog = Join-Path $TestDrive 'registry.log'
        # The import the worker and ISO setup share, against an isolated key
        # that stands in for HKLM.
        $script:preparationKey = 'Software\VantaRewriteTest\PreparationDriverPolicy\' + [guid]::NewGuid().ToString('N')
        $script:preparationRoot = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:preparationKey)
        $script:preparationBase = 'HKCU:\' + $script:preparationKey + '\SOFTWARE\'
    }
    AfterAll {
        $script:preparationRoot.Dispose()
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\VantaRewriteTest', $false)
    }

    It 'gets drivers through Windows Update without creating keys only to delete values from them' {
        Import-VantaRegistryFile (Join-Path $script:policyFiles 'Enable Drivers from Windows Update.reg') $script:registryLog $script:preparationRoot
        Test-Path -LiteralPath ($script:preparationBase + 'Policies\Microsoft\Windows\DriverSearching') | Should -BeFalse
        Test-Path -LiteralPath ($script:preparationBase + 'Policies\Microsoft\Windows\WindowsUpdate') | Should -BeFalse
        Test-Path -LiteralPath ($script:preparationBase + 'Microsoft\PolicyManager\default\Update') | Should -BeFalse
        (Get-ItemProperty ($script:preparationBase + 'Microsoft\Windows\CurrentVersion\DriverSearching')).SearchOrderConfig | Should -Be 1
    }

    It 'turns drivers off and back on, deleting values only where they are' {
        Import-VantaRegistryFile (Join-Path $script:policyFiles 'Disable Drivers from Windows Update.reg') $script:registryLog $script:preparationRoot
        (Get-ItemProperty ($script:preparationBase + 'Policies\Microsoft\Windows\DriverSearching')).SearchOrderConfig | Should -Be 0
        (Get-ItemProperty ($script:preparationBase + 'Microsoft\PolicyManager\default\Update\ExcludeWUDriversInQualityUpdate')).value | Should -Be 1
        Import-VantaRegistryFile (Join-Path $script:policyFiles 'Enable Drivers from Windows Update.reg') $script:registryLog $script:preparationRoot
        (Get-ItemProperty ($script:preparationBase + 'Policies\Microsoft\Windows\DriverSearching')).PSObject.Properties['SearchOrderConfig'] | Should -BeNullOrEmpty
        (Get-ItemProperty ($script:preparationBase + 'Policies\Microsoft\Windows\WindowsUpdate')).PSObject.Properties['ExcludeWUDriversInQualityUpdate'] | Should -BeNullOrEmpty
        Test-Path -LiteralPath ($script:preparationBase + 'Microsoft\PolicyManager\default\Update\ExcludeWUDriversInQualityUpdate') | Should -BeFalse
        (Get-ItemProperty ($script:preparationBase + 'Microsoft\Windows\CurrentVersion\DriverSearching')).DontSearchWindowsUpdate | Should -Be 0
    }

    It 'refuses a line it does not know rather than half-applying it' {
        $file = Join-Path $TestDrive 'odd.reg'
        $text = "Windows Registry Editor Version 5.00`r`n`r`n[HKEY_LOCAL_MACHINE\SOFTWARE\Applied]`r`n`"First`"=dword:00000001`r`n`r`n" +
            "[HKEY_CURRENT_USER\Software\Odd]`r`n`"Name`"=dword:00000001`r`n"
        [IO.File]::WriteAllText($file, $text, [Text.Encoding]::Unicode)
        { Import-VantaRegistryFile $file $script:registryLog $script:preparationRoot } | Should -Throw '*Vanta doesn''t apply*'
        Test-Path -LiteralPath ($script:preparationBase + 'Applied') | Should -BeFalse
    }
}
