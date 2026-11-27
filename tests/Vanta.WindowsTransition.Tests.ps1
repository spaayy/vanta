[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter',
    '',
    Justification = 'The machine doubles declare the parameter surface of the commands they stand in for.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidOverwritingBuiltInCmdlets',
    '',
    Justification = 'The registry cmdlets are shadowed so no test can reach the live HKLM policy key.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseSingularNouns',
    '',
    Justification = 'The doubles keep the names of the module commands they stand in for.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    '',
    Justification = 'Worker switches are read by the worker functions through dynamic scope.'
)]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $script:Library = Join-Path $script:VantaTestScriptsRoot 'Preparation\WindowsTransition.ps1'
    . (Join-Path $script:VantaTestScriptsRoot 'Preparation\Update-Windows.ps1') -JobPath $TestDrive -FunctionsOnly

    $script:Policy = 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $script:Ux = 'SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    $script:PauseKey = 'SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings'
    $script:Services = 'SYSTEM\CurrentControlSet\Services'
    $script:Record = 'SOFTWARE\Vanta\WindowsTransition'

    # An in-memory HKLM: every registry and service access of the library goes
    # through these doubles, which also record each change in order.
    function Reset-Machine {
        $script:Registry = @{}
        $script:Tasks = @{ 'Microsoft\Windows\WindowsUpdate\sih' = 'Enabled'; 'Microsoft\Windows\WindowsUpdate\sihboot' = 'Enabled' }
        $script:Writes = [Collections.Generic.List[string]]::new()
        $script:FailWrite = @{}
        $script:Packages = @('Z-Vanta-NoTelemetry-Package~31bf3856ad364e35~amd64~~5.0.0.0')
        $script:FreeBytes = 40GB
        $script:Health = 'Healthy'
        $script:Windows = [pscustomobject]@{ CurrentBuildNumber = '26100'; UBR = 9550; DisplayVersion = '24H2'; EditionID = 'Professional' }
        $script:BootId = 7
        $script:Copy = $null
        $script:CbsLines = @()
        $script:ToggleRecords = @{}
        $script:RebuildFacts = [pscustomobject]@{ WindowsOld = $false; SetupFolder = $false; PantherWritten = $false; VantaModules = $true }
        Set-Fake $script:Services\BITS Start DWord 3
        Set-Fake $script:Services\CryptSvc Start DWord 3
        Set-Fake $script:Services\TrustedInstaller Start DWord 3
        Set-Fake $script:Services\wuauserv Start DWord 3
        Set-Fake $script:Services\UsoSvc Start DWord 2
        Set-Fake 'SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' BootId DWord 7
        $script:Writes.Clear()
    }
    function Set-Fake([string]$Path, [string]$Name, [string]$Kind, $Data) {
        $script:Registry["$Path|$Name"] = [pscustomobject]@{ Kind = $Kind; Data = $Data }
    }
    function Get-Fake([string]$Path, [string]$Name) { $script:Registry["$Path|$Name"] }
    function Get-VantaTransitionValue([string]$Path, [string]$Name) {
        $entry = $script:Registry["$Path|$Name"]
        if ($null -eq $entry) { return [pscustomobject]@{ Present = $false; Kind = $null; Data = $null } }
        return [pscustomobject]@{ Present = $true; Kind = $entry.Kind; Data = $entry.Data }
    }
    function Set-VantaTransitionValue([string]$Path, [string]$Name, [string]$Kind, $Data) {
        $script:Writes.Add("set $Path|$Name")
        if ($script:FailWrite.ContainsKey("$Path|$Name")) { return }
        Set-Fake $Path $Name $Kind $Data
    }
    function Remove-VantaTransitionValue([string]$Path, [string]$Name) {
        $script:Writes.Add("remove $Path|$Name")
        if ($script:FailWrite.ContainsKey("$Path|$Name")) { return }
        $script:Registry.Remove("$Path|$Name")
    }
    function Test-VantaTransitionKey([string]$Path) {
        foreach ($key in $script:Registry.Keys) { if ($key.StartsWith("$Path|") -or $key.StartsWith("$Path\")) { return $true } }
        return $false
    }
    function Get-VantaTransitionSubKeyName([string]$Path) {
        @($script:Registry.Keys | Where-Object { $_.StartsWith("$Path\") } |
                ForEach-Object { ($_.Substring($Path.Length + 1) -split '[\\|]')[0] } | Sort-Object -Unique)
    }
    function New-VantaTransitionJournalKey([string]$Path) { }
    function Set-VantaTransitionServiceStart([string]$Name, [int]$Start) {
        $script:Writes.Add("service $Name $Start")
        Set-Fake "$script:Services\$Name" Start DWord $Start
    }
    function Start-VantaTransitionService([string]$Name) { $script:Writes.Add("start $Name") }
    function Get-VantaTransitionTask([string]$Path, [string]$Name) {
        $state = $script:Tasks["$Path\$Name"]
        if ($null -eq $state) { return [pscustomobject]@{ Present = $false; Kind = $null; Data = $null } }
        return [pscustomobject]@{ Present = $true; Kind = 'Task'; Data = $state }
    }
    function Set-VantaTransitionTask([string]$Path, [string]$Name, [string]$State) {
        $script:Writes.Add("task $Name $State")
        $script:Tasks["$Path\$Name"] = $State
    }
    function Stop-VantaTransitionService([string]$Name) { $script:Writes.Add("stop $Name") }
    function Get-VantaInstalledVantaPackage { $script:Packages }
    function Get-VantaTransitionCbsLogTail { $script:CbsLines }
    function Write-VantaTransitionCopy([string]$Json) { $script:Writes.Add('write copy'); $script:Copy = $Json }
    function Read-VantaTransitionCopy { $script:Copy }
    function Remove-VantaTransitionCopy { $script:Writes.Add('remove copy'); $script:Copy = $null }
    function Get-VantaTransitionRebuildFact([DateTime]$Since, [string]$WindowsPath) { $script:RebuildFacts }
    function Get-VantaTransitionCarry([string[]]$VantaPackages) { ConvertTo-VantaTransitionCarry (New-Vanta050Fact) $VantaPackages }
    function Get-VantaToggleStateRecords { $script:ToggleRecords.Clone() }
    function Set-VantaToggleState([string]$Name, [int]$State) { $script:Writes.Add("toggle $Name $State"); $script:ToggleRecords[$Name] = $State }
    function Repair-VantaToolboxRecord([string]$InstalledVersion) { $script:Writes.Add("repair $InstalledVersion") }
    # What Vanta 0.5.0 leaves that the record keeps: its markers, the toggle records
    # its choices wrote, Edge and Snipping Tool removed, OneDrive gone.
    function New-Vanta050Fact {
        [pscustomobject]@{
            State = $null; LegacyVersions = @('0.5.0')
            Toggles = @(
                [pscustomobject]@{ name = 'Mitigations'; state = 2; path = 'Enable All Mitigations.cmd' }
                [pscustomobject]@{ name = 'AutomaticUpdates'; state = 0 }
                [pscustomobject]@{ name = 'Hibernation'; state = 0 }
                [pscustomobject]@{ name = 'PowerSaving'; state = 1 }
                [pscustomobject]@{ name = 'FileSharing'; state = 0 }
            )
            Browser = 'Brave'; VantaModules = $true; Edge = $false; OneDrive = $false; Defender = $false
            Appx = @('Microsoft.WindowsCalculator_8wekyb3d8bbwe', 'Microsoft.Paint_8wekyb3d8bbwe')
            Toolbox = $true; CoreIsolationOff = $true; Browsers = @('browser-brave')
        }
    }
    function Get-VantaTransitionFreeSpace { $script:FreeBytes }
    function Get-VantaTransitionImageHealth { if ($script:Health -eq 'Throws') { throw 'DISM is unavailable' }; $script:Health }
    function Invoke-PreparationRestoreHealth { throw 'A test started DISM without standing in for it.' }

    # The pin writer uses the registry cmdlets; HKLM paths go to the double too.
    function ConvertTo-FakePath([string]$Path) { $Path -replace '^HKLM:\\', '' }
    function Test-Path {
        param([string]$LiteralPath, [string]$Path, $PathType)
        $target = if ($LiteralPath) { $LiteralPath } else { $Path }
        if ($target -like 'HKLM:*') { return Test-VantaTransitionKey (ConvertTo-FakePath $target) }
        Microsoft.PowerShell.Management\Test-Path -LiteralPath $target
    }
    function New-Item {
        param([string]$Path, $ItemType, [switch]$Force)
        if ($Path -notlike 'HKLM:*') { throw "Unexpected New-Item $Path" }
        $script:Writes.Add("create $(ConvertTo-FakePath $Path)")
        Set-Fake (ConvertTo-FakePath $Path) '(key)' 'Key' ''
    }
    function New-ItemProperty {
        param([string]$Path, [string]$Name, $Value, [string]$PropertyType, [switch]$Force)
        if ($Path -notlike 'HKLM:*') { throw "Unexpected New-ItemProperty $Path" }
        Set-VantaTransitionValue (ConvertTo-FakePath $Path) $Name $PropertyType $Value
    }
    function Get-ItemProperty {
        param([string]$LiteralPath, [string]$Path, $Name, $ErrorAction)
        $target = ConvertTo-FakePath $(if ($LiteralPath) { $LiteralPath } else { $Path })
        if ($target -eq 'SOFTWARE\Microsoft\Windows NT\CurrentVersion') { return $script:Windows }
        $values = [ordered]@{}
        foreach ($key in $script:Registry.Keys) {
            $parts = $key -split '\|', 2
            if ($parts[0] -eq $target -and $parts[1] -ne '(key)') { $values[$parts[1]] = $script:Registry[$key].Data }
        }
        if ($values.Count -eq 0) { return $null }
        return [pscustomobject]$values
    }
    foreach ($double in @('Get-VantaTransitionValue', 'Get-VantaTransitionSubKeyName', 'Set-VantaTransitionValue', 'Remove-VantaTransitionValue', 'Set-VantaTransitionServiceStart', 'Set-VantaTransitionTask', 'New-ItemProperty', 'Write-VantaTransitionCopy', 'Remove-VantaTransitionCopy', 'Set-VantaToggleState', 'Repair-VantaToolboxRecord')) {
        if ((Get-Command -Name $double -CommandType Function).ScriptBlock.ToString() -notmatch 'script:(Registry|Writes|Tasks)|Set-VantaTransitionValue') {
            throw "$double is not the in-memory double; no test may reach the live registry."
        }
    }

    function Read-Journal { (Get-Fake $script:Record 'Journal').Data | ConvertFrom-Json }
    function Get-Item-Value([string]$Path, [string]$Name) { $entry = Get-Fake $Path $Name; if ($entry) { $entry.Data } }

    # Vanta 0.5.0's "Disable Windows Updates": wuauserv stopped and disabled, the
    # sih and sihboot tasks disabled, and its choice recorded.
    function Set-Vanta050UpdatesOff {
        Set-Fake "$script:Services\wuauserv" Start DWord 4
        $script:Tasks['Microsoft\Windows\WindowsUpdate\sih'] = 'Disabled'
        $script:Tasks['Microsoft\Windows\WindowsUpdate\sihboot'] = 'Disabled'
        Set-Fake 'SOFTWARE\Vanta\Services\ToggleWindowsUpdates' state DWord 0
        Set-Fake 'SOFTWARE\Vanta\Services\ToggleWindowsUpdates' path String 'C:\Windows\VantaDesktop\3. General Configuration\Windows Updates\Toggle Windows Updates.cmd'
    }

    # Windows Update turned off and paused as Vanta 0.6's own toggles do it, or as
    # a user's tools can, on a PC that still has Vanta 0.5.0's malformed pin.
    function Set-HeldBackUpdate {
        Set-Fake $script:Policy DisableWindowsUpdateAccess DWord 1
        Set-Fake $script:Policy DoNotConnectToWindowsUpdateInternetLocations DWord 1
        Set-Fake "$script:Policy\AU" NoAutoUpdate DWord 1
        Set-Fake "$script:Services\wuauserv" Start DWord 4
        Set-Fake "$script:Services\UsoSvc" Start DWord 4
        Set-Fake "$script:Services\WaaSMedicSvc" Start DWord 4
        $script:Tasks['Microsoft\Windows\WindowsUpdate\sih'] = 'Disabled'
        Set-Fake $script:PauseKey PausedFeatureStatus DWord 1
        Set-Fake $script:PauseKey PausedQualityStatus DWord 1
        Set-Fake $script:Ux PauseUpdatesExpiryTime String '3000-12-31T14:03:37Z'
        Set-Fake $script:Ux PauseFeatureUpdatesStartTime String '2001-10-25T10:03:37Z'
        Set-Fake $script:Ux FlightSettingsMaxPauseDays DWord 356000
        Set-Fake $script:Ux HideMCTLink DWord 1
        Set-Fake $script:Ux RestartNotificationsAllowed2 DWord 0
        Set-Fake 'SYSTEM\Setup\UpgradeNotification' UpgradeAvailable DWord 0
        Set-Fake 'SOFTWARE\Vanta\Services\ToggleWindowsUpdates' state DWord 0
        Set-Fake 'SOFTWARE\Vanta\Services\PauseUpdates' state DWord 1
        # 0.5.0's malformed pin: a string where Windows expects 1, and no release.
        Set-Fake $script:Policy TargetReleaseVersion String '24H2'
        Set-Fake $script:Policy ProductVersion String 'Windows 11'
        Set-Fake $script:Policy ManagePreviewBuilds DWord 1
    }

    function Use-TransitionRun {
        Set-Variable -Scope 1 -Name WindowsTarget -Value '26H2'
        Set-Variable -Scope 1 -Name TargetBuild -Value 26300
        Set-Variable -Scope 1 -Name SourceBuilds -Value '26100,26200'
        Set-Variable -Scope 1 -Name FeatureKb -Value '5121794,5129195'
        Set-Variable -Scope 1 -Name PrerequisiteKb -Value '5124010'
        Set-Variable -Scope 1 -Name MinimumRevision -Value 9546
        Set-Variable -Scope 1 -Name AcceptLicense -Value ([switch]$true)
    }

    function New-Offer {
        param([string]$Title, [string[]]$Kb = @(), [switch]$Upgrade, [switch]$BrowseOnly, [bool]$Eula = $true, [int]$Type = 1)
        $category = if ($Upgrade) { [pscustomobject]@{ CategoryID = '3689bdc8-b205-4af4-8d4a-a63924c5e9d5'; Name = 'Upgrades' } }
        else { [pscustomobject]@{ CategoryID = '0fa1201d-4330-4fa8-8ae9-b877473b6441'; Name = 'Security Updates' } }
        $offer = [pscustomobject]@{
            Title = $Title; KBArticleIDs = $Kb; Categories = @($category); BrowseOnly = [bool]$BrowseOnly
            IsMandatory = $false; EulaAccepted = $Eula; DeploymentAction = 'Installation'; Type = $Type; MaxDownloadSize = 96GB
            InstallationBehavior = [pscustomobject]@{ RebootBehavior = 1; Impact = 0; CanRequestUserInput = $false }
            Identity = [pscustomobject]@{ UpdateID = [guid]::NewGuid().ToString(); RevisionNumber = 1 }
        }
        $offer | Add-Member ScriptMethod AcceptEula { $this.EulaAccepted = $true; $script:EulaAccepted++ }
        return $offer
    }
    function New-Result([int]$Code = 2, [int]$HResult = 0, [bool]$Restart = $true) {
        $result = [pscustomobject]@{ ResultCode = $Code; HResult = $HResult; RebootRequired = $Restart }
        $result | Add-Member ScriptMethod GetUpdateResult { param($Index) [pscustomobject]@{ ResultCode = $this.ResultCode; HResult = $this.HResult } }
        return $result
    }
    function New-Session {
        $session = [pscustomobject]@{ ClientApplicationID = '' }
        $session | Add-Member ScriptMethod CreateUpdateDownloader { [pscustomobject]@{ Updates = $null } }
        $session | Add-Member ScriptMethod CreateUpdateInstaller {
            $script:Installer = [pscustomobject]@{ Updates = $null; ForceQuiet = $false; AllowSourcePrompts = $true; RebootRequiredBeforeInstallation = $false }
            $script:Installer
        }
        return $session
    }
}

Describe 'Power-saving choice before a Windows move' {
    BeforeEach { Reset-Machine }
    It 'preserves the real power choice: <name>' -ForEach @(
        (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\windows-transition\power-saving-records.json') -Raw | ConvertFrom-Json) |
            ForEach-Object { @{ name = $_.name; active = $_.active; record = $_.record; expected = $_.expected } }
    ) {
        if ($null -ne $active) { Set-Fake 'SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' ActivePowerScheme String $active }
        if ($active -ieq '11111111-1111-1111-1111-111111111111') { Set-Fake 'SOFTWARE\Vanta\Services\PowerSaving' VantaPowerSchemeGuid String $active }   # o GUID que o Vanta registrou
        if ($null -ne $record) { Set-Fake 'SOFTWARE\Vanta\Services\PowerSaving' state DWord ([int64]$record) }
        $records = @(Get-VantaTransitionToggleRecord | Where-Object name -eq PowerSaving)
        if ($null -eq $expected) { $records | Should -HaveCount 0 }
        else { $records | Should -HaveCount 1; $records[0].state | Should -Be $expected }
        $script:Writes.Count | Should -Be 0
        $facts = New-Vanta050Fact
        $facts.Toggles = @(Get-VantaTransitionToggleRecord)
        $options = @(Get-VantaTransitionObservedOption $facts @())
        ($options -ccontains 'disable-power-saving') | Should -Be ($null -ne $expected -and $expected -eq 0)
    }
}

Describe 'Power-saving evidence never trusts a fixed GUID' {
    BeforeEach { Reset-Machine }
    It 'an active plan with the old fixed GUID that Vanta did not record (Atlas) is not the Vanta plan' {
        Set-Fake 'SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' ActivePowerScheme String '11111111-1111-1111-1111-111111111111'
        Set-Fake 'SOFTWARE\Vanta\Services\PowerSaving' state DWord 1
        $records = @(Get-VantaTransitionToggleRecord | Where-Object name -eq PowerSaving)
        $records | Should -HaveCount 1
        $records[0].state | Should -Be 1
    }
}

Describe 'Legacy automatic-update record recovery' {
    BeforeEach { Reset-Machine }
    It 'reads the real update policy when a CPU menu launcher overwrote its record' -ForEach @(
        @{ Kind = 'DWord'; Data = 2; Expected = 0 }
        @{ Kind = 'DWord'; Data = 4; Expected = 1 }
        @{ Kind = 'absent'; Data = 0; Expected = 1 }
        @{ Kind = 'String'; Data = '2'; Expected = $null }
        @{ Kind = 'DWord'; Data = 9; Expected = $null }
    ) {
        if ($Kind -ne 'absent') { Set-Fake 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'AUOptions' $Kind $Data }
        Get-VantaTransitionAutomaticUpdatesPolicyState | Should -Be $Expected
        $script:Writes.Count | Should -Be 0
    }
    It 'reads the same AutomaticUpdates record as the app: <name>' -ForEach @(
        (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\windows-transition\legacy-automatic-updates.json') -Raw | ConvertFrom-Json) |
            ForEach-Object { @{ name = $_.name; state = $_.state; launcher = $_.launcher; policy = $_.policy; record = $_.record } }
    ) {
        $recordKey = 'SOFTWARE\Vanta\Services\AutomaticUpdates'
        Set-Fake $recordKey state DWord ([int64]$state)
        if ($null -ne $launcher) { Set-Fake $recordKey path String $launcher }
        if ($null -ne $policy) { Set-Fake 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'AUOptions' $policy.kind $policy.data }
        $records = @(Get-VantaTransitionToggleRecord | Where-Object { $_.name -eq 'AutomaticUpdates' })
        if ($null -eq $record) { $records | Should -HaveCount 0 }
        else { $records | Should -HaveCount 1; $records[0].state | Should -Be $record }
    }
}

AfterAll {
    foreach ($shadow in @('Test-Path', 'New-Item', 'New-ItemProperty', 'Get-ItemProperty')) {
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath "Function:\$shadow" -ErrorAction SilentlyContinue
    }
}

Describe 'Windows transition library' {
    It 'leaves PowerShell module resolution and loaded modules as it found them' {
        $probe = Join-Path $TestDrive 'hygiene.ps1'
        [IO.File]::WriteAllText($probe, @'
param([string]$Library)
$env:PSModulePath = 'C:\vanta-sentinel-path'
$before = @(Get-Module).Count
. $Library
[Console]::WriteLine('PATH:' + $env:PSModulePath)
[Console]::WriteLine('MODULES:' + (@(Get-Module).Count - $before))
[Console]::WriteLine('FUNCTIONS:' + @(Get-ChildItem Function:\ | Where-Object Name -like '*VantaWindowsTransition*').Count)
'@)
        $output = & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probe -Library $script:Library
        ($output -join "`n") | Should -Match 'PATH:C:\\vanta-sentinel-path'
        ($output -join "`n") | Should -Match 'MODULES:0'
        ($output -join "`n") | Should -Match 'FUNCTIONS:[1-9]'
    }

    It 'lists exactly the items in the fixture the app also checks' {
        $fixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\windows-transition\items.json') -Raw | ConvertFrom-Json
        $items = @(& { . $script:Library; Get-VantaWindowsTransitionItem })
        $items.Count | Should -Be @($fixture).Count
        for ($i = 0; $i -lt $items.Count; $i++) {
            $expected = $fixture[$i]
            $items[$i].Id | Should -BeExactly $expected.id
            $items[$i].Group | Should -BeExactly $expected.group
            $items[$i].Path | Should -BeExactly $expected.path
            $items[$i].Name | Should -BeExactly $expected.name
            (@($items[$i].Kinds) -join ',') | Should -BeExactly (@($expected.kinds) -join ',')
            $items[$i].Lift | Should -Be $expected.lift
            $items[$i].Owner | Should -Be $expected.owner
            $items[$i].Rule | Should -BeExactly $expected.rule
        }
    }

    It 'never lists what is not a Windows Update blocker or belongs to the toggle store' {
        $paths = @(Get-VantaWindowsTransitionItem | ForEach-Object { "$($_.Path)\$($_.Name)" })
        foreach ($forbidden in @('HideMCTLink', 'RestartNotificationsAllowed2', 'UpgradeAvailable', 'WaaSMedicSvc', 'DisableWUfBSafeguards', 'SettingsPageVisibility', 'DeferFeatureUpdates', 'AUOptions', 'VantaOS')) {
            @($paths | Where-Object { $_ -match [regex]::Escape($forbidden) }) | Should -BeNullOrEmpty -Because "$forbidden must never be lifted"
        }
    }
}

Describe 'Windows Update blockers' {
    BeforeEach { Reset-Machine }

    It 'finds what the update toggles hold back and whether a recorded choice owns it' {
        Set-HeldBackUpdate
        $blockers = @(Get-VantaWindowsUpdateBlocker)
        $ids = @($blockers.Id)
        foreach ($id in @('policy.DisableWindowsUpdateAccess', 'policy.DoNotConnectToWindowsUpdateInternetLocations', 'policy.AU.NoAutoUpdate',
                'service.wuauserv', 'service.UsoSvc', 'pause.PausedFeatureStatus', 'pause.PausedQualityStatus',
                'pause.PauseUpdatesExpiryTime', 'pause.PauseFeatureUpdatesStartTime', 'pause.FlightSettingsMaxPauseDays')) {
            $ids | Should -Contain $id
        }
        @($blockers | Where-Object { -not $_.OwnerRecord }) | Should -BeNullOrEmpty
    }

    It 'ignores a pause that has ended and settings at their open values' {
        Set-Fake $script:PauseKey PausedFeatureStatus DWord 0
        Set-Fake $script:Ux PauseUpdatesExpiryTime String '2020-01-01T00:00:00Z'
        Set-Fake $script:Ux PauseUpdatesStartTime String '2019-12-01T00:00:00Z'
        Set-Fake $script:Policy DisableWindowsUpdateAccess DWord 0
        Set-Fake "$script:Services\wuauserv" Start DWord 3
        @(Get-VantaWindowsUpdateBlocker) | Should -BeNullOrEmpty
    }

    It 'counts a 0.5.0 quality-update delay without an owner record' {
        Set-Fake $script:Policy DeferQualityUpdates DWord 1
        Set-Fake $script:Policy DeferQualityUpdatesPeriodInDays DWord 30
        $blockers = @(Get-VantaWindowsUpdateBlocker)
        @($blockers.Id) | Should -Be @('policy.DeferQualityUpdates', 'policy.DeferQualityUpdatesPeriodInDays')
        @($blockers | Where-Object OwnerRecord) | Should -BeNullOrEmpty
    }
}

Describe 'The record of what Vanta changes' {
    BeforeEach { Reset-Machine; Set-HeldBackUpdate }

    It 'records type and absence, including a string target and a missing release, before changing anything' {
        $journal = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) `
            -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794' }) -UserSid 'S-1-5-21-1-2-3-1001' -VantaPackages $script:Packages
        @($script:Writes) | Should -Be @("set $script:Record|Journal", 'write copy')
        $saved = Read-Journal
        $entry = @($saved.items | Where-Object id -eq 'pin.TargetReleaseVersion')[0]
        $entry.present | Should -BeTrue
        $entry.kind | Should -BeExactly 'String'
        $entry.data | Should -BeExactly '24H2'
        $entry.lifted | Should -BeFalse
        @($saved.items | Where-Object id -eq 'pin.TargetReleaseVersionInfo')[0].present | Should -BeFalse
        @($saved.items | Where-Object id -eq 'service.wuauserv')[0].data | Should -Be 4
        @($saved.items | Where-Object id -eq 'policy.DisableWindowsUpdateAccess')[0].lifted | Should -BeTrue
        $saved.phase | Should -BeExactly 'lifted'
        @($saved.vantaPackages) | Should -Be $script:Packages
        $journal.kind | Should -BeExactly 'transition'
    }

    It 'keeps the first record on a rerun, so lifted values never become the originals' {
        $target = [pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794' }
        $journal = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) -Target $target -UserSid 'S'
        Invoke-VantaWindowsUpdateLift $journal
        $again = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) -Target $target -UserSid 'S'
        @($again.items | Where-Object id -eq 'policy.DisableWindowsUpdateAccess')[0].data | Should -Be 1
        @((Read-Journal).items | Where-Object id -eq 'service.wuauserv')[0].data | Should -Be 4
    }

    It 'adds the pin originals when a plain update''s record becomes a move' {
        $access = Save-VantaWindowsTransitionSnapshot -Kind access -Source ([pscustomobject]@{ build = 26200 }) -Target $null -UserSid 'S'
        @($access.items | Where-Object id -like 'pin.*') | Should -BeNullOrEmpty
        Invoke-VantaWindowsUpdateLift $access
        $moved = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26200 }) `
            -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794' }) -UserSid 'S' -VantaPackages $script:Packages
        $moved.kind | Should -BeExactly 'transition'
        @($moved.items | Where-Object id -eq 'pin.TargetReleaseVersion')[0].data | Should -BeExactly '24H2'
        @($moved.items | Where-Object id -eq 'policy.DisableWindowsUpdateAccess')[0].data | Should -Be 1 -Because 'the first record''s originals stay'
    }

    It 'records a blocker that appeared after the record with its value then' {
        Reset-Machine
        $journal = Save-VantaWindowsTransitionSnapshot -Kind access -Source ([pscustomobject]@{ build = 26200 }) -Target $null -UserSid 'S'
        @($journal.items | Where-Object lifted) | Should -BeNullOrEmpty
        # An earlier Vanta's launcher turns Windows Update off again.
        Set-Fake $script:Policy DisableWindowsUpdateAccess DWord 1
        Update-VantaTransitionLiftSet $journal
        $entry = @((Read-Journal).items | Where-Object id -eq 'policy.DisableWindowsUpdateAccess')[0]
        $entry.lifted | Should -BeTrue
        $entry.data | Should -Be 1
        Invoke-VantaWindowsUpdateLift (Read-Journal)
        Get-Fake $script:Policy DisableWindowsUpdateAccess | Should -BeNullOrEmpty
    }

    It 'refuses to start a move when a pin value can''t be recorded, before changing anything' {
        Set-Fake $script:Policy TargetReleaseVersionInfo String 'C:\evil'
        $script:Writes.Clear()
        $thrown = $null
        try {
            [void](Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) `
                -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794' }) -UserSid 'S')
        }
        catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly 'feature-pin'
        $thrown.Data['setting'] | Should -BeExactly 'TargetReleaseVersionInfo'
        @($script:Writes) | Should -BeNullOrEmpty
    }

    It 'records a pin written in lower case, as Windows reads it' {
        Set-Fake $script:Policy TargetReleaseVersionInfo String '24h2'
        $journal = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) `
            -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794' }) -UserSid 'S'
        @($journal.items | Where-Object id -eq 'pin.TargetReleaseVersionInfo')[0].data | Should -BeExactly '24h2'
    }

    It 'refuses a record missing an item''s flag as not valid, under the worker''s strict mode' {
        $journal = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) `
            -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794' }) -UserSid 'S'
        @($journal.items)[0].PSObject.Properties.Remove('lifted')
        Set-StrictMode -Version 3.0
        try { [void](Test-VantaWindowsTransitionJournal $journal) } catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly 'feature-journal'
    }

    It 'refuses a record that names <Case> and changes nothing' -TestCases @(
        @{ Case = 'an unknown item'; Mutate = { param($j) $j.items += [pscustomobject]@{ id = 'policy.Unknown'; present = $true; kind = 'DWord'; data = 1; ownerRecord = $false; lifted = $true } } }
        @{ Case = 'a service start out of range'; Mutate = { param($j) @($j.items | Where-Object id -eq 'service.wuauserv')[0].data = 9 } }
        @{ Case = 'a kind the item cannot have'; Mutate = { param($j) @($j.items | Where-Object id -eq 'policy.DisableWindowsUpdateAccess')[0].kind = 'String' } }
        @{ Case = 'a malformed target'; Mutate = { param($j) @($j.items | Where-Object id -eq 'pin.TargetReleaseVersion')[0].data = 'C:\evil' } }
        @{ Case = 'another schema'; Mutate = { param($j) $j.schema = 2 } }
    ) {
        param($Case, $Mutate)
        $journal = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) `
            -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794' }) -UserSid 'S'
        & $Mutate $journal
        Set-Fake $script:Record Journal String ($journal | ConvertTo-Json -Depth 8 -Compress)
        $script:Writes.Clear()
        try { Restore-VantaWindowsTransition -Outcome Abandoned } catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly 'feature-journal'
        @($script:Writes) | Should -BeNullOrEmpty -Because 'the record stays, and nothing is restored from it'
        (Test-VantaWindowsTransitionOpen).Readable | Should -BeFalse
    }
}

Describe 'Turning Windows Update on' {
    BeforeEach {
        Reset-Machine
        Set-HeldBackUpdate
        $script:Journal = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) `
            -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794' }) -UserSid 'S'
        $script:Writes.Clear()
    }

    It 'lifts only the blockers and leaves the rest of Windows Update and the toggle store alone' {
        Invoke-VantaWindowsUpdateLift $script:Journal
        Get-Fake $script:Policy DisableWindowsUpdateAccess | Should -BeNullOrEmpty
        (Get-Fake "$script:Services\wuauserv" Start).Data | Should -Be 3
        (Get-Fake "$script:Services\UsoSvc" Start).Data | Should -Be 3
        (Get-Fake $script:PauseKey PausedFeatureStatus).Data | Should -Be 0
        Get-Fake $script:Ux PauseUpdatesExpiryTime | Should -BeNullOrEmpty
        (Get-Fake "$script:Services\WaaSMedicSvc" Start).Data | Should -Be 4
        (Get-Fake $script:Ux HideMCTLink).Data | Should -Be 1
        (Get-Fake $script:Ux RestartNotificationsAllowed2).Data | Should -Be 0
        (Get-Fake 'SYSTEM\Setup\UpgradeNotification' UpgradeAvailable).Data | Should -Be 0
        (Get-Fake $script:Policy TargetReleaseVersion).Data | Should -BeExactly '24H2' -Because 'the target changes only when the move starts'
        @($script:Writes | Where-Object { $_ -match 'Vanta\\Services' }) | Should -BeNullOrEmpty
    }

    It 'changes nothing when run again' {
        Invoke-VantaWindowsUpdateLift $script:Journal
        $script:Writes.Clear()
        Invoke-VantaWindowsUpdateLift $script:Journal
        @($script:Writes | Where-Object { $_ -notlike 'start *' }) | Should -BeNullOrEmpty
    }

    It 'reports a value that does not stay put as set by a policy' {
        $script:FailWrite["$script:Policy|DisableWindowsUpdateAccess"] = $true
        try { Invoke-VantaWindowsUpdateLift $script:Journal } catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly 'feature-policy'
        $thrown.Data['setting'] | Should -BeExactly 'DisableWindowsUpdateAccess'
    }
}

Describe 'What Vanta 0.5.0 gave users' {
    BeforeEach {
        Reset-Machine
        $script:Journal = $null
    }

    It 'turns Windows Update and its tasks back on after "Disable Windows Updates", and nothing else' {
        Set-Vanta050UpdatesOff
        @(Get-VantaWindowsUpdateBlocker).Id | Should -Be @('service.wuauserv', 'task.sih', 'task.sihboot')
        $journal = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) `
            -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794' }) -UserSid 'S'
        $script:Writes.Clear()
        Invoke-VantaWindowsUpdateLift $journal
        @($script:Writes) | Should -Be @('service wuauserv 3', 'start wuauserv', 'task sih Enabled', 'task sihboot Enabled')
        # Put back before the move: exactly as the launcher left it.
        [void](Restore-VantaWindowsTransition -Outcome Abandoned)
        (Get-Fake "$script:Services\wuauserv" Start).Data | Should -Be 4
        $script:Tasks['Microsoft\Windows\WindowsUpdate\sih'] | Should -BeExactly 'Disabled'
        $script:Tasks['Microsoft\Windows\WindowsUpdate\sihboot'] | Should -BeExactly 'Disabled'
        (Get-Fake 'SOFTWARE\Vanta\Services\ToggleWindowsUpdates' state).Data | Should -Be 0
    }

    It 'leaves the recorded "Disable Windows Updates" to the Vanta install''s replay' {
        Set-Vanta050UpdatesOff
        $journal = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) `
            -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794' }) -UserSid 'S'
        Invoke-VantaWindowsUpdateLift $journal
        $result = Restore-VantaWindowsTransition -Outcome Installed
        @($result.owned) | Should -Be @('service.wuauserv', 'task.sih', 'task.sihboot')
        @($result.restored) | Should -BeNullOrEmpty
    }

    It 'lifts the quality-update deferral "Set Windows Update Deferral" set and puts it back, leaving the feature deferral the target overrides' {
        Set-Fake $script:Policy DeferFeatureUpdates DWord 1
        Set-Fake $script:Policy DeferFeatureUpdatesPeriodInDays DWord 365
        Set-Fake $script:Policy DeferQualityUpdates DWord 1
        Set-Fake $script:Policy DeferQualityUpdatesPeriodInDays DWord 30
        # The launcher's records went to a misspelt key, which no toggle owns.
        Set-Fake 'SOFTWARE\Vanta\ServicesQualityUpdateDeferrals' days DWord 30
        Set-Fake 'SOFTWARE\Vanta\ServicesFeatureUpdateDeferrals' days DWord 365
        $journal = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) `
            -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794' }) -UserSid 'S'
        $script:Writes.Clear()
        Invoke-VantaWindowsUpdateLift $journal
        @($script:Writes) | Should -Be @("remove $script:Policy|DeferQualityUpdates", "remove $script:Policy|DeferQualityUpdatesPeriodInDays")
        $result = Restore-VantaWindowsTransition -Outcome Installed
        (Get-Fake $script:Policy DeferQualityUpdates).Data | Should -Be 1
        (Get-Fake $script:Policy DeferQualityUpdatesPeriodInDays).Data | Should -Be 30
        (Get-Fake $script:Policy DeferFeatureUpdatesPeriodInDays).Data | Should -Be 365
        @($result.restored) | Should -Be @('policy.DeferQualityUpdates', 'policy.DeferQualityUpdatesPeriodInDays')
    }

    It 'leaves the automatic update, notification and driver choices alone: none stops an update Vanta runs' {
        # "Disable Automatic Updates (default)", "Disable Update Notifications" and
        # "Disable Drivers from Windows Update".
        Set-Fake "$script:Policy\AU" AUOptions DWord 2
        Set-Fake $script:Policy SetAutoRestartNotificationDisable DWord 1
        Set-Fake $script:Policy SetUpdateNotificationLevel DWord 2
        Set-Fake $script:Ux RestartNotificationsAllowed2 DWord 0
        Set-Fake $script:Policy ExcludeWUDriversInQualityUpdate DWord 1
        @(Get-VantaWindowsUpdateBlocker) | Should -BeNullOrEmpty
        $journal = Save-VantaWindowsTransitionSnapshot -Kind access -Source ([pscustomobject]@{ build = 26200 }) -Target $null -UserSid 'S'
        $script:Writes.Clear()
        Invoke-VantaWindowsUpdateLift $journal
        @($script:Writes) | Should -BeNullOrEmpty
    }

    It 'keeps the update tasks as they are when Windows Update itself is on' {
        $script:Tasks['Microsoft\Windows\WindowsUpdate\sih'] = 'Disabled'
        @(Get-VantaWindowsUpdateBlocker) | Should -BeNullOrEmpty
    }

    It 'goes on when a task can''t be turned on: Windows Update doesn''t need it' {
        Set-Vanta050UpdatesOff
        Mock Set-VantaTransitionTask { throw 'Access is denied.' }
        $journal = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) `
            -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794' }) -UserSid 'S'
        { Invoke-VantaWindowsUpdateLift $journal } | Should -Not -Throw
        (Get-Fake "$script:Services\wuauserv" Start).Data | Should -Be 3
    }
}

Describe 'Vanta 0.5.0 with Windows Update off, paused and delayed' {
    BeforeAll {
        $script:Vanta050 = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\windows-transition\vanta050-updates-off-paused-delayed.json') -Raw | ConvertFrom-Json
        $script:RealBlocker = (Get-Command Get-VantaWindowsUpdateBlocker -CommandType Function).ScriptBlock
    }
    BeforeEach {
        Reset-Machine
        $table = @{}
        foreach ($item in Get-VantaWindowsTransitionItem) { $table[$item.Id] = $item }
        foreach ($property in $script:Vanta050.values.PSObject.Properties) {
            $item = $table[$property.Name]
            if ($property.Value -is [string]) { Set-Fake $item.Path $item.Name String $property.Value }
            else { Set-Fake $item.Path $item.Name DWord ([int64]$property.Value) }
        }
        foreach ($record in $script:Vanta050.toggleRecords.PSObject.Properties) { Set-Fake "SOFTWARE\Vanta\Services\$($record.Name)" state DWord ([int64]$record.Value) }
        # The pause dates are read against the fixture's readAt time.
        $script:ReadAt = [DateTime]::Parse($script:Vanta050.readAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
        Mock Get-VantaWindowsUpdateBlocker { & $script:RealBlocker -Now $script:ReadAt }
        $script:VantaTransitionEvidencePath = Join-Path $TestDrive 'vanta050-evidence.log'
        Remove-Item -LiteralPath $script:VantaTransitionEvidencePath -ErrorAction SilentlyContinue
        $script:Journal = Save-VantaWindowsTransitionSnapshot -Kind access -Source ([pscustomobject]@{ build = 26200 }) -UserSid 'S'
    }

    It 'records the service as it is, off, with the toggle that owns it, and lifts it with the pause and the delay' {
        $entry = @($script:Journal.items | Where-Object id -eq 'service.wuauserv')[0]
        $entry.present | Should -BeTrue
        $entry.data | Should -Be 4
        $entry.lifted | Should -BeTrue
        $entry.ownerRecord | Should -BeTrue
        $lifted = @($script:Journal.items | Where-Object lifted | ForEach-Object id)
        foreach ($id in @('policy.DeferQualityUpdates', 'pause.PausedFeatureStatus', 'pause.PauseUpdatesExpiryTime')) { $lifted | Should -Contain $id }
        @($script:Journal.items | Where-Object id -eq 'service.UsoSvc')[0].lifted | Should -BeFalse
        Get-Content -LiteralPath $script:VantaTransitionEvidencePath -Raw | Should -Match 'recorded service\.wuauserv: DWord 4 \(will lift\) \(owner record\)'
    }

    It 'leaves the service to the replayed choice after the install and names it' {
        Invoke-VantaWindowsUpdateLift $script:Journal
        (Get-Fake "$script:Services\wuauserv" Start).Data | Should -Be 3
        $result = Restore-VantaWindowsTransition -Outcome Installed
        @($result.owned) | Should -Be @('service.wuauserv')
        @($result.restored) | Should -Contain 'pause.PauseUpdatesExpiryTime'
    }

    It 'turns the service off again exactly when the update is stopped' {
        Invoke-VantaWindowsUpdateLift $script:Journal
        $result = Restore-VantaWindowsTransition -Outcome Abandoned
        @($result.restored) | Should -Contain 'service.wuauserv'
        (Get-Fake "$script:Services\wuauserv" Start).Data | Should -Be 4
    }

    AfterAll { $script:VantaTransitionEvidencePath = $null }
}

Describe 'Owners of the lifted settings' {
    It 'only lifts what the owner toggle''s own states write' {
        $toggles = Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules\Toggles'
        $pause = Import-PowerShellDataFile -LiteralPath (Join-Path $toggles 'General\PauseUpdates.psd1')
        $paused = @(($pause.States | Where-Object Name -eq 'Enable').Registry | ForEach-Object { "$($_.Path -replace '^HKLM:\\', '')\$($_.Name)" })
        @(Get-VantaWindowsTransitionItem | Where-Object Owner -eq 'PauseUpdates').Count | Should -BeGreaterThan 0
        @(Get-VantaWindowsTransitionItem | Where-Object Owner -eq 'ToggleWindowsUpdates').Count | Should -BeGreaterThan 0
        foreach ($item in @(Get-VantaWindowsTransitionItem | Where-Object Owner -eq 'PauseUpdates')) {
            $paused | Should -Contain "$($item.Path)\$($item.Name)"
        }
        $written = [Collections.Generic.List[string]]::new()
        Add-Type -AssemblyName System.ServiceProcess
        & {
            function Set-VantaRegistryValue { param($Path, $Name, $Type, $Data) $written.Add("$($Path -replace '^HKLM:\\', '')\$Name") }
            function Set-VantaServiceStartup { param($Name, $StartupType) $written.Add("SYSTEM\CurrentControlSet\Services\$Name\Start") }
            function Get-Service { param($Name) [pscustomobject]@{ Status = [ServiceProcess.ServiceControllerStatus]::Stopped } }
            function Import-VantaModule { param($Name) }
            function Set-VantaSettingsPageVisibility { param($Operation, $Page) }
            function Write-VantaStep { param($Text) }
            . (Join-Path $toggles 'Advanced\ToggleWindowsUpdates.ps1')
            # After the definition file, which has its own: no task may really change.
            function Set-VantaWindowsUpdateTaskState {
                param($Enabled)
                foreach ($path in Get-VantaWindowsUpdateTaskPaths) { $written.Add($path) }
            }
            Disable-VantaWindowsUpdates ([pscustomobject]@{ Silent = $true })
        }
        foreach ($item in @(Get-VantaWindowsTransitionItem | Where-Object Owner -eq 'ToggleWindowsUpdates')) {
            $written | Should -Contain "$($item.Path)\$($item.Name)"
        }
    }
}

Describe 'The feature-update target' {
    BeforeEach { Reset-Machine; Set-HeldBackUpdate; Set-Fake "$script:Policy\AU" AUOptions DWord 2 }

    It 'replaces a string target with a working one and keeps the values beside it' {
        Set-VantaFeatureUpdateTarget -Release '26H2'
        $enable = Get-Fake $script:Policy TargetReleaseVersion
        $enable.Kind | Should -BeExactly 'DWord'
        $enable.Data | Should -Be 1
        (Get-Fake $script:Policy ProductVersion).Data | Should -BeExactly 'Windows 11'
        (Get-Fake $script:Policy TargetReleaseVersionInfo).Data | Should -BeExactly '26H2'
        (Get-Fake $script:Policy ManagePreviewBuilds).Data | Should -Be 1
        (Get-Fake "$script:Policy\AU" AUOptions).Data | Should -Be 2
        @($script:Writes | Where-Object { $_ -like 'create *' }) | Should -BeNullOrEmpty -Because 'recreating the key drops the values beside it'
        @($script:Writes | Where-Object { $_ -match 'DisableWUfBSafeguards' }) | Should -BeNullOrEmpty
    }

    It 'creates the policy key only when something deleted it' {
        foreach ($key in @($script:Registry.Keys | Where-Object { $_ -like "$script:Policy|*" -or $_ -like "$script:Policy\*" })) { $script:Registry.Remove($key) }
        Set-VantaFeatureUpdateTarget -Release '26H2'
        @($script:Writes | Where-Object { $_ -like 'create *' }) | Should -Be @("create $script:Policy")
        (Get-Fake $script:Policy TargetReleaseVersionInfo).Data | Should -BeExactly '26H2'
    }

    It 'fails when Windows does not keep the target' {
        $script:FailWrite["$script:Policy|TargetReleaseVersionInfo"] = $true
        { Set-VantaFeatureUpdateTarget -Release '26H2' } | Should -Throw '*did not keep*'
    }
}

Describe 'Checks before anything changes' {
    BeforeEach {
        Reset-Machine
        Set-HeldBackUpdate
        Use-TransitionRun
        $script:Writes.Clear()
        Mock Test-PreparationRestart { $false }
        Mock Test-PreparationNetwork { $true }
        Mock Invoke-PreparationWindows { throw 'No update may run after a refused check.' }
        Mock Write-PreparationState {}
    }

    It 'changes nothing without a usable connection, for a move or a plain update' {
        Mock Test-PreparationNetwork { $false }
        { Invoke-PreparationTransition } | Should -Throw -ExceptionType ([System.Net.NetworkInformation.NetworkInformationException])
        { Invoke-PreparationAccess } | Should -Throw -ExceptionType ([System.Net.NetworkInformation.NetworkInformationException])
        @($script:Writes) | Should -BeNullOrEmpty
    }

    It 'stops for <Case> with <Reason> and writes nothing' -TestCases @(
        @{ Case = 'an organisation''s update server'; Reason = 'feature-managed'; Arrange = { Set-Fake "$script:Policy\AU" UseWUServer DWord 1 } }
        @{ Case = 'a disabled BITS'; Reason = 'feature-blocked'; Arrange = { Set-Fake "$script:Services\BITS" Start DWord 4 } }
        @{ Case = 'too little free space'; Reason = 'feature-disk-space'; Arrange = { $script:FreeBytes = 2GB } }
        @{ Case = 'a component store Windows can no longer repair'; Reason = 'feature-servicing'; Arrange = { $script:Health = 'NonRepairable' } }
        @{ Case = 'a Windows build that is neither source nor target'; Reason = 'feature-build'; Arrange = { $script:Windows.CurrentBuildNumber = '22631' } }
    ) {
        param($Case, $Reason, $Arrange)
        & $Arrange
        try { Invoke-PreparationTransition } catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly $Reason
        @($script:Writes) | Should -BeNullOrEmpty
    }

    It 'checks before moving Windows after plain updates left their record open' {
        [void](Save-VantaWindowsTransitionSnapshot -Kind access -Source ([pscustomobject]@{ build = 26100 }) -Target $null -UserSid 'S')
        $script:FreeBytes = 2GB
        $script:Writes.Clear()
        try { Invoke-PreparationTransition } catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly 'feature-disk-space'
        @($script:Writes) | Should -BeNullOrEmpty -Because 'the record isn''t turned into a move and nothing is retargeted'
    }

    It 'names the service and the space it found' {
        Set-Fake "$script:Services\CryptSvc" Start DWord 4
        try { Invoke-PreparationTransition } catch { $blocked = Get-PreparationFailureDetail $_.Exception }
        $blocked.setting | Should -BeExactly 'CryptSvc'
        Set-Fake "$script:Services\CryptSvc" Start DWord 3
        $script:FreeBytes = 3GB
        try { Invoke-PreparationTransition } catch { $space = Get-PreparationFailureDetail $_.Exception }
        $space.freeGb | Should -Be '3'
        $space.neededGb | Should -Be '6'
        $space.drive | Should -Match '^[A-Z]:$'
    }

    It 'asks for a pending restart before recording anything' {
        Mock Test-PreparationRestart { $true }
        Invoke-PreparationTransition | Should -Be 'reboot'
        @($script:Writes) | Should -BeNullOrEmpty
    }

    It 'goes on with a store Windows <Case>' -TestCases @(
        @{ Case = 'can repair'; Health = 'Repairable' }
        @{ Case = 'could not check'; Health = 'Throws' }
    ) {
        param($Case, $Health)
        $script:Health = $Health
        { Invoke-PreparationTransition } | Should -Throw '*No update may run*'
        Get-Fake $script:Record Journal | Should -Not -BeNullOrEmpty
    }
}

Describe 'A component store that reads as repairable' {
    BeforeAll {
        $script:AppInvLog = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\windows-transition\cbs-appinv-baseline.txt'))
    }
    BeforeEach {
        Reset-Machine
        $script:Health = 'Repairable'
        $script:VantaTransitionEvidencePath = Join-Path $TestDrive 'store-evidence.log'
        Remove-Item -LiteralPath $script:VantaTransitionEvidencePath -ErrorAction SilentlyContinue
    }

    It 'reads the newest store check from the servicing log' {
        $finding = Get-VantaTransitionStoreFinding $script:AppInvLog
        $finding.Total | Should -Be 2
        @($finding.Items.Path) | Should -Be @(
            'amd64_microsoft-windows-a..n-experience-appinv_31bf3856ad364e35_10.0.26100.1591_none_b8a08e9482a41bbe\aeinvext.dll'
            'amd64_microsoft-windows-a..n-experience-appinv_31bf3856ad364e35_10.0.26100.1591_none_b8a08e9482a41bbe\Microsoft.Management.Deployment.winmd')
        $finding.Counts['CSI Payload Corruption'] | Should -Be 2
        $finding.Counts['CBS Manifest Corruption'] | Should -Be 0
    }

    It 'goes on and records <Case>' -TestCases @(
        @{ Case = 'the AppInv files the NoTelemetry package leaves after a store cleanup'; Label = 'the known Vanta package pattern'; Change = { $script:CbsLines = $script:AppInvLog } }
        @{ Case = 'the files a repair leaves instead'; Label = 'other'; Change = {
                $script:CbsLines = $script:AppInvLog -replace 'n-experience-appinv_31bf3856ad364e35_10\.0\.26100\.1591_none_b8a08e9482a41bbe\\aeinvext\.dll', 'entory-data-sources_31bf3856ad364e35_10.0.26100.1591_none_0\r\devinv.dll' } }
        @{ Case = 'a manifest corruption beside it'; Label = 'other'; Change = { $script:CbsLines = $script:AppInvLog -replace 'CSI Manifest Corruption:\t0', "CSI Manifest Corruption:`t1" } }
        @{ Case = 'the same files without the NoTelemetry package'; Label = 'other'; Change = { $script:CbsLines = $script:AppInvLog; $script:Packages = @() } }
        @{ Case = 'no store check in the servicing log'; Label = 'other'; Change = { $script:CbsLines = @('2026-10-01 21:44:29, Info CBS Exec: nothing') } }
    ) {
        param($Case, $Label, $Change)
        & $Change
        { Test-VantaWindowsTransitionPreflight } | Should -Not -Throw -Because $Case
        $evidence = Get-Content -LiteralPath $script:VantaTransitionEvidencePath -Raw
        $evidence | Should -Match ([regex]::Escape("component store is repairable ($Label)"))
        $evidence | Should -Match 'going on'
    }

    It 'lists the corrupt items the servicing log names' {
        $script:CbsLines = $script:AppInvLog
        Test-VantaWindowsTransitionPreflight
        Get-Content -LiteralPath $script:VantaTransitionEvidencePath -Raw | Should -Match 'CSI Payload Corrupt amd64_microsoft-windows-a\.\.n-experience-appinv_.*\\aeinvext\.dll; CSI Payload Corrupt .*Microsoft\.Management\.Deployment\.winmd'
    }

    It 'stops for a store Windows can no longer repair' {
        $script:CbsLines = $script:AppInvLog
        $script:Health = 'NonRepairable'
        try { Test-VantaWindowsTransitionPreflight } catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly 'feature-servicing'
    }

    It 'goes on and logs the error when the store check cannot run' {
        $script:Health = 'Throws'
        { Test-VantaWindowsTransitionPreflight } | Should -Not -Throw
        Get-Content -LiteralPath $script:VantaTransitionEvidencePath -Raw | Should -Match 'component store health could not be read \(0x[0-9A-F]{8}\): DISM is unavailable; going on'
    }
}

Describe 'Moving Windows' {
    BeforeEach {
        Reset-Machine
        Set-HeldBackUpdate
        Use-TransitionRun
        $script:EulaAccepted = 0
        $script:Offers = @{ default = @(); optional = @(); hidden = @() }
        $script:Collections = @()
        Mock Test-PreparationRestart { $false }
        Mock Test-PreparationNetwork { $true }
        Mock Write-PreparationState {}
        Mock Assert-PreparationContinue {}
        Mock Invoke-PreparationWindows { 'complete' }
        Mock Invoke-PreparationUpdates { 'complete' }
        Mock Restart-PreparationUpdateService { $false }
        Mock Get-PreparationFeatureHistory {}
        Mock Get-PreparationHardwareGap {}
        Mock Invoke-PreparationCommitCall {}
        Mock Add-PreparationWindowsUpdate { throw 'The move never goes through the quality-pass installer.' }
        Mock New-Object -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' } { New-Session }
        Mock New-Object -ParameterFilter { $ComObject -eq 'Microsoft.Update.UpdateColl' } {
            $collection = [pscustomobject]@{ Count = 0; Items = [Collections.ArrayList]::new() }
            $collection | Add-Member ScriptMethod Add { param($Update) [void]$this.Items.Add($Update); $this.Count++ }
            $script:Collections += $collection
            $collection
        }
        Mock Invoke-PreparationSearch {
            if ($Criteria -match 'IsHidden=1') { return $script:Offers.hidden }
            if ($Criteria -match 'OptionalInstallation') { return $script:Offers.optional }
            return $script:Offers.default
        }
        $script:Download = New-Result
        $script:Install = New-Result
        Mock Invoke-PreparationWindowsOperation { if ($Kind -eq 'Download') { $script:Download } else { $script:Install } }
        # Fake time: every wait only adds to the clock.
        $script:PreparationPolicyWaitSeconds = 120
        $script:PreparationTargetReread = $false
        $script:PreparationServiceRestarts = 0
        $script:Waited = 0
        Mock Wait-PreparationSeconds { $script:Waited += $Seconds }
        $script:VantaTransitionEvidencePath = Join-Path $TestDrive 'evidence.log'
        Remove-Item -LiteralPath $script:VantaTransitionEvidencePath -ErrorAction SilentlyContinue
    }

    It 'records first, lifts, brings monthly updates current, then retargets and installs only the package, alone' {
        $script:Offers.default = @(
            (New-Offer 'Windows 11, version 25H2' @('5054156') -Upgrade)
            (New-Offer 'Windows 11, version 26H2' @() -Upgrade)
            (New-Offer 'Feature update to Windows 11, version 26H2' @('5121794') -Upgrade -Eula $false)
        )
        Invoke-PreparationTransition | Should -Be 'reboot'
        $script:PreparationRestartReasons | Should -Be @('feature-update')
        $script:Writes[0] | Should -BeExactly "set $script:Record|Journal" -Because 'the originals are recorded before the first change'
        $retarget = $script:Writes.IndexOf("set $script:Policy|TargetReleaseVersionInfo")
        $retarget | Should -BeGreaterThan $script:Writes.IndexOf("remove $script:Policy|DisableWindowsUpdateAccess")
        Should -Invoke Invoke-PreparationWindows -Times 1 -Exactly
        $script:Collections[-1].Count | Should -Be 1
        $script:Collections[-1].Items[0].KBArticleIDs | Should -Be @('5121794')
        $script:EulaAccepted | Should -Be 1
        $script:Installer.ForceQuiet | Should -BeTrue
        $script:Installer.AllowSourcePrompts | Should -BeFalse
        (Read-Journal).phase | Should -BeExactly 'installed'
        Should -Invoke Invoke-PreparationCommitCall -Times 0 -Exactly -Because 'Vanta commits only just before its own restart'
        $evidence = Get-Content -LiteralPath $script:VantaTransitionEvidencePath -Raw
        $evidence | Should -Match "unexpected-offer, not installed: 'Windows 11, version 25H2' KB=5054156"
        $evidence | Should -Match 'lifted policy.DisableWindowsUpdateAccess: DWord 1 -> absent'
    }

    It 'takes the one upgrade naming the target release when Windows Update offers it under a new KB' {
        $script:Offers.default = @(
            (New-Offer 'Windows 11, version 25H2' @('5054156') -Upgrade)
            (New-Offer 'Windows 11, version 26H2' @('5139999') -Upgrade -Eula $false)
        )
        Invoke-PreparationTransition | Should -Be 'reboot'
        $script:Collections[-1].Count | Should -Be 1
        $script:Collections[-1].Items[0].KBArticleIDs | Should -Be @('5139999')
        $journal = Read-Journal
        $journal.offer.kb | Should -BeExactly '5139999'
        $journal.offer.updateId | Should -BeExactly $script:Offers.default[1].Identity.UpdateID
        $journal.offer.title | Should -BeExactly 'Windows 11, version 26H2'
        $evidence = Get-Content -LiteralPath $script:VantaTransitionEvidencePath -Raw
        $evidence | Should -Match "offer, chosen by the release 26H2 in its title: 'Windows 11, version 26H2' KB=5139999 id=\S+ rev 1"
        $evidence | Should -Match "unexpected-offer, not installed: 'Windows 11, version 25H2'"
    }

    It 'chooses none of several unknown upgrades naming the target, and installs nothing' {
        $script:Offers.default = @(
            (New-Offer 'Windows 11, version 26H2' @('5139998') -Upgrade)
            (New-Offer 'Windows 11, version 26H2 (repair)' @('5139999') -Upgrade)
        )
        try { Invoke-PreparationTransition } catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly 'feature-failed'
        Should -Invoke Invoke-PreparationWindowsOperation -Times 0 -Exactly
    }

    It 'never takes an upgrade to another release' {
        $script:Offers.default = @(New-Offer 'Windows 11, version 25H2' @('5054156') -Upgrade)
        try { Invoke-PreparationTransition } catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly 'feature-not-offered'
        Should -Invoke Invoke-PreparationWindowsOperation -Times 0 -Exactly
    }

    It 'restarts for an update that installed with errors or leaves work for the restart: result <Code>, restart <Restart>' -ForEach @(
        @{ Code = 4; HResult = -2145116149; Restart = $true }
        @{ Code = 3; HResult = 0; Restart = $false }
    ) {
        $script:Offers.default = @(New-Offer 'Windows 11, version 26H2' @('5129195') -Upgrade)
        $script:Install = New-Result $Code $HResult $Restart
        Invoke-PreparationTransition | Should -Be 'reboot'
        $script:PreparationRestartReasons | Should -Be @('feature-update')
        (Read-Journal).phase | Should -BeExactly 'installed'
        Should -Invoke Invoke-PreparationWindowsOperation -Times 1 -Exactly -ParameterFilter { $Kind -eq 'Install' }
    }

    It 'restarts Windows Update to read the new target before it searches' {
        $script:Offers.default = @(New-Offer 'Windows 11, version 26H2' @('5129195') -Upgrade)
        $script:Restarts = 0
        Mock Restart-PreparationUpdateService {
            $script:Restarts++
            Set-Fake 'SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\PolicyState' TargetReleaseVersion String '26H2'
            $true
        }
        Invoke-PreparationTransition | Should -Be 'reboot'
        $script:Restarts | Should -Be 1
        $evidence = Get-Content -LiteralPath $script:VantaTransitionEvidencePath -Raw
        $evidence | Should -Match "policy state before the search: target ''"
        $evidence | Should -Match "restarted wuauserv, policy state now: target '26H2'"
    }

    It 'searches again after a restart when the first search ran on the old policy' {
        # Busy finishing the monthly updates, Windows Update answers the first
        # search on the old policy and only takes the new target with it.
        $script:Restarts = 0
        Mock Restart-PreparationUpdateService { $script:Restarts++; $script:Restarts -gt 1 }
        $script:DefaultSearches = 0
        $script:Offer = New-Offer 'Windows 11, version 26H2' @('5129195') -Upgrade
        Mock Invoke-PreparationSearch {
            if ($Criteria -match 'IsHidden=1|OptionalInstallation') { return @() }
            $script:DefaultSearches++
            Set-Fake 'SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\PolicyState' TargetReleaseVersion String '26H2'
            if ($script:DefaultSearches -ge 2) { return @($script:Offer) }
            @()
        }
        Invoke-PreparationTransition | Should -Be 'reboot'
        $script:Restarts | Should -Be 2
        $script:DefaultSearches | Should -Be 2
        $script:Collections[-1].Items[0].KBArticleIDs | Should -Be @('5129195')
        Get-Content -LiteralPath $script:VantaTransitionEvidencePath -Raw | Should -Match 'no offer on the first search; restarted wuauserv'
    }

    It 'restarts once and keeps searching for 10 minutes when the target is read but nothing is offered, then says so' {
        Set-Fake 'SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\PolicyState' TargetReleaseVersion String '26H2'
        $script:Restarts = 0
        Mock Restart-PreparationUpdateService { $script:Restarts++; $true }
        try { Invoke-PreparationTransition } catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly 'feature-not-offered'
        $script:Restarts | Should -Be 1
        $script:Waited | Should -Be 600
        # The first search, then after 30, 60, 90 and every 120 seconds up to 600.
        Should -Invoke Invoke-PreparationSearch -Times 8 -Exactly -ParameterFilter { $Criteria -notmatch 'OptionalInstallation|IsHidden=1' }
        Get-Content -LiteralPath $script:VantaTransitionEvidencePath -Raw | Should -Match 'no offer within 600 s'
    }

    It 'installs the offer that appears on the third search after the wait starts' {
        Set-Fake 'SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\PolicyState' TargetReleaseVersion String '26H2'
        Mock Restart-PreparationUpdateService { $true }
        $script:DefaultSearches = 0
        $script:Offer = New-Offer 'Windows 11, version 26H2' @('5129195') -Upgrade
        Mock Invoke-PreparationSearch {
            if ($Criteria -match 'IsHidden=1|OptionalInstallation') { return @() }
            $script:DefaultSearches++
            if ($script:DefaultSearches -eq 4) { return @($script:Offer) }
            @()
        }
        Invoke-PreparationTransition | Should -Be 'reboot'
        $script:Waited | Should -Be 180 -Because 'it stops at the first offer, after 30, 60 and 90 seconds'
        $script:Collections[-1].Items[0].KBArticleIDs | Should -Be @('5129195')
    }

    It 'restarts Windows Update at most twice in a run, however long it waits' {
        $script:Restarts = 0
        Mock Restart-PreparationUpdateService { $script:Restarts++; $true }
        # The policy state never shows the target and nothing is ever offered;
        # the first search is refused once, so the run looks a second time.
        $script:refusals = 0
        Mock Find-PreparationFeatureOffer {
            $script:refusals++
            if ($script:refusals -eq 1) { throw ([Runtime.InteropServices.COMException]::new('policy', -2145124305)) }
        }
        try { Invoke-PreparationTransition } catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly 'feature-not-offered'
        $script:Restarts | Should -Be 2
        $log = Get-Content -LiteralPath $script:VantaTransitionEvidencePath -Raw
        $log | Should -Match 'not the target after 120 seconds'
        $log | Should -Match 'already restarted 2 times in this run'
    }

    It 'reports the wait as one while it waits, and stops when the user stops' {
        Set-Fake 'SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\PolicyState' TargetReleaseVersion String '26H2'
        Mock Restart-PreparationUpdateService { $true }
        Mock Wait-PreparationSeconds {
            $script:WaitDetail = $script:PreparationSearchDetail.Clone()
            throw (New-Object OperationCanceledException 'Preparation stopped after the current operation.')
        }
        { Invoke-PreparationTransition } | Should -Throw -ExceptionType ([OperationCanceledException])
        $script:WaitDetail.waiting | Should -BeExactly 'feature-offer'
        $script:PreparationSearchDetail.Count | Should -Be 0 -Because 'later searches are not the wait'
    }

    It 'rechecks only the offer once the target is set, and installs nothing else again' {
        Set-Fake 'SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\PolicyState' TargetReleaseVersion String '26H2'
        $journal = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) `
            -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794,5129195' }) -UserSid 'S'
        $journal.phase = 'targeted'
        Write-VantaWindowsTransition $journal
        Mock Invoke-PreparationWindows { throw 'A recheck never runs the monthly updates again.' }
        $script:Restarts = 0
        Mock Restart-PreparationUpdateService { $script:Restarts++; $true }
        Set-Variable -Name OfferOnly -Value ([switch]$true)
        try { Invoke-PreparationTransition } catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly 'feature-not-offered'
        $script:Restarts | Should -Be 0
        $script:Waited | Should -Be 0 -Because 'the app waits between rechecks, not the worker'
        Should -Invoke Invoke-PreparationWindows -Times 0 -Exactly
        $script:Offers.default = @(New-Offer 'Windows 11, version 26H2' @('5129195') -Upgrade)
        $script:PreparationTargetReread = $false
        Invoke-PreparationTransition | Should -Be 'reboot'
        $script:Collections[-1].Items[0].KBArticleIDs | Should -Be @('5129195')
        Should -Invoke Invoke-PreparationWindows -Times 0 -Exactly
    }

    It 'keeps the target unset while the monthly updates ask for a restart' {
        Mock Invoke-PreparationWindows { 'reboot' }
        Invoke-PreparationTransition | Should -Be 'reboot'
        (Get-Fake $script:Policy TargetReleaseVersion).Data | Should -BeExactly '24H2'
        (Read-Journal).phase | Should -BeExactly 'lifted'
    }

    It 'never accepts the licence terms without the user''s acceptance' {
        Set-Variable -Name AcceptLicense -Value ([switch]$false)
        $script:Offers.default = @(New-Offer 'Feature update' @('5121794') -Upgrade -Eula $false)
        try { Invoke-PreparationTransition } catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly 'feature-terms'
        $script:EulaAccepted | Should -Be 0
        Should -Invoke Invoke-PreparationWindowsOperation -Times 0 -Exactly
    }

    It 'asks for an optional offer when the plain search finds nothing' {
        $script:Offers.optional = @(New-Offer 'Feature update' @('5121794') -Upgrade)
        Invoke-PreparationTransition | Should -Be 'reboot'
        Should -Invoke Invoke-PreparationSearch -ParameterFilter { $Criteria -match "DeploymentAction='OptionalInstallation'" -and $Criteria -match 'CategoryIDs' }
    }

    It 'treats a client that cannot search for optional offers as no offer' {
        Mock Invoke-PreparationSearch {
            if ($Criteria -match 'OptionalInstallation') { throw ([Runtime.InteropServices.COMException]::new('invalid criteria', -2145124302)) }
            @()
        }
        try { Invoke-PreparationTransition } catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly 'feature-not-offered'
    }

    It 'tells <Reason> apart when nothing is offered' -TestCases @(
        @{ Reason = 'feature-hidden'; Arrange = { $script:Offers.hidden = @(New-Offer 'Feature update' @('5121794') -Upgrade) } }
        @{ Reason = 'feature-prerequisite'; Arrange = { $script:Windows.UBR = 9278 } }
        @{ Reason = 'feature-hardware'; Arrange = { Mock Get-PreparationHardwareGap { 'tpm'; 'uefi' } } }
        @{ Reason = 'feature-not-offered'; Arrange = { } }
    ) {
        param($Reason, $Arrange)
        & $Arrange
        try { Invoke-PreparationTransition } catch { $detail = Get-PreparationFailureDetail $_.Exception }
        $detail.reason | Should -BeExactly $Reason
        if ($Reason -eq 'feature-hardware') { $detail.hardware | Should -BeExactly 'tpm,uefi' }
        (Get-Fake $script:Policy TargetReleaseVersionInfo).Data | Should -BeExactly '26H2' -Because 'a PC that waits for the offer keeps asking for it'
    }

    It 'treats a package Windows installed on its own as installed' {
        Mock Get-PreparationFeatureHistory { [pscustomobject]@{ Date = [DateTime]::UtcNow.AddMinutes(5); ResultCode = 2; HResult = 0; Title = 'KB5121794' } }
        Invoke-PreparationTransition | Should -Be 'reboot'
        $script:PreparationRestartReasons | Should -Be @('feature-update')
        (Read-Journal).phase | Should -BeExactly 'installed'
    }

    It 'turns Windows Update on again when the search is refused by policy, once' {
        $script:Offers.default = @(New-Offer 'Feature update' @('5121794') -Upgrade)
        $script:refusals = 0
        Mock Find-PreparationFeatureUpdate {
            $script:refusals++
            if ($script:refusals -eq 1) { throw ([Runtime.InteropServices.COMException]::new('policy', -2145124305)) }
            [pscustomobject]@{ Update = $script:Offers.default[0]; Hidden = $false }
        }
        Mock Invoke-VantaWindowsUpdateLift {}
        Invoke-PreparationTransition | Should -Be 'reboot'
        Should -Invoke Invoke-VantaWindowsUpdateLift -Times 2 -Exactly
        Mock Find-PreparationFeatureUpdate { throw ([Runtime.InteropServices.COMException]::new('policy', -2145124305)) }
        Reset-Machine
        Set-HeldBackUpdate
        try { Invoke-PreparationTransition } catch { $detail = Get-PreparationFailureDetail $_.Exception }
        $detail.reason | Should -BeExactly 'feature-blocked'
        $detail.errorCode | Should -BeExactly '0x8024002F'
    }

    It 'looks for a hidden package among superseded updates too' {
        { Invoke-PreparationTransition } | Should -Throw '*does not offer*'
        Should -Invoke Invoke-PreparationSearch -ParameterFilter { $Criteria -match 'IsHidden=1' -and $IncludeSuperseded }
    }

    It 'retries a failed install once after a fresh search, then reports Windows''s code' {
        $script:Offers.default = @(New-Offer 'Feature update' @('5121794') -Upgrade)
        $script:Install = New-Result 4 -2145116149 $false
        try { Invoke-PreparationTransition } catch { $detail = Get-PreparationFailureDetail $_.Exception }
        $detail.reason | Should -BeExactly 'feature-failed'
        $detail.errorCode | Should -BeExactly '0x8024200B'
        Should -Invoke Invoke-PreparationWindowsOperation -Times 2 -Exactly -ParameterFilter { $Kind -eq 'Install' }
        (Read-Journal).phase | Should -BeExactly 'targeted'
    }

    It 'turns Windows Update on again once when it was turned off mid-install, then names what blocks it' {
        $script:Offers.default = @(New-Offer 'Feature update' @('5121794') -Upgrade)
        $script:Install = New-Result 4 -2145124306 $false
        Mock Invoke-VantaWindowsUpdateLift {}
        Mock Get-VantaWindowsUpdateBlocker { [pscustomobject]@{ Id = 'policy.DisableWindowsUpdateAccess' } }
        try { Invoke-PreparationTransition } catch { $detail = Get-PreparationFailureDetail $_.Exception }
        Should -Invoke Invoke-VantaWindowsUpdateLift -Times 2 -Exactly
        $detail.reason | Should -BeExactly 'feature-blocked'
        $detail.setting | Should -BeExactly 'DisableWindowsUpdateAccess'
        $detail.errorCode | Should -BeExactly '0x8024002E'
    }
}

Describe 'The record of updates Windows offers again after they installed' {
    BeforeEach {
        Reset-Machine
        Mock Get-PreparationInstalledVersion { 'Microsoft.SecHealthUI 1000.26100.9168.0' }
    }

    It 'keeps each update once, reads back what it wrote, and lets old entries lapse' {
        $update = New-Offer 'Update for Windows Security platform - KB5007651 (Version 10.0.29628.1000)' @('5007651')
        Add-PreparationReoffered $update
        Add-PreparationReoffered $update
        $entries = @(Read-PreparationReoffered)
        $entries.Count | Should -Be 1
        $entries[0].key | Should -BeExactly "$($update.Identity.UpdateID)/1"
        (Get-PreparationReofferedKey).Contains("$($update.Identity.UpdateID)/1") | Should -BeTrue
        (Get-Fake 'SOFTWARE\Vanta\Preparation' Reoffered).Kind | Should -BeExactly 'String'
        $stale = @([pscustomobject]@{ key = 'old/1'; at = [DateTime]::UtcNow.AddDays(-40).ToString('o') }) + $entries
        Set-Fake 'SOFTWARE\Vanta\Preparation' Reoffered String (ConvertTo-Json -InputObject $stale -Compress)
        @(Read-PreparationReoffered).key | Should -Be @("$($update.Identity.UpdateID)/1")
        Set-Fake 'SOFTWARE\Vanta\Preparation' Reoffered String '{not json'
        @(Read-PreparationReoffered) | Should -BeNullOrEmpty
    }

    It 'keeps every driver one run finds the device doesn''t need' {
        $drivers = @(1..21 | ForEach-Object { New-Offer "Fixture driver $_" -Type 2 })
        foreach ($driver in $drivers) { Add-PreparationDriverNotNeeded $driver }
        @(Read-PreparationReoffered).key | Should -Be @($drivers | ForEach-Object { "$($_.Identity.UpdateID)/1" })
    }
}

Describe 'The update service a search asks' {
    BeforeEach {
        Reset-Machine
        Mock Write-PreparationState {}
        $script:VantaTransitionEvidencePath = Join-Path $TestDrive 'search-evidence.log'
        Remove-Item -LiteralPath $script:VantaTransitionEvidencePath -ErrorAction SilentlyContinue
        $script:Searcher = [pscustomobject]@{ Online = $false; ServerSelection = 0; ServiceID = '00000000-0000-0000-0000-000000000000'; IncludePotentiallySupersededUpdates = $false }
        $script:Searcher | Add-Member ScriptMethod BeginSearch {
            param($Criteria, $Callback, $State)
            $job = [pscustomobject]@{ IsCompleted = $true }
            $job | Add-Member ScriptMethod CleanUp {}
            $job
        }
        $script:Searcher | Add-Member ScriptMethod EndSearch { param($Job) [pscustomobject]@{ ResultCode = 2; Updates = @() } }
        $script:SearchSession = [pscustomobject]@{}
        $script:SearchSession | Add-Member ScriptMethod CreateUpdateSearcher { $script:Searcher }
    }

    It 'asks the Windows Update service itself, online' {
        @(Invoke-PreparationSearch $script:SearchSession "IsInstalled=0 and Type='Software'") | Should -BeNullOrEmpty
        $script:Searcher.ServerSelection | Should -Be 2
        $script:Searcher.Online | Should -BeTrue
        Get-Content -LiteralPath $script:VantaTransitionEvidencePath -Raw | Should -Match "search on ServerSelection=2 \(Windows Update\): result 2, 0 update\(s\) for IsInstalled=0 and Type='Software'"
    }

    It 'leaves a PC whose updates come from its organisation''s server on that server' {
        Set-Fake 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' UseWUServer DWord 1
        [void](Invoke-PreparationSearch $script:SearchSession 'IsInstalled=0')
        $script:Searcher.ServerSelection | Should -Be 0
    }

    It 'names the service a search asks, never a ServiceID that means nothing there' {
        Format-PreparationService ([pscustomobject]@{ ServerSelection = 2; ServiceID = '00000000-0000-0000-0000-000000000000' }) | Should -BeExactly 'ServerSelection=2 (Windows Update)'
        Format-PreparationService ([pscustomobject]@{ ServerSelection = 0; ServiceID = '00000000-0000-0000-0000-000000000000' }) | Should -BeExactly 'ServerSelection=0 (the default service)'
        Format-PreparationService ([pscustomobject]@{ ServerSelection = 3; ServiceID = '855e8a7c-ecb4-4ca3-b045-1dfa50104289' }) | Should -BeExactly 'ServerSelection=3 (service 855e8a7c-ecb4-4ca3-b045-1dfa50104289)'
    }

    It 'records no offer yet and a missing prerequisite as outcomes, and anything else as a failure' {
        Get-PreparationEndStep @{ reason = 'feature-not-offered' } | Should -Be 'outcome'
        Get-PreparationEndStep @{ reason = 'feature-prerequisite' } | Should -Be 'outcome'
        Get-PreparationEndStep @{ reason = 'feature-hardware' } | Should -Be 'failed'
        Get-PreparationEndStep @{ failureMessage = 'Windows update search failed: 4' } | Should -Be 'failed'
    }

    It 'logs no offer yet as one outcome line and keeps the error record and stack trace for a failure' {
        $stop = {
            param($Reason)
            try { throw (New-VantaTransitionFailure 'Windows Update does not offer 26H2 to this PC yet.' $Reason) }
            catch { return $_ }
        }
        $record = & $stop 'feature-not-offered'
        $text = Format-PreparationStop $record (Get-PreparationFailureDetail $record.Exception)
        $text | Should -BeExactly 'Outcome (feature-not-offered): Windows Update does not offer 26H2 to this PC yet.'

        $record = & $stop 'feature-failed'
        $text = Format-PreparationStop $record (Get-PreparationFailureDetail $record.Exception)
        $text | Should -Match 'Windows Update does not offer 26H2'
        $text | Should -Match 'At .+:\d+ char:\d+'
    }

    It 'keeps one history entry, with a count and the first and last times, for repeated no-offer outcomes' {
        $journal = [pscustomobject]@{ history = @([pscustomobject]@{ at = '2026-10-02T09:00:00Z'; event = 'targeted'; detail = '' }) }
        $detail = 'reason=feature-not-offered code= Windows Update does not offer 26H2 to this PC yet.'
        foreach ($recheck in 1..11) { Add-VantaTransitionHistory $journal 'outcome' $detail }
        @($journal.history).Count | Should -Be 2
        $journal.history[-1].count | Should -Be 11
        $journal.history[-1].lastAt | Should -Not -BeNullOrEmpty
        # A different outcome, or a failure, starts a new entry.
        Add-VantaTransitionHistory $journal 'failed' 'reason=feature-hardware code= TPM'
        Add-VantaTransitionHistory $journal 'outcome' $detail
        @($journal.history).Count | Should -Be 4
        $journal.history[-1].PSObject.Properties['count'] | Should -BeNullOrEmpty
        # The record stays small.
        foreach ($step in 1..50) { Add-VantaTransitionHistory $journal "step-$step" '' }
        @($journal.history).Count | Should -Be 40
    }
}

Describe 'Optional prerequisites' {
    BeforeEach {
        Reset-Machine
        Use-TransitionRun
        $script:Windows.UBR = 9550
        $script:Optional = @(
            (New-Offer '2026-09 Cumulative Update Preview for Windows 11 Version 24H2 for x64-based Systems (KB5124010) (26100.9600)' @('5124010'))
            (New-Offer '2026-10 Cumulative Update Preview for Windows 11 Version 24H2 for x64-based Systems (KB5130001) (26100.9700)' @('5130001'))
            (New-Offer '2026-09 Cumulative Update Preview for .NET Framework 3.5 and 4.8.1 (KB5199999)' @('5199999'))
            (New-Offer 'An older cumulative update (KB5100000) (26100.9000)' @('5100000'))
            (New-Offer 'Windows 11, version 26H2' @('5124010') -Upgrade)
            (New-Offer 'Intel - System - 1.2.3.4' @() -Type 2)
        )
        foreach ($offer in $script:Optional) { $offer.DeploymentAction = 'OptionalInstallation' }
        Mock Invoke-PreparationSearch {
            if ($Criteria -match "DeploymentAction='OptionalInstallation'") { return $script:Optional }
            throw "Unexpected search $Criteria"
        }
    }

    It 'takes the cumulative update the move needs, or a newer one for this build, and no other optional update' {
        $found = @(Find-PreparationPrerequisiteUpdate (New-Session))
        @($found.KBArticleIDs) | Should -Be @('5124010', '5130001')
        Should -Invoke Invoke-PreparationSearch -Times 1 -Exactly -ParameterFilter { $Criteria -eq "IsInstalled=0 and IsHidden=0 and Type='Software' and DeploymentAction='OptionalInstallation'" }
    }

    It 'falls back to browse-only updates on a client that cannot ask for optional ones' {
        Mock Invoke-PreparationSearch {
            if ($Criteria -match 'OptionalInstallation') { throw ([Runtime.InteropServices.COMException]::new('invalid criteria', -2145124302)) }
            if ($Criteria -match 'BrowseOnly=1') { return @($script:Optional[0]) }
            throw "Unexpected search $Criteria"
        }
        @(Find-PreparationPrerequisiteUpdate (New-Session)).KBArticleIDs | Should -Be @('5124010')
    }

    It 'takes nothing once Windows has moved, or outside a move' {
        $script:Windows.CurrentBuildNumber = '26300'
        @(Find-PreparationPrerequisiteUpdate (New-Session)) | Should -BeNullOrEmpty
        $script:Windows.CurrentBuildNumber = '26100'
        Set-Variable -Name WindowsTarget -Value ''
        @(Find-PreparationPrerequisiteUpdate (New-Session)) | Should -BeNullOrEmpty
        Should -Invoke Invoke-PreparationSearch -Times 0 -Exactly
    }
}

Describe 'The new version in Windows Update history' {
    BeforeEach { Use-TransitionRun }

    It 'is the update Vanta installed, or one named for the release, never a monthly update sharing its KB' {
        $id = 'ba6eafb7-6fd3-4fb9-8462-3d86b81835b3'
        Test-PreparationFeatureHistoryEntry 'Windows 11, version 26H2' '' '' | Should -BeTrue
        Test-PreparationFeatureHistoryEntry 'Feature update to Windows 11, version 26H2 (KB5121794)' 'other' $id | Should -BeTrue
        Test-PreparationFeatureHistoryEntry 'Update with no release in its title' $id $id | Should -BeTrue
        Test-PreparationFeatureHistoryEntry '2026-09 Security Update (KB5129195) (26200.9457)' 'monthly' $id | Should -BeFalse
        Test-PreparationFeatureHistoryEntry 'Windows 11, version 25H2' 'other' $id | Should -BeFalse
    }
}

Describe 'Restarting into the new version' {
    BeforeEach {
        Reset-Machine
        Set-HeldBackUpdate
        Use-TransitionRun
        Mock Test-PreparationRestart { $false }
        Mock Write-PreparationState {}
        Mock Invoke-PreparationUpdates { 'complete' }
        Mock Invoke-PreparationCommitCall { $script:Commits++ }
        Mock Get-PreparationFeatureHistory { [pscustomobject]@{ Date = [DateTime]::UtcNow; ResultCode = 4; HResult = -2145116149; Title = 'KB5121794' } }
        $script:Commits = 0
        $journal = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) `
            -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794' }) -UserSid 'S' -VantaPackages $script:Packages
        Set-PreparationInstalled $journal 'update=fixture'
    }

    It 'commits once per boot, only when asked, and records the boot' {
        Invoke-PreparationCommit
        Invoke-PreparationCommit
        $script:Commits | Should -Be 1
        (Read-Journal).commitBoot | Should -BeExactly 'boot:7'
        Set-Fake 'SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' BootId DWord 8
        Invoke-PreparationCommit
        $script:Commits | Should -Be 2
    }

    It 'commits the update it installed, and restarts anyway when the commit fails' {
        $journal = Read-Journal
        $update = New-Offer 'Windows 11, version 26H2' @('5129195') -Upgrade
        Set-PreparationInstalled $journal 'update=offer' $update
        Mock Invoke-PreparationCommitCall { throw ([Runtime.InteropServices.COMException]::new('not initialised', -2145124348)) }
        { Invoke-PreparationCommit } | Should -Not -Throw
        Should -Invoke Invoke-PreparationCommitCall -Times 1 -Exactly -ParameterFilter { $UpdateId -eq $update.Identity.UpdateID }
        $after = Read-Journal
        $after.commitBoot | Should -BeExactly 'boot:7'
        $after.history[-1].detail | Should -Match 'commit failed 0x80240004.*restarting anyway'
    }

    It 'waits for the restart while still in the boot that installed it' {
        Invoke-PreparationTransition | Should -Be 'reboot'
        $script:PreparationRestartReasons | Should -Be @('feature-update')
        (Read-Journal).commitRetried | Should -BeFalse
    }

    It 'asks for one more restart after a restart without Vanta''s commit, then reports the rollback' {
        Set-Fake 'SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' BootId DWord 8
        Invoke-PreparationTransition | Should -Be 'reboot'
        $script:PreparationRestartReasons | Should -Be @('feature-commit')
        Set-Fake 'SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' BootId DWord 9
        try { Invoke-PreparationTransition } catch { $detail = Get-PreparationFailureDetail $_.Exception }
        $detail.reason | Should -BeExactly 'feature-rolled-back'
        $detail.errorCode | Should -BeExactly '0x8024200B'
    }

    It 'reports a rollback at once after a restart Vanta committed' {
        Invoke-PreparationCommit
        Set-Fake 'SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' BootId DWord 8
        try { Invoke-PreparationTransition } catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly 'feature-rolled-back'
    }

    It 'finishes the updates and records that Windows switched on in place when the Vanta components are all there' {
        $script:Windows.CurrentBuildNumber = '26300'
        Invoke-PreparationTransition | Should -Be 'complete'
        Should -Invoke Invoke-PreparationUpdates -Times 1 -Exactly
        $journal = Read-Journal
        $journal.phase | Should -BeExactly 'on-target'
        $journal.rebuild.rebuilt | Should -BeFalse
        @($journal.rebuild.signals) | Should -BeNullOrEmpty
        $journal.history[-1].event | Should -BeExactly 'on-target'
        $journal.history[-2].event | Should -BeExactly 'moved'
        $journal.history[-2].detail | Should -Match 'switched on in place'
        Get-VantaWindowsTransitionRebase | Should -BeNullOrEmpty
    }

    It 'stops when the Vanta components are gone with no sign that Setup ran' {
        $script:Windows.CurrentBuildNumber = '26300'
        $script:Packages = @()
        try { Invoke-PreparationTransition } catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly 'feature-components-lost'
        Should -Invoke Invoke-PreparationUpdates -Times 0 -Exactly
        (Read-Journal).rebuild.rebuilt | Should -BeFalse
    }

    It 'keeps the in-place move it recorded after the Vanta install removed a package' {
        $script:Windows.CurrentBuildNumber = '26300'
        Invoke-PreparationTransition | Should -Be 'complete'
        # The install's Defender choice uninstalled the package the record lists.
        $script:Packages = @()
        Invoke-PreparationTransition | Should -Be 'complete'
        $journal = Read-Journal
        @($journal.history | Where-Object { $_.event -eq 'moved' }).Count | Should -Be 1
        $journal.rebuild.rebuilt | Should -BeFalse
        @($journal.rebuild.signals) | Should -BeNullOrEmpty
        (Test-VantaWindowsTransitionOpen).Rebuild | Should -BeExactly 'in-place'
    }

    It 'takes a Rebase that put Vanta back for neither another Rebase nor lost components' {
        $script:Windows.CurrentBuildNumber = '26300'
        $journal = Read-Journal
        $journal | Add-Member -NotePropertyName carry -NotePropertyValue (ConvertTo-VantaTransitionCarry (New-Vanta050Fact) $script:Packages) -Force
        Write-VantaWindowsTransition $journal
        $script:Packages = @()
        $script:RebuildFacts = [pscustomobject]@{ WindowsOld = $true; SetupFolder = $true; PantherWritten = $true; VantaModules = $false }
        Invoke-PreparationTransition | Should -Be 'complete'
        # The Rebase install's last step leaves the record open over one setting.
        Mock Set-VantaTransitionServiceStart { throw 'Access is denied' } -ParameterFilter { $Name -eq 'wuauserv' }
        Mock Get-VantaTransitionOwnerRecord { $false }
        { Complete-VantaWindowsTransition -Rebased } | Should -Throw '*couldn''t put back*'
        (Test-VantaWindowsTransitionOpen).Rebuild | Should -BeExactly 'in-place'
        Invoke-PreparationTransition | Should -Be 'complete'
        (Read-Journal).rebuild.rebuilt | Should -BeFalse
        Get-VantaWindowsTransitionRebase | Should -BeNullOrEmpty
    }

    It 'records a rebuild by Setup, keeps going, and gives the Vanta install the recorded version and choices' {
        $script:Windows.CurrentBuildNumber = '26300'
        $journal = Read-Journal
        $journal | Add-Member -NotePropertyName carry -NotePropertyValue (ConvertTo-VantaTransitionCarry (New-Vanta050Fact) $script:Packages) -Force
        Write-VantaWindowsTransition $journal
        $script:Packages = @()
        $script:RebuildFacts = [pscustomobject]@{ WindowsOld = $true; SetupFolder = $true; PantherWritten = $true; VantaModules = $false }
        Invoke-PreparationTransition | Should -Be 'complete'
        $after = Read-Journal
        $after.rebuild.rebuilt | Should -BeTrue
        @($after.rebuild.signals) | Should -Be @('windows-old', 'setup-folder', 'setup-log', 'packages-missing', 'vanta-files-missing')
        Should -Invoke Invoke-PreparationUpdates -Times 1 -Exactly
        $rebase = Get-VantaWindowsTransitionRebase
        $rebase.VantaVersion | Should -BeExactly '0.5.0'
        @($rebase.Options) | Should -Contain 'mitigations-default'
    }
}

Describe 'Putting the settings back' {
    BeforeEach {
        Reset-Machine
        Set-HeldBackUpdate
        Set-Fake $script:Policy DeferQualityUpdates DWord 1
        Set-Fake $script:Policy DeferQualityUpdatesPeriodInDays DWord 30
        $journal = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) `
            -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794' }) -UserSid 'S'
        Invoke-VantaWindowsUpdateLift $journal
        Set-VantaFeatureUpdateTarget -Release '26H2'
        $script:Writes.Clear()
    }

    It 'puts back everything, the malformed target included, when Windows did not move' {
        $result = Restore-VantaWindowsTransition -Outcome Abandoned
        (Get-Fake $script:Policy DisableWindowsUpdateAccess).Data | Should -Be 1
        (Get-Fake "$script:Services\wuauserv" Start).Data | Should -Be 4
        (Get-Fake $script:Ux PauseUpdatesExpiryTime).Data | Should -BeExactly '3000-12-31T14:03:37Z'
        (Get-Fake $script:Policy DeferQualityUpdatesPeriodInDays).Data | Should -Be 30
        $pin = Get-Fake $script:Policy TargetReleaseVersion
        $pin.Kind | Should -BeExactly 'String'
        $pin.Data | Should -BeExactly '24H2'
        Get-Fake $script:Policy TargetReleaseVersionInfo | Should -BeNullOrEmpty
        $result.pin | Should -BeExactly 'restored'
    }

    It 'keeps the new target after Windows moved' {
        $result = Restore-VantaWindowsTransition -Outcome Moved
        (Get-Fake $script:Policy TargetReleaseVersionInfo).Data | Should -BeExactly '26H2'
        (Get-Fake $script:Policy TargetReleaseVersion).Kind | Should -BeExactly 'DWord'
        (Get-Fake $script:Policy DisableWindowsUpdateAccess).Data | Should -Be 1
        $result.pin | Should -BeExactly 'kept'
    }

    It 'leaves what the install''s replay owns and restores what nothing owns' {
        $result = Restore-VantaWindowsTransition -Outcome Installed
        Get-Fake $script:Policy DisableWindowsUpdateAccess | Should -BeNullOrEmpty -Because 'the replayed toggle decides it'
        (Get-Fake "$script:Services\wuauserv" Start).Data | Should -Be 3
        (Get-Fake $script:Policy DeferQualityUpdates).Data | Should -Be 1 -Because 'no toggle owns the 0.5.0 delay'
        @($result.owned) | Should -Contain 'service.wuauserv'
        @($result.restored) | Should -Contain 'policy.DeferQualityUpdates'
    }

    It 'puts back what a toggle owned when the install cleared its recorded state' {
        # The key stays, with its path, after the replay clears a state it no longer uses.
        Remove-VantaTransitionValue 'SOFTWARE\Vanta\Services\ToggleWindowsUpdates' 'state'
        $result = Restore-VantaWindowsTransition -Outcome Installed
        (Get-Fake "$script:Services\wuauserv" Start).Data | Should -Be 4
        @($result.restored) | Should -Contain 'service.wuauserv'
        @($result.owned) | Should -Not -Contain 'service.wuauserv'
    }

    It 'leaves a value someone changed after Vanta lifted it' {
        Set-Fake "$script:Services\wuauserv" Start DWord 2
        $result = Restore-VantaWindowsTransition -Outcome Abandoned
        (Get-Fake "$script:Services\wuauserv" Start).Data | Should -Be 2
        @($result.changed) | Should -Contain 'service.wuauserv'
    }

    # The app reads these fixtures; the worker must accept each record and write
    # results with the same fields, so neither side drifts from them.
    It 'accepts the records and writes the result the app''s fixtures show' {
        $fixtures = Join-Path $PSScriptRoot 'fixtures\windows-transition'
        foreach ($name in @('journal-access.json', 'journal-transition.json', 'journal-rebuilt.json')) {
            $record = Get-Content -LiteralPath (Join-Path $fixtures $name) -Raw | ConvertFrom-Json
            Test-VantaWindowsTransitionJournal $record | Should -BeTrue -Because $name
        }
        $expected = @((Get-Content -LiteralPath (Join-Path $fixtures 'last-result.json') -Raw | ConvertFrom-Json).PSObject.Properties.Name)
        $result = Restore-VantaWindowsTransition -Outcome Abandoned
        @($result.PSObject.Properties.Name) | Should -Be $expected
    }

    It 'puts back what it can when one setting fails, keeps the record open, and only retries that one' {
        $script:FailService = $true
        Mock Set-VantaTransitionServiceStart {
            if ($script:FailService -and $Name -eq 'wuauserv') { throw 'Access is denied' }
            Set-Fake "$script:Services\$Name" Start DWord $Start
        }
        $failure = $null
        try { [void](Restore-VantaWindowsTransition -Outcome Abandoned) } catch { $failure = $_.Exception }
        $failure.Data['reason'] | Should -BeExactly 'feature-restore'
        $failure.Data['setting'] | Should -BeExactly 'service.wuauserv'
        (Get-Fake $script:Policy DeferQualityUpdatesPeriodInDays).Data | Should -Be 30 -Because 'the others went back'
        (Get-Fake "$script:Services\wuauserv" Start).Data | Should -Be 3
        $open = Read-VantaWindowsTransition
        @($open.items | Where-Object lifted | ForEach-Object id) | Should -Be @('service.wuauserv')

        $script:FailService = $false
        $result = Restore-VantaWindowsTransition -Outcome Abandoned
        (Get-Fake "$script:Services\wuauserv" Start).Data | Should -Be 4
        @($result.restored) | Should -Be @('service.wuauserv')
        @($result.changed) | Should -BeNullOrEmpty -Because 'what went back the first time is not taken for a change'
        Read-VantaWindowsTransition | Should -BeNullOrEmpty
    }

    It 'closes the record last, keeps the result, and does nothing a second time' {
        [void](Restore-VantaWindowsTransition -Outcome Abandoned)
        $script:Writes[-2] | Should -BeExactly "remove $script:Record|Journal"
        $script:Writes[-1] | Should -BeExactly "set $script:Record|LastResult"
        $last = (Get-Fake $script:Record LastResult).Data | ConvertFrom-Json
        $last.outcome | Should -BeExactly 'Abandoned'
        @($last.history.event) | Should -Contain 'restore'
        $script:Writes.Clear()
        Restore-VantaWindowsTransition -Outcome Abandoned | Should -BeNullOrEmpty
        @($script:Writes) | Should -BeNullOrEmpty
    }

    It 'keeps the new target when put back before the owed restart' {
        Use-TransitionRun
        $journal = Read-Journal
        Set-PreparationInstalled $journal 'update=fixture'
        Mock Write-PreparationState {}
        $saved = $env:WINDIR
        try {
            $env:WINDIR = $TestDrive
            Invoke-PreparationRestore
        }
        finally { $env:WINDIR = $saved }
        (Get-Fake $script:Policy TargetReleaseVersionInfo).Data | Should -BeExactly '26H2'
        ((Get-Fake $script:Record LastResult).Data | ConvertFrom-Json).outcome | Should -BeExactly 'Moved'
    }

    It 'refuses while an Vanta install is unfinished' {
        $saved = $env:WINDIR
        try {
            $env:WINDIR = $TestDrive
            [void][IO.Directory]::CreateDirectory((Join-Path $TestDrive 'VantaOS\Install'))
            [IO.File]::WriteAllText((Join-Path $TestDrive 'VantaOS\Install\active.json'), '{}')
            try { Invoke-PreparationRestore } catch { $thrown = $_.Exception }
        }
        finally {
            $env:WINDIR = $saved
            Remove-Item -LiteralPath (Join-Path $TestDrive 'VantaOS') -Recurse -Force
        }
        $thrown.Data['reason'] | Should -BeExactly 'feature-install-active'
        @($script:Writes) | Should -BeNullOrEmpty
    }

    It 'leaves the record of a Windows that rebuilt itself to the install that puts Vanta back' {
        $journal = Read-Journal
        $journal | Add-Member -NotePropertyName carry -NotePropertyValue ([pscustomobject]@{
                vantaVersion = '0.5.0'; options = @('defender-disable'); optionSource = 'observed'; toggles = @(); browser = $null
                vantaModules = $true; edge = $false; oneDrive = $false; defender = $false; appx = @('Microsoft.Paint_8wekyb3d8bbwe') }) -Force
        $journal | Add-Member -NotePropertyName rebuild -NotePropertyValue ([pscustomobject]@{ rebuilt = $true; signals = @('windows-old'); checkedAt = '2026-10-02T00:00:00Z' }) -Force
        Write-VantaWindowsTransition $journal
        $script:Writes.Clear()
        $saved = $env:WINDIR
        try {
            $env:WINDIR = $TestDrive
            try { Invoke-PreparationRestore } catch { $thrown = $_.Exception }
        }
        finally { $env:WINDIR = $saved }
        $thrown.Data['reason'] | Should -BeExactly 'feature-install-active'
        @($script:Writes) | Should -BeNullOrEmpty
        Get-VantaWindowsTransitionRebase | Should -Not -BeNullOrEmpty
    }

    It 'records a Rebase as done before a setting that fails to go back keeps the record open' {
        $journal = Read-Journal
        $journal | Add-Member -NotePropertyName carry -NotePropertyValue ([pscustomobject]@{
                vantaVersion = '0.5.0'; options = @('defender-disable'); optionSource = 'observed'; toggles = @(); browser = $null
                vantaModules = $true; edge = $false; oneDrive = $false; defender = $false; appx = @('Microsoft.Paint_8wekyb3d8bbwe') }) -Force
        $journal | Add-Member -NotePropertyName rebuild -NotePropertyValue ([pscustomobject]@{ rebuilt = $true; signals = @('windows-old'); checkedAt = '2026-10-02T00:00:00Z' }) -Force
        Write-VantaWindowsTransition $journal
        Mock Set-VantaTransitionServiceStart { throw 'Access is denied' } -ParameterFilter { $Name -eq 'wuauserv' }
        Mock Get-VantaTransitionOwnerRecord { $false }
        { Complete-VantaWindowsTransition -Rebased } | Should -Throw '*couldn''t put back*'
        Read-VantaWindowsTransition | Should -Not -BeNullOrEmpty -Because 'the setting is still to be put back'
        Get-VantaWindowsTransitionRebase | Should -BeNullOrEmpty -Because 'a later install is not another Rebase'
    }

    It 'is the install''s closing step, which reports what it left' {
        $lines = @(Complete-VantaWindowsTransition)
        ($lines -join "`n") | Should -Match 'Left as the replayed choices set them: .*service\.wuauserv'
        Get-Fake $script:Record Journal | Should -BeNullOrEmpty
        Complete-VantaWindowsTransition | Should -Match 'nothing to put back'
    }
}

Describe 'Install and toggle guards while Windows Update is turned on' {
    BeforeAll {
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $script:VantaTestScriptsRoot 'Entry\Install-Vanta.ps1'), [ref]$null, [ref]$null)
        $guard = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-VantaWindowsUpdateInProgress' }, $true)
        . ([scriptblock]::Create($guard.Extent.Text))
    }
    BeforeEach { Reset-Machine; Set-HeldBackUpdate }

    It 'blocks the install while Windows has not reached the target' {
        [void](Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) `
                -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794' }) -UserSid 'S')
        $result = Test-VantaWindowsUpdateInProgress -WindowsBuild 26100
        $result.Passed | Should -BeFalse
        $result.Blocking | Should -BeTrue
        $unchecked = Test-VantaWindowsUpdateInProgress -WindowsBuild 26300
        $unchecked.Passed | Should -BeFalse -Because 'how Windows moved decides the install mode'
        $unchecked.Detail | Should -Match 'not checked how Windows moved'

        $journal = Read-VantaWindowsTransition
        $journal | Add-Member -NotePropertyName rebuild -NotePropertyValue ([pscustomobject]@{ rebuilt = $false; signals = @('windows-old'); checkedAt = '2026-10-02T00:00:00Z' }) -Force
        Write-VantaWindowsTransition $journal
        # The install itself changes the Vanta packages, so only the recorded decision counts.
        Mock Get-VantaInstalledVantaPackage { @() }
        (Test-VantaWindowsUpdateInProgress -WindowsBuild 26300).Passed | Should -BeTrue
        $journal.rebuild.signals = @('packages-missing')
        Write-VantaWindowsTransition $journal
        $lost = Test-VantaWindowsUpdateInProgress -WindowsBuild 26300
        $lost.Passed | Should -BeFalse
        $lost.Detail | Should -Match 'Vanta packages are gone'
    }


    It 'allows a plain update''s record and blocks an unreadable one' {
        [void](Save-VantaWindowsTransitionSnapshot -Kind access -Source ([pscustomobject]@{ build = 26200 }) -Target $null -UserSid 'S')
        (Test-VantaWindowsUpdateInProgress -WindowsBuild 26200).Passed | Should -BeTrue
        Set-Fake $script:Record Journal String '{not json'
        $unreadable = Test-VantaWindowsUpdateInProgress -WindowsBuild 26200
        $unreadable.Passed | Should -BeFalse
        $unreadable.Detail | Should -Match 'cannot be read'
        Reset-Machine
        (Test-VantaWindowsUpdateInProgress -WindowsBuild 26200).Passed | Should -BeTrue
    }

    It 'refuses the Windows Update and pause toggles by hand while the record is open, and only those' {
        { Assert-VantaToggleAllowedDuringTransition -Name ToggleWindowsUpdates } | Should -Not -Throw
        [void](Save-VantaWindowsTransitionSnapshot -Kind access -Source ([pscustomobject]@{ build = 26200 }) -Target $null -UserSid 'S')
        { Assert-VantaToggleAllowedDuringTransition -Name ToggleWindowsUpdates } | Should -Throw '*Vanta Manager is updating Windows*'
        { Assert-VantaToggleAllowedDuringTransition -Name PauseUpdates } | Should -Throw '*Vanta Manager is updating Windows*'
        { Assert-VantaToggleAllowedDuringTransition -Name AutomaticUpdates } | Should -Not -Throw
    }
}

Describe 'The install''s closing step' {
    BeforeAll { . (Join-Path $script:VantaTestScriptsRoot 'Install\Install-Plan.ps1') }

    It 'runs in <Mode> after the choices are replayed and the pin is written' -TestCases @(
        @{ Mode = 'Fresh' }, @{ Mode = 'Upgrade' }, @{ Mode = 'Reapply' }, @{ Mode = 'Rebase' }
    ) {
        param($Mode)
        $keys = @((Get-VantaInstallPlan -Mode $Mode).Key)
        $index = [array]::IndexOf($keys, 'Checkpoint/WindowsTransition')
        $index | Should -BeGreaterThan ([array]::IndexOf($keys, 'Defaults'))
        if ($keys -contains 'Tweaks/qol') { $index | Should -BeGreaterThan ([array]::IndexOf($keys, 'Tweaks/qol')) }
    }
}

Describe 'Disk cleanup while a move may need undoing' {
    BeforeAll {
        $previousErrorActionPreference = $ErrorActionPreference
        try { . (Join-Path $script:VantaTestScriptsRoot 'Install\Tasks\Invoke-DiskCleanup.ps1') -Scope CurrentUser -ExpectedUserSid 'not-a-sid' }
        catch { if ($_.Exception.Message -notlike '*is invalid*') { throw } }
        finally { $ErrorActionPreference = $previousErrorActionPreference }
    }

    It 'keeps setup logs, driver packages and restore points' {
        $script:Flags = @{}
        Mock Get-Process {}
        Mock Test-Path { $true }
        Mock Set-ItemProperty { $script:Flags[(Split-Path -Leaf $LiteralPath)] = $Value }
        Mock Start-Process {}
        Mock Test-VantaOtherWindowsInstall { $false }
        Mock Invoke-VantaTempCleanup {}
        Mock Invoke-VantaSystemShadowCopyCleanup {}
        $tools = Join-Path $TestDrive 'tools'
        [void][IO.Directory]::CreateDirectory($tools)
        foreach ($name in 'cleanmgr.exe', 'vssadmin.exe') { [IO.File]::WriteAllText((Join-Path $tools $name), '') }
        Invoke-VantaMachineCleanup -SystemRoot $TestDrive -WindowsRoot $TestDrive -CleanMgrPath (Join-Path $tools 'cleanmgr.exe') `
            -VssAdminPath (Join-Path $tools 'vssadmin.exe') -KeepRecovery
        $script:Flags['Setup Log Files'] | Should -Be 0
        $script:Flags['Device Driver Packages'] | Should -Be 0
        $script:Flags['Temporary Sync Files'] | Should -Be 2
        Should -Invoke Invoke-VantaSystemShadowCopyCleanup -Times 0 -Exactly
    }
}

