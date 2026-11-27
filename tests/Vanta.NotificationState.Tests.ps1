BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $script:NotificationScriptPath = Join-Path -Path $script:VantaTestScriptsRoot -ChildPath `
        'Install\Tasks\Set-NotificationState.ps1'
    $script:NotificationPolicyPath =
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'

    function Get-VantaInstallWorkRoot {
        return $script:VantaNotificationTestWorkRoot
    }

    function Get-VantaInstallState {
        return [pscustomobject]@{ status = 'Running' }
    }
}

AfterAll {
    Remove-Variable -Name VantaNotificationTestWorkRoot -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name VantaNotificationRegistryTestState -Scope Script -ErrorAction SilentlyContinue
}

Describe 'Temporary notification policy state' {
    BeforeEach {
        $script:VantaNotificationTestWorkRoot = Join-Path -Path $TestDrive -ChildPath `
            ([Guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $script:VantaNotificationTestWorkRoot -Force)
        $script:VantaNotificationRegistryTestState = @{
            KeyExists   = $false
            ValueExists = $false
            Kind        = [Microsoft.Win32.RegistryValueKind]::DWord
            Value       = $null
            IgnoreWrite = $false
        }

        Mock Import-Module {}
        Mock Test-Path -ParameterFilter {
            $LiteralPath -eq $script:NotificationPolicyPath
        } -MockWith {
            return [bool]$script:VantaNotificationRegistryTestState.KeyExists
        }
        Mock Get-Item -ParameterFilter {
            $LiteralPath -eq $script:NotificationPolicyPath
        } -MockWith {
            $key = [pscustomobject]@{}
            $key | Add-Member -MemberType ScriptMethod -Name GetValueNames -Value {
                if ($script:VantaNotificationRegistryTestState.ValueExists) {
                    return @('NoToastApplicationNotification')
                }
                return @()
            }
            $key | Add-Member -MemberType ScriptMethod -Name GetValueKind -Value {
                return $script:VantaNotificationRegistryTestState.Kind
            }
            $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value {
                $defaultValue = $args[1]
                if (-not $script:VantaNotificationRegistryTestState.ValueExists) {
                    return $DefaultValue
                }
                return $script:VantaNotificationRegistryTestState.Value
            }
            return $key
        }
        Mock New-Item -ParameterFilter {
            $Path -eq $script:NotificationPolicyPath
        } -MockWith {
            $script:VantaNotificationRegistryTestState.KeyExists = $true
        }
        Mock New-ItemProperty -ParameterFilter {
            $LiteralPath -eq $script:NotificationPolicyPath
        } -MockWith {
            if (-not $script:VantaNotificationRegistryTestState.IgnoreWrite) {
                $script:VantaNotificationRegistryTestState.KeyExists = $true
                $script:VantaNotificationRegistryTestState.ValueExists = $true
                $script:VantaNotificationRegistryTestState.Kind =
                    [Microsoft.Win32.RegistryValueKind]::DWord
                $script:VantaNotificationRegistryTestState.Value = [int]$Value
            }
        }
        Mock Remove-ItemProperty -ParameterFilter {
            $LiteralPath -eq $script:NotificationPolicyPath
        } -MockWith {
            if (-not $script:VantaNotificationRegistryTestState.IgnoreWrite) {
                $script:VantaNotificationRegistryTestState.ValueExists = $false
                $script:VantaNotificationRegistryTestState.Value = $null
            }
        }
    }

    It 'captures absence once and disables notifications' {
        . $script:NotificationScriptPath -Mode Disable

        $snapshotPath = Join-Path $script:VantaNotificationTestWorkRoot 'notification.json'
        $snapshot = [IO.File]::ReadAllText($snapshotPath) | ConvertFrom-Json
        $snapshot.existed | Should -BeFalse
        $snapshot.value | Should -BeNullOrEmpty
        $script:VantaNotificationRegistryTestState.Value | Should -Be 1

        $script:VantaNotificationRegistryTestState.Value = 0
        . $script:NotificationScriptPath -Mode Disable
        $snapshot = [IO.File]::ReadAllText($snapshotPath) | ConvertFrom-Json
        $snapshot.existed | Should -BeFalse
        $script:VantaNotificationRegistryTestState.Value | Should -Be 1
    }

    It 'restores the exact prior DWORD and removes the snapshot' {
        $script:VantaNotificationRegistryTestState.KeyExists = $true
        $script:VantaNotificationRegistryTestState.ValueExists = $true
        $script:VantaNotificationRegistryTestState.Value = [int]::MinValue

        . $script:NotificationScriptPath -Mode Disable
        . $script:NotificationScriptPath -Mode Enable

        $script:VantaNotificationRegistryTestState.ValueExists | Should -BeTrue
        $script:VantaNotificationRegistryTestState.Value | Should -Be ([int]::MinValue)
        [IO.File]::Exists((Join-Path $script:VantaNotificationTestWorkRoot 'notification.json')) |
            Should -BeFalse
    }

    It 'restores an absent value and tolerates a repeated restore' {
        . $script:NotificationScriptPath -Mode Disable
        . $script:NotificationScriptPath -Mode Enable
        . $script:NotificationScriptPath -Mode Enable

        $script:VantaNotificationRegistryTestState.ValueExists | Should -BeFalse
        [IO.File]::Exists((Join-Path $script:VantaNotificationTestWorkRoot 'notification.json')) |
            Should -BeFalse
    }

    It 'never recreates an existing policy key, which would drop its other values' {
        $script:VantaNotificationRegistryTestState.KeyExists = $true

        . $script:NotificationScriptPath -Mode Disable
        . $script:NotificationScriptPath -Mode Enable

        Should -Invoke New-Item -Times 0 -Exactly -ParameterFilter { $Path -eq $script:NotificationPolicyPath }
    }

    It 'rejects a pre-existing non-DWORD policy without changing it' {
        $script:VantaNotificationRegistryTestState.KeyExists = $true
        $script:VantaNotificationRegistryTestState.ValueExists = $true
        $script:VantaNotificationRegistryTestState.Kind =
            [Microsoft.Win32.RegistryValueKind]::String
        $script:VantaNotificationRegistryTestState.Value = 'custom'

        { . $script:NotificationScriptPath -Mode Disable } | Should -Throw '*must be a DWORD*'
        $script:VantaNotificationRegistryTestState.Value | Should -Be 'custom'
        [IO.File]::Exists((Join-Path $script:VantaNotificationTestWorkRoot 'notification.json')) |
            Should -BeFalse
    }

    It 'keeps the snapshot when restoration does not verify' {
        $script:VantaNotificationRegistryTestState.KeyExists = $true
        $script:VantaNotificationRegistryTestState.ValueExists = $true
        $script:VantaNotificationRegistryTestState.Value = 0
        . $script:NotificationScriptPath -Mode Disable
        $script:VantaNotificationRegistryTestState.IgnoreWrite = $true

        { . $script:NotificationScriptPath -Mode Enable } |
            Should -Throw '*did not match the requested state*'
        [IO.File]::Exists((Join-Path $script:VantaNotificationTestWorkRoot 'notification.json')) |
            Should -BeTrue
    }
}
