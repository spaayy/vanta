BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $modulesRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\package\Executables\VantaModules\Scripts\Modules'
    function New-VantaTestNanaZipBundle {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [string]$Name = '40174MouriNaruto.NanaZip',
            [string]$Publisher = 'CN=E310A153-74A9-4D81-800B-857A8D58408A',
            [string]$Version = '6.5.1767.0'
        )

        Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
        $file = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
        $archive = New-Object IO.Compression.ZipArchive(
            $file,
            [IO.Compression.ZipArchiveMode]::Create,
            $false
        )
        try {
            $entry = $archive.CreateEntry('AppxMetadata/AppxBundleManifest.xml')
            $entryStream = $entry.Open()
            $writer = New-Object IO.StreamWriter(
                $entryStream,
                (New-Object Text.UTF8Encoding($false))
            )
            try {
                $writer.Write(
                    '<?xml version="1.0" encoding="utf-8"?>' +
                    '<Bundle xmlns="http://schemas.microsoft.com/appx/2013/bundle">' +
                    '<Identity Name="' + $Name + '" Publisher="' + $Publisher +
                    '" Version="' + $Version + '" />' +
                    '</Bundle>'
                )
            }
            finally {
                $writer.Dispose()
                $entryStream.Dispose()
            }
        }
        finally {
            $archive.Dispose()
            $file.Dispose()
        }
    }

    Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Software\Vanta.Software.psd1') -Force
}

Describe 'Official archive-app mirrors' {
    It 'downloads each pinned NanaZip asset from its SourceForge mirror when GitHub fails' {
        $temp = Join-Path -Path $TestDrive -ChildPath 'nanazip-pinned-mirror'
        New-Item -Path $temp -ItemType Directory | Out-Null
        InModuleScope Vanta.Software -Parameters @{ Temp = $temp } {
            param($Temp)
            $assets = @(Get-VantaPinnedNanaZipReleaseAssets)
            $assets.Count | Should -Be 2
            $tag = [string]$assets[0].Tag
            foreach ($asset in $assets) {
                $asset.Sha256 | Should -Match '^[0-9a-f]{64}$'
                $asset.Size | Should -BeGreaterThan 0
            }
            $commands = [pscustomobject]@{
                GetProvisionedPackage = {
                    [pscustomobject]@{ DisplayName = '40174MouriNaruto.NanaZip'; Version = $tag }
                }.GetNewClosure()
                AddProvisionedPackage = { }
            }
            # Keeps the test off the network if a GitHub API lookup is reintroduced.
            Mock Invoke-VantaGitHubApiJson { throw 'GitHub is unavailable' }
            Mock Resolve-VantaProtectedExecutionPath { $Path }
            Mock Assert-VantaNanaZipBundleIdentity
            Mock Write-VantaLog
            Mock Invoke-VantaPinnedDownload {
                if ($Uri.Host -eq 'github.com') { throw 'HTTP 403' }
                $Destination
            }

            Install-VantaNanaZip -TempDir $Temp -Assets $assets -DismCommands $commands | Should -BeTrue

            Should -Invoke Invoke-VantaPinnedDownload -Times 4 -Exactly
            foreach ($asset in $assets) {
                foreach ($expectedUri in @(
                        "https://github.com/M2Team/NanaZip/releases/download/$tag/$($asset.Name)"
                        "https://downloads.sourceforge.net/project/nanazip/$tag/$($asset.Name)"
                    )) {
                    Should -Invoke Invoke-VantaPinnedDownload -Times 1 -Exactly -ParameterFilter {
                        $Uri.AbsoluteUri -ceq $expectedUri -and
                        $Sha256 -ceq $asset.Sha256 -and
                        $ExpectedBytes -eq $asset.Size
                    }
                }
            }
        }
    }
}

Describe 'Archive download failover' {
    It 'uses only GitHub when the first verified download succeeds' {
        InModuleScope Vanta.Software -Parameters @{ Destination = (Join-Path $TestDrive 'success.exe') } {
            Mock Write-VantaLog {}
            Mock Invoke-VantaPinnedDownload { $Destination }
            Invoke-VantaArchiveDownload -Uris @('https://github.com/a', 'https://downloads.sourceforge.net/a') -Destination $Destination -Sha256 ('a' * 64) -ExpectedBytes 42 | Should -Be $Destination
            Should -Invoke Invoke-VantaPinnedDownload -Times 1 -Exactly -ParameterFilter { $Uri.Host -eq 'github.com' }
        }
    }

    It 'tries the mirror with identical verification after GitHub fails' {
        InModuleScope Vanta.Software -Parameters @{ Destination = (Join-Path $TestDrive 'fallback.exe') } {
            Mock Write-VantaLog {}
            Mock Invoke-VantaPinnedDownload {
                if ($Uri.Host -eq 'github.com') { throw 'HTTP 403' }
                $Destination
            }
            Invoke-VantaArchiveDownload -Uris @('https://github.com/a', 'https://downloads.sourceforge.net/a') -Destination $Destination -Sha256 ('a' * 64) -ExpectedBytes 42 | Should -Be $Destination
            Should -Invoke Invoke-VantaPinnedDownload -Times 2 -Exactly -ParameterFilter { $Sha256 -eq ('a' * 64) -and $ExpectedBytes -eq 42 -and $MaximumSeconds -eq 60 }
            Should -Invoke Invoke-VantaPinnedDownload -Times 1 -Exactly -ParameterFilter { $Uri.Host -eq 'downloads.sourceforge.net' }
        }
    }

    It 'reports both sources when neither passes verification' {
        InModuleScope Vanta.Software -Parameters @{ Destination = (Join-Path $TestDrive 'failure.exe') } {
            Mock Write-VantaLog {}
            Mock Invoke-VantaPinnedDownload { throw 'SHA-256 mismatch' }
            { Invoke-VantaArchiveDownload -Uris @('https://github.com/a', 'https://downloads.sourceforge.net/a') -Destination $Destination -Sha256 ('a' * 64) -ExpectedBytes 42 } | Should -Throw '*github.com*sourceforge.net*'
        }
    }

    It 'gives each source a limit that grows with the asset size' {
        InModuleScope Vanta.Software -Parameters @{ Destination = (Join-Path $TestDrive 'bundle.msixbundle') } {
            Mock Write-VantaLog {}
            Mock Invoke-VantaPinnedDownload { $Destination }
            Invoke-VantaArchiveDownload -Uris @('https://github.com/a') -Destination $Destination -Sha256 ('a' * 64) -ExpectedBytes 11931446 | Should -Be $Destination
            Should -Invoke Invoke-VantaPinnedDownload -Times 1 -Exactly -ParameterFilter { $MaximumSeconds -eq 365 }
        }
    }

    It 'names the time limit when a source is too slow' {
        InModuleScope Vanta.Software -Parameters @{ Destination = (Join-Path $TestDrive 'slow.msixbundle') } {
            Mock Write-VantaLog {}
            Mock Invoke-VantaPinnedDownload {
                # The shape the shared HTTP reader throws when its deadline cancels a read.
                $deadline = New-Object Threading.CancellationTokenSource
                $deadline.Cancel()
                [Threading.Tasks.Task]::Delay(1000, $deadline.Token).GetAwaiter().GetResult()
            }
            { Invoke-VantaArchiveDownload -Uris @('https://github.com/a', 'https://downloads.sourceforge.net/a') -Destination $Destination -Sha256 ('a' * 64) -ExpectedBytes 11931446 } |
                Should -Throw "*github.com/a : the download didn't finish within its 365-second limit.*sourceforge.net/a : the download didn't finish*"
        }
    }
}

