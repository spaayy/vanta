[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidGlobalVars',
    '',
    Justification = 'Shell.Application doubles are COM-shaped script methods that resolve their recording state through a global variable.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter',
    '',
    Justification = 'Mock doubles declare the parameters of the commands they shadow.'
)]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Import-Module -Name (Join-Path -Path $script:VantaTestModulesRoot -ChildPath 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module -Name (Join-Path -Path $script:VantaTestModulesRoot -ChildPath 'Vanta.Shell\Vanta.Shell.psd1') -Force

    $script:testRoot = 'HKCU:\Software\VantaRewriteTest'
    $script:settingsKey = "$script:testRoot\Explorer"
    $script:defaultUserKey = "$script:testRoot\DefaultUser"
    $script:taskbandKey = 'HKCU\Software\VantaRewriteTest\Taskband'
    $script:tweaksRoot = Join-Path -Path $script:VantaTestScriptsRoot -ChildPath 'Tweaks'

    function Get-TestRegistryValue {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string]$Name
        )

        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            return $null
        }
        return $item.$Name
    }

    function ConvertTo-TestHexString {
        param([Parameter(Mandatory = $true)][byte[]]$Bytes)

        return (($Bytes | ForEach-Object { $_.ToString('X2') }) -join '')
    }
}

AfterAll {
    Remove-Item -Path 'HKCU:\Software\VantaRewriteTest' -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Set-VantaSettingsPageVisibility' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Shell
        Mock Test-VantaAdmin -ModuleName Vanta.Shell { $true }
        Mock Get-VantaSettingsPageVisibilityKey -ModuleName Vanta.Shell { $script:settingsKey }
        Remove-Item -Path $script:settingsKey -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'preserves an allowlist when hiding and unhiding one page including an empty list' {
        New-Item -Path $script:settingsKey -Force | Out-Null
        Set-ItemProperty -LiteralPath $script:settingsKey -Name SettingsPageVisibility -Value 'showonly:printers;windowsupdate' -Type String
        Set-VantaSettingsPageVisibility -Operation hide -Page printers -NoProcessCleanup
        Get-TestRegistryValue -Path $script:settingsKey -Name SettingsPageVisibility | Should -Be 'showonly:windowsupdate'
        Set-VantaSettingsPageVisibility -Operation hide -Page windowsupdate -NoProcessCleanup
        Get-TestRegistryValue -Path $script:settingsKey -Name SettingsPageVisibility | Should -Be 'showonly:'
        Set-VantaSettingsPageVisibility -Operation unhide -Page printers -NoProcessCleanup
        Get-TestRegistryValue -Path $script:settingsKey -Name SettingsPageVisibility | Should -Be 'showonly:printers'
    }

    It 'requires an administrator token' {
        Mock Test-VantaAdmin -ModuleName Vanta.Shell { $false }

        { Set-VantaSettingsPageVisibility -Operation hide -Page windowsupdate -NoProcessCleanup } |
            Should -Throw '*Administrator rights*'
        Test-Path -LiteralPath $script:settingsKey | Should -BeFalse
    }

    It 'rejects a page that is not a canonical identifier' {
        { Set-VantaSettingsPageVisibility -Operation hide -Page 'Windows Update' -NoProcessCleanup } |
            Should -Throw '*canonical page identifier*'
        { Set-VantaSettingsPageVisibility -Operation hide -Page ('a' * 257) -NoProcessCleanup } |
            Should -Throw '*canonical page identifier*'
    }

    It 'hides pages cumulatively under the hide: prefix without duplicates' {
        Set-VantaSettingsPageVisibility -Operation hide -Page windowsupdate -NoProcessCleanup
        Get-TestRegistryValue -Path $script:settingsKey -Name SettingsPageVisibility |
            Should -BeExactly 'hide:windowsupdate'

        Set-VantaSettingsPageVisibility -Operation hide -Page printers -NoProcessCleanup
        Set-VantaSettingsPageVisibility -Operation hide -Page windowsupdate -NoProcessCleanup
        Get-TestRegistryValue -Path $script:settingsKey -Name SettingsPageVisibility |
            Should -BeExactly 'hide:windowsupdate;printers'
    }

    It 'unhides one page and removes the value with the last page' {
        New-Item -Path $script:settingsKey -Force | Out-Null
        Set-ItemProperty -LiteralPath $script:settingsKey -Name SettingsPageVisibility `
            -Value 'hide:privacy-location;findmydevice' -Type String

        Set-VantaSettingsPageVisibility -Operation unhide -Page privacy-location -NoProcessCleanup
        Get-TestRegistryValue -Path $script:settingsKey -Name SettingsPageVisibility |
            Should -BeExactly 'hide:findmydevice'

        Set-VantaSettingsPageVisibility -Operation unhide -Page findmydevice -NoProcessCleanup
        Get-TestRegistryValue -Path $script:settingsKey -Name SettingsPageVisibility |
            Should -BeNullOrEmpty

        { Set-VantaSettingsPageVisibility -Operation unhide -Page findmydevice -NoProcessCleanup } |
            Should -Not -Throw
    }

    It 'refuses to rewrite a value of an unexpected kind' {
        New-Item -Path $script:settingsKey -Force | Out-Null
        Set-ItemProperty -LiteralPath $script:settingsKey -Name SettingsPageVisibility -Value 1 -Type DWord

        { Set-VantaSettingsPageVisibility -Operation hide -Page printers -NoProcessCleanup } |
            Should -Throw '*unsupported registry value kind*'
        Get-TestRegistryValue -Path $script:settingsKey -Name SettingsPageVisibility | Should -Be 1
    }

    It 'closes only Settings in the caller session, and none when cleanup is suppressed' {
        # Typed doubles bind to -InputObject as real processes do; plain objects would bind -Id.
        $currentSession = [Diagnostics.Process]::GetCurrentProcess().SessionId
        $processes = @(
            New-MockObject -Type 'System.Diagnostics.Process' `
                -Properties @{ ProcessName = 'SystemSettings'; Id = 4101; SessionId = $currentSession }
            New-MockObject -Type 'System.Diagnostics.Process' `
                -Properties @{ ProcessName = 'explorer'; Id = 4102; SessionId = $currentSession }
            New-MockObject -Type 'System.Diagnostics.Process' `
                -Properties @{ ProcessName = 'SystemSettings'; Id = 4103; SessionId = $currentSession + 1 }
        )
        Mock Get-Process -ModuleName Vanta.Shell -MockWith { $processes }.GetNewClosure()
        Mock Stop-Process -ModuleName Vanta.Shell

        Set-VantaSettingsPageVisibility -Operation hide -Page printers
        Should -Invoke Stop-Process -ModuleName Vanta.Shell -Times 1 -Exactly
        Should -Invoke Stop-Process -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
            $InputObject.Id -eq 4101 -and $Force
        }

        Set-VantaSettingsPageVisibility -Operation unhide -Page printers -NoProcessCleanup
        Should -Invoke Get-Process -ModuleName Vanta.Shell -Times 1 -Exactly
        Should -Invoke Stop-Process -ModuleName Vanta.Shell -Times 1 -Exactly
    }

    It 'reports a Settings window that will not close without failing the change' {
        Mock Get-Process -ModuleName Vanta.Shell {
            [pscustomobject]@{ ProcessName = 'SystemSettings'; Id = 4101; SessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId }
        }
        Mock Stop-Process -ModuleName Vanta.Shell { throw 'access denied' }

        { Set-VantaSettingsPageVisibility -Operation hide -Page printers } | Should -Not -Throw
        Get-TestRegistryValue -Path $script:settingsKey -Name SettingsPageVisibility |
            Should -BeExactly 'hide:printers'
        Should -Invoke Write-VantaLog -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -like '*4101*access denied*'
        }
    }
}