Describe 'What the record keeps of the Vanta install' {
    BeforeEach { Reset-Machine }

    It 'reads an Vanta 0.5.0 install''s choices from what they left, and leaves out what nothing shows' {
        $carry = ConvertTo-VantaTransitionCarry (New-Vanta050Fact) @('Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~5.0.0.0')
        $carry.vantaVersion | Should -BeExactly '0.5.0'
        $carry.optionSource | Should -BeExactly 'observed'
        @($carry.options) | Should -Be @('defender-disable', 'mitigations-default', 'auto-updates-disable', 'disable-hibernation', 'uninstall-edge', 'remove-snipping-tool',
            'disable-core-isolation', 'install-another-browser', 'browser-brave')
        $carry.browser | Should -BeExactly 'Brave'
        @($carry.toggles).Count | Should -Be 5
        $carry.oneDrive | Should -BeFalse
        Test-VantaTransitionCarry $carry | Should -BeTrue
    }

    It 'leaves out a Mitigations choice only the old Toolbox recorded, so a Rebase neither holds the update to it nor puts it back' {
        $facts = New-Vanta050Fact
        $facts.Toggles = @([pscustomobject]@{ name = 'Mitigations'; state = 2 }, [pscustomobject]@{ name = 'AutomaticUpdates'; state = 0 })
        $carry = ConvertTo-VantaTransitionCarry $facts @()
        @($carry.options | Where-Object { $_ -like 'mitigations-*' }) | Should -BeNullOrEmpty
        @($carry.toggles | ForEach-Object { $_.name }) | Should -Be @('AutomaticUpdates')
        Test-VantaTransitionCarry $carry | Should -BeTrue

        # The launcher that applied it decides, whatever the Toolbox wrote over it since.
        $facts.Toggles = @([pscustomobject]@{ name = 'Mitigations'; state = 2; path = 'Disable All Mitigations.cmd' })
        $carry = ConvertTo-VantaTransitionCarry $facts @()
        @($carry.options) | Should -Contain 'mitigations-disable'
        @($carry.toggles)[0].state | Should -Be 0
        @($carry.toggles)[0].path | Should -BeExactly 'Disable All Mitigations.cmd'
        Test-VantaTransitionCarry $carry | Should -BeTrue
        @($facts.Toggles)[0].state | Should -Be 2 -Because 'the facts it was given stay as they were'
    }

    # toolbox-records.json, which the update's Capture and Vanta Manager are tested
    # on too, each record read from the PC as the record of a move reads it. It
    # repairs only the ones the launcher table names; the Rebase repairs the rest
    # when it puts them back. A path that names no file isn't kept in the record, so
    # that case is the Capture's alone.
    It 'keeps a shared Toolbox record as the update''s Capture leaves it: <name>' -ForEach @(
        (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\windows-transition\toolbox-records.json') -Raw | ConvertFrom-Json) |
            Where-Object { $null -eq $_.path -or ($_.path -split '[\\/]')[-1] } |
            ForEach-Object { @{ name = $_.name; version = $_.version; record = $_.key; state = $_.state; path = $_.path; result = $_.result } }
    ) {
        Set-Fake "SOFTWARE\Vanta\Services\$record" state DWord ([int64]$state)
        if ($null -ne $path) { Set-Fake "SOFTWARE\Vanta\Services\$record" path String $path }
        $facts = New-Vanta050Fact
        $facts.Toggles = @(Get-VantaTransitionToggleRecord)
        if ([version]$version -lt [version]'0.6') { $facts.LegacyVersions = @($version) }
        else {
            $facts.LegacyVersions = @()
            $facts.State = [pscustomobject]@{ installedVersion = $version; options = @() }
        }
        $carry = ConvertTo-VantaTransitionCarry $facts @()
        $kept = @($carry.toggles | ForEach-Object { "$($_.name)=$($_.state)" }) -join ','
        if (@(Get-VantaToolboxLauncherRule | ForEach-Object { $_.Name }) -cnotcontains $record) { $kept | Should -BeExactly "$record=$state" -Because $name }
        elseif ($null -eq $result) { $kept | Should -BeNullOrEmpty -Because $name }
        else { $kept | Should -BeExactly "$($result.key)=$($result.state)" -Because $name }
    }

    It 'keeps Defender and Edge when they were there, and asks again when no record shows a choice' {
        $facts = New-Vanta050Fact
        $facts.Edge = $true
        $facts.Toggles = @()
        $facts.Appx = @('Microsoft.ScreenSketch_8wekyb3d8bbwe')
        $facts.Toolbox = $false
        $facts.CoreIsolationOff = $false
        $facts.Browser = $null
        $carry = ConvertTo-VantaTransitionCarry $facts @('Z-Vanta-NoTelemetry-Package~31bf3856ad364e35~amd64~~5.0.0.0')
        @($carry.options) | Should -Be @('defender-enable')
    }

    It 'finds OneDrive another account installed, not only the one running Vanta' {
        $list = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        Set-Fake "$list\S-1-5-21-1-1001" ProfileImagePath ExpandString 'C:\Users\Alex'
        Set-Fake "$list\S-1-5-21-1-1002" ProfileImagePath ExpandString 'C:\Users\Sam'
        Mock Get-VantaTransitionProfileSid { @('S-1-5-21-1-1001', 'S-1-5-21-1-1002') }
        $script:Present = @('C:\Users\Sam\AppData\Local\Microsoft\OneDrive\OneDrive.exe')
        Mock Test-VantaTransitionPath { $script:Present -contains $Path }
        Test-VantaTransitionOneDrive | Should -BeTrue
        $script:Present = @()
        Test-VantaTransitionOneDrive | Should -BeFalse
        Should -Invoke Test-VantaTransitionPath -ParameterFilter { $Path -like 'C:\Users\Alex\*' }
    }

    It 'finds LibreWolf, which Vanta 0.5.0 records as an empty browser name, only when it is the one browser installed' {
        $facts = New-Vanta050Fact
        $facts.Browser = ''
        $facts.Browsers = @('browser-librewolf')
        @(ConvertTo-VantaTransitionCarry $facts @()).options | Should -Contain 'browser-librewolf'
        $facts.Browsers = @('browser-librewolf', 'browser-firefox')
        @((ConvertTo-VantaTransitionCarry $facts @()).options | Where-Object { $_ -like '*browser*' }) | Should -BeNullOrEmpty
        # Vanta 0.6 writes the empty name for no browser chosen.
        $facts.State = [pscustomobject]@{ installedVersion = '0.6.0'; options = @('defender-enable') }
        $facts.Browsers = @('browser-chrome')
        @((ConvertTo-VantaTransitionCarry $facts @()).options | Where-Object { $_ -like '*browser*' }) | Should -BeNullOrEmpty
    }

    It 'reads core isolation from the values Vanta 0.5.0 and Windows leave: <name>' -ForEach @(
        (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\windows-transition\core-isolation.json') -Raw | ConvertFrom-Json) |
            ForEach-Object { @{ name = $_.name; values = $_.values; off = $_.off } }
    ) {
        $deviceGuard = 'SYSTEM\CurrentControlSet\Control\DeviceGuard'
        if ($null -ne $values.enableVirtualizationBasedSecurity) { Set-Fake $deviceGuard EnableVirtualizationBasedSecurity DWord ([int64]$values.enableVirtualizationBasedSecurity) }
        if ($null -ne $values.hypervisorEnforcedCodeIntegrity) { Set-Fake "$deviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" Enabled DWord ([int64]$values.hypervisorEnforcedCodeIntegrity) }
        if ($null -ne $values.runAsPpl) { Set-Fake 'SYSTEM\CurrentControlSet\Control\Lsa' RunAsPPL DWord ([int64]$values.runAsPpl) }
        Test-VantaTransitionCoreIsolationOff | Should -Be ([bool]$off)
    }

    It 'takes a recorded install''s options, with what the PC shows over the choices an earlier install never applied' {
        $facts = New-Vanta050Fact
        $facts.State = [pscustomobject]@{ installedVersion = '0.6.0'; options = @('defender-enable', 'mitigations-disable', 'auto-updates-default', 'install-eclean') }
        $facts.Toggles = @([pscustomobject]@{ name = 'Mitigations'; state = 2 })
        $facts.Edge = $true
        $facts.Appx = @()
        $facts.Toolbox = $false
        $facts.CoreIsolationOff = $false
        $facts.Browser = $null
        $carry = ConvertTo-VantaTransitionCarry $facts @('Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~5.0.0.0', 'Z-Vanta-NoTelemetry-Package~31bf3856ad364e35~amd64~~5.0.0.0')
        $carry.vantaVersion | Should -BeExactly '0.6.0'
        $carry.optionSource | Should -BeExactly 'recorded'
        @($carry.options) | Should -Be @('auto-updates-default', 'install-eclean', 'defender-disable', 'mitigations-default')
        Test-VantaTransitionCarry $carry | Should -BeTrue
    }

    It 'keeps the recorded choices the PC doesn''t show, a kept Defender missing without an Vanta package among them' {
        $facts = [pscustomobject]@{
            State = [pscustomobject]@{ installedVersion = '0.6.0-rc11'; options = @('defender-enable', 'keyboard-single', 'uninstall-edge', 'install-eclean') }
            LegacyVersions = @(); Toggles = @(); Browser = $null; VantaModules = $true; Edge = $false; OneDrive = $false; Defender = $false
            Appx = @(); Toolbox = $false; CoreIsolationOff = $false; Browsers = @()
        }
        @((ConvertTo-VantaTransitionCarry $facts @()).options) | Should -Be @('defender-enable', 'keyboard-single', 'install-eclean', 'uninstall-edge')
    }

    It 'accepts the record of a rebuilt Windows the app reads too, and gives the Vanta install its version and choices' {
        $text = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\windows-transition\journal-rebuilt.json') -Raw
        Set-Fake $script:Record Journal String $text
        $rebase = Get-VantaWindowsTransitionRebase
        $rebase.VantaVersion | Should -BeExactly '0.5.0'
        @($rebase.Options) | Should -Contain 'defender-disable'
        $rebase.Rebuild.rebuilt | Should -BeTrue
        $rebase.Carry.browser | Should -BeExactly 'Brave'
    }

    It 'reads the same options as the app for every shared case' {
        $cases = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\windows-transition\observed-options.json') -Raw | ConvertFrom-Json
        @($cases).Count | Should -BeGreaterThan 0
        foreach ($case in @($cases)) {
            $optional = { param($Name) $property = $case.facts.PSObject.Properties[$Name]; if ($null -ne $property) { $property.Value } }
            # A case that didn't read the WinDefend service key leaves defender out.
            $facts = [pscustomobject]@{
                State = $null; LegacyVersions = @('0.5.0'); Toggles = @($case.facts.toggles)
                Browser = $case.facts.browser; VantaModules = $true; Edge = $case.facts.edge; OneDrive = $false; Defender = & $optional 'defender'
                Appx = @($case.facts.appx); Toolbox = $case.facts.toolbox; CoreIsolationOff = $case.facts.coreIsolationOff; Browsers = @($case.facts.browsers)
                LanguageHotkey = & $optional 'languageHotkey'; KeyboardLayouts = [int](& $optional 'keyboardLayouts')
            }
            # The cases' records name no launcher, so the record of a move would
            # first leave out the Mitigations one as the old Toolbox's; the
            # Toolbox records have cases of their own (toolbox-records.json).
            (@(Get-VantaTransitionObservedOption $facts @($case.packages)) -join ',') | Should -BeExactly (@($case.options) -join ',') -Because $case.name
            # With nothing recorded, the merge gives the same options, except that an
            # empty browser name, Vanta 0.5.0's LibreWolf, names no browser on an
            # install with a record.
            $expected = @($case.options)
            if ('' -ceq $case.facts.browser) { $expected = @($expected | Where-Object { $_ -notlike 'browser-*' -and $_ -cne 'install-another-browser' }) }
            (@(Merge-VantaObservedOption @() $facts @($case.packages)) -join ',') | Should -BeExactly ($expected -join ',') -Because "$($case.name), merged over nothing"
        }
    }

    It 'keeps no version or choices on a PC without Vanta' {
        $facts = New-Vanta050Fact
        $facts.LegacyVersions = @()
        $carry = ConvertTo-VantaTransitionCarry $facts @()
        $carry.vantaVersion | Should -BeNullOrEmpty
        @($carry.options) | Should -BeNullOrEmpty
        $carry.optionSource | Should -BeExactly 'none'
    }

    It 'refuses a record whose kept install has <Case>' -TestCases @(
        @{ Case = 'an unknown option shape'; Change = { param($c) $c.options = @('Defender Disable') } }
        @{ Case = 'a toggle name with a path in it'; Change = { param($c) $c.toggles = @([pscustomobject]@{ name = '..\Policies'; state = 0 }) } }
        @{ Case = 'a version that is not one'; Change = { param($c) $c.vantaVersion = '0.5.0; rm' } }
        @{ Case = 'a flag that is not true or false'; Change = { param($c) $c.oneDrive = 'yes' } }
    ) {
        param($Case, $Change)
        $carry = ConvertTo-VantaTransitionCarry (New-Vanta050Fact) @()
        & $Change $carry
        $journal = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) `
            -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794,5129195' }) -UserSid 'S'
        $journal | Add-Member -NotePropertyName carry -NotePropertyValue $carry -Force
        try { Write-VantaWindowsTransition $journal } catch { $thrown = $_.Exception }
        $thrown.Data['reason'] | Should -BeExactly 'feature-journal' -Because $Case
    }

    It 'keeps it in the record of a move, and in a copy that stands in when the registry record is gone' {
        $journal = Save-VantaWindowsTransitionSnapshot -Kind transition -Source ([pscustomobject]@{ build = 26100 }) `
            -Target ([pscustomobject]@{ release = '26H2'; build = 26300; kb = '5121794,5129195' }) -UserSid 'S' `
            -Carry (ConvertTo-VantaTransitionCarry (New-Vanta050Fact) @())
        $journal.carry.vantaVersion | Should -BeExactly '0.5.0'
        $script:Copy | Should -Not -BeNullOrEmpty
        $script:Registry.Remove("$script:Record|Journal")
        (Read-VantaWindowsTransition).carry.browser | Should -BeExactly 'Brave'
        Remove-VantaWindowsTransition
        $script:Writes.IndexOf('remove copy') | Should -BeLessThan $script:Writes.IndexOf("remove $script:Record|Journal") -Because 'a copy left behind must never bring back a closed record'
        Read-VantaWindowsTransition | Should -BeNullOrEmpty
    }

    It 'never trusts a copy someone else owns' {
        $path = Join-Path $TestDrive 'copy\journal.json'
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
        [IO.File]::WriteAllText($path, '{}')
        # An elevated run creates files owned by Administrators, so hand the copy
        # to the account running the tests, which the copy never trusts.
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User
        if ($me.Value -eq 'S-1-5-18') { Set-ItResult -Skipped -Because 'SYSTEM is an owner the copy trusts'; return }
        $acl = [IO.File]::GetAccessControl($path)
        $acl.SetOwner($me)
        [IO.File]::SetAccessControl($path, $acl)
        $thrown = & {
            . $script:Library
            function Get-VantaTransitionCopyPath { $path }
            try { Read-VantaTransitionCopy } catch { $_.Exception }
        }
        $thrown.Data['reason'] | Should -BeExactly 'feature-journal'
    }

    It 'records the install''s choices only for the first record of a move' {
        $script:Windows.CurrentBuildNumber = '26100'
        Mock Test-PreparationRestart { $false }
        Mock Test-PreparationNetwork { $true }
        Mock Invoke-PreparationWindows { 'reboot' }
        Mock Write-PreparationState {}
        Mock Assert-PreparationContinue {}
        Mock Get-VantaTransitionCarry { ConvertTo-VantaTransitionCarry (New-Vanta050Fact) $VantaPackages }
        Use-TransitionRun
        Invoke-PreparationTransition | Should -Be 'reboot'
        (Read-Journal).carry.vantaVersion | Should -BeExactly '0.5.0'
        Invoke-PreparationTransition | Should -Be 'reboot'
        Should -Invoke Get-VantaTransitionCarry -Times 1 -Exactly
    }
}

Describe 'What the PC shows over recorded choices' {
    # merged-options.json, which Vanta Manager's tests read too. Each case has:
    #   base          the options recorded or requested
    #   packages      the Vanta packages at CurrentState 112 and, after the install,
    #                 those waiting for the restart as well
    #   facts         what the PC shows, named as in observed-options.json, with
    #                 defender (whether the WinDefend service key exists) and
    #                 defenderPackage (Installed, InstallPending or UninstallPending);
    #                 a fact left out, or null, wasn't read. Unlike there, an empty
    #                 browser name names no browser. In place of toolbox, a case may
    #                 give toolboxRecord and toolboxProgram (the Toolbox installer's
    #                 key and AtlasToolbox.exe); in place of appx, profiles (the
    #                 accounts in Windows's profile list) and appxPackages, each a
    #                 family with the sid and InstallState of every account
    #                 Get-AppxPackage -AllUsers lists for it. Vanta Manager reads only
    #                 its own account's apps, so only cases after the install do.
    #   afterInstall  whether the install has just changed the PC
    #   options       the merged options, in any order
    BeforeAll {
        # A case's facts as the machine facts give them, read by the same rules.
        function ConvertTo-CaseFact($Facts) {
            $facts = $Facts.PSObject.Copy()
            if ($null -ne $facts.PSObject.Properties['toolboxRecord']) {
                $toolbox = Test-VantaTransitionToolboxInstalled ([bool]$facts.toolboxRecord) ([bool]$facts.toolboxProgram)
                $facts | Add-Member -NotePropertyName toolbox -NotePropertyValue $toolbox -Force
            }
            if ($null -ne $facts.PSObject.Properties['appxPackages']) {
                $packages = @(foreach ($package in @($facts.appxPackages)) {
                        $users = @(foreach ($user in @($package.users)) {
                                [pscustomobject]@{ UserSecurityId = [pscustomobject]@{ Sid = [string]$user.sid }; InstallState = [string]$user.state }
                            })
                        [pscustomobject]@{ PackageFamilyName = [string]$package.family; PackageUserInformation = $users }
                    })
                $facts | Add-Member -NotePropertyName appx -NotePropertyValue @(Select-VantaTransitionInstalledAppx $packages @($facts.profiles)) -Force
            }
            return $facts
        }
    }

    It 'merges as the app does for the shared case: <name>' -ForEach @(
        (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\windows-transition\merged-options.json') -Raw | ConvertFrom-Json) |
            ForEach-Object { @{ name = $_.name; base = $_.base; facts = $_.facts; packages = $_.packages; afterInstall = $_.afterInstall; options = $_.options } }
    ) {
        $merged = @(Merge-VantaObservedOption @($base) (ConvertTo-CaseFact $facts) @($packages) -AfterInstall:([bool]$afterInstall))
        (@($merged | Sort-Object) -join ',') | Should -BeExactly (@($options | Sort-Object) -join ',')
        @($merged | Select-Object -Unique).Count | Should -Be $merged.Count
    }

    It 'names only options the Vanta package declares, and reads every choice group it declares' {
        $manifest = [IO.File]::ReadAllText((Join-Path $script:VantaTestRepoRoot 'package\atlas.json')) | ConvertFrom-Json
        $declared = @(@($manifest.choices) | ForEach-Object { @($_.options) } | ForEach-Object { [string]$_.id })
        $declared | Should -Contain 'install-eclean'
        foreach ($file in @('merged-options.json', 'observed-options.json')) {
            foreach ($case in @(Get-Content -LiteralPath (Join-Path $PSScriptRoot "fixtures\windows-transition\$file") -Raw | ConvertFrom-Json)) {
                $named = @($case.options)
                if ($null -ne $case.PSObject.Properties['base']) { $named += @($case.base) }
                foreach ($option in $named) { $declared | Should -Contain $option -Because "$file, $($case.name)" }
            }
        }
        # A renamed option would otherwise leave its choice unread.
        foreach ($pattern in @((Get-VantaTransitionChoiceGroup).Values | ForEach-Object { $_ })) {
            @($declared | Where-Object { $_ -like $pattern }) | Should -Not -BeNullOrEmpty -Because $pattern
        }
    }

    It 'keeps a choice added later, which nothing on the PC shows' {
        @(Merge-VantaObservedOption @('defender-enable', 'a-later-choice') ([pscustomobject]@{ Defender = $true }) @()) |
            Should -Be @('a-later-choice', 'defender-enable')
    }

    It 'reads facts given as a hashtable as it reads them given as an object' {
        $facts = @{ Toggles = @(@{ name = 'Mitigations'; state = 1 }); Edge = $true; DefenderPackage = 'Installed'; Browser = $null }
        $base = @('defender-enable', 'mitigations-disable', 'uninstall-edge', 'install-eclean')
        $expected = @('install-eclean', 'defender-disable', 'mitigations-default')
        @(Merge-VantaObservedOption $base $facts @()) | Should -Be $expected
        @(Merge-VantaObservedOption $base ([pscustomobject]$facts) @()) | Should -Be $expected
        @(Merge-VantaObservedOption @('install-another-browser', 'browser-firefox') @{ Browsers = $null; Defender = $true } @() -AfterInstall) |
            Should -Be @('install-another-browser', 'browser-firefox', 'defender-enable') -Because 'a null fact was not read'
    }

    It 'keeps the options it doesn''t replace first, in their order, and repeats none' {
        $facts = [pscustomobject]@{ Toggles = @([pscustomobject]@{ name = 'Mitigations'; state = 1 }) }
        @(Merge-VantaObservedOption @('install-eclean', 'keyboard-single', 'install-eclean', 'mitigations-disable') $facts @()) |
            Should -Be @('install-eclean', 'keyboard-single', 'mitigations-default')
    }

    It 'counts a pending NoDefender package by its state after the install, whatever packages it is given' {
        $pending = [pscustomobject]@{ Defender = $true; DefenderPackage = 'InstallPending' }
        @(Merge-VantaObservedOption @('defender-enable') $pending @() -AfterInstall) | Should -Be @('defender-disable')
        $restored = [pscustomobject]@{ Defender = $false; DefenderPackage = 'UninstallPending' }
        @(Merge-VantaObservedOption @('defender-disable') $restored @('Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~5.0.0.0') -AfterInstall) |
            Should -Be @('defender-enable')
        @(Merge-VantaObservedOption @('defender-disable') $restored @('Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~5.0.0.0')) |
            Should -Be @('defender-disable') -Because 'before an install only an installed package counts'
    }
}

Describe 'Where Vanta''s NoDefender package stands' {
    BeforeAll {
        $script:CbsPackages = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages'
        $script:NoDefender = "$script:CbsPackages\Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~5.0.0.0"
    }
    BeforeEach { Reset-Machine }

    It 'reads <State> from CurrentState <Value>' -ForEach @(
        @{ Value = 112; State = 'Installed' }
        @{ Value = 96; State = 'InstallPending' }
        @{ Value = 5; State = 'UninstallPending' }
    ) {
        Set-Fake $script:NoDefender CurrentState DWord $Value
        Get-VantaTransitionDefenderPackageState | Should -BeExactly $State
        $script:Writes.Count | Should -Be 0
    }

    It 'reads nothing without the package in one of those states' {
        Get-VantaTransitionDefenderPackageState | Should -BeNullOrEmpty
        Set-Fake "$script:CbsPackages\Z-Vanta-NoTelemetry-Package~31bf3856ad364e35~amd64~~5.0.0.0" CurrentState DWord 112
        Get-VantaTransitionDefenderPackageState | Should -BeNullOrEmpty -Because 'only the NoDefender package removes Defender'
        Set-Fake $script:NoDefender CurrentState DWord 80
        Get-VantaTransitionDefenderPackageState | Should -BeNullOrEmpty -Because 'a superseded package is neither installed nor pending'
        Set-Fake $script:NoDefender CurrentState String '112'
        Get-VantaTransitionDefenderPackageState | Should -BeNullOrEmpty -Because 'servicing writes CurrentState as a DWORD'
    }

    It 'counts first the state that leaves Defender removed after the restart, when Windows lists several versions' {
        Set-Fake $script:NoDefender CurrentState DWord 5
        Set-Fake "$script:CbsPackages\Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~6.0.0.0" CurrentState DWord 96
        Get-VantaTransitionDefenderPackageState | Should -BeExactly 'InstallPending'
        Set-Fake "$script:CbsPackages\Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~7.0.0.0" CurrentState DWord 112
        Get-VantaTransitionDefenderPackageState | Should -BeExactly 'Installed'
    }
}

Describe 'An account''s keyboard settings' {
    BeforeAll {
        function Set-TestHiveValue([string]$Sid, [string]$Path, [string]$Name, $Value, [Microsoft.Win32.RegistryValueKind]$Kind) {
            $key = $script:Users.CreateSubKey("$Sid\$Path")
            try { $key.SetValue($Name, $Value, $Kind) }
            finally { $key.Dispose() }
        }
    }
    BeforeEach {
        # A key under the test account's own hive stands in for HKU, with a hive
        # per SID beneath it.
        $script:UsersPath = "Software\VantaRewriteTest\KeyboardHives-$([guid]::NewGuid().ToString('N'))"
        $script:Users = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:UsersPath)
        Mock Get-VantaTransitionUsersRoot { $script:Users }
    }
    AfterEach {
        $script:Users.Dispose()
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($script:UsersPath, $false)
    }

    It 'reads Alt+Shift and the layouts from the hive of the account it names' {
        $sid = 'S-1-5-21-111-222-333-1001'
        Set-TestHiveValue $sid 'Keyboard Layout\Toggle' 'Language Hotkey' '3 ' String
        Set-TestHiveValue $sid 'Keyboard Layout\Preload' '1' '00000809' String
        Set-TestHiveValue $sid 'Keyboard Layout\Preload' '2' '00000415' String
        Set-TestHiveValue 'S-1-5-21-111-222-333-1002' 'Keyboard Layout\Toggle' 'Language Hotkey' '1' String
        Get-VantaTransitionLanguageHotkey -UserSid $sid | Should -BeExactly '3'
        Get-VantaTransitionKeyboardLayoutCount -UserSid $sid | Should -Be 2
        Get-VantaTransitionLanguageHotkey -UserSid 'S-1-5-21-111-222-333-1002' | Should -BeExactly '1'
        Get-VantaTransitionKeyboardLayoutCount -UserSid 'S-1-5-21-111-222-333-1002' | Should -Be 0
    }

    It 'reads Alt+Shift stored as the number Vanta 0.5.0 wrote' {
        Set-TestHiveValue 'S-1-5-21-111-222-333-1001' 'Keyboard Layout\Toggle' 'Language Hotkey' 3 DWord
        Get-VantaTransitionLanguageHotkey -UserSid 'S-1-5-21-111-222-333-1001' | Should -BeExactly '3'
    }

    It 'reads nothing for an account whose hive isn''t loaded' {
        Get-VantaTransitionLanguageHotkey -UserSid 'S-1-5-21-111-222-333-1003' | Should -BeNullOrEmpty
        Get-VantaTransitionKeyboardLayoutCount -UserSid 'S-1-5-21-111-222-333-1003' | Should -Be 0
    }

    It 'reads the account running it, never another hive, without a SID' {
        $null = Get-VantaTransitionLanguageHotkey
        $null = Get-VantaTransitionKeyboardLayoutCount
        Should -Invoke Get-VantaTransitionUsersRoot -Times 0 -Exactly
    }

    It 'refuses a SID that would reach another key' {
        { Get-VantaTransitionLanguageHotkey -UserSid 'S-1-5-21-111-222-333-1001\..\Software' } | Should -Throw '*not an account SID*'
        { Get-VantaTransitionKeyboardLayoutCount -UserSid 'Software' } | Should -Throw '*not an account SID*'
        Should -Invoke Get-VantaTransitionUsersRoot -Times 0 -Exactly
    }
}

Describe 'What the machine facts read' {
    BeforeEach {
        Reset-Machine
        Mock Get-VantaTransitionStateDocument { $null }
        Mock Test-VantaTransitionPath { $false }
        Mock Test-VantaTransitionOneDrive { $false }
        Mock Get-VantaTransitionBrowser { }
        Mock Get-VantaTransitionAppxName { @('Microsoft.Paint_8wekyb3d8bbwe') }
        Mock Get-VantaTransitionLanguageHotkey { "hotkey of $UserSid" }
        Mock Get-VantaTransitionKeyboardLayoutCount { if ($UserSid) { 2 } else { 1 } }
        Set-Fake 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages\Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~5.0.0.0' CurrentState DWord 96
    }

    It 'reads the keyboard settings of the account it names, and where the NoDefender package stands' {
        $facts = Get-VantaTransitionMachineFact -UserSid 'S-1-5-21-111-222-333-1001'
        $facts.LanguageHotkey | Should -BeExactly 'hotkey of S-1-5-21-111-222-333-1001'
        $facts.KeyboardLayouts | Should -Be 2
        $facts.DefenderPackage | Should -BeExactly 'InstallPending'
        @($facts.Appx) | Should -Be @('Microsoft.Paint_8wekyb3d8bbwe')
        (Get-VantaTransitionMachineFact).KeyboardLayouts | Should -Be 1 -Because 'without a SID the account running it counts'
    }

    It 'reads neither the apps nor a user''s keyboard settings with -MachineOnly' {
        Set-Fake 'SOFTWARE\Vanta\Services\KeyboardShortcuts' state DWord 0
        $facts = Get-VantaTransitionMachineFact -MachineOnly
        @($facts.Appx) | Should -BeNullOrEmpty
        $facts.LanguageHotkey | Should -BeNullOrEmpty
        $facts.KeyboardLayouts | Should -BeNullOrEmpty
        $facts.DefenderPackage | Should -BeExactly 'InstallPending'
        Should -Invoke Get-VantaTransitionAppxName -Times 0 -Exactly
        Should -Invoke Get-VantaTransitionLanguageHotkey -Times 0 -Exactly
        Should -Invoke Get-VantaTransitionKeyboardLayoutCount -Times 0 -Exactly
        # A layout count nobody read doesn't pick a single layout.
        $merged = @(Merge-VantaObservedOption @('keyboard-shortcuts', 'remove-snipping-tool') $facts @())
        $merged | Should -Contain 'keyboard-selector'
        $merged | Should -Not -Contain 'keyboard-single'
        $merged | Should -Contain 'remove-snipping-tool' -Because 'an app list nobody read keeps the choice'
    }

    It 'counts the Toolbox only with its program, not by the installer''s record an uninstall leaves' {
        Set-Fake 'SOFTWARE\Vanta\Toolbox' Version String '0.1.13'
        (Get-VantaTransitionMachineFact -MachineOnly).Toolbox | Should -BeFalse
        @(Merge-VantaObservedOption @() (Get-VantaTransitionMachineFact -MachineOnly) @()) | Should -Not -Contain 'install-toolbox'
        Mock Test-VantaTransitionPath { $Path -ceq [IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), 'Atlas Toolbox\AtlasToolbox.exe') }
        (Get-VantaTransitionMachineFact -MachineOnly).Toolbox | Should -BeTrue
        $script:Registry.Remove('SOFTWARE\Vanta\Toolbox|Version')
        (Get-VantaTransitionMachineFact -MachineOnly).Toolbox | Should -BeFalse
    }

    It 'reads the Vanta version from either form of the OEM markers: <Model>' -TestCases @(
        @{ Model = 'Vanta v0.6.0'; Organization = 'Vanta v0.6.0'; Versions = '0.6.0' }
        @{ Model = 'Vanta Playbook v0.5.0'; Organization = 'Vanta Playbook v0.5.0'; Versions = '0.5.0' }
        @{ Model = 'Vanta Playbook 0.4.1'; Organization = 'vanta playbook V0.4.1'; Versions = '0.4.1' }
        @{ Model = 'Vanta v0.6.0'; Organization = 'Vanta Playbook v0.5.0'; Versions = '0.5.0,0.6.0' }
        @{ Model = 'Atlas Toolbox v0.2.0'; Organization = 'Contoso'; Versions = '' }
    ) {
        param($Model, $Organization, $Versions)
        Set-Fake 'SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation' Model String $Model
        Set-Fake 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' RegisteredOrganization String $Organization
        (@(Get-VantaTransitionLegacyVersion | Sort-Object -Unique) -join ',') | Should -BeExactly $Versions
        (@((Get-VantaTransitionMachineFact -MachineOnly).LegacyVersions) -join ',') | Should -BeExactly $Versions
    }

    It 'reads only Vanta''s NoDefender package, by its name and a tilde, as the install reads it' {
        $packages = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages'
        Set-Fake "$packages\Z-Vanta-NoDefender-PackageExtra~31bf3856ad364e35~amd64~~5.0.0.0" CurrentState DWord 112
        Get-VantaTransitionDefenderPackageState | Should -BeExactly 'InstallPending'
    }
}

Describe 'Which apps count as installed' {
    BeforeAll {
        $script:Me = 'S-1-5-21-1000-2000-3000-1001'
        $script:Other = 'S-1-5-21-1000-2000-3000-1002'
        function New-TestPackage([string]$Family, [hashtable]$Users) {
            [pscustomobject]@{
                PackageFamilyName      = $Family
                PackageUserInformation = @(foreach ($sid in $Users.Keys) {
                        [pscustomobject]@{ UserSecurityId = [pscustomobject]@{ Sid = $sid; Username = 'someone' }; InstallState = $Users[$sid] }
                    })
            }
        }
    }

    It 'lists a family only where an account in the profile list has it installed' {
        Mock Get-VantaTransitionProfileSid { $script:Me; $script:Other }
        Mock Get-AppxPackage {
            New-TestPackage 'Microsoft.WindowsCalculator_8wekyb3d8bbwe' @{ $script:Me = 'Installed' }
            New-TestPackage 'Microsoft.WindowsCalculator_8wekyb3d8bbwe' @{ $script:Other = 'Installed' }
            New-TestPackage 'Microsoft.Paint_8wekyb3d8bbwe' @{ 'S-1-5-18' = 'Installed'; $script:Other = 'Installed' }
            New-TestPackage 'Microsoft.ScreenSketch_8wekyb3d8bbwe' @{ 'S-1-5-18' = 'Installed'; $script:Me = 'Staged'; 'S-1-5-21-1000-2000-3000-1009' = 'Installed' }
            New-TestPackage 'Microsoft.BingWeather_8wekyb3d8bbwe' @{ $script:Me = 'Installed(pending removal)' }
            [pscustomobject]@{ PackageFamilyName = 'Microsoft.Todos_8wekyb3d8bbwe' }
        }
        @(Get-VantaTransitionAppxName) | Should -Be @('Microsoft.Paint_8wekyb3d8bbwe', 'Microsoft.WindowsCalculator_8wekyb3d8bbwe')
        Should -Invoke Get-AppxPackage -Times 1 -Exactly -ParameterFilter { $AllUsers }
        # A removal that left Snipping Tool only where nobody can open it counts as done.
        @(Merge-VantaObservedOption @('remove-snipping-tool') ([pscustomobject]@{ Appx = @(Get-VantaTransitionAppxName) }) @() -AfterInstall) |
            Should -Be @('remove-snipping-tool')
    }

    It 'counts every account in the profile list, a work or school one too, and none of the system''s' {
        Reset-Machine
        $script:Work = 'S-1-12-1-1111-2222-3333-4444'
        foreach ($sid in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20', $script:Me, "$script:Me.bak", $script:Work)) {
            Set-Fake "SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" ProfileImagePath ExpandString "C:\Users\$sid"
        }
        @(Get-VantaTransitionProfileSid | Sort-Object) | Should -Be @($script:Work, $script:Me)
        # Snipping Tool kept by the work account is still on this PC.
        Mock Get-AppxPackage {
            New-TestPackage 'Microsoft.ScreenSketch_8wekyb3d8bbwe' @{ $script:Work = 'Installed'; $script:Me = 'Staged' }
            New-TestPackage 'Microsoft.WindowsCalculator_8wekyb3d8bbwe' @{ $script:Me = 'Installed' }
        }
        @(Get-VantaTransitionAppxName) | Should -Be @('Microsoft.ScreenSketch_8wekyb3d8bbwe', 'Microsoft.WindowsCalculator_8wekyb3d8bbwe')
    }

    It 'lists none, which reads as not listed, when the apps can''t be read' {
        Mock Get-VantaTransitionProfileSid { $script:Me }
        Mock Get-AppxPackage { throw 'access denied' }
        @(Get-VantaTransitionAppxName) | Should -BeNullOrEmpty
    }

    It 'reads an account''s registration as Vanta.Appx does' {
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $script:VantaTestModulesRoot 'Vanta.Appx\Domain\Removal.ps1'), [ref]$null, [ref]$null)
        $kind = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-VantaAppxRegistrationKind' }, $true)
        . ([scriptblock]::Create($kind.Extent.Text))
        foreach ($state in @('Installed', 'installed', 'Staged', 'NotInstalled', 'Staged(pending removal)', 'Installed(pending removal)',
                'Installed (pending removal)', 'Paused', 'Modified', '', ' Installed ')) {
            Test-VantaTransitionAppxInstalled $state | Should -Be ((Get-VantaAppxRegistrationKind -InstallState $state) -ceq 'Installed') -Because "'$state'"
        }
    }
}

Describe 'Telling a rebuilt Windows from one switched on in place' {
    BeforeAll {
        # The real reader, on folders under the test drive; the harness stands in for it elsewhere.
        $ast = [Management.Automation.Language.Parser]::ParseFile($script:Library, [ref]$null, [ref]$null)
        $reader = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-VantaTransitionRebuildFact' }, $true)
        . ([scriptblock]::Create($reader.Extent.Text))
    }
    BeforeEach {
        Reset-Machine
        $script:Windows050 = Join-Path $TestDrive 'Drive\Windows'
        Remove-Item -LiteralPath (Join-Path $TestDrive 'Drive') -Recurse -Force -ErrorAction SilentlyContinue
        [void][IO.Directory]::CreateDirectory((Join-Path $script:Windows050 'VantaModules\Scripts'))
        $script:Since = [DateTime]::UtcNow.AddHours(-1)
        $script:Journal = [pscustomobject]@{
            vantaPackages = @('Z-Vanta-NoTelemetry-Package~31bf3856ad364e35~amd64~~5.0.0.0')
            carry = [pscustomobject]@{ vantaModules = $true }
        }
    }

    It 'is not fooled by the empty Windows.old a cumulative update leaves' {
        [void][IO.Directory]::CreateDirectory((Join-Path $TestDrive 'Drive\Windows.old\Windows'))
        $facts = Get-VantaTransitionRebuildFact -Since $script:Since -WindowsPath $script:Windows050
        $facts.WindowsOld | Should -BeFalse
        $rebuild = Resolve-VantaTransitionRebuild $script:Journal $facts @($script:Journal.vantaPackages)
        $rebuild.rebuilt | Should -BeFalse
        $rebuild.setup | Should -BeFalse
    }

    It 'needs Setup''s traces and Vanta''s components gone together' -TestCases @(
        @{ Case = 'Setup ran, Vanta is all there'; Old = $true; Bt = $true; Log = $false; Modules = $true; Packages = $true; Rebuilt = $false; Lost = $false; Decision = 'in-place' }
        @{ Case = 'Windows.old filled but no Setup trace'; Old = $true; Bt = $false; Log = $false; Modules = $false; Packages = $false; Rebuilt = $false; Lost = $true; Decision = 'components-lost' }
        @{ Case = 'Setup log only, Vanta gone'; Old = $false; Bt = $false; Log = $true; Modules = $false; Packages = $false; Rebuilt = $false; Lost = $true; Decision = 'components-lost' }
        @{ Case = 'a rebuild by Setup'; Old = $true; Bt = $false; Log = $true; Modules = $false; Packages = $false; Rebuilt = $true; Lost = $true; Decision = 'rebuilt' }
        @{ Case = 'a rebuild that kept the Vanta folder'; Old = $true; Bt = $true; Log = $false; Modules = $true; Packages = $false; Rebuilt = $true; Lost = $true; Decision = 'rebuilt' }
    ) {
        param($Case, $Old, $Bt, $Log, $Modules, $Packages, $Rebuilt, $Lost, $Decision)
        $drive = Join-Path $TestDrive 'Drive'
        if ($Old) { [void][IO.Directory]::CreateDirectory((Join-Path $drive 'Windows.old\Windows\System32')) }
        if ($Bt) { [void][IO.Directory]::CreateDirectory((Join-Path $drive '$WINDOWS.~BT')) }
        if ($Log) {
            [void][IO.Directory]::CreateDirectory((Join-Path $script:Windows050 'Panther'))
            [IO.File]::WriteAllText((Join-Path $script:Windows050 'Panther\setupact.log'), 'setup')
        }
        if (-not $Modules) { Remove-Item -LiteralPath (Join-Path $script:Windows050 'VantaModules') -Recurse -Force }
        $present = if ($Packages) { @($script:Journal.vantaPackages) } else { @() }
        $rebuild = Resolve-VantaTransitionRebuild $script:Journal (Get-VantaTransitionRebuildFact -Since $script:Since -WindowsPath $script:Windows050) $present
        $rebuild.rebuilt | Should -Be $Rebuilt -Because $Case
        $rebuild.lost | Should -Be $Lost -Because $Case
        Get-VantaTransitionRebuildDecision ([pscustomobject]@{ rebuild = [pscustomobject]@{ rebuilt = $rebuild.rebuilt; signals = $rebuild.signals } }) |
            Should -BeExactly $Decision -Because $Case
        # A Rebase that put Vanta back clears rebuilt and keeps the signals.
        $cleared = if ($Decision -ceq 'rebuilt') { 'in-place' } else { $Decision }
        Get-VantaTransitionRebuildDecision ([pscustomobject]@{ rebuild = [pscustomobject]@{ rebuilt = $false; signals = $rebuild.signals } }) |
            Should -BeExactly $cleared -Because "$Case, after a Rebase"
    }

    It 'ignores a Setup log older than the move' {
        [void][IO.Directory]::CreateDirectory((Join-Path $script:Windows050 'Panther'))
        $log = Join-Path $script:Windows050 'Panther\setupact.log'
        [IO.File]::WriteAllText($log, 'setup')
        [IO.File]::SetLastWriteTimeUtc($log, $script:Since.AddDays(-30))
        (Get-VantaTransitionRebuildFact -Since $script:Since -WindowsPath $script:Windows050).PantherWritten | Should -BeFalse
    }
}

Describe 'Putting Vanta back on a rebuilt Windows' {
    BeforeEach {
        Reset-Machine
        $script:Win = Join-Path $TestDrive 'Rebuilt\Windows'
        Remove-Item -LiteralPath (Join-Path $TestDrive 'Rebuilt') -Recurse -Force -ErrorAction SilentlyContinue
        [void][IO.Directory]::CreateDirectory((Join-Path $script:Win 'VantaModules\Other'))
        $script:OldOther = Join-Path $TestDrive 'Rebuilt\Windows.old\Windows\VantaModules\Other'
        [void][IO.Directory]::CreateDirectory($script:OldOther)
        [IO.File]::WriteAllText((Join-Path $script:OldOther 'winServices.reg'), 'Windows Registry Editor Version 5.00')
    }

    It 'brings back the service backup from Windows.old and keeps one that exists' {
        Copy-VantaRebaseServiceBackup -Name 'winServices.reg' -WindowsPath $script:Win | Should -Match 'brought back'
        [IO.File]::ReadAllText((Join-Path $script:Win 'VantaModules\Other\winServices.reg')) | Should -BeExactly 'Windows Registry Editor Version 5.00'
        [IO.File]::WriteAllText((Join-Path $script:OldOther 'winServices.reg'), 'changed')
        Copy-VantaRebaseServiceBackup -Name 'winServices.reg' -WindowsPath $script:Win | Should -Match 'kept the existing'
        [IO.File]::ReadAllText((Join-Path $script:Win 'VantaModules\Other\winServices.reg')) | Should -BeExactly 'Windows Registry Editor Version 5.00'
        Copy-VantaRebaseServiceBackup -Name 'vantaServices.reg' -WindowsPath $script:Win | Should -Match 'no vantaServices.reg'
    }

    It 'never copies through a link' {
        $target = Join-Path $TestDrive 'Elsewhere'
        [void][IO.Directory]::CreateDirectory($target)
        [IO.File]::WriteAllText((Join-Path $target 'vantaServices.reg'), 'planted')
        Remove-Item -LiteralPath $script:OldOther -Recurse -Force
        [void](Microsoft.PowerShell.Management\New-Item -ItemType Junction -Path $script:OldOther -Target $target)
        Copy-VantaRebaseServiceBackup -Name 'vantaServices.reg' -WindowsPath $script:Win | Should -Match 'is a link'
        [IO.File]::Exists((Join-Path $script:Win 'VantaModules\Other\vantaServices.reg')) | Should -BeFalse
    }

    It 'brings back the recorded choices only when Windows lost them all' {
        $carry = ConvertTo-VantaTransitionCarry (New-Vanta050Fact) @()
        $lines = @(Restore-VantaRebaseChoice $carry)
        $lines[0] | Should -Match 'brought back 5 recorded choices'
        $script:ToggleRecords['AutomaticUpdates'] | Should -Be 0
        (Get-Fake 'SOFTWARE\Vanta\SetupOptions' browser).Data | Should -BeExactly 'Brave'
        $script:Writes.Clear()
        $script:ToggleRecords = @{ FileSharing = 1 }
        @(Restore-VantaRebaseChoice $carry)[0] | Should -Match 'kept the 1 recorded choices'
        @($script:Writes | Where-Object { $_ -like 'toggle *' }) | Should -BeNullOrEmpty
        $script:ToggleRecords['FileSharing'] | Should -Be 1
    }

    It 'brings back the 0.5.0 launcher name with a choice, for the repair that reads it' {
        # 0.5.0's "Hide Lock Screen.cmd" wrote state 1, the opposite of the choice.
        $carry = ConvertTo-VantaTransitionCarry (New-Vanta050Fact) @()
        $carry.toggles = @([pscustomobject]@{ name = 'LockScreen'; state = 1; path = 'Hide Lock Screen.cmd' })
        Test-VantaTransitionCarry $carry | Should -BeTrue
        $null = @(Restore-VantaRebaseChoice $carry)
        $script:ToggleRecords['LockScreen'] | Should -Be 1
        (Get-Fake 'SOFTWARE\Vanta\Services\LockScreen' path).Data | Should -BeExactly 'Hide Lock Screen.cmd'
        $carry.toggles = @([pscustomobject]@{ name = 'LockScreen'; state = 1; path = '..\..\Windows\evil.ps1' })
        Test-VantaTransitionCarry $carry | Should -BeFalse
    }

    It 'reads the records it brought back as Vanta 0.6 means them, launcher names and all' {
        Mock Repair-VantaToolboxRecord { $script:Writes.Add("repair $InstalledVersion"); "Removed the old Atlas Toolbox's 'SearchIndexing' record." }
        $carry = ConvertTo-VantaTransitionCarry (New-Vanta050Fact) @()
        $lines = @(Restore-VantaRebaseChoice $carry)
        $lines | Should -Contain "Removed the old Atlas Toolbox's 'SearchIndexing' record."
        $script:Writes.IndexOf('repair 0.5.0') | Should -BeGreaterThan $script:Writes.IndexOf('set SOFTWARE\Vanta\Services\Mitigations|path')
        # Records Windows kept, or some an attempt stopped part way put back, too:
        # the ones it has repaired already stay as they are.
        $script:ToggleRecords = @{ FileSharing = 1 }
        $null = @(Restore-VantaRebaseChoice $carry)
        Should -Invoke Repair-VantaToolboxRecord -Times 2 -Exactly -ParameterFilter { $InstalledVersion -ceq '0.5.0' }
    }

    It 'keeps only the file name of the launcher that wrote a record' {
        Set-Fake 'SOFTWARE\Vanta\Services\OldContextMenu' state DWord 0
        Set-Fake 'SOFTWARE\Vanta\Services\OldContextMenu' path String 'C:\Windows\VantaDesktop. Interface Tweaks\Context Menus\Windows 11\Old Context Menu (default).cmd'
        $records = @(Get-VantaTransitionToggleRecord)
        $records | Should -HaveCount 1
        $records[0].path | Should -BeExactly 'Old Context Menu (default).cmd'
    }

    It 'repeats only the app removals of apps that were not there before Windows moved' {
        $definitions = @(
            [pscustomobject]@{ Name = 'Microsoft.Paint*'; Option = $null; IgnoreErrors = $false }
            [pscustomobject]@{ Name = 'Microsoft.BingWeather*'; Option = $null; IgnoreErrors = $false }
            [pscustomobject]@{ Name = 'Microsoft.MicrosoftEdge.Stable_8wekyb3d8bbwe'; Option = 'uninstall-edge'; IgnoreErrors = $true }
        )
        $selection = @(Select-VantaRebaseAppxRemoval $definitions @('Microsoft.Paint_8wekyb3d8bbwe', 'Microsoft.WindowsCalculator_8wekyb3d8bbwe'))
        @($selection | Where-Object { -not $_.Kept } | ForEach-Object { $_.Definition.Name }) | Should -Be @('Microsoft.BingWeather*', 'Microsoft.MicrosoftEdge.Stable_8wekyb3d8bbwe')
        @($selection | Where-Object Kept | ForEach-Object { $_.Definition.Name }) | Should -Be @('Microsoft.Paint*')

        # A record without the list removes nothing: any of them may be the user's.
        @(Select-VantaRebaseAppxRemoval $definitions @() | Where-Object { -not $_.Kept }) | Should -BeNullOrEmpty
    }
}

Describe 'The Rebase install plan' {
    BeforeAll {
        . (Join-Path $script:VantaTestScriptsRoot 'Install\Install-Plan.ps1')
        Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
        Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Tweaks\Vanta.Tweaks.psd1') -Force -DisableNameChecking
    }

    It 'is the Upgrade plan plus the fresh-install phases a rebuilt Windows undid' {
        $upgrade = @((Get-VantaInstallPlan -Mode Upgrade).Key)
        $rebase = @((Get-VantaInstallPlan -Mode Rebase).Key)
        @($rebase | Where-Object { $upgrade -notcontains $_ }) | Should -Be @('Checkpoint/RebaseRecovery', 'Services', 'Components', 'AppxSupport')
        @($upgrade | Where-Object { $rebase -notcontains $_ }) | Should -BeNullOrEmpty
        $fresh = @((Get-VantaInstallPlan -Mode Fresh).Key)
        @($fresh | Where-Object { $rebase -notcontains $_ }) | Should -Be @('Tweak/qol/set-hidden-settings-pages', 'Tweak/scripts/set-power-settings') -Because 'a rebuild keeps the user''s settings pages and power plan'
        [array]::IndexOf($rebase, 'Checkpoint/RebaseRecovery') | Should -BeLessThan ([array]::IndexOf($rebase, 'Checkpoint/LegacyChoices'))
        [array]::IndexOf($rebase, 'Checkpoint/RebaseRecovery') | Should -BeGreaterThan ([array]::IndexOf($rebase, 'Checkpoint/PayloadReplacement'))
        [array]::IndexOf($rebase, 'Services') | Should -BeLessThan ([array]::IndexOf($rebase, 'Defaults')) -Because 'the replay of recorded choices comes after the phases that set defaults'
    }

    It 'repeats exactly the fresh-install tweaks that leave the user''s own settings alone' {
        $rebase = @()
        $fresh = @()
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $script:VantaTestScriptsRoot 'Tweaks') -Filter '*.psd1' -Recurse) {
            if ($file.Name -eq 'tweaks.manifest.psd1') { continue }
            $tweak = Import-PowerShellDataFile -LiteralPath $file.FullName
            if ($tweak['OnUpgrade'] -ne 'Skip') { continue }
            $slug = $file.FullName.Substring((Join-Path $script:VantaTestScriptsRoot 'Tweaks').Length + 1).Replace('\', '/') -replace '\.psd1$', ''
            $fresh += $slug
            $context = [pscustomobject]@{ IsUpgrade = $true; IsRebase = $true; IsArm64 = $true; WindowsBuild = 26300; IsInstallStateBacked = $true; Options = @() }
            if (Test-VantaTweakApplicable -Tweak $tweak -Context $context) { $rebase += $slug }
            $upgrade = [pscustomobject]@{ IsUpgrade = $true; IsRebase = $false; IsArm64 = $true; WindowsBuild = 26300; IsInstallStateBacked = $true; Options = @() }
            Test-VantaTweakApplicable -Tweak $tweak -Context $upgrade | Should -BeFalse -Because "$slug stays fresh-only on a plain upgrade"
        }
        @($rebase | Sort-Object) | Should -Be @('misc/delete-windows-specific-files', 'scripts/backup-services', 'scripts/disable-pnp', 'scripts/set-profile-pictures')
        @($fresh | Where-Object { $rebase -notcontains $_ } | Sort-Object) | Should -Be @(
            'qol/appearance/vanta-theme', 'qol/config-start-menu', 'qol/explorer/debloat-send-to',
            'qol/set-hidden-settings-pages', 'qol/taskbar/config-pins', 'scripts/set-file-associations')
    }
}