Describe 'Visual C++ v14 prerequisite detection' {
    BeforeEach {
        InModuleScope Vanta.Software {
            Mock Write-VantaLog {}
            Mock Get-Item { [pscustomobject]@{ VersionInfo = [pscustomobject]@{ ProductVersion = '14.44.35211.0' } } }
            Mock Get-ItemProperty { throw 'No runtime registration' }
        }
    }

    It 'accepts an installed equal or newer <Architecture> runtime <Version>' -TestCases @(
        @{ Architecture = 'x64'; Version = 'v14.51.36247.0' }
        @{ Architecture = 'x86'; Version = 'v14.51.36231.0' }
        @{ Architecture = 'x64'; Version = 'v14.44.35211.0' }
    ) {
        param($Architecture, $Version)
        InModuleScope Vanta.Software -Parameters @{ Architecture = $Architecture; Version = $Version } {
            Mock Get-ItemProperty { [pscustomobject]@{ Installed = 1; Version = $Version } } -ParameterFilter {
                $LiteralPath -eq "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\$Architecture"
            }
            Test-VantaVisualCppRuntimeCurrent -Architecture $Architecture -InstallerPath 'fixture.exe' | Should -BeTrue
        }
    }

    It 'does not skip for an older, malformed, unrelated, or uninstalled runtime (<Version>, <Installed>)' -TestCases @(
        @{ Version = 'v14.43.34808.0'; Installed = 1 }
        @{ Version = 'invalid'; Installed = 1 }
        @{ Version = 'v15.0.0.0'; Installed = 1 }
        @{ Version = 'v14.51.36247.0'; Installed = 0 }
    ) {
        param($Version, $Installed)
        InModuleScope Vanta.Software -Parameters @{ Version = $Version; Installed = $Installed } {
            Mock Get-ItemProperty { [pscustomobject]@{ Installed = $Installed; Version = $Version } }
            Test-VantaVisualCppRuntimeCurrent -Architecture x64 -InstallerPath 'fixture.exe' | Should -BeFalse
        }
    }

    It 'does not use x64 registration to satisfy x86' {
        InModuleScope Vanta.Software {
            Mock Get-ItemProperty { [pscustomobject]@{ Installed = 1; Version = 'v14.51.36247.0' } } -ParameterFilter { $LiteralPath -like '*\x64' }
            Test-VantaVisualCppRuntimeCurrent -Architecture x86 -InstallerPath 'fixture.exe' | Should -BeFalse
        }
    }

    It 'falls back to installation when registration is missing or unreadable' {
        InModuleScope Vanta.Software {
            Test-VantaVisualCppRuntimeCurrent -Architecture x64 -InstallerPath 'fixture.exe' | Should -BeFalse
        }
    }

    It 'falls back to installation when package metadata cannot be parsed' {
        InModuleScope Vanta.Software {
            Mock Get-Item { [pscustomobject]@{ VersionInfo = [pscustomobject]@{ ProductVersion = '' } } }
            Test-VantaVisualCppRuntimeCurrent -Architecture x64 -InstallerPath 'fixture.exe' | Should -BeFalse
        }
    }
}

Describe 'Select-VantaCbsPackage' {
    It 'matches CABs by pattern and architecture' {
        InModuleScope Vanta.Software {
            $candidates = @(
                'C:\Packages\Z-Vanta-NoTelemetry-Package-arm64-1.cab'
                'C:\Packages\Z-Vanta-NoTelemetry-Package-amd64-1.cab'
                'C:\Packages\Z-Vanta-NoDefender-Package-arm64-1.cab'
                'C:\Packages\Z-Vanta-NoDefender-Package-amd64-1.cab'
            )
            $patterns = @('*Z-Vanta-NoDefender-Package*', '*Z-Vanta-NoTelemetry-Package*')

            $result = Select-VantaCbsPackage -Candidates $candidates -Patterns $patterns -Architecture 'amd64' -SingleUsePatterns

            $result.Matched | Should -Be @(
                'C:\Packages\Z-Vanta-NoTelemetry-Package-amd64-1.cab'
                'C:\Packages\Z-Vanta-NoDefender-Package-amd64-1.cab'
            )
            @($result.UnmatchedPatterns).Count | Should -Be 0
        }
    }

    It 'reports patterns that matched nothing for <Architecture>' -TestCases @(
        @{ Architecture = 'arm64'; Matched = @('C:\Packages\Z-Vanta-NoDefender-Package-arm64-1.cab'); Unmatched = @('*Z-Vanta-NoTelemetry-Package*') }
        @{ Architecture = 'amd64'; Matched = @(); Unmatched = @('*Z-Vanta-NoDefender-Package*', '*Z-Vanta-NoTelemetry-Package*') }
    ) {
        $result = InModuleScope Vanta.Software -Parameters @{ Architecture = $Architecture } {
            Select-VantaCbsPackage -Candidates @('C:\Packages\Z-Vanta-NoDefender-Package-arm64-1.cab') `
                -Patterns @('*Z-Vanta-NoDefender-Package*', '*Z-Vanta-NoTelemetry-Package*') `
                -Architecture $Architecture -SingleUsePatterns
        }

        @($result.Matched) -join ',' | Should -BeExactly ($Matched -join ',')
        @($result.UnmatchedPatterns) -join ',' | Should -BeExactly ($Unmatched -join ',')
    }

    It 'consumes each pattern on its first match with -SingleUsePatterns (CAB install semantics)' {
        InModuleScope Vanta.Software {
            $candidates = @(
                'C:\Packages\Z-Vanta-NoDefender-Package-amd64-2.cab'
                'C:\Packages\Z-Vanta-NoDefender-Package-amd64-1.cab'
            )

            $result = Select-VantaCbsPackage -Candidates $candidates -Patterns @('*Z-Vanta-NoDefender-Package*') -Architecture 'amd64' -SingleUsePatterns

            $result.Matched | Should -Be @('C:\Packages\Z-Vanta-NoDefender-Package-amd64-2.cab')
        }
    }

    It 'lets one pattern match multiple candidates without -SingleUsePatterns (uninstall semantics)' {
        InModuleScope Vanta.Software {
            $candidates = @(
                'Z-Vanta-NoDefender-Package~amd64~~1.0.0.0'
                'Z-Vanta-NoDefender-Package~amd64~~2.0.0.0'
            )

            $result = Select-VantaCbsPackage -Candidates $candidates -Patterns @('*Z-Vanta-NoDefender-Package*') -Architecture 'amd64'

            @($result.Matched).Count | Should -Be 2
            @($result.UnmatchedPatterns).Count | Should -Be 0
        }
    }
}

Describe 'Get-VantaSoftwareComponentMap' {
    It 'maps every Install-VantaSoftware component to an existing installer function' {
        InModuleScope Vanta.Software {
            $map = Get-VantaSoftwareComponentMap
            $components = (Get-Command -Name Install-VantaSoftware).Parameters['Component'].Attributes |
                Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] } |
                ForEach-Object { $_.ValidValues }

            @($map.Keys | Sort-Object) | Should -Be @($components | Sort-Object)
            foreach ($function in $map.Values) {
                Get-Command -Name $function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            }
        }
    }
}