Describe 'Set-VantaFileAssociations' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Shell
    }

    It 'maps every registered 7-Zip archive handler to OpenWithProgids' {
        Mock Test-VantaMachineClassRegistration -ModuleName Vanta.Shell { $true }

        $changes = @(InModuleScope Vanta.Shell { Get-VantaArchiveAssociationChange })
        $handlers = @($changes | Where-Object Path -Like '*\OpenWithProgids')
        $handlers.Count | Should -BeGreaterThan 0
        foreach ($handler in $handlers) {
            $handler.Path -cmatch '^SOFTWARE\\Classes\\\.(?<ext>[0-9a-z]+)\\OpenWithProgids$' | Should -BeTrue
            $handler.Name | Should -BeExactly "7-Zip.$($Matches.ext)"
            $handler.Value | Should -BeExactly ''
            $handler.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::String)
        }

        $options = $changes[-1]
        $options.Path | Should -BeExactly 'SOFTWARE\7-Zip\Options'
        $options.Name | Should -BeExactly 'ContextMenu'
        $options.Value | Should -Be 1073746726
        $options.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::DWord)
    }

    It 'plans nothing when no 7-Zip handler is registered on the machine' {
        Mock Test-VantaMachineClassRegistration -ModuleName Vanta.Shell { $false }

        @(InModuleScope Vanta.Shell { Get-VantaArchiveAssociationChange }).Count | Should -Be 0
    }

    It 'applies every planned change for the checked user and propagates the first write failure' {
        Mock Test-VantaMachineClassRegistration -ModuleName Vanta.Shell { $true }
        Mock Assert-VantaFileAssociationUser -ModuleName Vanta.Shell
        Mock Write-VantaFileAssociationChange -ModuleName Vanta.Shell
        $planned = @(InModuleScope Vanta.Shell { Get-VantaArchiveAssociationChange }).Count
        $planned | Should -BeGreaterThan 0

        Set-VantaFileAssociations | Should -BeNullOrEmpty
        Should -Invoke Write-VantaFileAssociationChange -ModuleName Vanta.Shell -Times $planned -Exactly
        Should -Invoke Assert-VantaFileAssociationUser -ModuleName Vanta.Shell -Times 1 -Exactly

        Mock Write-VantaFileAssociationChange -ModuleName Vanta.Shell { throw 'registry write failed' }
        { Set-VantaFileAssociations } | Should -Throw '*registry write failed*'
    }

    It 'validates the expected user SID before any registry work' {
        Mock Test-VantaMachineClassRegistration -ModuleName Vanta.Shell { $true }
        Mock Write-VantaFileAssociationChange -ModuleName Vanta.Shell

        { Set-VantaFileAssociations -ExpectedUserSid 'not-a-sid' } |
            Should -Throw "*expected file-association user SID 'not-a-sid' is invalid*"
        { Set-VantaFileAssociations -ExpectedUserSid 'S-1-5-21-0-0-0-1000' } |
            Should -Throw '*does not match expected SID*'
        Should -Invoke Write-VantaFileAssociationChange -ModuleName Vanta.Shell -Times 0
    }

    It 'writes a planned value into the current-user hive' {
        InModuleScope Vanta.Shell {
            Write-VantaFileAssociationChange -Change (New-VantaFileAssociationChange `
                    -Path 'Software\VantaRewriteTest\Assoc\.zip\OpenWithProgids' `
                    -Name '7-Zip.zip' -Value '' -Kind String)
            Write-VantaFileAssociationChange -Change (New-VantaFileAssociationChange `
                    -Path 'Software\VantaRewriteTest\Assoc\Options' `
                    -Name 'ContextMenu' -Value 1073746726 -Kind DWord)
        }

        $handler = Get-Item -LiteralPath "$script:testRoot\Assoc\.zip\OpenWithProgids"
        $handler.GetValueKind('7-Zip.zip') | Should -Be ([Microsoft.Win32.RegistryValueKind]::String)
        $handler.GetValue('7-Zip.zip') | Should -BeExactly ''
        Get-TestRegistryValue -Path "$script:testRoot\Assoc\Options" -Name ContextMenu |
            Should -Be 1073746726
    }
}

