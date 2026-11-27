[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidGlobalVars',
    '',
    Justification = 'Module-scoped mock bodies cannot see test-file variables, so shared fixture state is staged as global variables.'
)]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    # A bare Windows PowerShell 5.1 host has not loaded the service controller types.
    Add-Type -AssemblyName System.ServiceProcess
    Import-Module -Name (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module -Name (Join-Path $script:VantaTestModulesRoot 'Vanta.Search\Vanta.Search.psd1') -Force

    $script:testRoot = 'HKCU:\Software\VantaRewriteTest'
    $script:entryPath = Join-Path $script:VantaTestScriptsRoot 'Entry\Set-IndexConfiguration.ps1'
    $script:launcherPath = Join-Path $script:VantaTestScriptsRoot 'Entry\Set-IndexConfiguration.cmd'
}

AfterAll {
    Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Variable -Name VantaSearchTestCalls, VantaSearchTestService, VantaSearchTestUsersRoot `
        -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Index path behavior' {
    BeforeAll {
        # Point the module's fixed HKLM roots at the scratch hive for the duration
        # of this block so policy lists run against a real registry.
        $script:savedRoots = InModuleScope Vanta.Search {
            [pscustomobject]@{
                Paths    = $script:VantaIndexPathRoots
                Policies = $script:VantaIndexPolicyRoots
            }
        }
        InModuleScope Vanta.Search {
            $script:VantaIndexPathRoots = @{
                Include = 'HKCU:\Software\VantaRewriteTest\Search\Paths'
                Exclude = 'HKCU:\Software\VantaRewriteTest\Search\Exclusions'
            }
            # The other policy lists the module clears move under the scratch key too,
            # so CleanPolicies walks the real list without touching HKLM.
            $machinePrefix = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\'
            $script:VantaIndexPolicyRoots = @(
                $script:VantaIndexPathRoots.Include
                $script:VantaIndexPathRoots.Exclude
                foreach ($policyRoot in @($saved.Policies | Where-Object { @($saved.Paths.Values) -notcontains $_ })) {
                    if (-not $policyRoot.StartsWith($machinePrefix, [StringComparison]::OrdinalIgnoreCase)) {
                        throw "Policy root '$policyRoot' cannot be moved into the scratch hive."
                    }
                    'Registry::HKEY_CURRENT_USER\Software\VantaRewriteTest\' + $policyRoot.Substring($machinePrefix.Length)
                }
            )
        } -Parameters @{ saved = $script:savedRoots }
    }

    AfterAll {
        InModuleScope Vanta.Search {
            $script:VantaIndexPathRoots = $saved.Paths
            $script:VantaIndexPolicyRoots = $saved.Policies
        } -Parameters @{ saved = $script:savedRoots }
    }

    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Search
        Mock Test-VantaAdmin -ModuleName Vanta.Search { $true }
    }

    AfterEach {
        Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'preserves literal path data and accepts drive and UNC absolute paths' {
        $drivePath = Join-Path $TestDrive 'Index %VANTA_PERCENT% & !VANTA_BANG! Folder'
        InModuleScope Vanta.Search { ConvertTo-VantaIndexPath -Candidate $candidate } -Parameters @{ candidate = $drivePath } |
            Should -BeExactly ([IO.Path]::GetFullPath($drivePath))

        $uncPath = '\\server\share\Index %VANTA_PERCENT% & !VANTA_BANG! Folder'
        InModuleScope Vanta.Search { ConvertTo-VantaIndexPath -Candidate $candidate } -Parameters @{ candidate = $uncPath } |
            Should -BeExactly ([IO.Path]::GetFullPath($uncPath))
    }

    It 'rejects relative, root-relative, incomplete UNC, and wildcard paths' {
        foreach ($candidate in @(
                '.\relative',
                '\root-relative',
                'C:drive-relative',
                '\\server-only',
                (Join-Path $TestDrive 'wild*card'),
                (Join-Path $TestDrive 'wild?card')
            )) {
            { InModuleScope Vanta.Search { ConvertTo-VantaIndexPath -Candidate $candidate } -Parameters @{ candidate = $candidate } } |
                Should -Throw
        }
    }

    It 'writes policy URLs as REG_SZ value names and data without creating Gather-style children' {
        $includeRoot = 'HKCU:\Software\VantaRewriteTest\Search\Paths'
        Set-VantaIndexConfiguration -Operation Include -IndexPath 'C:\Wanted\..\Wanted\'
        $url = 'file:///C:\Wanted\'
        $entry = Get-Item -LiteralPath $includeRoot
        $entry.GetValueNames() | Should -Be @($url)
        $entry.GetValue($url) | Should -BeExactly $url
        $entry.GetValueKind($url) | Should -Be ([Microsoft.Win32.RegistryValueKind]::String)
        @(Get-ChildItem -LiteralPath $includeRoot).Count | Should -Be 0
    }

    It 'reuses a case-insensitive matching entry without allocating another key' {
        $excludeRoot = 'HKCU:\Software\VantaRewriteTest\Search\Exclusions'
        Set-VantaIndexConfiguration -Operation Exclude -IndexPath 'c:\wanted\'
        Set-VantaIndexConfiguration -Operation Exclude -IndexPath 'C:\Wanted'
        $entry = Get-Item -LiteralPath $excludeRoot
        @($entry.GetValueNames()).Count | Should -Be 1
        $entry.GetValue('file:///C:\Wanted\*') | Should -BeExactly 'file:///C:\Wanted\*'
        @(Get-ChildItem -LiteralPath $excludeRoot).Count | Should -Be 0
    }

    It 'preserves literal characters and formats UNC exclusions' {
        $path = '\\server\share\Index %VANTA_PERCENT% & !VANTA_BANG! Folder'
        Set-VantaIndexConfiguration -Operation Exclude -IndexPath $path
        $url = 'file://server\share\Index %VANTA_PERCENT% & !VANTA_BANG! Folder\*'
        $entry = Get-Item -LiteralPath 'HKCU:\Software\VantaRewriteTest\Search\Exclusions'
        $entry.GetValue($url) | Should -BeExactly $url
    }

    It 'clears every policy list, including the two earlier RCs wrote, and keeps Search-owned scope and caches' {
        $internalRoot = 'HKCU:\Software\VantaRewriteTest\Search\Gather'
        $cacheRoot = 'HKCU:\Software\VantaRewriteTest\Search\CurrentPolicies'
        foreach ($root in @($internalRoot, $cacheRoot)) {
            New-Item -Path "$root\Stale" -Force | Out-Null
            Set-ItemProperty -LiteralPath $root -Name Included -Value 1 -Type DWord
        }
        New-Item -Path 'HKCU:\Software\VantaRewriteTest\Search\Paths\0' -Force | Out-Null
        # Written out rather than derived from the module's list, so dropping either
        # entry from that list leaves these seeded and fails the test.
        $legacyRoots = @(
            'HKCU:\Software\VantaRewriteTest\Policies\Microsoft\Windows\Windows Search\DefaultIndexedPaths'
            'HKCU:\Software\VantaRewriteTest\Policies\Microsoft\Windows\Windows Search\DefaultExcludedPaths'
        )
        foreach ($root in $legacyRoots) {
            New-Item -Path "$root\Stale" -Force | Out-Null
            Set-ItemProperty -LiteralPath $root -Name 'C:\Stale' -Value 'C:\Stale' -Type String
        }

        Set-VantaIndexConfiguration -Operation CleanPolicies

        foreach ($root in @(
                'HKCU:\Software\VantaRewriteTest\Search\Paths'
                'HKCU:\Software\VantaRewriteTest\Search\Exclusions'
                $legacyRoots
            )) {
            Test-Path -LiteralPath $root | Should -BeTrue
            @(Get-ChildItem -LiteralPath $root).Count | Should -Be 0
            @((Get-Item -LiteralPath $root).GetValueNames()).Count | Should -Be 0
        }
        foreach ($root in @($internalRoot, $cacheRoot)) {
            Test-Path -LiteralPath "$root\Stale" | Should -BeTrue
            (Get-Item -LiteralPath $root).GetValue('Included') | Should -Be 1
        }
    }

    It 'commits the complete staged preset and propagates effective-scope verification failure' {
        Set-VantaIndexConfiguration -Operation Include -IndexPath 'C:\Windows\VantaDesktop'
        Set-VantaIndexConfiguration -Operation Exclude -IndexPath 'C:\Users'
        Mock Invoke-VantaSearchScopeNative -ModuleName Vanta.Search { throw 'effective scope differs' }
        { InModuleScope Vanta.Search { Complete-VantaIndexScope } } | Should -Throw '*effective scope differs*'
        Should -Invoke Invoke-VantaSearchScopeNative -ModuleName Vanta.Search -Times 1 -Exactly -ParameterFilter {
            $Includes.Count -eq 1 -and $Includes[0] -ceq 'file:///C:\Windows\VantaDesktop\' -and
            $Excludes.Count -eq 1 -and $Excludes[0] -ceq 'file:///C:\Users\*'
        }
    }

    It 'does not reset the current scope when there is no staged preset' {
        Mock Invoke-VantaSearchScopeNative -ModuleName Vanta.Search { throw 'must not reset' }
        InModuleScope Vanta.Search { Complete-VantaIndexScope }
        Should -Invoke Invoke-VantaSearchScopeNative -ModuleName Vanta.Search -Times 0
    }

    It 'rejects corrupt staged rules before native scope changes' {
        $root = 'HKCU:\Software\VantaRewriteTest\Search\Paths'
        New-Item -Path $root -Force | Out-Null
        Set-ItemProperty -LiteralPath $root -Name bad -Value 'relative-path' -Type String
        Mock Invoke-VantaSearchScopeNative -ModuleName Vanta.Search { throw 'must not apply' }
        { InModuleScope Vanta.Search { Complete-VantaIndexScope } } | Should -Throw '*Invalid staged*'
        Should -Invoke Invoke-VantaSearchScopeNative -ModuleName Vanta.Search -Times 0
    }
}

Describe 'Set-VantaIndexConfiguration' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Search
        Mock Test-VantaAdmin -ModuleName Vanta.Search { $true }
        $global:VantaSearchTestCalls = New-Object 'System.Collections.Generic.List[string]'
        Mock Get-VantaIndexNativePaths -ModuleName Vanta.Search {
            [pscustomobject]@{ Sc = 'C:\Windows\System32\sc.exe' }
        }
    }

    It 'configures and moves WSearch to the requested runtime state' {
        $service = [pscustomobject]@{
            Status = [ServiceProcess.ServiceControllerStatus]::Stopped
        }
        $service | Add-Member -MemberType ScriptMethod -Name Refresh -Value {}
        $service | Add-Member -MemberType ScriptMethod -Name Start -Value {
            [void]$global:VantaSearchTestCalls.Add('Start')
            $this.Status = [ServiceProcess.ServiceControllerStatus]::Running
        }
        $service | Add-Member -MemberType ScriptMethod -Name Stop -Value {
            [void]$global:VantaSearchTestCalls.Add('Stop')
            $this.Status = [ServiceProcess.ServiceControllerStatus]::Stopped
        }
        $service | Add-Member -MemberType ScriptMethod -Name Continue -Value {
            [void]$global:VantaSearchTestCalls.Add('Continue')
            $this.Status = [ServiceProcess.ServiceControllerStatus]::Running
        }
        $service | Add-Member -MemberType ScriptMethod -Name WaitForStatus -Value {
            param($RequestedStatus, $Timeout)
            [void]$Timeout
            [void]$global:VantaSearchTestCalls.Add("Wait:$RequestedStatus")
            $this.Status = $RequestedStatus
        }
        $service | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
            [void]$global:VantaSearchTestCalls.Add('Dispose')
        }
        $global:VantaSearchTestService = $service
        Mock Invoke-VantaHiddenProcess -ModuleName Vanta.Search {
            [void]$global:VantaSearchTestCalls.Add("native:$($ArgumentList -join ',')")
        }
        Mock Get-Service -ModuleName Vanta.Search { $global:VantaSearchTestService }

        InModuleScope Vanta.Search { Set-VantaSearchServiceState -State Running }
        $global:VantaSearchTestService.Status = [ServiceProcess.ServiceControllerStatus]::Running
        InModuleScope Vanta.Search { Set-VantaSearchServiceState -State Stopped }

        @($global:VantaSearchTestCalls) | Should -Be @(
            'native:config,WSearch,start=,delayed-auto'
            'Start'
            'Wait:Running'
            'Dispose'
            'native:config,WSearch,start=,disabled'
            'Stop'
            'Wait:Stopped'
            'Dispose'
        )
        Should -Invoke Invoke-VantaHiddenProcess -ModuleName Vanta.Search -Times 2 -Exactly `
            -ParameterFilter { $Wait -and $FilePath -eq 'C:\Windows\System32\sc.exe' }
    }

    It 'starts WSearch, commits and verifies the scope, then reveals settings' {
        Mock Set-VantaSearchServiceState -ModuleName Vanta.Search {
            [void]$global:VantaSearchTestCalls.Add("service:$State")
        }
        Mock Set-VantaIndexSettingsVisibility -ModuleName Vanta.Search {
            [void]$global:VantaSearchTestCalls.Add("hidden:$Hidden")
        }
        Mock Complete-VantaIndexScope -ModuleName Vanta.Search {
            [void]$global:VantaSearchTestCalls.Add('scope:verified')
        }
        # Start runs no native command of its own; any that appeared would break the
        # exact sequence below.
        Mock Invoke-VantaHiddenProcess -ModuleName Vanta.Search {
            [void]$global:VantaSearchTestCalls.Add("native:$([IO.Path]::GetFileName($FilePath))")
        }

        Set-VantaIndexConfiguration -Operation Start

        @($global:VantaSearchTestCalls) | Should -Be @(
            'service:Running'
            'scope:verified'
            'hidden:False'
        )
    }

    It 'hides settings before stopping WSearch' {
        Mock Set-VantaIndexSettingsVisibility -ModuleName Vanta.Search {
            [void]$global:VantaSearchTestCalls.Add("hidden:$Hidden")
        }
        Mock Set-VantaSearchServiceState -ModuleName Vanta.Search {
            [void]$global:VantaSearchTestCalls.Add("service:$State")
        }

        Set-VantaIndexConfiguration -Operation Stop

        @($global:VantaSearchTestCalls) | Should -Be @(
            'hidden:True'
            'service:Stopped'
        )
    }

    It 'writes the two supported DWORD settings with their product values' {
        Mock Set-VantaIndexDword -ModuleName Vanta.Search {}

        Set-VantaIndexConfiguration -Operation SetRespectPowerModes -SettingValue 1
        Set-VantaIndexConfiguration -Operation ResetSetupCompleted

        Should -Invoke Set-VantaIndexDword -ModuleName Vanta.Search -Times 1 -Exactly -ParameterFilter {
            $KeyPath -eq 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Search\Gather\Windows\SystemIndex' -and
            $Name -eq 'RespectPowerModes' -and $Value -eq 1
        }
        Should -Invoke Set-VantaIndexDword -ModuleName Vanta.Search -Times 1 -Exactly -ParameterFilter {
            $KeyPath -eq 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Search' -and
            $Name -eq 'SetupCompletedSuccessfully' -and $Value -eq 0
        }
    }

    It 'rejects operation-specific arguments before checking administrator rights' {
        Mock Test-VantaAdmin -ModuleName Vanta.Search { throw 'administrator check should not run' }

        { Set-VantaIndexConfiguration -Operation Include } |
            Should -Throw '*requires a fully qualified index path*'
        { Set-VantaIndexConfiguration -Operation Stop -IndexPath 'C:\Unexpected' } |
            Should -Throw '*does not accept an index path*'
        { Set-VantaIndexConfiguration -Operation SetRespectPowerModes } |
            Should -Throw '*requires an explicit setting value*'
        { Set-VantaIndexConfiguration -Operation Start -SettingValue 1 } |
            Should -Throw '*does not accept a setting value*'

        Should -Invoke Test-VantaAdmin -ModuleName Vanta.Search -Times 0 -Exactly
    }

    It 'requires administrator rights before mutating anything' {
        Mock Test-VantaAdmin -ModuleName Vanta.Search { $false }
        Mock Set-VantaIndexDword -ModuleName Vanta.Search { throw 'must not write' }

        { Set-VantaIndexConfiguration -Operation ResetSetupCompleted } |
            Should -Throw '*Administrator privileges are required*'
        Should -Invoke Set-VantaIndexDword -ModuleName Vanta.Search -Times 0
    }
}

