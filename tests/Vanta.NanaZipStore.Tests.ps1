BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Software\Vanta.Software.psd1') -Force
}

Describe 'NanaZip Store installation' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Software
        Mock Get-VantaNanaZipStoreJournal -ModuleName Vanta.Software { [pscustomobject]@{ Pending = $false } }
        Mock Set-VantaNanaZipStorePending -ModuleName Vanta.Software
        Mock Start-Sleep -ModuleName Vanta.Software
    }


    It 'falls back when Store cannot activate and there is no pending request' {
        Mock New-VantaNanaZipStoreManager -ModuleName Vanta.Software { throw 'Store unavailable' }
        InModuleScope Vanta.Software { Install-VantaNanaZipFromStore -DismCommands @{} | Should -BeFalse }
        Should -Invoke Set-VantaNanaZipStorePending -ModuleName Vanta.Software -Times 0 -Exactly
    }

    It 'does not fall back when a previous request is unresolved and <Failure>' -TestCases @(
        @{ Failure = 'Store cannot activate'; ManagerFails = $true }
        @{ Failure = 'the Store queue cannot be read'; ManagerFails = $false }
    ) {
        Mock Get-VantaNanaZipStoreJournal -ModuleName Vanta.Software { [pscustomobject]@{ Pending = $true } }
        if ($ManagerFails) {
            Mock New-VantaNanaZipStoreManager -ModuleName Vanta.Software { throw 'Store unavailable' }
        }
        else {
            Mock New-VantaNanaZipStoreManager -ModuleName Vanta.Software { [pscustomobject]@{ CanInstallForAllUsers = $true } }
            Mock Get-VantaNanaZipStoreItems -ModuleName Vanta.Software { throw 'queue unavailable' }
        }
        InModuleScope Vanta.Software { { Install-VantaNanaZipFromStore -DismCommands @{} } | Should -Throw '*unknown outcome*' }
    }

    It 'requires provisioning after a completed Store operation' {
        InModuleScope Vanta.Software {
            Mock New-VantaNanaZipStoreManager { [pscustomobject]@{ CanInstallForAllUsers = $true } }
            Mock Get-VantaNanaZipStoreItems { [pscustomobject]@{ ProductId = '9N8G7TSCL18R' } }
            Mock Wait-VantaNanaZipStoreItems { $true }
            $commands = @{ GetProvisionedPackage = { @() } }
            { Install-VantaNanaZipFromStore -DismCommands $commands } | Should -Throw '*provisioning could not be verified*'
            Should -Invoke Set-VantaNanaZipStorePending -Times 0 -Exactly -ParameterFilter { -not $Pending }
        }
    }

    It 'accepts verified provisioning and clears the pending marker' {
        InModuleScope Vanta.Software {
            Mock New-VantaNanaZipStoreManager { [pscustomobject]@{ CanInstallForAllUsers = $true } }
            Mock Get-VantaNanaZipStoreItems { [pscustomobject]@{ ProductId = '9N8G7TSCL18R' } }
            Mock Wait-VantaNanaZipStoreItems { $true }
            $commands = @{ GetProvisionedPackage = { [pscustomobject]@{ DisplayName = '40174MouriNaruto.NanaZip' } } }
            Install-VantaNanaZipFromStore -DismCommands $commands | Should -BeTrue
            Should -Invoke Set-VantaNanaZipStorePending -Times 1 -Exactly -ParameterFilter { -not $Pending }
        }
    }

    It 'never falls back while a deployment is still active' {
        InModuleScope Vanta.Software {
            Mock New-VantaNanaZipStoreManager { [pscustomobject]@{ CanInstallForAllUsers = $true } }
            Mock Get-VantaNanaZipStoreItems { [pscustomobject]@{ ProductId = '9N8G7TSCL18R' } }
            Mock Wait-VantaNanaZipStoreItems { throw 'still installing' }
            { Install-VantaNanaZipFromStore -DismCommands @{} } | Should -Throw '*still installing*'
            Should -Invoke Set-VantaNanaZipStorePending -Times 0 -Exactly -ParameterFilter { -not $Pending }
        }
    }

    It 'records pending state before requesting a fresh installation' {
        InModuleScope Vanta.Software {
            $script:storePending = $false
            Mock New-VantaNanaZipStoreManager { [pscustomobject]@{ CanInstallForAllUsers = $true } }
            Mock Get-VantaNanaZipStoreItems { @() }
            Mock Get-VantaNanaZipStoreEntitlement
            Mock Set-VantaNanaZipStorePending { $script:storePending = $Pending }
            Mock Request-VantaNanaZipStoreInstall {
                $script:storePending | Should -BeTrue
                throw 'lost RPC response'
            }
            { Install-VantaNanaZipFromStore -DismCommands @{} } | Should -Throw '*lost RPC response*'
            $script:storePending | Should -BeTrue
        }
    }

    It 'falls back on entitlement failure without requesting deployment' {
        InModuleScope Vanta.Software {
            Mock New-VantaNanaZipStoreManager { [pscustomobject]@{ CanInstallForAllUsers = $true } }
            Mock Get-VantaNanaZipStoreItems { @() }
            Mock Get-VantaNanaZipStoreEntitlement { throw 'network unavailable' }
            Mock Request-VantaNanaZipStoreInstall { throw 'must not deploy' }
            Install-VantaNanaZipFromStore -DismCommands @{} | Should -BeFalse
            Should -Invoke Request-VantaNanaZipStoreInstall -Times 0 -Exactly
        }
    }

    It 'allows fallback only after failed jobs are terminal and removed from the queue' {
        InModuleScope Vanta.Software {
            $script:queueReads = 0
            $manager = [pscustomobject]@{ CanInstallForAllUsers = $true }
            $manager | Add-Member ScriptMethod Cancel { param($ProductId) $ProductId | Should -BeExactly '9N8G7TSCL18R' }
            Mock New-VantaNanaZipStoreManager { $manager }
            Mock Get-VantaNanaZipStoreItems {
                $script:queueReads++
                if ($script:queueReads -le 2) { [pscustomobject]@{ ProductId='9N8G7TSCL18R' } }
            }
            Mock Wait-VantaNanaZipStoreItems { $false }
            Install-VantaNanaZipFromStore -DismCommands @{ GetProvisionedPackage = { @() } } | Should -BeFalse
            $script:queueReads | Should -Be 3
            Should -Invoke Set-VantaNanaZipStorePending -Times 1 -Exactly -ParameterFilter { -not $Pending }
        }
    }
}