Describe 'Set-VantaSendToContextMenu' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Shell
        Mock Assert-VantaSendToUser -ModuleName Vanta.Shell { 'S-1-5-21-1-2-3-1001' }
        Mock Get-VantaSendToItem -ModuleName Vanta.Shell {
            [ordered]@{
                'Removable Drives'          = $null
                'Bluetooth'                 = 'C:\SendTo\Bluetooth File Transfer.lnk'
                'Desktop (create shortcut)' = 'C:\SendTo\Desktop.DeskLink'
                'Mail recipient'            = 'C:\SendTo\Mail Recipient.MAPIMail'
                'Documents'                 = 'C:\SendTo\Documents.mydocs'
            }
        }
        Mock Set-VantaSendToItemState -ModuleName Vanta.Shell
    }

    It 'accepts exactly one selection mode' {
        { Set-VantaSendToContextMenu -Disable @('Bluetooth') -Enable @('Documents') } |
            Should -Throw '*exactly one of*'
        { Set-VantaSendToContextMenu -DebloatDefaults -Disable @('Bluetooth') } |
            Should -Throw '*exactly one of*'
        Should -Invoke Set-VantaSendToItemState -ModuleName Vanta.Shell -Times 0
    }

    It 'disables the documented default items and skips absent ones' {
        Set-VantaSendToContextMenu -DebloatDefaults

        Should -Invoke Set-VantaSendToItemState -ModuleName Vanta.Shell -Times 3 -Exactly -ParameterFilter {
            $Enabled -eq $false
        }
        foreach ($expected in @('Documents', 'Mail recipient', 'Bluetooth')) {
            Should -Invoke Set-VantaSendToItemState -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
                $Name -ceq $expected -and $Enabled -eq $false
            }
        }
        Should -Invoke Set-VantaSendToItemState -ModuleName Vanta.Shell -Times 0 -ParameterFilter {
            $Name -ceq 'Desktop (create shortcut)' -or $Name -ceq 'Removable Drives'
        }
    }

    It 'enables a selected item through its recorded path' {
        Set-VantaSendToContextMenu -Enable @('Bluetooth')

        Should -Invoke Set-VantaSendToItemState -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'Bluetooth' -and $Path -eq 'C:\SendTo\Bluetooth File Transfer.lnk' -and $Enabled -eq $true
        }
    }

    It 'forwards the caller-supplied user SID' {
        Set-VantaSendToContextMenu -Disable @('Documents') -ExpectedUserSid 'S-1-5-21-1-2-3-1001'

        Should -Invoke Assert-VantaSendToUser -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
            $ExpectedUserSid -eq 'S-1-5-21-1-2-3-1001'
        }
    }

    It 'rejects an unknown selector before changing anything' {
        { Set-VantaSendToContextMenu -Disable @('Typo') } |
            Should -Throw '*Unsupported Send-To item selector*'
        Should -Invoke Set-VantaSendToItemState -ModuleName Vanta.Shell -Times 0
    }

    It 'resolves known names and wildcard selectors in stable order' {
        InModuleScope Vanta.Shell {
            $known = [string[]]@('Bluetooth', 'Mail recipient', 'Documents')
            @(Resolve-VantaSendToSelectorName -Selector @('Mail*', 'Bluetooth', 'Mail*') -KnownName $known) |
                Should -Be @('Mail recipient', 'Bluetooth')
            { Resolve-VantaSendToSelectorName -Selector @() -KnownName @('Documents') } |
                Should -Throw '*cannot be empty*'
            { Resolve-VantaSendToSelectorName -Selector @(' ') -KnownName @('Documents') } |
                Should -Throw '*cannot be empty or whitespace*'
        }
    }

    It 'interprets the multichoice output as cancel, disable-all or an enabled set' {
        InModuleScope Vanta.Shell {
            $cancelled = ConvertFrom-VantaSendToChoice -Output @() -AvailableName @('Documents') -DisableAllChoice '[all]'
            $cancelled.Cancelled | Should -BeTrue
            @($cancelled.Enabled).Count | Should -Be 0
            (ConvertFrom-VantaSendToChoice -Output @('') -AvailableName @('Documents') -DisableAllChoice '[all]').Cancelled |
                Should -BeTrue

            $none = ConvertFrom-VantaSendToChoice -Output @('[all]') -AvailableName @('Documents', 'Bluetooth') -DisableAllChoice '[all]'
            $none.Cancelled | Should -BeFalse
            @($none.Enabled).Count | Should -Be 0

            $some = ConvertFrom-VantaSendToChoice -Output @('Documents;Bluetooth') -AvailableName @('Documents', 'Bluetooth') -DisableAllChoice '[all]'
            $some.Enabled | Should -Be @('Documents', 'Bluetooth')

            { ConvertFrom-VantaSendToChoice -Output @('Documents;[all]') -AvailableName @('Documents') -DisableAllChoice '[all]' } |
                Should -Throw '*cannot be combined*'
            { ConvertFrom-VantaSendToChoice -Output @('Unknown') -AvailableName @('Documents') -DisableAllChoice '[all]' } |
                Should -Throw '*unsupported item*'
            { ConvertFrom-VantaSendToChoice -Output @('Documents;Documents') -AvailableName @('Documents') -DisableAllChoice '[all]' } |
                Should -Throw '*duplicate item*'
            { ConvertFrom-VantaSendToChoice -Output @('a', 'b') -AvailableName @('a') -DisableAllChoice '[all]' } |
                Should -Throw '*2 output lines*'
        }
    }

}