Describe 'Set-VantaIndexingMachineState' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Search
        $global:VantaSearchTestCalls = New-Object 'System.Collections.Generic.List[object]'
        Mock Set-VantaIndexConfiguration -ModuleName Vanta.Search {
            $global:VantaSearchTestCalls.Add([pscustomobject]@{
                    Operation         = $Operation
                    IndexPath         = $IndexPath
                    SettingValue      = $SettingValue
                    SettingValueBound = $PesterBoundParameters.ContainsKey('SettingValue')
                })
        }
    }

    It 'stops indexing only for the Disable state' {
        Set-VantaIndexingMachineState -State Disable

        @($global:VantaSearchTestCalls.Operation) | Should -Be @('Stop')
    }

    It 'rejects RespectPowerModes outside the Full state' {
        { Set-VantaIndexingMachineState -State Minimal -RespectPowerModes 1 } |
            Should -Throw '*does not accept RespectPowerModes*'
        $global:VantaSearchTestCalls.Count | Should -Be 0
    }

    It 'preserves an independent power-mode preference when replaying full indexing' {
        Mock Get-ChildItem -ModuleName Vanta.Search { @() }
        Set-VantaIndexingMachineState -State Full -PreservePowerModes
        @($global:VantaSearchTestCalls.Operation) | Should -Contain 'Start'
        @($global:VantaSearchTestCalls.Operation) | Should -Not -Contain 'SetRespectPowerModes'
    }

    It 'rejects contradictory power-mode requests before touching indexing' {
        { Set-VantaIndexingMachineState -State Full -RespectPowerModes 0 -PreservePowerModes } | Should -Throw '*PreservePowerModes requires*'
        $global:VantaSearchTestCalls.Count | Should -Be 0
    }

    It 'emits the minimal-indexing plan with forced power-mode respect' {
        Set-VantaIndexingMachineState -State Minimal
        $operations = $global:VantaSearchTestCalls.ToArray()
        $windows = [IO.Path]::GetFullPath([Environment]::GetFolderPath('Windows'))

        @($operations.Operation) | Should -Be @(
            'Stop',
            'CleanPolicies',
            'Include',
            'Include',
            'Exclude',
            'Start',
            'SetRespectPowerModes'
        )
        $operations[2].IndexPath | Should -BeExactly ([IO.Path]::Combine(
                [IO.Path]::GetFullPath([Environment]::GetFolderPath('CommonApplicationData')),
                'Microsoft', 'Windows', 'Start Menu', 'Programs'))
        $operations[3].IndexPath | Should -BeExactly ([IO.Path]::Combine($windows, 'VantaDesktop'))
        $operations[4].IndexPath | Should -BeExactly ([IO.Path]::Combine([IO.Path]::GetPathRoot($windows), 'Users'))
        $operations[-1].SettingValueBound | Should -BeTrue
        $operations[-1].SettingValue | Should -Be 1
    }

    It 'emits the full-indexing plan, excludes each profile AppData and passes the requested power mode' {
        $usersRoot = Join-Path $TestDrive 'Users'
        New-Item -Path (Join-Path $usersRoot 'alice\AppData') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $usersRoot 'bob\MicrosoftEdgeBackups') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $usersRoot 'carol') -ItemType Directory -Force | Out-Null
        $global:VantaSearchTestUsersRoot = $usersRoot
        Mock Get-ChildItem -ModuleName Vanta.Search -ParameterFilter { $Directory -and $LiteralPath -like '*\Users' } {
            [IO.DirectoryInfo[]]@(
                [IO.DirectoryInfo]::new((Join-Path $global:VantaSearchTestUsersRoot 'alice'))
                [IO.DirectoryInfo]::new((Join-Path $global:VantaSearchTestUsersRoot 'bob'))
                [IO.DirectoryInfo]::new((Join-Path $global:VantaSearchTestUsersRoot 'carol'))
            )
        }

        Set-VantaIndexingMachineState -State Full -RespectPowerModes 0
        $operations = $global:VantaSearchTestCalls.ToArray()

        @($operations.Operation) | Should -Be @(
            'Stop',
            'CleanPolicies',
            'Include',
            'Include',
            'Include',
            'Exclude',
            'Exclude',
            'Start',
            'SetRespectPowerModes'
        )
        $operations[5].IndexPath | Should -BeExactly (Join-Path $usersRoot 'alice\AppData')
        $operations[6].IndexPath | Should -BeExactly (Join-Path $usersRoot 'bob\MicrosoftEdgeBackups')
        $operations[-1].SettingValueBound | Should -BeTrue
        $operations[-1].SettingValue | Should -Be 0
    }

    It 'stops at the first failed index operation' {
        Mock Set-VantaIndexConfiguration -ModuleName Vanta.Search {
            $global:VantaSearchTestCalls.Add([pscustomobject]@{ Operation = $Operation })
            if ($Operation -eq 'CleanPolicies') {
                throw 'policy reset failed'
            }
        }

        { Set-VantaIndexingMachineState -State Minimal } | Should -Throw '*policy reset failed*'
        @($global:VantaSearchTestCalls.Operation) | Should -Be @('Stop', 'CleanPolicies')
    }
}