Describe 'Install-VantaEclean' {
    It 'does not start the installer when publisher verification fails' {
        InModuleScope Vanta.Software {
            Mock Invoke-VantaSoftwareDownload
            Mock Assert-VantaFileSignature { throw 'publisher verification failed' }
            Mock Start-VantaSoftwareInstaller

            { Install-VantaEclean -TempDir $TestDrive } | Should -Throw '*publisher verification failed*'
            Should -Invoke Start-VantaSoftwareInstaller -Times 0
        }
    }

    It 'verifies the eclean publisher and installs silently' {
        InModuleScope Vanta.Software {
            Mock Invoke-VantaSoftwareDownload
            Mock Assert-VantaFileSignature
            Mock Start-VantaSoftwareInstaller

            Install-VantaEclean -TempDir $TestDrive

            Should -Invoke Assert-VantaFileSignature -Times 1 -Exactly -ParameterFilter {
                $ExpectedSubjectCn -ceq 'eclean Labs AB'
            }
            Should -Invoke Start-VantaSoftwareInstaller -Times 1 -Exactly -ParameterFilter {
                $ArgumentList.Count -eq 1 -and $ArgumentList[0] -ceq '/S'
            }
        }
    }
}

Describe 'Test-VantaSoftwareArm64' {
    It 'recognizes exactly one native <SystemType> computer-system result' -TestCases @(
        @{ SystemType = 'ARM64-based PC'; Expected = $true }
        @{ SystemType = 'x64-based PC'; Expected = $false }
    ) {
        InModuleScope Vanta.Software -Parameters @{ SystemType = $SystemType; Expected = $Expected } {
            Mock Get-CimInstance {
                [pscustomobject]@{ SystemType = $SystemType }
            }

            Test-VantaSoftwareArm64 | Should -Be $Expected
            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $ClassName -ceq 'Win32_ComputerSystem' -and $ErrorAction -eq 'Stop'
            }
        }
    }

    It 'fails closed for an unknown or empty native architecture value' {
        InModuleScope Vanta.Software {
            Mock Get-CimInstance {
                [pscustomobject]@{ SystemType = 'Unknown' }
            }
            { Test-VantaSoftwareArm64 } | Should -Throw -ExpectedMessage '*Unsupported or unreadable*'

            Mock Get-CimInstance {
                [pscustomobject]@{ SystemType = $null }
            }
            { Test-VantaSoftwareArm64 } | Should -Throw -ExpectedMessage '*Unsupported or unreadable*'
        }
    }
}

Describe 'Get-VantaCbsArchitecture' {
    It 'uses the exact module architecture authority for <Expected> CBS packages' -TestCases @(
        @{ IsArm64 = $true; Expected = 'arm64' }
        @{ IsArm64 = $false; Expected = 'amd64' }
    ) {
        InModuleScope Vanta.Software -Parameters @{ IsArm64 = $IsArm64; Expected = $Expected } {
            Mock Test-VantaSoftwareArm64 { $IsArm64 }

            Get-VantaCbsArchitecture | Should -BeExactly $Expected
            Should -Invoke Test-VantaSoftwareArm64 -Times 1 -Exactly
        }
    }
}

Describe 'Install-VantaSoftware' {
    It 'returns false when protected staging cleanup fails instead of reporting success' {
        InModuleScope Vanta.Software -Parameters @{ Root = $TestDrive } {
            $stage = Join-Path -Path $Root -ChildPath 'cleanup-failure'
            New-Item -Path $stage -ItemType Directory | Out-Null
            Mock Assert-VantaPrivilege
            Mock New-VantaProtectedStagingDirectory { $stage }
            Mock Resolve-VantaProtectedExecutionPath { $Path }
            Mock Install-VantaBraveBrowser
            Mock Remove-Item -ParameterFilter { $LiteralPath -eq $stage } -MockWith {
                throw 'simulated cleanup failure'
            }
            Mock Write-VantaLog

            Install-VantaSoftware -Component Brave | Should -BeFalse
            Test-Path -LiteralPath $stage | Should -BeTrue
            Should -Invoke Write-VantaLog -Times 1 -ParameterFilter {
                $Level -eq 'Warning' -and $Message -like '*staging cleanup failed*'
            }
        }
    }

    It 'retains staging when installer process-tree containment is unconfirmed' {
        InModuleScope Vanta.Software -Parameters @{ Root = $TestDrive } {
            $stage = Join-Path -Path $Root -ChildPath 'unconfirmed-containment'
            New-Item -Path $stage -ItemType Directory | Out-Null
            Mock Assert-VantaPrivilege
            Mock New-VantaProtectedStagingDirectory { $stage }
            Mock Install-VantaBraveBrowser { throw 'simulated containment failure' }
            Mock Test-VantaContainedProcessContainmentUnconfirmed { $true }
            Mock Remove-Item
            Mock Write-VantaLog

            Install-VantaSoftware -Component Brave | Should -BeFalse
            Test-Path -LiteralPath $stage | Should -BeTrue
            Should -Invoke Remove-Item -Times 0 -ParameterFilter { $LiteralPath -eq $stage }
            Should -Invoke Write-VantaLog -Times 1 -ParameterFilter {
                $Level -eq 'Warning' -and $Message -like '*staging was retained*'
            }
        }
    }

    It 'returns exactly one Boolean even when a component writes pipeline output' {
        InModuleScope Vanta.Software -Parameters @{ Root = $TestDrive } {
            $stage = Join-Path -Path $Root -ChildPath 'single-boolean-outcome'
            New-Item -Path $stage -ItemType Directory | Out-Null
            Mock Assert-VantaPrivilege
            Mock New-VantaProtectedStagingDirectory { $stage }
            Mock Resolve-VantaProtectedExecutionPath { $Path }
            Mock Install-VantaBraveBrowser { 'component diagnostic output' }
            Mock Write-VantaLog

            $result = @(Install-VantaSoftware -Component Brave)

            $result.Count | Should -Be 1
            $result[0].GetType().FullName | Should -BeExactly 'System.Boolean'
            $result[0] | Should -BeTrue
        }
    }
}

Describe 'Assert-VantaFileHash' {
    It 'passes when the file hash matches the expected SHA256' {
        $file = Join-Path -Path $TestDrive -ChildPath 'download.bin'
        Set-Content -LiteralPath $file -Value 'vanta test payload' -NoNewline
        $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash

        InModuleScope Vanta.Software -Parameters @{ Path = $file; Hash = $hash } {
            Mock Resolve-VantaProtectedExecutionPath { $Path }
            { Assert-VantaFileHash -Path $Path -ExpectedSha256 $Hash -Description 'test file' } | Should -Not -Throw
        }
    }

    It 'throws a refusal when the file hash does not match' {
        $file = Join-Path -Path $TestDrive -ChildPath 'download.bin'
        Set-Content -LiteralPath $file -Value 'vanta test payload' -NoNewline

        InModuleScope Vanta.Software -Parameters @{ Path = $file } {
            Mock Resolve-VantaProtectedExecutionPath { $Path }
            $wrongHash = 'deadbeef' * 8
            { Assert-VantaFileHash -Path $Path -ExpectedSha256 $wrongHash -Description 'test file' } |
                Should -Throw -ExpectedMessage '*Refusing*'
        }
    }
}