Describe 'Assert-VantaSendToUser' {
    BeforeEach {
        Mock Initialize-VantaRegistryIdentityContext -ModuleName Vanta.Shell
    }

    It 'binds the registry engine to the token SID unless the caller names one' {
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

        InModuleScope Vanta.Shell -Parameters @{ Sid = $sid } {
            Assert-VantaSendToUser -ExpectedUserSid $Sid | Should -BeExactly $Sid
            Assert-VantaSendToUser -ExpectedUserSid '' | Should -BeExactly $Sid
            Assert-VantaSendToUser | Should -BeExactly $Sid
            Assert-VantaSendToUser -ExpectedUserSid 'S-1-5-21-1-2-3-2002' | Should -BeExactly $Sid
        }

        Should -Invoke Initialize-VantaRegistryIdentityContext -ModuleName Vanta.Shell -Times 3 -Exactly -ParameterFilter {
            $CurrentToken -and $ExpectedUserSid -ceq $sid
        }
        # A caller-supplied SID reaches Vanta.Registry unchanged so its mismatch check still runs.
        Should -Invoke Initialize-VantaRegistryIdentityContext -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
            $CurrentToken -and $ExpectedUserSid -ceq 'S-1-5-21-1-2-3-2002'
        }
    }
}

Describe 'Send-To item state' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Shell
    }

    It 'hides and unhides a Send-To file through its hidden attribute' {
        $fixture = Join-Path $TestDrive 'Mail Recipient.MAPIMail'
        [IO.File]::WriteAllText($fixture, 'fixture')

        InModuleScope Vanta.Shell -Parameters @{ Fixture = $fixture } {
            Set-VantaSendToItemState -Name 'Mail recipient' -Path $Fixture -Enabled $false
            ((Get-Item -LiteralPath $Fixture -Force).Attributes -band [IO.FileAttributes]::Hidden) |
                Should -Be ([IO.FileAttributes]::Hidden)

            Set-VantaSendToItemState -Name 'Mail recipient' -Path $Fixture -Enabled $true
            ((Get-Item -LiteralPath $Fixture -Force).Attributes -band [IO.FileAttributes]::Hidden) |
                Should -Be 0
        }
    }

    It 'uses the removable-drive policy for its registry-backed item' {
        Mock Set-VantaRegistryValue -ModuleName Vanta.Shell
        Mock Remove-VantaRegistryValue -ModuleName Vanta.Shell

        InModuleScope Vanta.Shell {
            Set-VantaSendToItemState -Name 'Removable Drives' -Path $null -Enabled $false
            Set-VantaSendToItemState -Name 'Removable Drives' -Path $null -Enabled $true
        }

        Should -Invoke Set-VantaRegistryValue -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -and
            $Name -eq 'NoDrivesInSendToMenu' -and $Type -eq 'DWord' -and $Data -eq 1
        }
        Should -Invoke Remove-VantaRegistryValue -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -and
            $Name -eq 'NoDrivesInSendToMenu'
        }
    }
}