Describe 'Disable-VantaStoreSearchRecommendations' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Search
        Mock Invoke-VantaHiddenProcess -ModuleName Vanta.Search {}
    }

    It 'creates the Store search database and denies Everyone access through icacls' {
        $localAppData = Join-Path $TestDrive 'Local'
        $expectedDb = Join-Path $localAppData 'Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalState\store.db'

        Disable-VantaStoreSearchRecommendations -LocalAppDataPath $localAppData

        Test-Path -LiteralPath $expectedDb -PathType Leaf | Should -BeTrue
        Should -Invoke Invoke-VantaHiddenProcess -ModuleName Vanta.Search -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq (Join-Path ([Environment]::SystemDirectory) 'icacls.exe') -and
            $Wait -and
            @($ArgumentList).Count -eq 3 -and
            $ArgumentList[0] -eq $expectedDb -and
            $ArgumentList[1] -eq '/deny' -and
            $ArgumentList[2] -eq '*S-1-1-0:F'
        }
    }

    It 'keeps an existing database file and still applies the deny rule' {
        $localAppData = Join-Path $TestDrive 'Local'
        $expectedDb = Join-Path $localAppData 'Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalState\store.db'
        New-Item -Path (Split-Path $expectedDb -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath $expectedDb -Value 'existing' -Encoding ASCII

        Disable-VantaStoreSearchRecommendations -LocalAppDataPath $localAppData

        (Get-Content -LiteralPath $expectedDb -Raw).Trim() | Should -BeExactly 'existing'
        Should -Invoke Invoke-VantaHiddenProcess -ModuleName Vanta.Search -Times 1 -Exactly
    }

    It 'fails without a local application-data directory' {
        { Disable-VantaStoreSearchRecommendations -LocalAppDataPath '' } |
            Should -Throw '*LocalApplicationData is not available*'
        Should -Invoke Invoke-VantaHiddenProcess -ModuleName Vanta.Search -Times 0
    }
}