Describe 'Assert-VantaFileSignature' {
    It 'passes for a valid signature whose quoted subject CN matches the expected publisher' {
        InModuleScope Vanta.Software {
            Mock Resolve-VantaProtectedExecutionPath { $Path }
            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{
                    Status            = [System.Management.Automation.SignatureStatus]::Valid
                    SignerCertificate = [pscustomobject]@{ Subject = 'CN="Brave Software, Inc.", O="Brave Software, Inc.", L=San Francisco, S=California, C=US' }
                }
            }

            { Assert-VantaFileSignature -Path 'C:\fake\installer.exe' -ExpectedSubjectCn 'Brave Software, Inc.' -Description 'Brave' } | Should -Not -Throw
        }
    }

    It 'throws a refusal when the signature status is not valid' {
        InModuleScope Vanta.Software {
            Mock Resolve-VantaProtectedExecutionPath { $Path }
            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{
                    Status            = [System.Management.Automation.SignatureStatus]::HashMismatch
                    SignerCertificate = [pscustomobject]@{ Subject = 'CN="Brave Software, Inc.", O="Brave Software, Inc.", L=San Francisco, S=California, C=US' }
                }
            }

            { Assert-VantaFileSignature -Path 'C:\fake\installer.exe' -ExpectedSubjectCn 'Brave Software, Inc.' -Description 'Brave' } |
                Should -Throw -ExpectedMessage '*Refusing*'
        }
    }

    It 'throws a refusal when the signature is valid but signed by another publisher' {
        InModuleScope Vanta.Software {
            Mock Resolve-VantaProtectedExecutionPath { $Path }
            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{
                    Status            = [System.Management.Automation.SignatureStatus]::Valid
                    SignerCertificate = [pscustomobject]@{ Subject = 'CN=Evil Corp, O=Evil Corp, C=US' }
                }
            }

            { Assert-VantaFileSignature -Path 'C:\fake\installer.exe' -ExpectedSubjectCn 'Brave Software, Inc.' -Description 'Brave' } |
                Should -Throw -ExpectedMessage '*Refusing*'
        }
    }

}

Describe 'Get-VantaSoftwarePickerItem' {
    It 'offers <Offered> on build <Build>' -TestCases @(
        @{ Build = 22631; Offered = 'StartIsBack.StartAllBack'; Hidden = 'StartIsBack.StartIsBack' }
        @{ Build = 19045; Offered = 'StartIsBack.StartIsBack'; Hidden = 'StartIsBack.StartAllBack' }
    ) {
        $items = InModuleScope Vanta.Software -Parameters @{ Build = $Build } {
            Get-VantaSoftwarePickerItem -WindowsBuild $Build
        }

        @($items | Where-Object { $_.Package -eq $Offered }).Count | Should -Be 1
        @($items | Where-Object { $_.Package -eq $Hidden }).Count | Should -Be 0
    }

    It 'gives every build <Build> entry a name and a unique id and source that the installer accepts' -TestCases @(
        @{ Build = 22631 }
        @{ Build = 19045 }
    ) {
        InModuleScope Vanta.Software -Parameters @{ Build = $Build } {
            param($Build)
            $items = @(Get-VantaSoftwarePickerItem -WindowsBuild $Build)
            # Check against the install boundary's own parameter validation.
            $parameters = (Get-Command -Name Invoke-VantaSoftwarePickerPackageInstall).Parameters
            $pattern = @($parameters['PackageId'].Attributes |
                    Where-Object { $_ -is [Management.Automation.ValidatePatternAttribute] })
            $sources = @($parameters['Source'].Attributes |
                    Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] })
            $pattern.Count | Should -Be 1
            $sources.Count | Should -Be 1

            $items.Count | Should -BeGreaterThan 0
            foreach ($item in $items) {
                $item.Text | Should -Not -BeNullOrEmpty
                [regex]::IsMatch($item.Package, $pattern[0].RegexPattern, $pattern[0].Options) |
                    Should -BeTrue -Because "'$($item.Package)' must pass the PackageId validation"
                $item.Source -cin $sources[0].ValidValues |
                    Should -BeTrue -Because "'$($item.Package)' must use an accepted source"
            }
            @($items.Package | Sort-Object -Unique).Count | Should -Be $items.Count
        }
    }
}

Describe 'Invoke-VantaSoftwarePickerPackageBatch' {
    It 'attempts every selected package and returns an aggregate failure record' {
        InModuleScope Vanta.Software {
            Mock Invoke-VantaSoftwarePickerPackageInstall {
                if ($PackageId -ceq 'Vendor.Broken') {
                    throw 'fixture install failed'
                }
            }
            Mock Write-VantaWarning
            $catalog = @(
                [pscustomobject]@{ Package = 'Vendor.First'; Source = 'winget' }
                [pscustomobject]@{ Package = 'Vendor.Broken'; Source = 'winget' }
                [pscustomobject]@{ Package = 'Vendor.Last'; Source = 'msstore' }
            )

            $failures = @(Invoke-VantaSoftwarePickerPackageBatch `
                    -PackageId @('Vendor.First', 'Vendor.Broken', 'Vendor.Last') `
                    -Catalog $catalog)

            Should -Invoke Invoke-VantaSoftwarePickerPackageInstall -Times 3 -Exactly
            Should -Invoke Write-VantaWarning -Times 1 -Exactly
            $failures.Count | Should -Be 1
            $failures[0].PackageId | Should -BeExactly 'Vendor.Broken'
            $failures[0].Message | Should -BeExactly 'fixture install failed'
        }
    }

    It 'reports missing catalog entries without skipping later packages' {
        InModuleScope Vanta.Software {
            Mock Invoke-VantaSoftwarePickerPackageInstall
            Mock Write-VantaWarning
            $catalog = @(
                [pscustomobject]@{ Package = 'Vendor.Present'; Source = 'winget' }
            )

            $failures = @(Invoke-VantaSoftwarePickerPackageBatch `
                    -PackageId @('Vendor.Missing', 'Vendor.Present') `
                    -Catalog $catalog)

            Should -Invoke Invoke-VantaSoftwarePickerPackageInstall -Times 1 -Exactly `
                -ParameterFilter { $PackageId -ceq 'Vendor.Present' }
            $failures.Count | Should -Be 1
            $failures[0].PackageId | Should -BeExactly 'Vendor.Missing'
        }
    }
}

Describe 'Invoke-VantaSoftwarePickerPackageInstall' {
    BeforeEach {
        $script:fakeWinget = Join-Path -Path $TestDrive -ChildPath 'winget.cmd'
        Mock Get-VantaTrustedWingetPath -ModuleName Vanta.Software { $script:fakeWinget }
        Mock Assert-VantaTrustedWingetSource -ModuleName Vanta.Software
        Mock Write-VantaNote -ModuleName Vanta.Software
    }

    It 'accepts an installed package that has no applicable upgrade and keeps WinGet output off the pipeline' {
        Set-Content -LiteralPath $script:fakeWinget -Encoding Ascii -Value @(
            '@echo No available upgrade found.'
            '@exit /b -1978335189'
        )

        $output = @(InModuleScope Vanta.Software {
                Invoke-VantaSoftwarePickerPackageInstall -PackageId 'Notepad++.Notepad++' -Source winget
            })

        $output.Count | Should -Be 0
        Should -Invoke Write-VantaNote -ModuleName Vanta.Software -Times 1 -Exactly -ParameterFilter {
            $Text -like "'Notepad++.Notepad++' is already installed*"
        }
    }

    It 'reports any other WinGet exit code in hexadecimal' {
        Set-Content -LiteralPath $script:fakeWinget -Encoding Ascii -Value '@exit /b -1978335212'

        InModuleScope Vanta.Software {
            { Invoke-VantaSoftwarePickerPackageInstall -PackageId 'Valve.Steam' -Source winget } |
                Should -Throw "*'Valve.Steam' from 'winget' with exit code 0x8A150014."
        }
        Should -Invoke Write-VantaNote -ModuleName Vanta.Software -Times 0
    }
}

Describe 'CBS Safe Mode retry fallback' {
    It 'arms the compact retry with the verified package paths' {
        InModuleScope Vanta.Software {
            Mock Enable-VantaCbsRetry {}
            Register-VantaCbsFailureFallback -RetryPackages @(
                [pscustomobject]@{ Path = 'C:\Packages\one.cab'; Sha256 = ('A' * 64) }
                [pscustomobject]@{ Path = 'C:\Packages\two.cab'; Sha256 = ('B' * 64) }
            )
            Should -Invoke Enable-VantaCbsRetry -Times 1 -Exactly -ParameterFilter {
                @($Packages).Count -eq 2 -and
                $Packages[0] -ceq 'C:\Packages\one.cab' -and
                $Packages[1] -ceq 'C:\Packages\two.cab'
            }
        }
    }

    It 'tells the user that the Safe Mode retry is armed and how to run it' {
        InModuleScope Vanta.Software {
            Mock Assert-VantaPrivilege {}
            Mock Initialize-VantaCbsEnvironment {}
            Mock Write-Host {}
            Mock Enable-VantaCbsRetry {}
            Mock Install-VantaCbsCab {
                [pscustomobject]@{
                    Path = $CabPath; Success = $false; RetryEligible = $true
                    Sha256 = ('A' * 64); FailureKind = 'Servicing'
                }
            }
            { Install-VantaCbsPackage -Packages @('C:\Packages\one.cab') -PackagesPath 'C:\Packages' `
                    -LiteralPaths -NonInteractive } |
                Should -Throw '*one.cab.*Safe Mode with Command Prompt*Invoke-VantaCbsRetry.cmd*'
            Should -Invoke Enable-VantaCbsRetry -Times 1 -Exactly
        }
    }
}