Describe 'Shell context-menu argument helpers' {
    It 'quotes <Name> using Windows argv rules' -TestCases @(
        @{ Name = 'an empty value'; Value = ''; Expected = '""' }
        @{ Name = 'a drive root'; Value = 'C:\'; Expected = '"C:\\"' }
        @{ Name = 'a UNC root'; Value = '\\server\share\'; Expected = '"\\server\share\\"' }
        @{
            Name = 'spaces and a trailing separator'
            Value = 'C:\folder with spaces\'
            Expected = '"C:\folder with spaces\\"'
        }
        @{
            Name = 'an embedded quote'
            Value = 'synthetic\value"with-quote\'
            Expected = '"synthetic\value\"with-quote\\"'
        }
    ) {
        ConvertTo-VantaShellWindowsArgument -Value $Value | Should -BeExactly $Expected
    }

    It 'refuses an argument beyond the Windows command-line length limit' {
        { ConvertTo-VantaShellWindowsArgument -Value ('a' * 32768) } |
            Should -Throw '*command-line length limit*'
    }

    It 'builds non-recursive and recursive native ownership arguments' {
        $file = Get-VantaTakeOwnershipArgumentPlan -TargetType File -TargetPath 'C:\file.txt'
        $directory = Get-VantaTakeOwnershipArgumentPlan -TargetType Directory -TargetPath 'C:\directory' -YesChoice 'Y'
        $drive = Get-VantaTakeOwnershipArgumentPlan -TargetType Drive -TargetPath 'C:\' -YesChoice 'Y'

        $file.TakeOwnArguments | Should -Be @('/f', 'C:\file.txt')
        $file.IcaclsArguments | Should -Contain '/l'
        foreach ($plan in @($directory, $drive)) {
            $plan.TakeOwnArguments | Should -Contain '/r'
            $plan.TakeOwnArguments | Should -Contain '/SKIPSL'
            $plan.IcaclsArguments | Should -Contain '/l'
        }
        $directory.IcaclsArguments | Should -Contain '/q'
        $drive.IcaclsArguments | Should -Not -Contain '/q'
        { Get-VantaTakeOwnershipArgumentPlan -TargetType Directory -TargetPath 'C:\directory' } |
            Should -Throw '*localized affirmative choice*'
    }

    It 'skips a directory the administrator cannot list instead of failing the scan' {
        $root = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'ownership-unlistable')
        $locked = New-Item -ItemType Directory -Path (Join-Path $root.FullName 'locked')
        [IO.File]::WriteAllText((Join-Path $root.FullName 'file.txt'), 'x')
        $acl = Get-Acl -LiteralPath $locked.FullName
        $deny = [Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.WindowsIdentity]::GetCurrent().User,
            [Security.AccessControl.FileSystemRights]::ListDirectory,
            [Security.AccessControl.AccessControlType]::Deny
        )
        $acl.AddAccessRule($deny)
        Set-Acl -LiteralPath $locked.FullName -AclObject $acl
        $linkPath = Join-Path $root.FullName 'a-open\link'

        try {
            { [void][IO.Directory]::GetFileSystemEntries($locked.FullName) } | Should -Throw
            { Assert-VantaTakeOwnershipTree -RootPath $root.FullName } | Should -Not -Throw
            { Assert-VantaTakeOwnershipTree -RootPath $locked.FullName } | Should -Not -Throw

            # 'a-open' is pushed before 'locked', so the scan reaches it only after skipping 'locked'.
            [void](New-Item -ItemType Directory -Path (Join-Path $root.FullName 'a-open'))
            $target = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'ownership-unlistable-target')
            [void](New-Item -ItemType Junction -Path $linkPath -Target $target.FullName)
            { Assert-VantaTakeOwnershipTree -RootPath $root.FullName } |
                Should -Throw '*descendant reparse point*'
        }
        finally {
            if (Test-Path -LiteralPath $linkPath) {
                Remove-Item -LiteralPath $linkPath -Force
            }
            $acl = Get-Acl -LiteralPath $locked.FullName
            [void]$acl.RemoveAccessRule($deny)
            Set-Acl -LiteralPath $locked.FullName -AclObject $acl
        }
    }

    It 'accepts a plain tree and rejects a descendant junction without traversing it' {
        $root = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'ownership-tree')
        [void](New-Item -ItemType Directory -Path (Join-Path $root.FullName 'child'))
        [IO.File]::WriteAllText((Join-Path $root.FullName 'child\file.txt'), 'x')
        { Assert-VantaTakeOwnershipTree -RootPath $root.FullName } | Should -Not -Throw

        $target = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'junction-target')
        $junctionPath = Join-Path $root.FullName 'junction'
        [void](New-Item -ItemType Junction -Path $junctionPath -Target $target.FullName)

        try {
            { Assert-VantaTakeOwnershipTree -RootPath $root.FullName } |
                Should -Throw '*descendant reparse point*'
        }
        finally {
            Remove-Item -LiteralPath $junctionPath -Force
        }
    }
}

