BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $modulesRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\package\Executables\VantaModules\Scripts\Modules'
    Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Services\Vanta.Services.psd1') -Force

    $script:testRoot = 'HKCU:\Software\VantaRewriteTest'
    $script:servicesRoot = "$script:testRoot\Services"

    function Write-TestVantaServicesBackup {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path,

            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string[]]$Lines
        )

        $parent = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
        [void][IO.Directory]::CreateDirectory($parent)
        [IO.File]::WriteAllLines(
            $Path,
            $Lines,
            (New-Object Text.UTF8Encoding($false, $true))
        )
    }
}

AfterAll {
    Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Set-VantaServiceStartup' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Services
        New-Item -Path $script:servicesRoot -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'writes and returns a typed Start value' {
        New-Item -Path "$script:servicesRoot\TestSvc" -Force | Out-Null

        $result = Set-VantaServiceStartup -Name 'TestSvc' -StartupType 4 `
            -ServicesRoot $script:servicesRoot -PassThru

        $key = Get-Item -LiteralPath "$script:servicesRoot\TestSvc"
        $key.GetValue('Start') | Should -Be 4
        $key.GetValueKind('Start') |
            Should -Be ([Microsoft.Win32.RegistryValueKind]::DWord)
        $result.Applied | Should -BeTrue
        $result.StartupType | Should -Be 4
    }

    It 'succeeds without writing when the typed startup setting is already correct' {
        New-Item -Path "$script:servicesRoot\TestSvc" -Force | Out-Null
        New-ItemProperty -Path "$script:servicesRoot\TestSvc" -Name Start -Value 4 -PropertyType DWord | Out-Null
        Mock Set-ItemProperty -ModuleName Vanta.Services { throw 'write must not run' }

        $result = Set-VantaServiceStartup -Name TestSvc -StartupType 4 -ServicesRoot $script:servicesRoot -PassThru

        $result.Applied | Should -BeTrue
        $result.StartupType | Should -Be 4
        Should -Invoke Set-ItemProperty -ModuleName Vanta.Services -Times 0 -Exactly
    }

    It 'repairs a matching value with the wrong registry type' {
        New-Item -Path "$script:servicesRoot\TestSvc" -Force | Out-Null
        New-ItemProperty -Path "$script:servicesRoot\TestSvc" -Name Start -Value '4' -PropertyType String | Out-Null

        Set-VantaServiceStartup -Name TestSvc -StartupType 4 -ServicesRoot $script:servicesRoot

        $key = Get-Item -LiteralPath "$script:servicesRoot\TestSvc"
        try { $key.GetValueKind('Start') | Should -Be ([Microsoft.Win32.RegistryValueKind]::DWord) }
        finally { $key.Close() }
    }

    It 'fails for a missing required service but allows reviewed optional absence' {
        { Set-VantaServiceStartup -Name 'MissingSvc' -StartupType 2 `
                -ServicesRoot $script:servicesRoot } |
            Should -Throw '*Required service or driver*'

        $result = Set-VantaServiceStartup -Name 'MissingSvc' -StartupType 2 `
            -ServicesRoot $script:servicesRoot -AllowMissing -PassThru
        $result.Applied | Should -BeFalse
        $result.StartupType | Should -BeNullOrEmpty
        # A service this PC doesn't have, such as BthPan without Bluetooth, is no warning.
        Should -Invoke Write-VantaLog -ModuleName Vanta.Services -Times 0 -Exactly -ParameterFilter { $Level -eq 'Warning' }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Services -Times 1 -Exactly -ParameterFilter { $Message -eq "Service or driver 'MissingSvc' isn't on this PC; nothing to change." }
    }

    It 'tolerates disabling an absent service and verifies it without drift' {
        $result = Set-VantaServiceStartup -Name MissingSvc -StartupType 4 `
            -ServicesRoot $script:servicesRoot -PassThru
        $result.Applied | Should -BeFalse
        @(Test-VantaServiceEntries -Entries @(@{ Name = 'MissingSvc'; StartupType = 4 }) `
            -ServicesRoot $script:servicesRoot).Count | Should -Be 0
        @(Test-VantaServiceEntries -Entries @(@{ Name = 'MissingSvc'; StartupType = 2 }) `
            -ServicesRoot $script:servicesRoot).Count | Should -Be 1
    }

    It 'does not let AllowMissing hide an existing-service write failure' {
        New-Item -Path "$script:servicesRoot\TestSvc" -Force | Out-Null
        Mock Set-ItemProperty -ModuleName Vanta.Services { throw 'simulated access denied' }

        { Set-VantaServiceStartup -Name 'TestSvc' -StartupType 4 `
                -ServicesRoot $script:servicesRoot -AllowMissing } |
            Should -Throw '*simulated access denied*'
    }

    It 'rejects invalid startup types and provider navigation names' {
        { Set-VantaServiceStartup -Name 'TestSvc' -StartupType 5 `
                -ServicesRoot $script:servicesRoot } | Should -Throw
        foreach ($name in @('.', '..')) {
            { Set-VantaServiceStartup -Name $name -StartupType 4 `
                    -ServicesRoot $script:servicesRoot } | Should -Throw '*not canonical*'
        }
    }
}

Describe 'Stop-VantaService' {
    It 'warns instead of failing when a service cannot be stopped' {
        Mock Write-VantaLog -ModuleName Vanta.Services

        { Stop-VantaService -Name 'VantaRewriteTestMissingSvc' } | Should -Not -Throw

        Should -Invoke Write-VantaLog -ModuleName Vanta.Services -Times 1 -Exactly
    }
}

Describe 'Vanta service backup' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Services
        $script:backupPath = Join-Path -Path $TestDrive -ChildPath 'Other\services.reg'
    }

    It 'exports sorted service Start values and validates the result' {
        Mock Get-VantaServicesBackupRecordSet -ModuleName Vanta.Services {
            @(
                [pscustomobject]@{ Name = 'Zulu'; Start = [int]4 }
                [pscustomobject]@{ Name = 'Alpha'; Start = [int]2 }
            )
        }

        Export-VantaServicesBackup -FilePath $script:backupPath
        $content = Get-Content -LiteralPath $script:backupPath -Raw

        $content | Should -Match '"Start"=dword:00000004'
        $content.IndexOf('Services\Alpha]') |
            Should -BeLessThan $content.IndexOf('Services\Zulu]')
    }

    It 'keeps the first valid backup without enumerating current services again' {
        Write-TestVantaServicesBackup -Path $script:backupPath -Lines @(
            'Windows Registry Editor Version 5.00'
            ''
            '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Original]'
            '"Start"=dword:00000003'
        )
        $originalBytes = [Convert]::ToBase64String(
            [IO.File]::ReadAllBytes($script:backupPath)
        )
        Mock Get-VantaServicesBackupRecordSet -ModuleName Vanta.Services {
            throw 'service enumeration should not run'
        }

        Export-VantaServicesBackup -FilePath $script:backupPath

        [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:backupPath)) |
            Should -BeExactly $originalBytes
        Should -Invoke Get-VantaServicesBackupRecordSet `
            -ModuleName Vanta.Services -Times 0 -Exactly
    }

    It 'does not overwrite an invalid existing backup' {
        Write-TestVantaServicesBackup -Path $script:backupPath -Lines @('not a registry backup')
        Mock Get-VantaServicesBackupRecordSet -ModuleName Vanta.Services {
            @([pscustomobject]@{ Name = 'Alpha'; Start = [int]2 })
        }

        { Export-VantaServicesBackup -FilePath $script:backupPath } | Should -Throw

        Get-Content -LiteralPath $script:backupPath -Raw |
            Should -Match '^not a registry backup'
        Should -Invoke Get-VantaServicesBackupRecordSet `
            -ModuleName Vanta.Services -Times 0 -Exactly
    }

    It 'rejects malformed, duplicate, and excluded records' {
        Mock Set-VantaServiceStartup -ModuleName Vanta.Services
        $invalidBackups = @(
            @(
                'Windows Registry Editor Version 5.00'
                '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Alpha]'
            )
            @(
                'Windows Registry Editor Version 5.00'
                '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Alpha]'
                '"Start"=dword:00000002'
                '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Alpha]'
                '"Start"=dword:00000003'
            )
            @(
                'Windows Registry Editor Version 5.00'
                '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\WinDefend]'
                '"Start"=dword:00000002'
            )
        )

        foreach ($lines in $invalidBackups) {
            Write-TestVantaServicesBackup -Path $script:backupPath -Lines $lines
            { Restore-VantaServicesBackup -FilePath $script:backupPath } |
                Should -Throw
        }
        Should -Invoke Set-VantaServiceStartup `
            -ModuleName Vanta.Services -Times 0 -Exactly
    }

    It 'restores typed values and reports services removed since backup' {
        # Removed restores to Manual: the real helper skips a missing service bound for
        # Disabled before it checks AllowMissing, so only a value like this one needs it.
        Write-TestVantaServicesBackup -Path $script:backupPath -Lines @(
            'Windows Registry Editor Version 5.00'
            '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Alpha]'
            '"Start"=dword:00000002'
            '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Removed]'
            '"Start"=dword:00000003'
        )
        Mock Set-VantaServiceStartup -ModuleName Vanta.Services {
            if ($Name -ceq 'Alpha') {
                return [pscustomobject]@{
                    Name = $Name; Applied = $true; StartupType = [int]$StartupType
                }
            }
            return [pscustomobject]@{
                Name = $Name; Applied = $false; StartupType = $null
            }
        }

        $result = Restore-VantaServicesBackup -FilePath $script:backupPath

        $result.RestoredCount | Should -Be 1
        $result.MissingCount | Should -Be 1
        Should -Invoke Set-VantaServiceStartup `
            -ModuleName Vanta.Services -Times 2 -Exactly
        Should -Invoke Set-VantaServiceStartup -ModuleName Vanta.Services -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'Alpha' -and $StartupType -eq 2 -and $AllowMissing -and $PassThru
        }
        Should -Invoke Set-VantaServiceStartup -ModuleName Vanta.Services -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'Removed' -and $StartupType -eq 3 -and $AllowMissing -and $PassThru
        }
    }

}

Describe 'Invoke-VantaServiceEntries' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Services
        Mock Set-VantaServiceStartup -ModuleName Vanta.Services
        Mock Stop-Service -ModuleName Vanta.Services
        Mock Start-Service -ModuleName Vanta.Services
    }

    It 'applies Change entries through the checked startup helper, forwarding AllowMissing' {
        Invoke-VantaServiceEntries -Entries @(
            @{ Name = 'Alpha'; StartupType = 4 }
            @{ Name = 'Beta'; Operation = 'Change'; StartupType = 3; AllowMissing = $true }
            @{ Name = 'Gamma'; StartupType = 0; AllowMissing = $false }
        )

        Should -Invoke Set-VantaServiceStartup -ModuleName Vanta.Services -Times 3 -Exactly
        Should -Invoke Set-VantaServiceStartup -ModuleName Vanta.Services -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'Alpha' -and $StartupType -eq 4 -and -not $AllowMissing
        }
        Should -Invoke Set-VantaServiceStartup -ModuleName Vanta.Services -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'Beta' -and $StartupType -eq 3 -and $AllowMissing
        }
        Should -Invoke Set-VantaServiceStartup -ModuleName Vanta.Services -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'Gamma' -and $StartupType -eq 0 -and -not $AllowMissing
        }
        Should -Invoke Stop-Service -ModuleName Vanta.Services -Times 0 -Exactly
        Should -Invoke Start-Service -ModuleName Vanta.Services -Times 0 -Exactly
    }

    It 'routes Stop and Start entries to the service controller cmdlets' {
        Invoke-VantaServiceEntries -Entries @(
            @{ Name = 'Alpha'; Operation = 'Stop' }
            @{ Name = 'Beta'; Operation = 'Start' }
        )

        Should -Invoke Stop-Service -ModuleName Vanta.Services -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'Alpha' -and $Force
        }
        Should -Invoke Start-Service -ModuleName Vanta.Services -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'Beta'
        }
        Should -Invoke Set-VantaServiceStartup -ModuleName Vanta.Services -Times 0 -Exactly
    }

    It 'rejects malformed entries before touching any service' -TestCases @(
        @{ Entry = @{ StartupType = 4 }; Message = '*has no Name*' }
        @{ Entry = @{ Name = 'Alpha' }; Message = '*no valid StartupType*' }
        @{ Entry = @{ Name = 'Alpha'; StartupType = 5 }; Message = '*no valid StartupType*' }
        @{ Entry = @{ Name = 'Alpha'; Operation = 'Restart' }; Message = "*Unknown service operation 'Restart'*" }
    ) {
        { Invoke-VantaServiceEntries -Entries @($Entry) } | Should -Throw $Message

        Should -Invoke Set-VantaServiceStartup -ModuleName Vanta.Services -Times 0 -Exactly
        Should -Invoke Stop-Service -ModuleName Vanta.Services -Times 0 -Exactly
        Should -Invoke Start-Service -ModuleName Vanta.Services -Times 0 -Exactly
    }

    It 'propagates a required failure and stops at the failing entry' {
        Mock Set-VantaServiceStartup -ModuleName Vanta.Services -ParameterFilter { $Name -ceq 'Beta' } -MockWith {
            throw "Service or driver 'Beta' did not retain startup type '4'."
        }

        {
            Invoke-VantaServiceEntries -Entries @(
                @{ Name = 'Alpha'; StartupType = 4 }
                @{ Name = 'Beta'; StartupType = 4 }
                @{ Name = 'Gamma'; StartupType = 4 }
            )
        } | Should -Throw '*did not retain startup type*'

        Should -Invoke Set-VantaServiceStartup -ModuleName Vanta.Services -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'Alpha'
        }
        Should -Invoke Set-VantaServiceStartup -ModuleName Vanta.Services -Times 0 -Exactly -ParameterFilter {
            $Name -ceq 'Gamma'
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Services -Times 0 -Exactly
    }

    It 'turns a failure into a warning and continues when the entry ignores errors' {
        Mock Set-VantaServiceStartup -ModuleName Vanta.Services -ParameterFilter { $Name -ceq 'Beta' } -MockWith {
            throw 'simulated access denied'
        }
        Mock Stop-Service -ModuleName Vanta.Services -MockWith { throw 'cannot stop' }

        Invoke-VantaServiceEntries -Entries @(
            @{ Name = 'Beta'; StartupType = 4; IgnoreErrors = $true }
            @{ Name = 'Delta'; Operation = 'Stop'; IgnoreErrors = $true }
            @{ Operation = 'Start'; IgnoreErrors = $true }
            @{ Name = 'Gamma'; StartupType = 2 }
        )

        Should -Invoke Set-VantaServiceStartup -ModuleName Vanta.Services -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'Gamma' -and $StartupType -eq 2
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Services -Times 3 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -like 'Ignored service entry failure*'
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Services -Times 1 -Exactly -ParameterFilter {
            $Message -like "*(service: 'Beta')*simulated access denied*"
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Services -Times 1 -Exactly -ParameterFilter {
            $Message -like "*(service: 'Delta')*cannot stop*"
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Services -Times 1 -Exactly -ParameterFilter {
            $Message -like "*(service: '<no name>')*has no Name*"
        }
    }

    It 'accepts an empty entry list' {
        { Invoke-VantaServiceEntries -Entries @() } | Should -Not -Throw
        Should -Invoke Set-VantaServiceStartup -ModuleName Vanta.Services -Times 0 -Exactly
    }

    It 'names Windows'' own reason when a service won''t start' {
        # Start-Service's message names only the service; the reason is its innermost cause.
        Mock Start-Service -ModuleName Vanta.Services -MockWith {
            $reason = [ComponentModel.Win32Exception]::new(1058, 'The service is disabled.')
            $inner = [InvalidOperationException]::new("Cannot start service w32time on computer '.'.", $reason)
            throw [InvalidOperationException]::new("Service 'Windows Time (w32time)' cannot be started due to the following error: Cannot start service w32time on computer '.'.", $inner)
        }

        { Invoke-VantaServiceEntries -Entries @(@{ Name = 'w32time'; Operation = 'Start' }) } |
            Should -Throw "Service 'Windows Time (w32time)' cannot be started*The service is disabled."
        Invoke-VantaServiceEntries -Entries @(@{ Name = 'w32time'; Operation = 'Start'; IgnoreErrors = $true })
        Should -Invoke Write-VantaLog -ModuleName Vanta.Services -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -like "Ignored service entry failure (service: 'w32time'):*The service is disabled."
        }
    }
}