Describe 'Start-VantaSoftwareInstaller' {
    It 'runs the installer hidden/waited and returns quietly on a success exit code (0)' {
        InModuleScope Vanta.Software {
            Mock Invoke-VantaContainedProcess {
                [pscustomobject]@{
                    ExitCodeUInt32 = [uint32]0
                }
            }

            { Start-VantaSoftwareInstaller -FilePath 'C:\fake\setup.exe' -ArgumentList @('/S', '/AllUsers') -Description 'Test' -TimeoutSeconds 123 } |
                Should -Not -Throw

            Should -Invoke Invoke-VantaContainedProcess -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'C:\fake\setup.exe' -and
                @($ArgumentList).Count -eq 2 -and
                $ArgumentList[0] -ceq '/S' -and
                $ArgumentList[1] -ceq '/AllUsers' -and
                $WorkingDirectory -eq 'C:\fake' -and
                $TimeoutSeconds -eq 123 -and
                $Hidden -and $NoWindow
            }
        }
    }

    It 'judges exit code <ExitCode> with <Codes> success codes' -TestCases @(
        @{ ExitCode = 1; Codes = 'the default'; SuccessExitCode = $null; Failure = '*failed with exit code 1*' }
        # 1638 (another version installed) is only a success where a caller says so.
        @{ ExitCode = 1638; Codes = 'caller-supplied 0 and 3010'; SuccessExitCode = @(0, 3010); Failure = '*exit code 1638*' }
        @{ ExitCode = 3010; Codes = 'caller-supplied 0 and 3010'; SuccessExitCode = @(0, 3010); Failure = $null }
    ) {
        InModuleScope Vanta.Software -Parameters @{ ExitCode = $ExitCode; SuccessExitCode = $SuccessExitCode; Failure = $Failure } {
            Mock Invoke-VantaContainedProcess { [pscustomobject]@{ ExitCodeUInt32 = [uint32]$ExitCode } }
            $codes = @{}
            if ($null -ne $SuccessExitCode) { $codes.SuccessExitCode = $SuccessExitCode }
            $install = {
                Start-VantaSoftwareInstaller -FilePath 'C:\fake\setup.exe' -ArgumentList '/S' -Description 'Test' @codes
            }

            if ($Failure) { $install | Should -Throw -ExpectedMessage $Failure }
            else { $install | Should -Not -Throw }
        }
    }
}

Describe 'Start-VantaSoftwareOptionalInstaller' {
    It 'returns <Expected> with <Warnings> warning(s) so its caller can aggregate failure' -TestCases @(
        @{ Fails = $true; Expected = $false; Warnings = 1 }
        @{ Fails = $false; Expected = $true; Warnings = 0 }
    ) {
        InModuleScope Vanta.Software -Parameters @{ Fails = $Fails; Expected = $Expected; Warnings = $Warnings } {
            Mock Start-VantaSoftwareInstaller { if ($Fails) { throw 'failed with exit code 1' } }
            Mock Test-VantaContainedProcessContainmentUnconfirmed { $false }
            Mock Write-VantaLog

            Start-VantaSoftwareOptionalInstaller -FilePath 'C:\fake\setup.exe' -ArgumentList '/S' -Description 'Optional thing' |
                Should -Be $Expected

            Should -Invoke Write-VantaLog -Times $Warnings -Exactly -ParameterFilter {
                $Level -eq 'Warning' -and $Message -like '*failed with exit code 1*'
            }
        }
    }

    It 'rethrows an unconfirmed-containment failure instead of starting a fallback concurrently' {
        InModuleScope Vanta.Software {
            Mock Start-VantaSoftwareInstaller { throw 'containment unknown' }
            Mock Test-VantaContainedProcessContainmentUnconfirmed { $true }
            Mock Write-VantaLog

            { Start-VantaSoftwareOptionalInstaller -FilePath 'C:\fake\setup.exe' -Description 'Optional thing' } |
                Should -Throw -ExpectedMessage '*containment unknown*'
            Should -Invoke Write-VantaLog -Times 0
        }
    }
}