Describe 'Archive installer Store-first routing' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Software
        Mock Test-Path -ModuleName Vanta.Software -ParameterFilter { $LiteralPath -like '*7-Zip*' } { $false }
        Mock Get-VantaDismProvisioningCommands -ModuleName Vanta.Software { @{ GetProvisionedPackage = { @() } } }
        Mock Install-VantaNanaZip -ModuleName Vanta.Software { throw 'download must not start' }
        Mock Get-VantaPinnedNanaZipReleaseAssets -ModuleName Vanta.Software { throw 'assets must not be fetched' }
    }

    It 'does not download installers when Store succeeds' {
        Mock Install-VantaNanaZipFromStore -ModuleName Vanta.Software { $true }
        InModuleScope Vanta.Software { Install-VantaArchiveTool -TempDir 'C:\unused' }
        Should -Invoke Install-VantaNanaZip -ModuleName Vanta.Software -Times 0 -Exactly
        Should -Invoke Get-VantaPinnedNanaZipReleaseAssets -ModuleName Vanta.Software -Times 0 -Exactly
    }

    It 'does not start download fallback after an uncertain Store result' {
        Mock Install-VantaNanaZipFromStore -ModuleName Vanta.Software { throw 'deployment uncertain' }
        InModuleScope Vanta.Software { { Install-VantaArchiveTool -TempDir 'C:\unused' } | Should -Throw '*deployment uncertain*' }
        Should -Invoke Install-VantaNanaZip -ModuleName Vanta.Software -Times 0 -Exactly
    }
}

Describe 'Store deployment state handling' {
    It 'waits for every returned item, including dependencies' {
        InModuleScope Vanta.Software {
            Mock Write-VantaLog
            $done = [pscustomobject]@{}
            $done | Add-Member ScriptMethod GetCurrentStatus { [pscustomobject]@{ InstallState='Completed'; PercentComplete=100; ErrorCode=$null } }
            $done | Add-Member NoteProperty ProductId '9N8G7TSCL18R'
            $active = [pscustomobject]@{ ProductId='dependency' }
            $active | Add-Member ScriptMethod GetCurrentStatus { [pscustomobject]@{ InstallState='Downloading'; PercentComplete=10; ErrorCode=$null } }
            { Wait-VantaNanaZipStoreItems -Manager @{} -Items @($done,$active) -TimeoutSeconds 0 } | Should -Throw '*still queued or installing*'
            Wait-VantaNanaZipStoreItems -Manager @{} -Items @($done) | Should -BeTrue
        }
    }
}