Describe 'Index configuration process contracts' {
    It 'returns a checked standalone failure from the compatibility entry script' {
        $hostPath = Join-Path $PSHOME 'powershell.exe'
        $savedErrorPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $output = & $hostPath -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass `
                -File $script:entryPath -Operation SetRespectPowerModes 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $savedErrorPreference
        }

        $exitCode | Should -Be 1
        ($output | Out-String) | Should -Match 'requires an explicit setting value'
    }

    It 'hands <Argument> from the compatibility launcher as one path the engine accepts' -ForEach @(
        @{ Argument = 'D:\Data\'; Expected = 'D:\Data' }
        @{ Argument = 'D:\'; Expected = 'D:\' }
        @{ Argument = 'D:\Data'; Expected = 'D:\Data' }
        @{ Argument = '\\server\share\'; Expected = '\\server\share' }
    ) {
        # The launcher runs only from the installed Windows directory, so run its
        # path-forwarding lines against a probe that reports what -File bound.
        $lines = @([IO.File]::ReadAllLines($script:launcherPath))
        $start = [Array]::IndexOf($lines, ':invokeWithPath')
        $start | Should -BeGreaterThan -1
        $end = $start + 1
        while ($end -lt $lines.Count -and $lines[$end] -notmatch ' -IndexPath ') {
            $end++
        }
        $end | Should -BeLessThan $lines.Count

        $probe = Join-Path $TestDrive 'Show-IndexPath.ps1'
        Set-Content -LiteralPath $probe -Encoding Ascii -Value @'
param([string]$Operation, [string]$IndexPath)
[Console]::Out.WriteLine($IndexPath)
'@
        $harness = Join-Path $TestDrive 'invoke-with-path.cmd'
        $harnessLines = @(
            '@echo off'
            'setlocal EnableExtensions DisableDelayedExpansion'
            'set "operation=Include"'
            'set "indexPath=%~1"'
            "set `"script=$probe`""
            'set "VantaNativePowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"'
        ) + $lines[($start + 1)..$end]
        [IO.File]::WriteAllLines($harness, [string[]]$harnessLines, [Text.Encoding]::ASCII)

        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = Join-Path ([Environment]::SystemDirectory) 'cmd.exe'
        $startInfo.Arguments = "/d /c call `"$harness`" `"$Argument`""
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $process = [Diagnostics.Process]::Start($startInfo)
        try {
            $bound = $process.StandardOutput.ReadToEnd().Trim()
            $process.WaitForExit()
        }
        finally {
            $process.Dispose()
        }

        InModuleScope Vanta.Search -Parameters @{ Bound = $bound } {
            param($Bound)
            ConvertTo-VantaIndexPath -Candidate $Bound
        } | Should -BeExactly $Expected
    }

    It 'rejects unsupported compatibility-launcher arguments with code 2' {
        $cmdPath = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
        & $cmdPath /d /c "call `"$script:launcherPath`" /unsupported" *> $null
        $LASTEXITCODE | Should -Be 2

        & $cmdPath /d /c "call `"$script:launcherPath`" /include" *> $null
        $LASTEXITCODE | Should -Be 2
    }
}