Describe 'Set-VantaStartLayout' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Shell
        Mock Get-VantaStartDefaultUserKey -ModuleName Vanta.Shell { $script:defaultUserKey }
        Mock Get-VantaStartWindowsVersion -ModuleName Vanta.Shell {
            [pscustomobject]@{ Build = 26100; Revision = 4770 }
        }
        $script:layoutPath = Join-Path $TestDrive 'StartLayout.json'
        Mock Get-VantaStartLayoutPath -ModuleName Vanta.Shell { $script:layoutPath }
        Set-Content -LiteralPath $script:layoutPath -Encoding UTF8 -Value @'
{ "applyOnce": true, "pinnedList": [ { "packagedAppId": "Microsoft.WindowsCalculator_8wekyb3d8bbwe!App" } ] }
'@
        Remove-Item -Path $script:defaultUserKey -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'accepts the included Start layout' {
        Mock Get-VantaStartLayoutPath -ModuleName Vanta.Shell {
            Join-Path -Path $script:VantaTestRepoRoot -ChildPath 'package\Executables\VantaModules\Other\StartLayout.json'
        }

        { Set-VantaStartLayout } | Should -Not -Throw
    }

    It 'requires a layout that applies once with at least one pin' {
        Set-Content -LiteralPath $script:layoutPath -Encoding UTF8 -Value '{ "applyOnce": false, "pinnedList": [ { } ] }'
        { Set-VantaStartLayout } | Should -Throw '*must apply once*'

        Set-Content -LiteralPath $script:layoutPath -Encoding UTF8 -Value '{ "applyOnce": true, "pinnedList": [] }'
        { Set-VantaStartLayout } | Should -Throw '*must apply once*'

        Set-Content -LiteralPath $script:layoutPath -Encoding UTF8 -Value '{ not json'
        { Set-VantaStartLayout } | Should -Throw '*Start layout is invalid*'

        Remove-Item -LiteralPath $script:layoutPath -Force
        { Set-VantaStartLayout } | Should -Throw '*Start layout is missing*'
    }

    It 'removes the default Start advertisements from the default-user hive' {
        $startKey = "$script:defaultUserKey\SOFTWARE\Microsoft\Windows\CurrentVersion\Start"
        New-Item -Path $startKey -Force | Out-Null
        Set-ItemProperty -LiteralPath $startKey -Name Config -Value ([byte[]]@(1, 2, 3)) -Type Binary
        Set-ItemProperty -LiteralPath $startKey -Name Other -Value 1 -Type DWord

        Set-VantaStartLayout

        Get-TestRegistryValue -Path $startKey -Name Config | Should -BeNullOrEmpty
        Get-TestRegistryValue -Path $startKey -Name Other | Should -Be 1
        { Set-VantaStartLayout } | Should -Not -Throw
    }

    It 'names the exact build that introduced the 24H2 GPO and warns only below it' {
        InModuleScope Vanta.Shell {
            Test-VantaStartPinPolicySupported -Build 26100 -Revision 4769 | Should -BeFalse
            Test-VantaStartPinPolicySupported -Build 26100 -Revision 4770 | Should -BeTrue
            Test-VantaStartPinPolicySupported -Build 26100 -Revision 9000 | Should -BeTrue
            Test-VantaStartPinPolicySupported -Build 26200 -Revision 1 | Should -BeTrue
            Test-VantaStartPinPolicySupported -Build 22631 -Revision 9999 | Should -BeFalse
        }

        Set-VantaStartLayout
        Should -Invoke Write-VantaLog -ModuleName Vanta.Shell -Times 0 -ParameterFilter { $Level -eq 'Warning' }

        Mock Get-VantaStartWindowsVersion -ModuleName Vanta.Shell {
            [pscustomobject]@{ Build = 26100; Revision = 4769 }
        }
        Set-VantaStartLayout
        Should -Invoke Write-VantaLog -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -like '*26100.4769*' -and $Message -like '*26100.4770*'
        }
    }
}