Describe 'Invoke-VantaSoftwareDownload' {
    It 'streams HTTPS into the protected destination through the shared size-limited reader' {
        InModuleScope Vanta.Software -Parameters @{ Root = $TestDrive } {
            $destination = Join-Path -Path $Root -ChildPath 'installer.exe'
            Mock Resolve-VantaProtectedExecutionPath { $Path }
            Mock Invoke-VantaLimitedHttpGet {
                $bytes = [Text.Encoding]::UTF8.GetBytes('signed fixture')
                $OutputStream.Write($bytes, 0, $bytes.Length)
                return $bytes.Length
            }

            Invoke-VantaSoftwareDownload `
                -Uri 'https://downloads.example.test/setup.exe' `
                -Destination $destination `
                -Description 'fixture' `
                -MaximumBytes 4096 `
                -MaximumSeconds 45 | Should -Be $destination

            Get-Content -LiteralPath $destination -Raw | Should -BeExactly 'signed fixture'
            Should -Invoke Invoke-VantaLimitedHttpGet -Times 1 -Exactly -ParameterFilter {
                $Uri.AbsoluteUri -ceq 'https://downloads.example.test/setup.exe' -and
                $MaximumBytes -eq 4096 -and
                $MaximumSeconds -eq 45 -and
                $AllowRedirect
            }
        }
    }

    It 'rejects HTTP before creating a destination' {
        InModuleScope Vanta.Software -Parameters @{ Root = $TestDrive } {
            Mock Invoke-VantaLimitedHttpGet
            $destination = Join-Path $Root 'setup.exe'

            { Invoke-VantaSoftwareDownload -Uri 'http://example.test/setup.exe' `
                    -Destination $destination -Description 'fixture' } |
                Should -Throw -ExpectedMessage '*Only HTTPS*'
            Test-Path -LiteralPath $destination | Should -BeFalse
            Should -Invoke Invoke-VantaLimitedHttpGet -Times 0
        }
    }

    It 'removes a partial file when size-limited streaming fails' {
        InModuleScope Vanta.Software -Parameters @{ Root = $TestDrive } {
            $destination = Join-Path -Path $Root -ChildPath 'partial.exe'
            Mock Resolve-VantaProtectedExecutionPath { $Path }
            Mock Invoke-VantaLimitedHttpGet {
                $bytes = [Text.Encoding]::UTF8.GetBytes('partial')
                $OutputStream.Write($bytes, 0, $bytes.Length)
                throw 'network failed'
            }

            { Invoke-VantaSoftwareDownload -Uri 'https://example.test/setup.exe' `
                    -Destination $destination -Description 'fixture' } |
                Should -Throw -ExpectedMessage '*network failed*'
            Test-Path -LiteralPath $destination | Should -BeFalse
        }
    }
}

Describe 'LibreWolf latest-release identity and publisher boundary' {
    BeforeEach {
        $script:LibreWolfRelease = [pscustomobject]@{
            tag_name   = '152.0.5-1'
            draft      = $false
            prerelease = $false
            assets     = @(
                [pscustomobject]@{
                    name                 = 'librewolf-152.0.5-1-windows-x86_64-setup.exe'
                    browser_download_url = 'https://dl.librewolf.net/librewolf/152.0.5-1/librewolf-152.0.5-1-windows-x86_64-setup.exe'
                }
                [pscustomobject]@{
                    name                 = 'librewolf-152.0.5-1-windows-arm64-setup.exe'
                    browser_download_url = 'https://dl.librewolf.net/librewolf/152.0.5-1/librewolf-152.0.5-1-windows-arm64-setup.exe'
                }
            )
        }
        $script:LibreWolfWingetManifestText = @'
PackageIdentifier: LibreWolf.LibreWolf
PackageVersion: 152.0.5-1
InstallerType: nullsoft
Scope: machine
Installers:
- InstallerSha256: 227F69A02C286F90E82B6155F7CBFD01EACC63DDAE7CA73594EC32C5F4BC84F6
  InstallerUrl: https://dl.librewolf.net/librewolf/152.0.5-1/librewolf-152.0.5-1-windows-x86_64-setup.exe
  Architecture: x64
  ProductCode: ignored-extra-field
- Architecture: arm64
  InstallerUrl: https://dl.librewolf.net/librewolf/152.0.5-1/librewolf-152.0.5-1-windows-arm64-setup.exe
  InstallerSha256: 03B5E2E68A4B17551CC0798C015EBA3DF528C5CA5F27EC9D53065A8FDC90123E
ManifestType: installer
'@
        $manifestBytes = (New-Object Text.UTF8Encoding($false)).GetBytes(
            $script:LibreWolfWingetManifestText
        )
        $script:LibreWolfWingetContent = [pscustomobject]@{
            encoding = 'base64'
            content  = [Convert]::ToBase64String($manifestBytes)
        }
        $script:LibreWolfResolvedRelease = [pscustomobject]@{
            Tag = '152.0.5-1'
            Uri = [uri]'https://dl.librewolf.net/librewolf/152.0.5-1/librewolf-152.0.5-1-windows-x86_64-setup.exe'
        }
    }

    It 'selects the exact architecture-specific stable Codeberg asset' {
        InModuleScope Vanta.Software -Parameters @{
            Release = $script:LibreWolfRelease
        } {
            $metadata = Resolve-VantaLibreWolfReleaseMetadata `
                -Release $Release -Architecture x86_64

            $metadata.Tag | Should -BeExactly '152.0.5-1'
            $metadata.Name | Should -BeExactly 'librewolf-152.0.5-1-windows-x86_64-setup.exe'
            $metadata.Uri.AbsoluteUri | Should -BeExactly 'https://dl.librewolf.net/librewolf/152.0.5-1/librewolf-152.0.5-1-windows-x86_64-setup.exe'
            @($metadata.PSObject.Properties.Name) | Should -Be @('Tag', 'Name', 'Uri')
        }
    }

    It 'rejects <Case>' -TestCases @(
        @{
            Case    = 'a duplicate installer asset'
            Change  = { param($Release) $Release.assets += $Release.assets[0].PSObject.Copy() }
            Message = '*exactly one*'
        }
        @{
            Case    = 'an installer asset outside the canonical download host'
            Change  = {
                param($Release)
                $Release.assets[0].browser_download_url =
                'https://attacker.example/librewolf/152.0.5-1/librewolf-152.0.5-1-windows-x86_64-setup.exe'
            }
            Message = '*canonical LibreWolf download URL*'
        }
        @{
            Case    = 'a prerelease'
            Change  = { param($Release) $Release.prerelease = $true }
            Message = '*not a stable LibreWolf release*'
        }
        @{
            Case    = 'a draft'
            Change  = { param($Release) $Release.draft = $true }
            Message = '*not a stable LibreWolf release*'
        }
        @{
            Case    = 'a tag that leaves the download path'
            Change  = { param($Release) $Release.tag_name = '152.0.5-1/..' }
            Message = '*not a stable LibreWolf release*'
        }
    ) {
        & $Change $script:LibreWolfRelease
        InModuleScope Vanta.Software -Parameters @{
            Release = $script:LibreWolfRelease
            Message = $Message
        } {
            { Resolve-VantaLibreWolfReleaseMetadata `
                    -Release $Release -Architecture x86_64 } |
                Should -Throw -ExpectedMessage $Message
        }
    }

    It 'reads the selected installer despite field reordering, extra fields, and another architecture' {
        InModuleScope Vanta.Software -Parameters @{
            ContentMetadata = $script:LibreWolfWingetContent
            ReleaseMetadata = $script:LibreWolfResolvedRelease
        } {
            Resolve-VantaLibreWolfWingetManifestHash `
                -ContentMetadata $ContentMetadata `
                -ReleaseMetadata $ReleaseMetadata `
                -Architecture x86_64 |
                Should -BeExactly '227f69a02c286f90e82b6155f7cbfd01eacc63ddae7ca73594ec32c5f4bc84f6'
        }
    }

    It 'rejects an independent manifest that redirects the selected architecture' {
        $script:LibreWolfWingetManifestText = $script:LibreWolfWingetManifestText.Replace(
            'https://dl.librewolf.net/librewolf/152.0.5-1/librewolf-152.0.5-1-windows-x86_64-setup.exe',
            'https://attacker.example/setup.exe'
        )
        $manifestBytes = (New-Object Text.UTF8Encoding($false)).GetBytes(
            $script:LibreWolfWingetManifestText
        )
        $script:LibreWolfWingetContent.content = [Convert]::ToBase64String($manifestBytes)
        InModuleScope Vanta.Software -Parameters @{
            ContentMetadata = $script:LibreWolfWingetContent
            ReleaseMetadata = $script:LibreWolfResolvedRelease
        } {
            { Resolve-VantaLibreWolfWingetManifestHash `
                    -ContentMetadata $ContentMetadata `
                    -ReleaseMetadata $ReleaseMetadata `
                    -Architecture x86_64 } |
                Should -Throw -ExpectedMessage '*does not attest*'
        }
    }

    It 'installs the newest release winget-pkgs has merged while a newer one awaits review' {
        $newer = [pscustomobject]@{
            tag_name   = '152.0.6-1'
            draft      = $false
            prerelease = $false
            assets     = @([pscustomobject]@{
                    name                 = 'librewolf-152.0.6-1-windows-x86_64-setup.exe'
                    browser_download_url = 'https://dl.librewolf.net/librewolf/152.0.6-1/librewolf-152.0.6-1-windows-x86_64-setup.exe'
                })
        }
        $draft = [pscustomobject]@{ tag_name = '152.0.7-1'; draft = $true; prerelease = $false; assets = @() }
        InModuleScope Vanta.Software -Parameters @{
            Releases = @($draft, $newer, $script:LibreWolfRelease)
            Manifest = $script:LibreWolfWingetContent
        } {
            Mock Write-VantaLog
            Mock Invoke-VantaSoftwareApiJson { $Releases }
            Mock Invoke-VantaGitHubApiJson { throw "Unexpected GitHub request for '$Uri'." }
            Mock Invoke-VantaGitHubApiJson -ParameterFilter {
                $Uri.AbsolutePath -ceq '/repos/microsoft/winget-pkgs/contents/manifests/l/LibreWolf/LibreWolf'
            } -MockWith {
                [pscustomobject]@{ name = '152.0.4-1'; type = 'dir' }
                [pscustomobject]@{ name = '152.0.5-1'; type = 'dir' }
            }
            Mock Invoke-VantaGitHubApiJson -ParameterFilter {
                $Uri.AbsolutePath -ceq '/repos/microsoft/winget-pkgs/contents/manifests/l/LibreWolf/LibreWolf/152.0.5-1/LibreWolf.LibreWolf.installer.yaml'
            } -MockWith { $Manifest }

            $metadata = Get-VantaLatestLibreWolfInstallerMetadata -Architecture x86_64

            $metadata.Tag | Should -BeExactly '152.0.5-1'
            $metadata.Uri.AbsoluteUri | Should -BeExactly 'https://dl.librewolf.net/librewolf/152.0.5-1/librewolf-152.0.5-1-windows-x86_64-setup.exe'
            $metadata.Sha256 | Should -BeExactly '227f69a02c286f90e82b6155f7cbfd01eacc63ddae7ca73594ec32c5f4bc84f6'
            Should -Invoke Invoke-VantaGitHubApiJson -Times 2 -Exactly
            Should -Invoke Write-VantaLog -Times 1 -Exactly -ParameterFilter {
                $Message -like '*152.0.6-1 is awaiting Microsoft winget-pkgs review; installing 152.0.5-1*'
            }
        }
    }

    It 'fails before reading a manifest when winget-pkgs has merged none of the newest releases' {
        InModuleScope Vanta.Software -Parameters @{ Releases = @($script:LibreWolfRelease) } {
            Mock Write-VantaLog
            Mock Invoke-VantaSoftwareApiJson { $Releases }
            Mock Invoke-VantaGitHubApiJson { throw "Unexpected GitHub request for '$Uri'." }
            Mock Invoke-VantaGitHubApiJson -ParameterFilter {
                $Uri.AbsolutePath -ceq '/repos/microsoft/winget-pkgs/contents/manifests/l/LibreWolf/LibreWolf'
            } -MockWith {
                [pscustomobject]@{ name = '152.0.4-1'; type = 'dir' }
            }

            { Get-VantaLatestLibreWolfInstallerMetadata -Architecture x86_64 } |
                Should -Throw "*hasn't merged any of the newest LibreWolf releases (152.0.5-1)*"
            Should -Invoke Invoke-VantaGitHubApiJson -Times 1 -Exactly
        }
    }
}

Describe 'NanaZip package identity and provisioning boundary' {
    It 'accepts the exact Store bundle name, publisher, and release version' {
        $bundle = Join-Path -Path $TestDrive -ChildPath 'NanaZip.msixbundle'
        New-VantaTestNanaZipBundle -Path $bundle

        InModuleScope Vanta.Software -Parameters @{ Bundle = $bundle } {
            Mock Resolve-VantaProtectedExecutionPath { $Path }

            { Assert-VantaNanaZipBundleIdentity -Path $Bundle -Version '6.5.1767.0' } |
                Should -Not -Throw
        }
    }

    It 'rejects a hash-valid bundle for a different package publisher' {
        $bundle = Join-Path -Path $TestDrive -ChildPath 'WrongPublisher.msixbundle'
        New-VantaTestNanaZipBundle -Path $bundle -Publisher 'CN=Attacker'

        InModuleScope Vanta.Software -Parameters @{ Bundle = $bundle } {
            Mock Resolve-VantaProtectedExecutionPath { $Path }

            { Assert-VantaNanaZipBundleIdentity -Path $Bundle -Version '6.5.1767.0' } |
                Should -Throw -ExpectedMessage '*reviewed Store package*'
        }
    }

}

Describe 'Install-VantaNanaZip provisioning' {
    BeforeEach {
        $script:NanaZipMutationAssets = @(
            [pscustomobject]@{
                Name = 'NanaZip_6.5.1767.0.msixbundle'
                Tag = '6.5.1767.0'
                Uri = [uri]'https://example.invalid/NanaZip_6.5.1767.0.msixbundle'
                Sha256 = '1' * 64
                Size = 123L
            }
            [pscustomobject]@{
                Name = 'NanaZip_6.5.1767.0.xml'
                Tag = '6.5.1767.0'
                Uri = [uri]'https://example.invalid/NanaZip_6.5.1767.0.xml'
                Sha256 = '2' * 64
                Size = 456L
            }
        )
    }

    It 'downloads the exact pair, provisions it with DISM, and verifies the installed version' {
        $temp = Join-Path -Path $TestDrive -ChildPath 'nanazip-success'
        New-Item -Path $temp -ItemType Directory | Out-Null
        InModuleScope Vanta.Software -Parameters @{
            Temp = $temp
            Assets = $script:NanaZipMutationAssets
        } {
            $script:AddedPackage = $null
            $commands = [pscustomobject]@{
                GetProvisionedPackage = {
                    [pscustomobject]@{
                        DisplayName = '40174MouriNaruto.NanaZip'
                        Version = '6.5.1767.0'
                    }
                }
                AddProvisionedPackage = {
                    param(
                        [switch]$Online,
                        [string]$PackagePath,
                        [string]$LicensePath
                    )
                    $script:AddedPackage = [pscustomobject]@{
                        Online = $Online
                        PackagePath = $PackagePath
                        LicensePath = $LicensePath
                    }
                }
            }
            Mock Resolve-VantaProtectedExecutionPath { $Path }
            Mock Invoke-VantaPinnedDownload { $Destination }
            Mock Assert-VantaNanaZipBundleIdentity

            Install-VantaNanaZip `
                -TempDir $Temp `
                -Assets $Assets `
                -DismCommands $commands | Should -BeTrue

            Should -Invoke Invoke-VantaPinnedDownload -Times 2 -Exactly
            Should -Invoke Assert-VantaNanaZipBundleIdentity -Times 1 -Exactly `
                -ParameterFilter { $Version -ceq '6.5.1767.0' }
            $script:AddedPackage.Online | Should -BeTrue
            $script:AddedPackage.PackagePath | Should -BeLike '*NanaZip_6.5.1767.0.msixbundle'
            $script:AddedPackage.LicensePath | Should -BeLike '*NanaZip_6.5.1767.0.xml'
        }
    }

    It 'reports a download failure as a download-source failure without calling DISM' {
        $temp = Join-Path -Path $TestDrive -ChildPath 'nanazip-pre-mutation'
        New-Item -Path $temp -ItemType Directory | Out-Null
        InModuleScope Vanta.Software -Parameters @{
            Temp = $temp
            Assets = $script:NanaZipMutationAssets
        } {
            $commands = [pscustomobject]@{
                GetProvisionedPackage = { throw 'must not read back before provisioning' }
                AddProvisionedPackage = { throw 'must not mutate after a download failure' }
            }
            Mock Resolve-VantaProtectedExecutionPath { $Path }
            Mock Invoke-VantaPinnedDownload { throw 'verified download unavailable' }
            Mock Write-VantaLog

            { Install-VantaNanaZip -TempDir $Temp -Assets $Assets -DismCommands $commands } | Should -Throw '*verified download sources*'
        }
    }

    It 'rethrows the original error when the readback after DISM fails' {
        $temp = Join-Path -Path $TestDrive -ChildPath 'nanazip-readback-failure'
        New-Item -Path $temp -ItemType Directory | Out-Null
        InModuleScope Vanta.Software -Parameters @{
            Temp = $temp
            Assets = $script:NanaZipMutationAssets
        } {
            $commands = [pscustomobject]@{
                GetProvisionedPackage = {
                    [CmdletBinding()]
                    param([switch]$Online)
                    [void]$Online
                    return @()
                }
                AddProvisionedPackage = {
                    [CmdletBinding()]
                    param(
                        [switch]$Online,
                        [string]$PackagePath,
                        [string]$LicensePath
                    )
                    [void]$Online
                    [void]$PackagePath
                    [void]$LicensePath
                }
            }
            Mock Resolve-VantaProtectedExecutionPath { $Path }
            Mock Invoke-VantaPinnedDownload { $Destination }
            Mock Assert-VantaNanaZipBundleIdentity

            # Exact match: DISM may have changed machine state, so the error must
            # not be reworded as a download-source failure.
            { Install-VantaNanaZip -TempDir $Temp -Assets $Assets -DismCommands $commands } |
                Should -Throw -ExpectedMessage "DISM returned without provisioning NanaZip version '6.5.1767.0'."
        }
    }
}

Describe 'Install-VantaArchiveTool asset selection' {
    BeforeEach {
        Mock Install-VantaNanaZipFromStore -ModuleName Vanta.Software { $false }
        Mock Test-Path -ModuleName Vanta.Software -ParameterFilter {
            $LiteralPath -eq 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\7-Zip'
        } -MockWith { $false }
        Mock Read-MessageBox -ModuleName Vanta.Software {
            throw 'An archive installation test attempted to show an interactive prompt.'
        }
    }
    It 'reports a NanaZip integrity failure before installation' {
        InModuleScope Vanta.Software {
            $commands = [pscustomobject]@{
                GetProvisionedPackage = {
                    [CmdletBinding()]
                    param([switch]$Online)
                    [void]$Online
                    return @()
                }
                AddProvisionedPackage = { }
            }
            Mock Get-VantaDismProvisioningCommands { $commands }
            Mock Get-VantaPinnedNanaZipReleaseAssets { throw 'digest missing' }
            Mock Install-VantaNanaZip
            Mock Write-VantaLog

            { Install-VantaArchiveTool -TempDir 'C:\fake\temp' } | Should -Throw '*integrity could not be established*'
            Should -Invoke Install-VantaNanaZip -Times 0 -Exactly
        }
    }

    It 'falls back to the pinned NanaZip download when the Store path declines' {
        InModuleScope Vanta.Software {
            $commands = [pscustomobject]@{
                GetProvisionedPackage = {
                    [CmdletBinding()]
                    param([switch]$Online)
                    [void]$Online
                    return @()
                }
                AddProvisionedPackage = { }
            }
            Mock Get-VantaDismProvisioningCommands { $commands }
            Mock Get-VantaPinnedNanaZipReleaseAssets {
                [pscustomobject]@{ Name = 'NanaZip_6.5.1767.0.msixbundle'; Tag = '6.5.1767.0' }
                [pscustomobject]@{ Name = 'NanaZip_6.5.1767.0.xml'; Tag = '6.5.1767.0' }
            }
            Mock Install-VantaNanaZip { $true }
            Mock Write-VantaLog

            Install-VantaArchiveTool -TempDir 'C:\fake\temp'

            Should -Invoke Install-VantaNanaZipFromStore -Times 1 -Exactly -ParameterFilter {
                $null -ne $DismCommands.AddProvisionedPackage
            }
            Should -Invoke Install-VantaNanaZip -Times 1 -Exactly -ParameterFilter {
                @($Assets).Count -eq 2 -and
                $Assets[0].Name -ceq 'NanaZip_6.5.1767.0.msixbundle' -and
                $Assets[1].Name -ceq 'NanaZip_6.5.1767.0.xml' -and
                $null -ne $DismCommands.AddProvisionedPackage -and
                $TempDir -ceq 'C:\fake\temp'
            }
        }
    }

    It 'keeps an installed 7-Zip without asking or installing NanaZip' {
        InModuleScope Vanta.Software {
            Mock Test-Path -ParameterFilter {
                $LiteralPath -eq 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\7-Zip'
            } -MockWith { $true }
            Mock Get-VantaDismProvisioningCommands { throw 'DISM is not needed when 7-Zip stays.' }
            Mock Install-VantaNanaZip
            Mock Write-VantaLog

            Install-VantaArchiveTool -TempDir 'C:\fake\temp'

            Should -Invoke Install-VantaNanaZipFromStore -Times 0 -Exactly
            Should -Invoke Install-VantaNanaZip -Times 0 -Exactly
            Should -Invoke Write-VantaLog -Times 1 -Exactly -ParameterFilter {
                $Message -like '7-Zip is installed*skips NanaZip*'
            }
        }
    }
}