Describe 'Stalled NanaZip cancellation before download fallback' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Software
        Mock Start-Sleep -ModuleName Vanta.Software
    }
    It 'waits until every handle reports a terminal state' {
        InModuleScope Vanta.Software {
            $script:reads = 0
            $item = [pscustomobject]@{}
            $item | Add-Member ScriptMethod GetCurrentStatus {
                $script:reads++
                [pscustomobject]@{ InstallState = $(if ($script:reads -lt 3) { 'Installing' } else { 'Canceled' }) }
            }
            $manager = [pscustomobject]@{}
            $manager | Add-Member ScriptMethod Cancel { param($ProductId) $ProductId | Should -BeExactly '9N8G7TSCL18R' }
            Mock Get-VantaNanaZipStoreItems { @() }
            { Stop-VantaNanaZipStoreInstall -Manager $manager -Items @($item) -Attempts 3 } | Should -Not -Throw
            $script:reads | Should -Be 3
        }
    }
    It 'waits until the Store queue no longer lists NanaZip' {
        InModuleScope Vanta.Software {
            $script:queueReads = 0
            $item = [pscustomobject]@{}
            $item | Add-Member ScriptMethod GetCurrentStatus { [pscustomobject]@{ InstallState = 'Canceled' } }
            $manager = [pscustomobject]@{}
            $manager | Add-Member ScriptMethod Cancel {}
            Mock Get-VantaNanaZipStoreItems {
                $script:queueReads++
                if ($script:queueReads -le 2) { [pscustomobject]@{ ProductId = '9N8G7TSCL18R' } }
            }
            { Stop-VantaNanaZipStoreInstall -Manager $manager -Items @($item) -Attempts 3 } | Should -Not -Throw
            $script:queueReads | Should -Be 3
            Should -Invoke Start-Sleep -Times 2 -Exactly
        }
    }
    It 'refuses fallback while the Store queue still lists NanaZip' {
        InModuleScope Vanta.Software {
            $item = [pscustomobject]@{}
            $item | Add-Member ScriptMethod GetCurrentStatus { [pscustomobject]@{ InstallState = 'Canceled' } }
            $manager = [pscustomobject]@{}
            $manager | Add-Member ScriptMethod Cancel {}
            Mock Get-VantaNanaZipStoreItems { [pscustomobject]@{ ProductId = '9N8G7TSCL18R' } }
            { Stop-VantaNanaZipStoreInstall -Manager $manager -Items @($item) -Attempts 2 } | Should -Throw '*not confirmed*'
        }
    }
    It 'refuses fallback when cancellation cannot be confirmed' {
        InModuleScope Vanta.Software {
            $item = [pscustomobject]@{}
            $item | Add-Member ScriptMethod GetCurrentStatus { [pscustomobject]@{ InstallState='Installing' } }
            $manager = [pscustomobject]@{}
            $manager | Add-Member ScriptMethod Cancel {}
            Mock Get-VantaNanaZipStoreItems { @() }
            { Stop-VantaNanaZipStoreInstall -Manager $manager -Items @($item) -Attempts 2 } | Should -Throw '*not confirmed*'
        }
    }
    It 'falls back after timeout only once cancellation is confirmed' {
        InModuleScope Vanta.Software {
            Mock Get-VantaNanaZipStoreJournal { [pscustomobject]@{ Pending=$false } }
            Mock New-VantaNanaZipStoreManager { [pscustomobject]@{ CanInstallForAllUsers=$true } }
            Mock Get-VantaNanaZipStoreItems { [pscustomobject]@{ ProductId='9N8G7TSCL18R' } }
            Mock Wait-VantaNanaZipStoreItems { throw [TimeoutException]::new('Stalled') }
            Mock Stop-VantaNanaZipStoreInstall {}
            Mock Set-VantaNanaZipStorePending {}
            Install-VantaNanaZipFromStore -DismCommands @{ GetProvisionedPackage={ @() } } | Should -BeFalse
            Should -Invoke Stop-VantaNanaZipStoreInstall -Times 1 -Exactly
            Should -Invoke Set-VantaNanaZipStorePending -Times 1 -Exactly -ParameterFilter { -not $Pending }
        }
    }
}