Describe 'Set-VantaTaskbarPins' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Shell
        Mock Test-VantaTaskbarExecutable -ModuleName Vanta.Shell { $true }
        Mock Stop-Process -ModuleName Vanta.Shell
        $script:appData = Join-Path $TestDrive 'AppData'
        Remove-Item -LiteralPath $script:appData -Recurse -Force -ErrorAction SilentlyContinue
        $script:profileAppData = $script:appData
        $script:taskBarFolder = Join-Path $script:appData 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
        New-Item -Path $script:taskBarFolder -ItemType Directory -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $script:taskBarFolder 'Stale.lnk'), 'stale')
        Mock Get-VantaTaskbarProfileTarget -ModuleName Vanta.Shell {
            [pscustomobject]@{
                Sid         = 'S-1-5-21-1-2-3-1001'
                AppData     = $script:profileAppData
                RegistryKey = $script:taskbandKey
            }
        }
        $script:stagedShortcuts = [Collections.Generic.List[string]]::new()
        Mock New-VantaShortcut -ModuleName Vanta.Shell {
            $script:stagedShortcuts.Add($Destination)
            [IO.File]::WriteAllText($Destination, "shortcut to $Source")
        }
        Remove-Item -Path "$script:testRoot\Taskband" -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'replaces the pin folder with File Explorer plus the selected browser and writes the Taskband values' {
        Set-VantaTaskbarPins -Browser 'Brave'

        @(Get-ChildItem -LiteralPath $script:taskBarFolder | ForEach-Object { $_.Name } | Sort-Object) |
            Should -Be @('Brave.lnk', 'File Explorer.lnk')
        $table = InModuleScope Vanta.Shell { Get-VantaTaskbarShortcutTable }
        ConvertTo-TestHexString -Bytes (Get-TestRegistryValue -Path "$script:testRoot\Taskband" -Name Favorites) |
            Should -Be $table['Brave'].RegFavorites
        ConvertTo-TestHexString -Bytes (Get-TestRegistryValue -Path "$script:testRoot\Taskband" -Name FavoritesResolve) |
            Should -Be $table['Brave'].RegFavoritesResolve
        Should -Invoke New-VantaShortcut -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
            $Destination -like '*\File Explorer.lnk' -and $AppUserModelId -eq 'Microsoft.Windows.Explorer'
        }
        Should -Invoke New-VantaShortcut -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
            $Destination -like '*\Brave.lnk' -and $Source -eq $table['Brave'].Path
        }
        Should -Invoke Stop-Process -ModuleName Vanta.Shell -Times 0
    }

    It 'falls back to Microsoft Edge and then to File Explorer alone' {
        Mock Test-VantaTaskbarExecutable -ModuleName Vanta.Shell { $Path -like '*\msedge.exe' }
        Set-VantaTaskbarPins -Browser 'Firefox'

        @(Get-ChildItem -LiteralPath $script:taskBarFolder | ForEach-Object { $_.Name } | Sort-Object) |
            Should -Be @('File Explorer.lnk', 'Microsoft Edge.lnk')
        Should -Invoke Write-VantaLog -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -match "'Firefox' is not installed"
        }

        Mock Test-VantaTaskbarExecutable -ModuleName Vanta.Shell { $false }
        Set-VantaTaskbarPins -Browser 'Unknown Browser'

        @(Get-ChildItem -LiteralPath $script:taskBarFolder | ForEach-Object { $_.Name }) |
            Should -Be @('File Explorer.lnk')
        $table = InModuleScope Vanta.Shell { Get-VantaTaskbarShortcutTable }
        ConvertTo-TestHexString -Bytes (Get-TestRegistryValue -Path "$script:testRoot\Taskband" -Name Favorites) |
            Should -Be $table['File Explorer'].RegFavorites
        Should -Invoke Write-VantaLog -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -match "'Unknown Browser' is not a supported taskbar pin"
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -match 'Microsoft Edge is not installed'
        }
    }

    It 'skips a profile without an AppData directory and still removes its staging directory' {
        $script:profileAppData = Join-Path $TestDrive 'missing-appdata'

        Set-VantaTaskbarPins

        Should -Invoke Write-VantaLog -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -like '*skipping taskbar pin cleanup*'
        }
        Test-Path -LiteralPath "$script:testRoot\Taskband" | Should -BeFalse
        (Get-ChildItem -LiteralPath $script:taskBarFolder).Name | Should -Be 'Stale.lnk'
        $script:stagedShortcuts.Count | Should -BeGreaterThan 0
        foreach ($staged in $script:stagedShortcuts) {
            Test-Path -LiteralPath (Split-Path -Parent $staged) | Should -BeFalse
        }
    }

    It 'removes the staging directory even when a Taskband write fails' {
        Mock Set-VantaRegistryValue -ModuleName Vanta.Shell { throw 'registry write failed' }

        { Set-VantaTaskbarPins } | Should -Throw '*registry write failed*'
        $script:stagedShortcuts.Count | Should -BeGreaterThan 0
        foreach ($staged in $script:stagedShortcuts) {
            Test-Path -LiteralPath (Split-Path -Parent $staged) | Should -BeFalse
        }
    }

    It 'fails pinning when Windows refuses a Taskband write' {
        # The real Set-VantaRegistryValue runs, so a Taskband write that allowed an
        # OS-protected refusal would log it and report success with the old pins.
        Mock Write-VantaLog -ModuleName Vanta.Registry
        $script:taskbandRefusal = InModuleScope Vanta.Registry {
            New-VantaRegistryValueRefusedRecord -ProviderPath 'HKEY_CURRENT_USER\Software\VantaRewriteTest\Taskband' `
                -Name 'Favorites' -Cause ([UnauthorizedAccessException]::new('denied'))
        }
        Mock Set-VantaRegistryValueCore -ModuleName Vanta.Registry { throw $script:taskbandRefusal }

        { Set-VantaTaskbarPins } | Should -Throw -ErrorId 'VantaRegistryValueWriteRefused'
        Should -Invoke Set-VantaRegistryValueCore -ModuleName Vanta.Registry -Times 1 -Exactly
        $script:stagedShortcuts.Count | Should -BeGreaterThan 0
        foreach ($staged in $script:stagedShortcuts) {
            Test-Path -LiteralPath (Split-Path -Parent $staged) | Should -BeFalse
        }
    }

    It 'converts a recorded Taskband hex string to its bytes and rejects malformed data' {
        InModuleScope Vanta.Shell {
            $bytes = ConvertFrom-VantaTaskbarHexString -Hex 'FF00ab'
            $bytes.GetType() | Should -Be ([byte[]])
            $bytes | Should -Be @([byte]0xFF, [byte]0x00, [byte]0xAB)
            { ConvertFrom-VantaTaskbarHexString -Hex 'ABC' } | Should -Throw '*even-length hexadecimal*'
            { ConvertFrom-VantaTaskbarHexString -Hex '0G' } | Should -Throw '*even-length hexadecimal*'
        }
    }
}

Describe 'Add-VantaMusicVideosToHome' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Shell
        $global:VantaShellHomeTest = @{
            Pins        = @()
            Invocations = [Collections.Generic.List[string]]::new()
            HomeMissing = $false
        }
        Mock Get-VantaShellApplication -ModuleName Vanta.Shell {
            $shell = [pscustomobject]@{}
            $shell | Add-Member -MemberType ScriptMethod -Name Namespace -Value {
                param($Path)

                if ($Path -eq 'shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}') {
                    if ($global:VantaShellHomeTest.HomeMissing) {
                        return $null
                    }
                    $homeNamespace = [pscustomobject]@{}
                    $homeNamespace | Add-Member -MemberType ScriptMethod -Name Items -Value {
                        @($global:VantaShellHomeTest.Pins | ForEach-Object { [pscustomobject]@{ Path = $_ } })
                    }
                    return $homeNamespace
                }

                $self = [pscustomobject]@{ Path = $Path }
                $self | Add-Member -MemberType ScriptMethod -Name InvokeVerb -Value {
                    param($Verb)
                    $global:VantaShellHomeTest.Invocations.Add("$Verb|$($this.Path)")
                }
                return [pscustomobject]@{ Self = $self }
            }
            return $shell
        }
        $script:videosFolder = (New-Item -ItemType Directory -Path (Join-Path $TestDrive 'Videos') -Force).FullName
        $script:musicFolder = (New-Item -ItemType Directory -Path (Join-Path $TestDrive 'Music') -Force).FullName
        $script:missingFolder = Join-Path $TestDrive 'Unavailable\Videos'
        Mock Get-VantaHomeFolderCandidate -ModuleName Vanta.Shell {
            [pscustomobject]@{ Name = 'Videos'; Path = $script:videosFolder }
            [pscustomobject]@{ Name = 'Music'; Path = $script:musicFolder }
        }
    }

    AfterEach {
        Remove-Variable -Name VantaShellHomeTest -Scope Global -ErrorAction SilentlyContinue
    }

    It 'pins the Videos and Music folders in order when neither is pinned yet' {
        Add-VantaMusicVideosToHome

        @($global:VantaShellHomeTest.Invocations) |
            Should -Be @("pintohome|$script:videosFolder", "pintohome|$script:musicFolder")
        Should -Invoke Write-VantaLog -ModuleName Vanta.Shell -Times 0 -ParameterFilter { $Level -eq 'Warning' }
    }

    It 'leaves a folder alone that Home already lists' {
        $global:VantaShellHomeTest.Pins = @($script:videosFolder)

        Add-VantaMusicVideosToHome

        @($global:VantaShellHomeTest.Invocations) | Should -Be @("pintohome|$script:musicFolder")
    }

    It 'skips and names a missing folder but still pins the other' {
        Mock Get-VantaHomeFolderCandidate -ModuleName Vanta.Shell {
            [pscustomobject]@{ Name = 'Videos'; Path = $script:missingFolder }
            [pscustomobject]@{ Name = 'Music'; Path = $script:musicFolder }
        }
        Add-VantaMusicVideosToHome
        @($global:VantaShellHomeTest.Invocations) | Should -Be @("pintohome|$script:musicFolder")
        Should -Invoke Write-VantaLog -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -like '*Videos folder*'
        }

        # Windows reports a known folder that doesn't exist as an empty path.
        $global:VantaShellHomeTest.Invocations.Clear()
        Mock Get-VantaHomeFolderCandidate -ModuleName Vanta.Shell {
            [pscustomobject]@{ Name = 'Videos'; Path = $script:videosFolder }
            [pscustomobject]@{ Name = 'Music'; Path = '' }
        }
        Add-VantaMusicVideosToHome
        @($global:VantaShellHomeTest.Invocations) | Should -Be @("pintohome|$script:videosFolder")
        Should -Invoke Write-VantaLog -ModuleName Vanta.Shell -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -like '*Music folder*'
        }
    }

    It 'fails when the Home namespace cannot be opened' {
        $global:VantaShellHomeTest.HomeMissing = $true

        { Add-VantaMusicVideosToHome } | Should -Throw '*File Explorer Home namespace*'
    }
}

Describe 'Vanta.Shell tweak bindings' {
    It 'runs <Definition> as the non-elevated user' -ForEach @(
        @{ Definition = 'scripts\set-file-associations.psd1' }
        @{ Definition = 'qol\explorer\debloat-send-to.psd1' }
    ) {
        $path = Join-Path $script:tweaksRoot $Definition
        $tweak = Import-PowerShellDataFile -LiteralPath $path

        $tweak.RunAs | Should -BeExactly 'User'
    }
}
