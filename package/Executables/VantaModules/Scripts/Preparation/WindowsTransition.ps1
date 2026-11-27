# Moving Windows to a newer release through Windows Update, and putting back the
# Windows Update settings changed for it. Function definitions only: the update
# worker, the Vanta.InstallState module and many install, toggle and tweak scripts
# dot-source this file, and none of them may inherit a side effect from it.
# Windows PowerShell 5.1.

# The journal lives under HKLM, which only administrators and SYSTEM can write, so a
# standard user cannot plant values for a restore to write back.
function Get-VantaWindowsTransitionRoot { 'SOFTWARE\Vanta\WindowsTransition' }

function New-VantaTransitionFailure([string]$Message, [string]$Reason, [hashtable]$Detail = @{}) {
    $failure = [Exception]::new($Message)
    if ($Reason) { $failure.Data['reason'] = $Reason }
    foreach ($key in $Detail.Keys) { $failure.Data[$key] = [string]$Detail[$key] }
    return $failure
}

# Steps go to the evidence log the caller chose (the worker's, or none), so a
# failed or refused move can be followed afterwards.
function Write-VantaTransitionEvidence([string]$Text) {
    $path = Get-Variable -Name VantaTransitionEvidencePath -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if (-not $path) { return }
    $line = '{0:yyyy-MM-ddTHH:mm:ssZ} {1}' -f [DateTime]::UtcNow, $Text
    try {
        $file = [IO.FileInfo]::new($path)
        # Keep one older log, so the history can't grow without limit. Its name
        # still ends in .log, which diagnostics collect.
        if ($file.Exists -and $file.Length -gt 1MB) {
            [IO.File]::Copy($path, [IO.Path]::ChangeExtension($path, '.old.log'), $true)
            [IO.File]::WriteAllText($path, '')
        }
        [IO.File]::AppendAllText($path, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    }
    catch {
        Write-Verbose "The transition evidence log could not be written: $_"
    }
}

# The only registry values, services and scheduled tasks a transition may change or
# restore. A journal entry for anything else is refused. Rules: nonzero (a DWORD
# other than 0 blocks), disabled (a service Start of 4 blocks), future (a pause end
# date still ahead blocks), paused (lifted only while the pause blocks), task (a
# disabled task, turned on only with the rest of Windows Update), pin (never lifted;
# retargeted by Set-VantaFeatureUpdateTarget).
# Vanta 0.5.0's "Disable Windows Updates" disables wuauserv and the sih and sihboot
# tasks, which 25H2 and later no longer have: an absent task is recorded as absent
# and left alone. Its deferral launcher sets the Defer* policies. The policies, UsoSvc and the
# pause values are what Vanta 0.6's own toggles, or a user's tools, set.
function Get-VantaWindowsTransitionItem {
    $policy = 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $pause = 'SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings'
    $ux = 'SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    $services = 'SYSTEM\CurrentControlSet\Services'
    # Id, group, key or task path, value or task name, kinds, lifted value, owner
    # toggle and rule. A leading comma keeps each row an array of its own.
    $rows = @(
        ,@('policy.DisableWindowsUpdateAccess', 'off', $policy, 'DisableWindowsUpdateAccess', 'DWord', $null, 'ToggleWindowsUpdates', 'nonzero')
        ,@('policy.DoNotConnectToWindowsUpdateInternetLocations', 'off', $policy, 'DoNotConnectToWindowsUpdateInternetLocations', 'DWord', $null, 'ToggleWindowsUpdates', 'nonzero')
        ,@('policy.AU.NoAutoUpdate', 'off', "$policy\AU", 'NoAutoUpdate', 'DWord', $null, 'ToggleWindowsUpdates', 'nonzero')
        ,@('service.wuauserv', 'off', "$services\wuauserv", 'Start', 'DWord', 3, 'ToggleWindowsUpdates', 'disabled')
        ,@('service.UsoSvc', 'off', "$services\UsoSvc", 'Start', 'DWord', 3, 'ToggleWindowsUpdates', 'disabled')
        ,@('task.sih', 'off', 'Microsoft\Windows\WindowsUpdate', 'sih', 'Task', 'Enabled', 'ToggleWindowsUpdates', 'task')
        ,@('task.sihboot', 'off', 'Microsoft\Windows\WindowsUpdate', 'sihboot', 'Task', 'Enabled', 'ToggleWindowsUpdates', 'task')
        ,@('policy.DeferQualityUpdates', 'delayed', $policy, 'DeferQualityUpdates', 'DWord', $null, $null, 'nonzero')
        ,@('policy.DeferQualityUpdatesPeriodInDays', 'delayed', $policy, 'DeferQualityUpdatesPeriodInDays', 'DWord', $null, $null, 'nonzero')
        ,@('pause.PausedFeatureStatus', 'paused', $pause, 'PausedFeatureStatus', 'DWord', 0, 'PauseUpdates', 'nonzero')
        ,@('pause.PausedQualityStatus', 'paused', $pause, 'PausedQualityStatus', 'DWord', 0, 'PauseUpdates', 'nonzero')
        ,@('pause.PauseFeatureUpdatesStartTime', 'paused', $ux, 'PauseFeatureUpdatesStartTime', 'String', $null, 'PauseUpdates', 'paused')
        ,@('pause.PauseFeatureUpdatesEndTime', 'paused', $ux, 'PauseFeatureUpdatesEndTime', 'String', $null, 'PauseUpdates', 'future')
        ,@('pause.PauseQualityUpdatesStartTime', 'paused', $ux, 'PauseQualityUpdatesStartTime', 'String', $null, 'PauseUpdates', 'paused')
        ,@('pause.PauseQualityUpdatesEndTime', 'paused', $ux, 'PauseQualityUpdatesEndTime', 'String', $null, 'PauseUpdates', 'future')
        ,@('pause.PauseUpdatesStartTime', 'paused', $ux, 'PauseUpdatesStartTime', 'String', $null, 'PauseUpdates', 'paused')
        ,@('pause.PauseUpdatesExpiryTime', 'paused', $ux, 'PauseUpdatesExpiryTime', 'String', $null, 'PauseUpdates', 'future')
        ,@('pause.FlightSettingsMaxPauseDays', 'paused', $ux, 'FlightSettingsMaxPauseDays', 'DWord', $null, 'PauseUpdates', 'paused')
        ,@('pin.TargetReleaseVersion', 'pin', $policy, 'TargetReleaseVersion', 'DWord,String', $null, $null, 'pin')
        ,@('pin.ProductVersion', 'pin', $policy, 'ProductVersion', 'String', $null, $null, 'pin')
        ,@('pin.TargetReleaseVersionInfo', 'pin', $policy, 'TargetReleaseVersionInfo', 'String', $null, $null, 'pin')
    )
    foreach ($row in $rows) {
        [pscustomobject][ordered]@{
            Id = $row[0]; Group = $row[1]; Path = $row[2]; Name = $row[3]
            Kinds = @($row[4] -split ','); Lift = $row[5]; Owner = $row[6]; Rule = $row[7]
        }
    }
}

function ConvertTo-VantaTransitionDword($Value) {
    # RegistryKey returns REG_DWORD as a signed Int32; keep it as the unsigned value.
    return [int64][BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$Value), 0)
}

# Registry and service access goes through these few functions, so tests can stand
# in for the machine and the code that decides never touches it directly.
function Get-VantaTransitionValue([string]$Path, [string]$Name) {
    $absent = [pscustomobject]@{ Present = $false; Kind = $null; Data = $null }
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Path, $false)
    if ($null -eq $key) { return $absent }
    try {
        if (@($key.GetValueNames()) -notcontains $Name) { return $absent }
        $kind = [string]$key.GetValueKind($Name)
        $data = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($kind -eq 'DWord') { $data = ConvertTo-VantaTransitionDword $data }
        return [pscustomobject]@{ Present = $true; Kind = $kind; Data = $data }
    }
    finally { $key.Dispose() }
}

function Set-VantaTransitionValue([string]$Path, [string]$Name, [ValidateSet('DWord', 'String')][string]$Kind, $Data) {
    $key = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($Path)
    try {
        if ($Kind -eq 'DWord') {
            $value = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$Data), 0)
            $key.SetValue($Name, $value, [Microsoft.Win32.RegistryValueKind]::DWord)
        }
        else { $key.SetValue($Name, [string]$Data, [Microsoft.Win32.RegistryValueKind]::String) }
    }
    finally { $key.Dispose() }
}

function Remove-VantaTransitionValue([string]$Path, [string]$Name) {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Path, $true)
    if ($null -eq $key) { return }
    try { $key.DeleteValue($Name, $false) }
    finally { $key.Dispose() }
}

function Get-VantaTransitionSubKeyName([string]$Path) {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Path, $false)
    if ($null -eq $key) { return }
    try { @($key.GetSubKeyNames()) }
    finally { $key.Dispose() }
}

function Test-VantaTransitionKey([string]$Path) {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Path, $false)
    if ($null -eq $key) { return $false }
    $key.Dispose()
    return $true
}

# sc.exe changes what the service manager holds as well as the registry, so the
# change applies without a restart.
function Set-VantaTransitionServiceStart([string]$Name, [ValidateRange(2, 4)][int]$Start) {
    $mode = @{ 2 = 'auto'; 3 = 'demand'; 4 = 'disabled' }[$Start]
    $output = & ([IO.Path]::Combine([Environment]::SystemDirectory, 'sc.exe')) config $Name start= $mode 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sc.exe could not set $Name to $mode ($LASTEXITCODE): $output" }
}

# A scheduled task as the journal records it: Enabled or Disabled.
function Get-VantaTransitionTask([string]$Path, [string]$Name) {
    $task = Get-ScheduledTask -TaskPath "\$Path\" -TaskName $Name -ErrorAction SilentlyContinue
    if ($null -eq $task) { return [pscustomobject]@{ Present = $false; Kind = $null; Data = $null } }
    $state = if ([string]$task.State -eq 'Disabled') { 'Disabled' } else { 'Enabled' }
    return [pscustomobject]@{ Present = $true; Kind = 'Task'; Data = $state }
}

function Set-VantaTransitionTask([string]$Path, [string]$Name, [ValidateSet('Enabled', 'Disabled')][string]$State) {
    if ($State -eq 'Enabled') { Enable-ScheduledTask -TaskPath "\$Path\" -TaskName $Name -ErrorAction Stop | Out-Null }
    else { Disable-ScheduledTask -TaskPath "\$Path\" -TaskName $Name -ErrorAction Stop | Out-Null }
}

function Start-VantaTransitionService([string]$Name) {
    Start-Service -Name $Name -ErrorAction Stop
}

# Windows Update is never stopped while it installs something; turned off, it
# stays stopped from the next start.
function Stop-VantaTransitionService([string]$Name) {
    if ($Name -eq 'wuauserv' -and (New-Object -ComObject Microsoft.Update.Installer).IsBusy) {
        throw 'Windows Update is installing something, so it stops at the next restart instead'
    }
    Stop-Service -Name $Name -Force -ErrorAction Stop
}

# Creates the journal key with an explicit descriptor: SYSTEM and Administrators
# full control, Users read. A key someone else owns is never trusted.
function New-VantaTransitionJournalKey([string]$Path = (Get-VantaWindowsTransitionRoot)) {
    $trusted = @('S-1-5-18', 'S-1-5-32-544')
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Path, $false)
    if ($null -ne $key) {
        try { $owner = $key.GetAccessControl().GetOwner([Security.Principal.SecurityIdentifier]).Value }
        finally { $key.Dispose() }
        if ($trusted -notcontains $owner) {
            throw (New-VantaTransitionFailure "The Windows Update record key is owned by $owner, not by SYSTEM or Administrators." 'feature-journal')
        }
        return
    }
    $security = New-Object Security.AccessControl.RegistrySecurity
    $security.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;CI;KA;;;SY)(A;CI;KA;;;BA)(A;CI;KR;;;BU)')
    $created = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($Path, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, $security)
    $created.Dispose()
}

# A toggle's recorded choice, which its replay acts on. A key whose state an
# older record left cleared holds no choice.
function Get-VantaTransitionOwnerRecord([string]$Toggle) {
    if (-not $Toggle) { return $false }
    $state = Get-VantaTransitionValue "SOFTWARE\Vanta\Services\$Toggle" 'state'
    return [bool]($state.Present -and $state.Kind -eq 'DWord')
}

function Test-VantaTransitionString([string]$Text, [int]$Limit) {
    return $Text.Length -le $Limit -and $Text -notmatch '[\x00-\x1f\x7f]'
}

# Whether one recorded value may be written back for this item: a kind the table
# allows, and a well-formed value within its length limit.
function Test-VantaTransitionItemValue($Item, $Entry) {
    if ($Entry.present -isnot [bool]) { return $false }
    if (-not $Entry.present) { return $true }
    $kind = [string]$Entry.kind
    if ($Item.Kinds -cnotcontains $kind) { return $false }
    if ($kind -eq 'Task') { return @('Enabled', 'Disabled') -ccontains [string]$Entry.data }
    if ($kind -eq 'DWord') {
        if ($Entry.data -isnot [int] -and $Entry.data -isnot [long] -and $Entry.data -isnot [int64]) { return $false }
        $number = [int64]$Entry.data
        if ($number -lt 0 -or $number -gt 4294967295) { return $false }
        if ($Item.Name -eq 'Start' -and $number -gt 4) { return $false }
        if ($Item.Id -eq 'pin.TargetReleaseVersion' -and $number -gt 1) { return $false }
        return $true
    }
    if ($Entry.data -isnot [string]) { return $false }
    switch ($Item.Id) {
        'pin.TargetReleaseVersion' { return $Entry.data -imatch '^\d{2}H\d$' }
        'pin.TargetReleaseVersionInfo' { return $Entry.data -imatch '^(\d{2}H\d)?$' }
        'pin.ProductVersion' { return Test-VantaTransitionString $Entry.data 25 }
        default { return Test-VantaTransitionString $Entry.data 64 }
    }
}

# Refuses the whole journal when anything in it is unexpected: nothing is then
# changed or restored on its strength.
function Test-VantaWindowsTransitionJournal($Journal) {
    try { return (Test-VantaWindowsTransitionJournalShape $Journal) }
    catch {
        # Under strict mode a missing property throws on its own; whatever the
        # check trips on, the record is refused as not valid.
        if ([string]$_.Exception.Data['reason'] -eq 'feature-journal') { throw }
        throw (New-VantaTransitionFailure "The Windows Update record is not valid: $($_.Exception.Message)" 'feature-journal')
    }
}

function Test-VantaWindowsTransitionJournalShape($Journal) {
    $fail = { param($Why) throw (New-VantaTransitionFailure "The Windows Update record is not valid: $Why" 'feature-journal') }
    foreach ($name in @('schema', 'kind', 'phase', 'items', 'source', 'createdAt')) {
        if ($null -eq $Journal.PSObject.Properties[$name]) { & $fail "missing $name" }
    }
    if ($Journal.schema -ne 1) { & $fail "schema $($Journal.schema)" }
    if (@('transition', 'access') -cnotcontains $Journal.kind) { & $fail "kind $($Journal.kind)" }
    if (@('lifted', 'targeted', 'installed', 'on-target') -cnotcontains $Journal.phase) { & $fail "phase $($Journal.phase)" }
    if ($Journal.kind -eq 'transition') {
        $target = $Journal.PSObject.Properties['target']
        if ($null -eq $target -or $null -eq $target.Value -or [string]$target.Value.release -cnotmatch '^\d{2}H\d$' -or
            [string]$target.Value.kb -cnotmatch '^(\d{7}(,\d{7})*)?$' -or $target.Value.build -isnot [int]) { & $fail 'target' }
    }
    $offer = $Journal.PSObject.Properties['offer']
    if ($null -ne $offer -and $null -ne $offer.Value) {
        $value = $offer.Value
        if ([string]$value.kb -cnotmatch '^(\d{7}(,\d{7})*)?$' -or [string]$value.updateId -cnotmatch '^[0-9A-Za-z-]{1,64}$' -or
            $value.revision -isnot [int] -or -not (Test-VantaTransitionString ([string]$value.title) 200)) { & $fail 'offer' }
    }
    $table = @{}
    foreach ($item in Get-VantaWindowsTransitionItem) { $table[$item.Id] = $item }
    $seen = @{}
    foreach ($entry in @($Journal.items)) {
        $id = [string]$entry.id
        if (-not $table.ContainsKey($id) -or $seen.ContainsKey($id)) { & $fail "item $id" }
        $seen[$id] = $true
        if (-not (Test-VantaTransitionItemValue $table[$id] $entry)) { & $fail "value of $id" }
        if ($entry.lifted -isnot [bool] -or $entry.ownerRecord -isnot [bool]) { & $fail "flags of $id" }
        if ($Journal.kind -eq 'access' -and $table[$id].Group -eq 'pin' -and $entry.lifted) { & $fail "pin in access record" }
    }
    $packages = $Journal.PSObject.Properties['vantaPackages']
    if ($null -ne $packages) {
        foreach ($package in @($packages.Value)) {
            if ([string]$package -cnotmatch '^Z-(?:Atlas|Vanta)-[A-Za-z0-9-]+~[0-9a-f]{16}~[a-z0-9]+~[a-zA-Z-]*~[0-9.]+$') { & $fail 'package name' }
        }
    }
    $carry = $Journal.PSObject.Properties['carry']
    if ($null -ne $carry -and -not (Test-VantaTransitionCarry $carry.Value)) { & $fail 'carry' }
    $rebuild = $Journal.PSObject.Properties['rebuild']
    if ($null -ne $rebuild -and $null -ne $rebuild.Value) {
        if ($rebuild.Value.rebuilt -isnot [bool]) { & $fail 'rebuild' }
        foreach ($signal in @($rebuild.Value.signals)) {
            if (@('windows-old', 'setup-folder', 'setup-log', 'packages-missing', 'vanta-files-missing') -cnotcontains [string]$signal) { & $fail 'rebuild signal' }
        }
    }
    return $true
}

# A copy of the record beside Vanta Manager's recovery files under Program Files,
# which only administrators write. A Windows that rebuilds itself keeps Program
# Files, but may not keep the registry key that holds the record.
function Get-VantaTransitionCopyPath {
    return [IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), 'Vanta Setup Recovery\WindowsTransition\journal.json')
}

function Write-VantaTransitionCopy([string]$Json) {
    $path = Get-VantaTransitionCopyPath
    $directory = [IO.Path]::GetDirectoryName($path)
    if (-not [IO.Directory]::Exists($directory)) {
        $security = New-Object Security.AccessControl.DirectorySecurity
        $security.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)')
        [void][IO.Directory]::CreateDirectory($directory, $security)
    }
    $temporary = "$path.tmp"
    [IO.File]::WriteAllText($temporary, $Json, [Text.UTF8Encoding]::new($false))
    if ([IO.File]::Exists($path)) { [IO.File]::Replace($temporary, $path, [NullString]::Value) }
    else { [IO.File]::Move($temporary, $path) }
}

# The copy's text, or $null without one. A copy someone other than SYSTEM,
# Administrators or TrustedInstaller owns is never trusted.
function Read-VantaTransitionCopy {
    $path = Get-VantaTransitionCopyPath
    if (-not [IO.File]::Exists($path)) { return $null }
    $file = [IO.FileInfo]::new($path)
    $owner = $file.GetAccessControl().GetOwner([Security.Principal.SecurityIdentifier]).Value
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $file.Length -gt 512KB -or
        @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464') -notcontains $owner) {
        throw (New-VantaTransitionFailure "The copy of the Windows Update record at $path can't be trusted." 'feature-journal')
    }
    return [IO.File]::ReadAllText($path)
}

function Remove-VantaTransitionCopy {
    $path = Get-VantaTransitionCopyPath
    if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
}

# $null when there is no journal; throws feature-journal for one that cannot be
# trusted, so no caller acts on it. Without the registry record, its copy stands in.
function Read-VantaWindowsTransition([string]$Root = (Get-VantaWindowsTransitionRoot)) {
    $value = Get-VantaTransitionValue $Root 'Journal'
    if ($value.Present) {
        if ($value.Kind -ne 'String') { throw (New-VantaTransitionFailure 'The Windows Update record has an unexpected registry type.' 'feature-journal') }
        $text = [string]$value.Data
    }
    else {
        $text = Read-VantaTransitionCopy
        if ($null -eq $text) { return $null }
        Write-VantaTransitionEvidence 'the registry record is gone; read its copy under Program Files'
    }
    try { $journal = $text | ConvertFrom-Json -ErrorAction Stop }
    catch { throw (New-VantaTransitionFailure "The Windows Update record is not readable: $($_.Exception.Message)" 'feature-journal') }
    [void](Test-VantaWindowsTransitionJournal $journal)
    return $journal
}

function Write-VantaWindowsTransition($Journal, [string]$Root = (Get-VantaWindowsTransitionRoot)) {
    [void](Test-VantaWindowsTransitionJournal $Journal)
    $json = $Journal | ConvertTo-Json -Depth 8 -Compress
    New-VantaTransitionJournalKey $Root
    Set-VantaTransitionValue $Root 'Journal' 'String' $json
    # Only a rebuilt Windows needs the copy; failing to write it stops nothing.
    try { Write-VantaTransitionCopy $json }
    catch { Write-VantaTransitionEvidence "the copy of the record could not be written: $($_.Exception.Message)" }
}

# The copy goes first, so a copy left behind can never bring back a closed record.
function Remove-VantaWindowsTransition([string]$Root = (Get-VantaWindowsTransitionRoot)) {
    Remove-VantaTransitionCopy
    Remove-VantaTransitionValue $Root 'Journal'
}

# What a rebuild check's signals mean: Setup ran (Windows.old beside Setup's folder
# or a fresh Setup log) and Vanta's components went missing. The check and every
# later read of its record use this one rule.
function Get-VantaTransitionRebuildVerdict([string[]]$Signals) {
    return [pscustomobject]@{
        Setup = $Signals -contains 'windows-old' -and ($Signals -contains 'setup-folder' -or $Signals -contains 'setup-log')
        Lost = $Signals -contains 'packages-missing' -or $Signals -contains 'vanta-files-missing'
    }
}

# How Windows moved, as Vanta Manager decided once on the target build: 'rebuilt',
# 'in-place', or 'components-lost' when Vanta's components were gone without Setup
# rebuilding Windows. $null until it has checked. The decision is read back, never
# made again: the install changes the packages. A Rebase install that put Vanta
# back clears rebuilt; the signals still show that Setup ran, so the components
# they found gone aren't a loss.
function Get-VantaTransitionRebuildDecision($Journal) {
    $recorded = $Journal.PSObject.Properties['rebuild']
    if ($null -eq $recorded -or $null -eq $recorded.Value) { return $null }
    if ($recorded.Value.rebuilt) { return 'rebuilt' }
    $verdict = Get-VantaTransitionRebuildVerdict @($recorded.Value.signals)
    if ($verdict.Lost -and -not $verdict.Setup) { return 'components-lost' }
    return 'in-place'
}

# Kind, target and phase of an open journal, without acting on it. Unreadable
# journals are reported as such, never as absent.
function Test-VantaWindowsTransitionOpen([string]$Root = (Get-VantaWindowsTransitionRoot)) {
    try { $journal = Read-VantaWindowsTransition $Root }
    catch { return [pscustomobject]@{ Readable = $false; Kind = $null; Phase = $null; TargetBuild = 0; Rebuild = $null; Error = $_.Exception.Message } }
    if ($null -eq $journal) { return $null }
    $build = if ($journal.kind -eq 'transition') { [int]$journal.target.build } else { 0 }
    $rebuild = Get-VantaTransitionRebuildDecision $journal
    return [pscustomobject]@{ Readable = $true; Kind = [string]$journal.kind; Phase = [string]$journal.phase; TargetBuild = $build; Rebuild = $rebuild; Error = $null }
}

function Add-VantaTransitionHistory($Journal, [string]$Step, [string]$Detail = '') {
    $entries = @()
    if ($null -ne $Journal.PSObject.Properties['history']) { $entries = @($Journal.history) }
    $now = [DateTime]::UtcNow.ToString('o')
    $last = if ($entries.Count) { $entries[-1] } else { $null }
    # Looking again while Windows Update has yet to offer the release repeats the
    # same outcome; one entry counts the repeats, with the first and last times.
    if ($Step -ceq 'outcome' -and $null -ne $last -and [string]$last.event -ceq 'outcome' -and [string]$last.detail -ceq $Detail) {
        $count = if ($null -ne $last.PSObject.Properties['count']) { [int]$last.count } else { 1 }
        $last | Add-Member -NotePropertyName count -NotePropertyValue ($count + 1) -Force
        $last | Add-Member -NotePropertyName lastAt -NotePropertyValue $now -Force
    }
    else { $entries += [pscustomobject][ordered]@{ at = $now; event = $Step; detail = $Detail } }
    # The newest entries matter most; the record stays small.
    if ($entries.Count -gt 40) { $entries = $entries[($entries.Count - 40)..($entries.Count - 1)] }
    if ($null -eq $Journal.PSObject.Properties['history']) { $Journal | Add-Member -NotePropertyName history -NotePropertyValue @() }
    $Journal.history = @($entries)
    Write-VantaTransitionEvidence "$Step $Detail"
}

function Get-VantaTransitionLive($Item) {
    if ($Item.Kinds -ccontains 'Task') { return Get-VantaTransitionTask $Item.Path $Item.Name }
    return Get-VantaTransitionValue $Item.Path $Item.Name
}

function Test-VantaTransitionFutureDate([string]$Text, [DateTime]$Now) {
    $parsed = [DateTime]::MinValue
    if (-not [DateTime]::TryParse($Text, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
        return $false
    }
    return $parsed -gt $Now
}

# Which fixed-table items hold Windows Update back right now, read only. Each has
# its group (off, paused, delayed) and whether its owner toggle has a record.
function Get-VantaWindowsUpdateBlocker([DateTime]$Now = [DateTime]::UtcNow) {
    $items = @(Get-VantaWindowsTransitionItem | Where-Object Group -ne 'pin')
    $live = @{}
    foreach ($item in $items) { $live[$item.Id] = Get-VantaTransitionLive $item }
    $blocking = {
        param($Item, $Value)
        if (-not $Value.Present) { return $false }
        switch ($Item.Rule) {
            'nonzero' { return $Value.Kind -eq 'DWord' -and [int64]$Value.Data -ne 0 }
            'disabled' { return $Value.Kind -eq 'DWord' -and [int64]$Value.Data -eq 4 }
            'future' { return $Value.Kind -eq 'String' -and (Test-VantaTransitionFutureDate ([string]$Value.Data) $Now) }
            default { return $false }
        }
    }
    $pauseActive = $false
    foreach ($item in $items | Where-Object Group -eq 'paused') {
        if (& $blocking $item $live[$item.Id]) { $pauseActive = $true }
    }
    $offActive = $false
    foreach ($item in $items | Where-Object { $_.Group -eq 'off' -and $_.Rule -ne 'task' }) {
        if (& $blocking $item $live[$item.Id]) { $offActive = $true }
    }
    foreach ($item in $items) {
        $value = $live[$item.Id]
        # While updates are paused, every pause date goes with the pause, past
        # ones included; Windows reads them together. The update tasks come
        # back with the service that runs them.
        $blocks = if ($item.Rule -in @('paused', 'future')) { $pauseActive -and $value.Present }
        elseif ($item.Rule -eq 'task') { $offActive -and $value.Present -and $value.Data -eq 'Disabled' }
        else { & $blocking $item $value }
        if ($blocks) {
            [pscustomobject]@{
                Id = $item.Id; Group = $item.Group; Owner = $item.Owner
                OwnerRecord = Get-VantaTransitionOwnerRecord $item.Owner; Live = $value
            }
        }
    }
}

function Get-VantaTransitionFreeSpace {
    return [int64]([IO.DriveInfo]::new([IO.Path]::GetPathRoot([Environment]::SystemDirectory)).AvailableFreeSpace)
}

function Get-VantaTransitionImageHealth {
    Import-Module -Name Dism -ErrorAction Stop
    return [string](Repair-WindowsImage -Online -CheckHealth -ErrorAction Stop).ImageHealthState
}

# The end of the servicing log, where Windows writes what its last store check
# found. Read without locking out Windows, which keeps the file open.
function Get-VantaTransitionCbsLogTail([int64]$Bytes = 16MB) {
    $path = [IO.Path]::Combine([Environment]::GetFolderPath('Windows'), 'Logs\CBS\CBS.log')
    if (-not [IO.File]::Exists($path)) { return @() }
    $stream = [IO.FileStream]::new($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
    try {
        $start = [Math]::Max(0, $stream.Length - $Bytes)
        [void]$stream.Seek($start, [IO.SeekOrigin]::Begin)
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd()
    }
    finally { $stream.Dispose() }
    return ($text -split "`r?`n")
}

# The newest store check's findings in servicing log lines: the corrupt items
# it lists and its counts by kind. $null when the lines hold no complete check.
function Get-VantaTransitionStoreFinding([string[]]$Lines) {
    $start = -1
    for ($i = $Lines.Count - 1; $i -ge 0; $i--) {
        if ($Lines[$i] -match 'Checking System Update Readiness\.') { $start = $i; break }
    }
    if ($start -lt 0) { return $null }
    $items = @(); $counts = [ordered]@{}; $total = $null
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -match 'Total Operation Time') { break }
        if ($line -match '\(p\)\t([^\t]+)\t\([a-z]+\)\t+(\S.*?)\s*$') {
            $items += [pscustomobject]@{ Kind = $Matches[1].Trim(); Path = $Matches[2] }
        }
        elseif ($line -match 'Total Detected Corruption:\s*(\d+)') { $total = [int]$Matches[1] }
        elseif ($null -ne $total -and $line -match '\t((?:CBS|CSI) [A-Za-z ]+(?:Corruption|Corrupt)):\s*(\d+)') {
            $counts[$Matches[1]] = [int]$Matches[2]
        }
    }
    if ($null -eq $total) { return $null }
    return [pscustomobject]@{ Total = $total; Counts = $counts; Items = @($items) }
}

# Whether a store check's findings are the pattern Vanta's NoTelemetry package is
# known to leave: a component store cleanup rebuilds the replaced Application
# Experience (AppInv) 10.0.26100.1591 component from its baseline without
# aeinvext.dll and Microsoft.Management.Deployment.winmd. A label for the log
# only: a repair moves the findings to other 1591-baseline files, so no decision
# rests on it.
function Test-VantaTransitionKnownStoreDamage($Finding, [string[]]$VantaPackages) {
    if ($null -eq $Finding -or $Finding.Total -lt 1) { return $false }
    if (@($VantaPackages | Where-Object { $_ -match '^Z-(?:Atlas|Vanta)-NoTelemetry-Package' }).Count -eq 0) { return $false }
    $known = '^[a-z0-9]+_microsoft-windows-a\.\.n-experience-appinv_31bf3856ad364e35_10\.0\.26100\.1591_[^\\]+\\(aeinvext\.dll|Microsoft\.Management\.Deployment\.winmd)$'
    if (@($Finding.Items).Count -ne $Finding.Total) { return $false }
    foreach ($item in @($Finding.Items)) {
        if ($item.Kind -ne 'CSI Payload Corrupt' -or $item.Path -notmatch $known) { return $false }
    }
    foreach ($kind in @($Finding.Counts.Keys)) {
        $expected = if ($kind -eq 'CSI Payload Corruption') { $Finding.Total } else { 0 }
        if ($Finding.Counts[$kind] -ne $expected) { return $false }
    }
    return $Finding.Counts.Contains('CSI Payload Corruption')
}

# An organisation's update server owns this PC's updates; Vanta does not
# override where updates come from.
function Test-VantaWindowsUpdateManaged {
    $server = Get-VantaTransitionValue 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'UseWUServer'
    Write-VantaTransitionEvidence "read AU\UseWUServer: $(Format-VantaTransitionValue $server)"
    if ($server.Present -and $server.Kind -eq 'DWord' -and [int64]$server.Data -eq 1) {
        throw (New-VantaTransitionFailure 'This PC gets updates from an update server its organisation runs.' 'feature-managed')
    }
}

# What Windows Update needs to work at all and Vanta will not change itself.
# Read only; the first problem ends it, before anything changes.
function Test-VantaWindowsTransitionPreflight([int64]$MinimumFreeBytes = 6GB) {
    Test-VantaWindowsUpdateManaged
    foreach ($service in @('BITS', 'CryptSvc', 'TrustedInstaller')) {
        $start = Get-VantaTransitionValue "SYSTEM\CurrentControlSet\Services\$service" 'Start'
        Write-VantaTransitionEvidence "read $service Start: $(if ($start.Present) { $start.Data } else { 'absent' })"
        if (-not $start.Present -or ($start.Kind -eq 'DWord' -and [int64]$start.Data -eq 4)) {
            throw (New-VantaTransitionFailure "The $service service is turned off or missing." 'feature-blocked' @{ setting = $service })
        }
    }
    $free = Get-VantaTransitionFreeSpace
    $drive = ([IO.Path]::GetPathRoot([Environment]::SystemDirectory)).TrimEnd('\')
    Write-VantaTransitionEvidence "read free space on ${drive}: $free bytes (needs $MinimumFreeBytes)"
    if ($free -lt $MinimumFreeBytes) {
        throw (New-VantaTransitionFailure "Drive $drive has $free bytes free; Windows needs $MinimumFreeBytes." 'feature-disk-space' @{
                drive = $drive; freeGb = [Math]::Floor($free / 1GB); neededGb = [Math]::Ceiling($MinimumFreeBytes / 1GB) })
    }
    try {
        $health = Get-VantaTransitionImageHealth
        Write-VantaTransitionEvidence "read component store health: $health"
    }
    catch {
        # A check that cannot run is not evidence of damage, and the build after
        # the restart decides whether Windows moved.
        Write-VantaTransitionEvidence ("component store health could not be read (0x{0:X8}): {1}; going on" -f $_.Exception.HResult, $_.Exception.Message)
        $health = 'Unknown'
    }
    if ($health -eq 'Repairable') {
        # Vanta PCs can read as repairable from the packages' supersedence, which
        # a repair doesn't fully clear, and Windows Update installs on such a
        # store. So it is recorded and the move goes on; whether Windows moved
        # is decided after the restart. The servicing log says what Windows's
        # last full check found.
        $finding = Get-VantaTransitionStoreFinding @(Get-VantaTransitionCbsLogTail)
        $listed = if ($null -ne $finding) { (@($finding.Items | ForEach-Object { "$($_.Kind) $($_.Path)" }) -join '; ') } else { 'no store check in the servicing log' }
        $pattern = if (Test-VantaTransitionKnownStoreDamage $finding @(Get-VantaInstalledVantaPackage)) { 'the known Vanta package pattern' } else { 'other' }
        Write-VantaTransitionEvidence "component store is repairable ($pattern): $listed; going on"
    }
    elseif ($health -eq 'NonRepairable') {
        throw (New-VantaTransitionFailure "Windows reports that its component store is $health." 'feature-servicing')
    }
}

# Installed Vanta CBS packages, from the servicing registry (CurrentState 112 is
# Installed). Read only and fast enough to run on every resume.
function Get-VantaInstalledVantaPackage {
    $root = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages'
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($root, $false)
    if ($null -eq $key) { return }
    try {
        foreach ($name in @($key.GetSubKeyNames() | Where-Object { $_ -match '^Z-(?:Atlas|Vanta)-' } | Sort-Object)) {
            $state = Get-VantaTransitionValue "$root\$name" 'CurrentState'
            if ($state.Present -and $state.Kind -eq 'DWord' -and [int64]$state.Data -eq 112) { $name }
        }
    }
    finally { $key.Dispose() }
}

# What this PC's Vanta install was, read before Windows moves: if Windows rebuilds
# itself instead of switching releases, the Vanta install afterwards needs it to
# put Vanta back with the same choices, even when the registry it came from is gone.
# Read only. Each source is its own function so tests can stand in for the machine.
function Get-VantaTransitionStateDocument {
    $path = [IO.Path]::Combine([Environment]::GetFolderPath('Windows'), 'VantaOS\state.json')
    if (-not [IO.File]::Exists($path)) { return $null }
    try { return [IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop }
    catch {
        Write-VantaTransitionEvidence "the Vanta state document could not be read: $($_.Exception.Message)"
        return $null
    }
}

# The version an OEM model or registered organisation value names. Vanta writes
# 'Vanta v<version>' to both; releases before Vanta 0.6 wrote 'Vanta Playbook v<version>'.
# Returns nothing for any other value. The install state module reads the markers with it too.
function ConvertFrom-VantaVersionMarker([string]$Value) {
    if ($Value -match '^(?:Atlas|Vanta) (?:Playbook )?v?(\d+\.\d+\.\d+)$') { $Matches[1] }
}

function Get-VantaTransitionLegacyVersion {
    foreach ($marker in @(
            @('SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation', 'Model'),
            @('SOFTWARE\Microsoft\Windows NT\CurrentVersion', 'RegisteredOrganization'))) {
        $value = Get-VantaTransitionValue $marker[0] $marker[1]
        if ($value.Present) { ConvertFrom-VantaVersionMarker ([string]$value.Data) }
    }
}

function Get-VantaTransitionToggleRecord {
    # The active Vanta plan is stronger evidence than an old record saying that
    # power saving is enabled. Keep that choice before Windows can replace the plan.
    $active = Get-VantaTransitionValue 'SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' 'ActivePowerScheme'
    # the Vanta plan is the one whose GUID Vanta recorded; a fixed GUID could be another program's plan (Atlas)
    $own = Get-VantaTransitionValue 'SOFTWARE\Vanta\Services\PowerSaving' 'VantaPowerSchemeGuid'
    $vantaActive = $active.Present -and $active.Kind -eq 'String' -and $own.Present -and $own.Kind -eq 'String' -and
        [string]$own.Data -and [string]$active.Data -ieq [string]$own.Data
    if ($vantaActive) { [pscustomobject]@{ name = 'PowerSaving'; state = 0 } }
    foreach ($name in @(Get-VantaTransitionSubKeyName 'SOFTWARE\Vanta\Services')) {
        if ($vantaActive -and $name -ieq 'PowerSaving') { continue }
        $state = Get-VantaTransitionValue "SOFTWARE\Vanta\Services\$name" 'state'
        if (-not $state.Present -or $state.Kind -ne 'DWord') { continue }
        $value = [int64]$state.Data
        if ($name -eq 'AutomaticUpdates' -and $value -eq 1) {
            $launcher = Get-VantaTransitionValue "SOFTWARE\Vanta\Services\$name" 'path'
            if ($launcher.Present -and $launcher.Kind -eq 'String') {
                $file = ([string]$launcher.Data -split '[\\/]')[-1]
                if ($file -in @('Add Idle Toggle in Desktop Context Menu.cmd', 'Remove Idle Toggle in Desktop Context Menu (default).cmd')) {
                    $value = Get-VantaTransitionAutomaticUpdatesPolicyState
                    if ($null -eq $value) { continue }
                }
            }
        }
        $record = [ordered]@{ name = $name; state = $value }
        # The file name of the 0.5.0 launcher that wrote it, as data: some of those
        # wrote the opposite value, and Initialize-VantaToggleStateStore corrects it
        # by name. A Rebase that has to bring the records back needs it too.
        $launcher = Get-VantaTransitionValue "SOFTWARE\Vanta\Services\$name" 'path'
        if ($launcher.Present -and $launcher.Kind -eq 'String') {
            $file = ([string]$launcher.Data -split '[\\/]')[-1]
            if ($file -match '^[A-Za-z0-9 ().,_-]{1,128}\.cmd$') { $record.path = $file }
        }
        [pscustomobject]$record
    }
}

# Whether $Version, an installed Vanta's, is older than 0.6. Beside such an Vanta
# the old Atlas Toolbox (0.1.x) wrote toggle records of its own.
function Test-VantaVersionBefore06([string]$Version) {
    return $Version -match '^(\d+)\.(\d+)\.' -and [version]"$($Matches[1]).$($Matches[2])" -lt [version]'0.6'
}

# The Toolbox records named here hold a multi-option choice, which Vanta 0.5's
# launchers also wrote. A launcher always left its file name as 'path' beside the
# state, which it applied; the Toolbox never did, numbered the choices its own
# way, and never changed the PC. Each launcher comes with the state it applied.
# Repair-VantaToolboxRecord (Vanta.InstallState) and the record of a move both go
# by this table, and Vanta Manager by toolbox-records.json, which pins it.
function Get-VantaToolboxLauncherRule {
    @(
        @{ Name = 'Mitigations'; Launchers = @{ 'Disable All Mitigations.cmd' = 0; 'Set Windows Default Mitigations.cmd' = 1; 'Enable All Mitigations.cmd' = 2 } }
        @{ Name = 'ShortcutIcon'; Launchers = @{ 'Default Windows (default).cmd' = 0; 'Classic.cmd' = 1; 'None (security risk).cmd' = 2 } }
    )
}

# The toggle records of an Vanta before 0.6, with the ones the table names as the
# update's Capture leaves them: a launcher's file name gives the state, and a
# record without one, which only the Toolbox wrote, is left out. The record of a
# move is read before any update has done that. It keeps only a file name it can
# trust (Get-VantaTransitionToggleRecord), and none of the table's launchers has
# another, so a path it can't keep counts as none.
function Select-VantaTransitionLauncherRecord($Records) {
    $rules = @{}
    foreach ($rule in @(Get-VantaToolboxLauncherRule)) { $rules[$rule.Name] = $rule.Launchers }
    foreach ($record in @($Records | Where-Object { $null -ne $_ })) {
        $launchers = $rules[[string]$record.name]
        $launcher = $record.PSObject.Properties['path']
        if ($null -eq $launchers) { $record }
        elseif ($null -eq $launcher) { continue }
        elseif ($launchers.ContainsKey([string]$launcher.Value)) {
            [pscustomobject][ordered]@{ name = [string]$record.name; state = [int64]$launchers[[string]$launcher.Value]; path = [string]$launcher.Value }
        }
        else { $record }
    }
}

function Get-VantaTransitionAutomaticUpdatesPolicyState {
    $policy = Get-VantaTransitionValue 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'AUOptions'
    if (-not $policy.Present) { return 1 }
    if ($policy.Kind -ne 'DWord') { return $null }
    if ([int64]$policy.Data -eq 2) { return 0 }
    if ([int64]$policy.Data -in @(3, 4, 5)) { return 1 }
    return $null
}

function Get-VantaTransitionAppxName {
    try { return @(Select-VantaTransitionInstalledAppx @(Get-AppxPackage -AllUsers -ErrorAction Stop) @(Get-VantaTransitionProfileSid)) }
    catch {
        Write-VantaTransitionEvidence "installed apps could not be listed: $($_.Exception.Message)"
        return @()
    }
}

# The families of $Packages, as Get-AppxPackage -AllUsers gives them, installed
# for one of the accounts $ProfileSids names. The list also holds a package only
# staged, one whose removal Windows finishes once the app closes or the account
# signs out, and one registered only to SYSTEM or an account that no longer
# exists. An app removal leaves those behind and lets them pass, as nobody can
# open them (Resolve-VantaAppxRemovalLeftover, Vanta.Appx), so they don't count.
function Select-VantaTransitionInstalledAppx($Packages, [string[]]$ProfileSids) {
    $accounts = @($ProfileSids | Where-Object { $_ })
    $families = foreach ($package in @($Packages | Where-Object { $null -ne $_ })) {
        $family = $package.PSObject.Properties['PackageFamilyName']
        $information = $package.PSObject.Properties['PackageUserInformation']
        if ($null -eq $family -or -not [string]$family.Value -or $null -eq $information) { continue }
        foreach ($entry in @($information.Value | Where-Object { $null -ne $_ })) {
            $identity = $entry.PSObject.Properties['UserSecurityId']
            $sid = if ($null -ne $identity -and $null -ne $identity.Value -and $null -ne $identity.Value.PSObject.Properties['Sid']) { [string]$identity.Value.Sid }
            $state = $entry.PSObject.Properties['InstallState']
            if ($sid -and $accounts -contains $sid -and (Test-VantaTransitionAppxInstalled $(if ($null -ne $state) { [string]$state.Value }))) {
                [string]$family.Value
                break
            }
        }
    }
    return @($families | Sort-Object -Unique)
}

# Whether an account's registration of an app, by its InstallState, is installed,
# as Vanta.Appx's Get-VantaAppxRegistrationKind reads it: not staged or not
# installed, and not waiting for Windows to finish removing it. This file runs on
# its own before an update, so it can't load that module.
function Test-VantaTransitionAppxInstalled([string]$InstallState) {
    $state = $InstallState.Trim()
    return ($state -replace '\s*\([^)]*\)$', '') -notin @('Staged', 'NotInstalled') -and $state -notmatch '\(pending removal\)$'
}

function Test-VantaTransitionPath([string]$Path) { return [IO.File]::Exists($Path) -or [IO.Directory]::Exists($Path) }

function Get-VantaTransitionProfileListKey { 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' }

# The accounts of the people who use this PC, from Windows's profile list: local
# and Microsoft accounts, and work or school (Microsoft Entra ID) ones, as the
# update's sign-in stamps count them (Set-VantaUpgradeUserStamp). The system's own
# service profiles are left out, and so is a profile Windows set aside (.bak).
function Get-VantaTransitionProfileSid {
    @(Get-VantaTransitionSubKeyName (Get-VantaTransitionProfileListKey) | Where-Object { $_ -match '^S-1-(5-21|12-1)-\d+-\d+-\d+-\d+$' })
}

function Get-VantaTransitionProfilePath {
    foreach ($sid in @(Get-VantaTransitionProfileSid)) {
        $path = Get-VantaTransitionValue "$(Get-VantaTransitionProfileListKey)\$sid" 'ProfileImagePath'
        if ($path.Present -and $path.Kind -in @('String', 'ExpandString') -and [string]$path.Data) {
            [Environment]::ExpandEnvironmentVariables([string]$path.Data)
        }
    }
}

# OneDrive installed for the whole PC or by any account on it, not only the one
# running Vanta: a Rebase then leaves it, so nobody's OneDrive is uninstalled
# because Windows moved. Only whether the program file exists is read.
function Test-VantaTransitionOneDrive {
    $paths = @(
        [IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), 'Microsoft OneDrive\OneDrive.exe'),
        [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'Microsoft\OneDrive\OneDrive.exe')
    ) + @(Get-VantaTransitionProfilePath | ForEach-Object { [IO.Path]::Combine($_, 'AppData\Local\Microsoft\OneDrive\OneDrive.exe') })
    foreach ($path in $paths) {
        if (Test-VantaTransitionPath $path) { return $true }
    }
    return $false
}

# What this PC shows of its Vanta install. -UserSid names the account whose
# keyboard settings count; without it they are those of the account running
# this, which for preparation is the signed-in user. -MachineOnly leaves out what
# an install's Capture can't read: the keyboard settings, before it knows its
# user, and the app list, in the time it has. The keyboard facts are then null
# and the app list empty, which both read as not read, not as nothing there.
function Get-VantaTransitionMachineFact([string]$UserSid, [switch]$MachineOnly) {
    $windows = [Environment]::GetFolderPath('Windows')
    $x86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $browser = Get-VantaTransitionValue 'SOFTWARE\Vanta\SetupOptions' 'browser'
    return [pscustomobject]@{
        State = Get-VantaTransitionStateDocument
        LegacyVersions = @(Get-VantaTransitionLegacyVersion | Sort-Object -Unique)
        Toggles = @(Get-VantaTransitionToggleRecord)
        Browser = if ($browser.Present -and $browser.Kind -eq 'String') { [string]$browser.Data } else { $null }
        VantaModules = Test-VantaTransitionPath ([IO.Path]::Combine($windows, 'VantaModules\Scripts'))
        Edge = Test-VantaTransitionPath ([IO.Path]::Combine($x86, 'Microsoft\Edge\Application\msedge.exe'))
        OneDrive = Test-VantaTransitionOneDrive
        Defender = Test-VantaTransitionKey 'SYSTEM\CurrentControlSet\Services\WinDefend'
        DefenderPackage = Get-VantaTransitionDefenderPackageState
        Appx = @(if (-not $MachineOnly) { Get-VantaTransitionAppxName })
        Toolbox = Test-VantaTransitionToolboxInstalled (Test-VantaTransitionKey 'SOFTWARE\Vanta\Toolbox') `
            (Test-VantaTransitionPath ([IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), 'Atlas Toolbox\AtlasToolbox.exe')))
        CoreIsolationOff = Test-VantaTransitionCoreIsolationOff
        Browsers = @(Get-VantaTransitionBrowser)
        LanguageHotkey = if ($MachineOnly) { $null } else { Get-VantaTransitionLanguageHotkey -UserSid $UserSid }
        KeyboardLayouts = if ($MachineOnly) { $null } else { Get-VantaTransitionKeyboardLayoutCount -UserSid $UserSid }
    }
}

# Whether the Atlas Toolbox is installed, from the Toolbox installer's own record
# and whether its program is there. Toolbox 0.1.x leaves the record behind when
# it is uninstalled, so it counts only beside the program, as Vanta's Toolbox
# install checks for it. Vanta Manager reads the Toolbox the same way.
function Test-VantaTransitionToolboxInstalled([bool]$Record, [bool]$Program) { return $Record -and $Program }

# Where Vanta's NoDefender package stands in servicing: Installed (CurrentState
# 112), or until the restart InstallPending (96) or UninstallPending (5); $null
# without one in those states. Of several versions listed, the state that leaves
# Defender removed after the restart counts first. The install's
# Get-VantaServicingPackageState reads a package the same way, by its name and a
# tilde, so another package whose name begins with this one's isn't taken for it.
function Get-VantaTransitionDefenderPackageState {
    $root = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages'
    $states = @()
    foreach ($name in @(Get-VantaTransitionSubKeyName $root | Where-Object { $_ -match '^Z-(?:Atlas|Vanta)-NoDefender-Package~' })) {
        $state = Get-VantaTransitionValue "$root\$name" 'CurrentState'
        if ($state.Present -and $state.Kind -eq 'DWord') { $states += [int64]$state.Data }
    }
    if ($states -contains 112) { return 'Installed' }
    if ($states -contains 96) { return 'InstallPending' }
    if ($states -contains 5) { return 'UninstallPending' }
    return $null
}

# HKU, where Windows loads the hive of each signed-in account. Tests stand in a
# key of their own for it.
function Get-VantaTransitionUsersRoot { [Microsoft.Win32.Registry]::Users }

# One account's key, read only. With a SID it is read through that account's
# loaded hive, as Import-VantaLegacyChoices does from TrustedInstaller, whose own
# HKCU is not the installing user's; without one, the account running this.
function Open-VantaTransitionUserKey([string]$UserSid, [string]$Path) {
    if (-not $UserSid) { return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path, $false) }
    if ($UserSid -cnotmatch '^S-\d-\d+(?:-\d+)+$') { throw "'$UserSid' is not an account SID." }
    return (Get-VantaTransitionUsersRoot).OpenSubKey("$UserSid\$Path", $false)
}

# Alt+Shift (Keyboard Layout\Toggle, Language Hotkey) as text: Vanta 0.5.0 stored
# it as a number, Windows and Settings as text.
function Get-VantaTransitionLanguageHotkey([string]$UserSid) {
    $key = Open-VantaTransitionUserKey $UserSid 'Keyboard Layout\Toggle'
    if ($null -eq $key) { return $null }
    try {
        if (@($key.GetValueNames()) -notcontains 'Language Hotkey') { return $null }
        switch ([string]$key.GetValueKind('Language Hotkey')) {
            'DWord' { return [string][int64]$key.GetValue('Language Hotkey') }
            'String' { return ([string]$key.GetValue('Language Hotkey')).Trim() }
        }
        return $null
    }
    finally { $key.Dispose() }
}

function Get-VantaTransitionKeyboardLayoutCount([string]$UserSid) {
    $key = Open-VantaTransitionUserKey $UserSid 'Keyboard Layout\Preload'
    if ($null -eq $key) { return 0 }
    try { return @($key.GetValueNames()).Count }
    finally { $key.Dispose() }
}

# What Vanta 0.5.0's "Disable Core Isolation" (ConfigVBS.ps1 -DisableAllVBS)
# leaves under Control\DeviceGuard, not the policy path: virtualisation-based
# security set off, and memory integrity off where Windows had its key. Without
# that key the script's write of it failed and only the first value was set, so
# memory integrity may be absent, but not on. Turning memory integrity off in
# Windows Security alone doesn't set the first.
function Test-VantaTransitionCoreIsolationOff {
    $vbs = Get-VantaTransitionValue 'SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity'
    $hvci = Get-VantaTransitionValue 'SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled'
    $vbsOff = $vbs.Present -and $vbs.Kind -eq 'DWord' -and [int64]$vbs.Data -eq 0
    $hvciOn = $hvci.Present -and $hvci.Kind -eq 'DWord' -and [int64]$hvci.Data -ne 0
    return $vbsOff -and -not $hvciOn
}

# The browsers Vanta offers that are installed, by option name.
function Get-VantaTransitionBrowser {
    $programFiles = [Environment]::GetFolderPath('ProgramFiles')
    foreach ($browser in @(
            @('browser-brave', 'BraveSoftware\Brave-Browser\Application\brave.exe'),
            @('browser-firefox', 'Mozilla Firefox\firefox.exe'),
            @('browser-chrome', 'Google\Chrome\Application\chrome.exe'),
            @('browser-librewolf', 'LibreWolf\librewolf.exe'))) {
        if (Test-VantaTransitionPath ([IO.Path]::Combine($programFiles, $browser[1]))) { $browser[0] }
    }
}

# Whether a fact was read. A reader that failed, or one an install's Capture
# skips, leaves its fact out or null, and the choice it shows then stays as
# recorded or requested. Facts come as an object, as
# Get-VantaTransitionMachineFact gives them, or as a hashtable.
function Test-VantaTransitionFactRead($Facts, [string]$Name) {
    if ($Facts -is [Collections.IDictionary]) { return $Facts.Contains($Name) -and $null -ne $Facts[$Name] }
    return $null -ne $Facts -and $null -ne $Facts.PSObject.Properties[$Name] -and $null -ne $Facts.PSObject.Properties[$Name].Value
}

function Get-VantaTransitionFactValue($Facts, [string]$Name) {
    if (-not (Test-VantaTransitionFactRead $Facts $Name)) { return $null }
    if ($Facts -is [Collections.IDictionary]) { return $Facts[$Name] }
    return $Facts.PSObject.Properties[$Name].Value
}

# The install choices the PC can show, with the options each covers, in the
# order their options are listed.
function Get-VantaTransitionChoiceGroup {
    return [ordered]@{
        defender = @('defender-enable', 'defender-disable')
        mitigations = @('mitigations-disable', 'mitigations-default')
        autoUpdates = @('auto-updates-disable', 'auto-updates-default')
        hibernation = @('disable-hibernation')
        powerSaving = @('disable-power-saving')
        edge = @('uninstall-edge')
        snippingTool = @('remove-snipping-tool')
        coreIsolation = @('disable-core-isolation')
        browser = @('install-another-browser', 'browser-*')
        keyboard = @('keyboard-shortcuts', 'keyboard-selector', 'keyboard-single')
    }
}

# What the PC shows, group by group: the options its evidence gives, or none when
# it shows the choice cleared. A group nothing shows is left out, so a choice is
# never guessed. $Base, the options recorded or requested, names the browser to
# look for and gives the keyboard choice the detail its evidence lacks.
# -AfterInstall reads a PC the install has just changed: a Defender package
# Windows adds or takes off at the restart already counts, and a Toolbox or a
# chosen browser that isn't there counts as gone. -Legacy reads an Vanta without
# a state document, whose browser record means what Vanta 0.5.0 meant by it.
function Get-VantaTransitionChoiceEvidence($Facts, [string[]]$VantaPackages = @(), [string[]]$Base = @(), [switch]$AfterInstall, [switch]$Legacy) {
    $shows = { param([string]$Group, [string[]]$Options) [pscustomobject]@{ Group = $Group; Options = @($Options) } }
    $records = @{}
    foreach ($record in @(Get-VantaTransitionFactValue $Facts 'Toggles' | Where-Object { $null -ne $_ })) { $records[[string]$record.name] = [int64]$record.state }

    # Only Vanta's NoDefender package removes Defender, and any other Vanta
    # package or the WinDefend service shows it kept. Defender missing without
    # that package shows nothing: Vanta didn't remove it, so it isn't taken for a
    # choice to remove it.
    $packages = @($VantaPackages | Where-Object { $_ })
    $package = [string](Get-VantaTransitionFactValue $Facts 'DefenderPackage')
    if ($AfterInstall -and $package -ceq 'UninstallPending') { & $shows 'defender' 'defender-enable' }
    elseif ($package -ceq 'Installed' -or ($AfterInstall -and $package -ceq 'InstallPending') -or
        @($packages | Where-Object { $_ -match '^Z-(?:Atlas|Vanta)-NoDefender-Package' }).Count -gt 0) { & $shows 'defender' 'defender-disable' }
    elseif ($packages.Count -gt 0 -or $true -eq (Get-VantaTransitionFactValue $Facts 'Defender')) { & $shows 'defender' 'defender-enable' }

    if ($records.ContainsKey('Mitigations')) { & $shows 'mitigations' $(if ($records['Mitigations'] -eq 0) { 'mitigations-disable' } else { 'mitigations-default' }) }
    if ($records.ContainsKey('AutomaticUpdates')) { & $shows 'autoUpdates' $(if ($records['AutomaticUpdates'] -eq 0) { 'auto-updates-disable' } else { 'auto-updates-default' }) }
    if ($records.ContainsKey('Hibernation')) { & $shows 'hibernation' @(if ($records['Hibernation'] -eq 0) { 'disable-hibernation' }) }
    if ($records.ContainsKey('PowerSaving')) { & $shows 'powerSaving' @(if ($records['PowerSaving'] -eq 0) { 'disable-power-saving' }) }
    $edge = Get-VantaTransitionFactValue $Facts 'Edge'
    if ($null -ne $edge) { & $shows 'edge' @(if (-not $edge) { 'uninstall-edge' }) }
    # Windows always has apps, so an empty list means they couldn't be listed.
    $appx = @(Get-VantaTransitionFactValue $Facts 'Appx' | Where-Object { $_ })
    if ($appx.Count -gt 0) { & $shows 'snippingTool' @(if (@($appx | Where-Object { $_ -like 'Microsoft.ScreenSketch_*' }).Count -eq 0) { 'remove-snipping-tool' }) }
    $coreIsolationOff = Get-VantaTransitionFactValue $Facts 'CoreIsolationOff'
    if ($null -ne $coreIsolationOff) { & $shows 'coreIsolation' @(if ($coreIsolationOff) { 'disable-core-isolation' }) }

    # The taskbar pin record names the browser a new installation chose, and
    # updates leave it as it is, so an installed browser chosen since, such as
    # one Choose again added, comes first. Vanta 0.5.0 recorded LibreWolf as an
    # empty name, so on its installs the one browser installed then decides.
    # Vanta 0.6 records no browser that way, and one someone installed
    # themselves isn't a choice. The record outlives a browser someone
    # uninstalled, so the one it names counts only while it is there, once the
    # browsers have been read.
    $name = Get-VantaTransitionFactValue $Facts 'Browser'
    $installed = @(Get-VantaTransitionFactValue $Facts 'Browsers' | Where-Object { $_ })
    $chosen = @($Base | Where-Object { $_ -like 'browser-*' } | Select-Object -First 1)
    $browser = if ($chosen.Count -gt 0 -and $installed -contains $chosen[0]) { $chosen[0] }
    else {
        $named = switch ([string]$name) {
            'Brave' { 'browser-brave' }
            'Firefox' { 'browser-firefox' }
            'Google Chrome' { 'browser-chrome' }
            'LibreWolf' { 'browser-librewolf' }
            default { if ($Legacy -and $null -ne $name -and $installed.Count -eq 1) { $installed[0] } }
        }
        if ($named -and (-not (Test-VantaTransitionFactRead $Facts 'Browsers') -or $installed -contains $named)) { $named }
    }
    if ($browser) { & $shows 'browser' @('install-another-browser', $browser) }
    elseif ($AfterInstall -and (Test-VantaTransitionFactRead $Facts 'Browsers')) { & $shows 'browser' @() }

    # A KeyboardShortcuts record says whether the shortcuts are on. Without one,
    # Alt+Shift does: Vanta 0.5.0 turned it and Ctrl+Shift off for every user (3),
    # and someone who turned them back on in Settings has 1 or 2 again. Off is all
    # either shows, so a recorded language selector or single layout stays.
    # Without a layout count, as at an install's Capture, it is the language
    # selector, as for a KeyboardShortcuts record of 0 set between installs.
    $off = $null
    if ($records.ContainsKey('KeyboardShortcuts') -and $records['KeyboardShortcuts'] -in @(0, 1)) { $off = $records['KeyboardShortcuts'] -eq 0 }
    else {
        $hotkey = [string](Get-VantaTransitionFactValue $Facts 'LanguageHotkey')
        if ($hotkey -ceq '3') { $off = $true }
        elseif ($hotkey) { $off = $false }
    }
    if ($false -eq $off) { & $shows 'keyboard' 'keyboard-shortcuts' }
    elseif ($off) {
        $kept = @($Base | Where-Object { $_ -ceq 'keyboard-selector' -or $_ -ceq 'keyboard-single' })
        $layouts = Get-VantaTransitionFactValue $Facts 'KeyboardLayouts'
        $keyboard = if ($kept.Count -gt 0) { $kept[0] } elseif ($null -eq $layouts -or [int]$layouts -gt 1) { 'keyboard-selector' } else { 'keyboard-single' }
        & $shows 'keyboard' $keyboard
    }
}

# The install options what the PC shows gives on its own, which for an Vanta
# without a state document (0.5.x and 0.4.1) are its choices: the Defender
# package, the toggle records the choices left, and what was removed. A choice
# nothing shows is left out, never guessed; Vanta Manager asks for it again.
function Get-VantaTransitionObservedOption($Facts, [string[]]$VantaPackages) {
    foreach ($group in @(Get-VantaTransitionChoiceEvidence $Facts $VantaPackages -Legacy)) { $group.Options }
}

# The install choices this PC has: group by group, what it shows replaces the
# options in $Base, recorded or requested, and $Base keeps every choice the PC
# doesn't show, install-eclean and any added later among them. The options $Base
# keeps come first, in its order. -AfterInstall reads a PC the install has just
# changed. Vanta Manager's kept_options applies the same rules before the
# install; merged-options.json keeps the two in step. Like the file's other
# option lists, one option comes back on its own, so callers wrap it in @().
function Merge-VantaObservedOption($Base, $Facts, [string[]]$VantaPackages = @(), [switch]$AfterInstall) {
    $requested = @($Base | ForEach-Object { [string]$_ } | Where-Object { $_ })
    $groups = Get-VantaTransitionChoiceGroup
    $evidence = @(Get-VantaTransitionChoiceEvidence $Facts $VantaPackages $requested -AfterInstall:$AfterInstall)
    $shown = @(foreach ($group in $evidence) { $groups[$group.Group] })
    $merged = [Collections.Generic.List[string]]::new()
    foreach ($option in $requested) {
        if (@($shown | Where-Object { $option -like $_ }).Count -eq 0 -and -not $merged.Contains($option)) { $merged.Add($option) }
    }
    foreach ($option in @($evidence | ForEach-Object { $_.Options })) {
        if (-not $merged.Contains($option)) { $merged.Add($option) }
    }
    return $merged.ToArray()
}

function ConvertTo-VantaTransitionCarry($Facts, [string[]]$VantaPackages = @()) {
    $state = $Facts.State
    $version = $null
    $recorded = $null
    $options = @()
    $source = 'none'
    if ($null -ne $state -and $null -ne $state.PSObject.Properties['installedVersion'] -and [string]$state.installedVersion -match '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') {
        $version = [string]$state.installedVersion
        $recorded = @()
        if ($null -ne $state.PSObject.Properties['options']) { $recorded = @($state.options | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^[a-z0-9-]{1,64}$' }) }
    }
    elseif (@($Facts.LegacyVersions).Count -eq 1) {
        $version = [string]@($Facts.LegacyVersions)[0]
    }
    # No update has repaired an older Vanta's records yet, so the record keeps
    # them as the update's Capture leaves them. Otherwise a Rebase would put back,
    # and hold the update to, a choice only the old Toolbox wrote.
    if ($version -and (Test-VantaVersionBefore06 $version)) {
        $Facts = $Facts.PSObject.Copy()
        $Facts.Toggles = @(Select-VantaTransitionLauncherRecord $Facts.Toggles)
    }
    if ($null -ne $recorded) {
        # An earlier install may have recorded a choice it never applied, so what
        # the PC shows wins: a Rebase after this move puts back what it has.
        $options = @(Merge-VantaObservedOption $recorded $Facts $VantaPackages)
        $source = 'recorded'
    }
    elseif ($version) {
        $options = @(Get-VantaTransitionObservedOption $Facts $VantaPackages)
        $source = 'observed'
    }
    return [pscustomobject][ordered]@{
        vantaVersion = $version; options = @($options); optionSource = $source
        toggles = @($Facts.Toggles | Where-Object { [string]$_.name -match '^[A-Za-z0-9]{1,64}$' -and [int64]$_.state -ge 0 -and [int64]$_.state -le 1000 } | Select-Object -First 400)
        browser = if ($Facts.Browser -and (Test-VantaTransitionString $Facts.Browser 32)) { $Facts.Browser } else { $null }
        vantaModules = [bool]$Facts.VantaModules; edge = [bool]$Facts.Edge; oneDrive = [bool]$Facts.OneDrive; defender = [bool]$Facts.Defender
        appx = @($Facts.Appx | Where-Object { $_ -match '^[A-Za-z0-9._-]{1,128}$' } | Select-Object -First 800)
    }
}

function Get-VantaTransitionCarry([string[]]$VantaPackages = @()) {
    $carry = ConvertTo-VantaTransitionCarry (Get-VantaTransitionMachineFact) $VantaPackages
    Write-VantaTransitionEvidence "recorded the Vanta install: version $(if ($carry.vantaVersion) { $carry.vantaVersion } else { 'none' }), options ($($carry.optionSource)) $($carry.options -join ','), $(@($carry.toggles).Count) toggle records, $(@($carry.appx).Count) apps, Vanta files $($carry.vantaModules), Edge $($carry.edge), OneDrive $($carry.oneDrive), Defender $($carry.defender)"
    return $carry
}

function Test-VantaTransitionCarry($Carry) {
    if ($null -eq $Carry) { return $true }
    if ($null -ne $Carry.vantaVersion -and [string]$Carry.vantaVersion -cnotmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') { return $false }
    if (@('recorded', 'observed', 'none') -cnotcontains [string]$Carry.optionSource) { return $false }
    foreach ($option in @($Carry.options)) { if ([string]$option -cnotmatch '^[a-z0-9-]{1,64}$') { return $false } }
    foreach ($record in @($Carry.toggles)) {
        if ([string]$record.name -cnotmatch '^[A-Za-z0-9]{1,64}$' -or ($record.state -isnot [int] -and $record.state -isnot [long]) -or [int64]$record.state -lt 0 -or [int64]$record.state -gt 1000) { return $false }
        $launcher = $record.PSObject.Properties['path']
        if ($null -ne $launcher -and [string]$launcher.Value -cnotmatch '^[A-Za-z0-9 ().,_-]{1,128}\.cmd$') { return $false }
    }
    if (@($Carry.toggles).Count -gt 400 -or @($Carry.appx).Count -gt 800) { return $false }
    foreach ($name in @($Carry.appx)) { if ([string]$name -cnotmatch '^[A-Za-z0-9._-]{1,128}$') { return $false } }
    if ($null -ne $Carry.browser -and -not (Test-VantaTransitionString ([string]$Carry.browser) 32)) { return $false }
    foreach ($flag in @('vantaModules', 'edge', 'oneDrive', 'defender')) { if ($Carry.$flag -isnot [bool]) { return $false } }
    return $true
}

# Whether Windows rebuilt itself instead of switching releases, from what a rebuild
# leaves: a populated Windows.old, Setup's working folder or a Setup log written
# during the move, and Vanta's components gone. A cumulative update can leave an
# empty Windows.old, so no single sign decides.
function Get-VantaTransitionRebuildFact([DateTime]$Since, [string]$WindowsPath = [Environment]::GetFolderPath('Windows')) {
    # Windows.old and Setup's working folder sit beside the Windows folder.
    $drive = [IO.Path]::GetDirectoryName($WindowsPath.TrimEnd('\'))
    $old = [IO.Path]::Combine($drive, 'Windows.old\Windows')
    $panther = [IO.Path]::Combine($WindowsPath, 'Panther\setupact.log')
    $oldFilled = $false
    if ([IO.Directory]::Exists($old)) {
        try { $oldFilled = @([IO.Directory]::EnumerateFileSystemEntries($old) | Select-Object -First 1).Count -gt 0 }
        catch { $oldFilled = $true }
    }
    return [pscustomobject]@{
        WindowsOld = $oldFilled
        SetupFolder = [IO.Directory]::Exists([IO.Path]::Combine($drive, '$WINDOWS.~BT'))
        PantherWritten = [IO.File]::Exists($panther) -and [IO.File]::GetLastWriteTimeUtc($panther) -ge $Since
        VantaModules = [IO.Directory]::Exists([IO.Path]::Combine($WindowsPath, 'VantaModules\Scripts'))
    }
}

function Resolve-VantaTransitionRebuild($Journal, $Facts, [string[]]$PresentPackages) {
    $carry = if ($null -ne $Journal.PSObject.Properties['carry']) { $Journal.carry } else { $null }
    $missing = @(@($Journal.vantaPackages) | Where-Object { $PresentPackages -notcontains $_ })
    $modulesLost = $null -ne $carry -and [bool]$carry.vantaModules -and -not $Facts.VantaModules
    $signals = @()
    if ($Facts.WindowsOld) { $signals += 'windows-old' }
    if ($Facts.SetupFolder) { $signals += 'setup-folder' }
    if ($Facts.PantherWritten) { $signals += 'setup-log' }
    if ($missing.Count -gt 0) { $signals += 'packages-missing' }
    if ($modulesLost) { $signals += 'vanta-files-missing' }
    $verdict = Get-VantaTransitionRebuildVerdict $signals
    return [pscustomobject][ordered]@{
        rebuilt = $verdict.Setup -and $verdict.Lost; setup = [bool]$verdict.Setup; lost = [bool]$verdict.Lost
        signals = @($signals); missing = @($missing); checkedAt = [DateTime]::UtcNow.ToString('o')
    }
}

# A service backup from the Windows that Setup replaced, back beside Vanta's new
# files: it describes the services before Vanta first changed them, which the
# rebuilt Windows can no longer show. Only a plain file of a service backup's size
# is copied, and an existing backup is kept.
function Copy-VantaRebaseServiceBackup([string]$Name, [string]$WindowsPath = [Environment]::GetFolderPath('Windows')) {
    $destination = [IO.Path]::Combine($WindowsPath, 'VantaModules\Other', $Name)
    if ([IO.File]::Exists($destination)) { return "kept the existing ${Name}" }
    $source = [IO.Path]::Combine([IO.Path]::GetDirectoryName($WindowsPath.TrimEnd('\')), 'Windows.old\Windows\VantaModules\Other', $Name)
    if (-not [IO.File]::Exists($source)) { return "no ${Name} to bring back" }
    $file = [IO.FileInfo]::new($source)
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return "left ${Name}: it is a link" }
    for ($directory = $file.Directory; $null -ne $directory -and $null -ne $directory.Parent; $directory = $directory.Parent) {
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return "left ${Name}: '$($directory.FullName)' is a link" }
    }
    if ($file.Length -gt 32MB) { return "left ${Name}: larger than a service backup" }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
    [IO.File]::Copy($source, $destination, $false)
    return "brought back ${Name} from Windows.old"
}

# The recorded choices, back from the record of the move when the rebuilt Windows
# lost the registry that held them. Choices Windows kept are never replaced.
# Get-VantaToggleStateRecords and Set-VantaToggleState come from Vanta.Toggles,
# Repair-VantaToolboxRecord from Vanta.InstallState.
function Restore-VantaRebaseChoice($Carry) {
    $records = Get-VantaToggleStateRecords
    if ($records.Count -gt 0) { "kept the $($records.Count) recorded choices Windows kept" }
    else {
        $restored = 0
        foreach ($record in @($Carry.toggles)) {
            Set-VantaToggleState -Name ([string]$record.name) -State ([int]$record.state)
            # The 0.5.0 launcher name goes back beside the state, so the choices step
            # that follows corrects a value that launcher wrote the wrong way round.
            $launcher = $record.PSObject.Properties['path']
            if ($null -ne $launcher) {
                Set-VantaTransitionValue "SOFTWARE\Vanta\Services\$([string]$record.name)" 'path' 'String' ([string]$launcher.Value)
            }
            $restored++
        }
        "brought back $restored recorded choices from the record of the move"
    }
    # The records an Vanta before 0.6 left, the old Atlas Toolbox's among them,
    # read as Vanta 0.6 means them before the legacy choices step reads them. The
    # update's Capture found none to repair when Windows had lost them, and an
    # attempt stopped part way may have put back only some. A record already
    # repaired is left as it is, while its launcher's path is still there: the
    # legacy choices step, which removes it, comes after.
    foreach ($line in @(Repair-VantaToolboxRecord -InstalledVersion ([string]$Carry.vantaVersion))) { $line }
    if ($Carry.browser) {
        $browser = Get-VantaTransitionValue 'SOFTWARE\Vanta\SetupOptions' 'browser'
        if (-not $browser.Present) {
            Set-VantaTransitionValue 'SOFTWARE\Vanta\SetupOptions' 'browser' 'String' ([string]$Carry.browser)
            "brought back the recorded browser choice '$($Carry.browser)'"
        }
    }
}

# The app removals a Rebase repeats: only families nothing had installed before
# Windows moved. One that was there was kept or put back by the user, and removing
# it would delete its data.
function Select-VantaRebaseAppxRemoval($Definition, [AllowEmptyCollection()][string[]]$Before) {
    # Windows always has apps, so an empty list means they couldn't be listed
    # when the move was recorded: no removal is known to be safe, so none runs.
    $unknown = @($Before).Count -eq 0
    foreach ($item in @($Definition)) {
        $pattern = [string]$item.Name
        $kept = $unknown -or @($Before | Where-Object { $_ -like $pattern -or ($_ -split '_')[0] -like $pattern }).Count -gt 0
        [pscustomobject]@{ Definition = $item; Kept = $kept }
    }
}

# The Vanta install's view of an open move after which Windows rebuilt itself:
# the version and choices recorded before it. $null when there is none.
function Get-VantaWindowsTransitionRebase([string]$Root = (Get-VantaWindowsTransitionRoot)) {
    $journal = Read-VantaWindowsTransition $Root
    if ($null -eq $journal -or $journal.kind -ne 'transition') { return $null }
    $rebuild = $journal.PSObject.Properties['rebuild']
    if ($null -eq $rebuild -or $null -eq $rebuild.Value -or -not [bool]$rebuild.Value.rebuilt) { return $null }
    $carry = if ($null -ne $journal.PSObject.Properties['carry']) { $journal.carry } else { $null }
    if ($null -eq $carry -or -not $carry.vantaVersion) { return $null }
    return [pscustomobject]@{ VantaVersion = [string]$carry.vantaVersion; Options = @($carry.options); Carry = $carry; Rebuild = $rebuild.Value }
}

# One item as it is now, for the journal, or nothing when its value is of a kind
# or shape the table does not allow (it is then never changed or restored).
function New-VantaTransitionEntry($Item, [bool]$Lift) {
    $value = Get-VantaTransitionLive $Item
    # The move rewrites the pin, so a pin value the record can't hold stops it
    # before anything changes.
    if ($Item.Group -eq 'pin' -and $value.Present -and
        -not (Test-VantaTransitionItemValue $Item ([pscustomobject]@{ present = $true; kind = $value.Kind; data = $value.Data }))) {
        Write-VantaTransitionEvidence "refused: $($Item.Id) is $(Format-VantaTransitionValue $value)"
        throw (New-VantaTransitionFailure "The feature-update policy value $($Item.Name) has a value Vanta can't put back later." 'feature-pin' @{ setting = $Item.Name })
    }
    if ($value.Present -and $Item.Kinds -cnotcontains $value.Kind) {
        Write-VantaTransitionEvidence "left $($Item.Id): unexpected kind $($value.Kind)"
        return
    }
    if ($value.Present -and $value.Kind -eq 'String' -and -not (Test-VantaTransitionString ([string]$value.Data) 64)) {
        Write-VantaTransitionEvidence "left $($Item.Id): value is not plain text"
        return
    }
    return [pscustomobject][ordered]@{
        id = $Item.Id; present = [bool]$value.Present; kind = $value.Kind; data = $value.Data
        ownerRecord = [bool](Get-VantaTransitionOwnerRecord $Item.Owner); lifted = $Lift
    }
}

# Something can hold Windows Update back after the record was made, such as a
# launcher from an earlier Vanta. Its value now is what to put back later.
function Update-VantaTransitionLiftSet($Journal, [string]$Root = (Get-VantaWindowsTransitionRoot)) {
    $table = @{}
    foreach ($item in Get-VantaWindowsTransitionItem) { $table[$item.Id] = $item }
    $entries = [Collections.ArrayList]::new()
    foreach ($entry in @($Journal.items)) { [void]$entries.Add($entry) }
    $added = @()
    foreach ($blocker in @(Get-VantaWindowsUpdateBlocker)) {
        $index = -1
        for ($i = 0; $i -lt $entries.Count; $i++) { if ([string]$entries[$i].id -eq $blocker.Id) { $index = $i } }
        if ($index -ge 0 -and $entries[$index].lifted) { continue }
        $entry = New-VantaTransitionEntry $table[$blocker.Id] $true
        if ($null -eq $entry) { continue }
        if ($index -ge 0) { $entries[$index] = $entry } else { [void]$entries.Add($entry) }
        $added += $blocker.Id
    }
    if ($added.Count -eq 0) { return }
    $Journal.items = @($entries)
    Add-VantaTransitionHistory $Journal 'new-blocker' ($added -join ',')
    Write-VantaWindowsTransition $Journal $Root
}

# Records every table item as it is now, before the first change, with whether it
# will be lifted. An existing journal is kept: a resumed run must never record
# lifted values as the originals.
function Save-VantaWindowsTransitionSnapshot {
    param(
        [ValidateSet('transition', 'access')][string]$Kind,
        $Source, $Target, [string]$UserSid, [string[]]$VantaPackages = @(), $Carry = $null,
        [string]$Root = (Get-VantaWindowsTransitionRoot)
    )
    $existing = Read-VantaWindowsTransition $Root
    if ($null -ne $existing) {
        if ($existing.kind -eq 'access' -and $Kind -eq 'transition') {
            # A plain update before this one never touched the pin, so its
            # values now are the originals.
            $pins = @(foreach ($item in Get-VantaWindowsTransitionItem | Where-Object Group -eq 'pin') { New-VantaTransitionEntry $item $false })
            $existing.items = @($existing.items) + $pins
            $existing.kind = 'transition'
            $existing | Add-Member -NotePropertyName target -NotePropertyValue $Target -Force
            $existing.vantaPackages = @($VantaPackages)
            if ($null -ne $Carry) { $existing | Add-Member -NotePropertyName carry -NotePropertyValue $Carry -Force }
            Add-VantaTransitionHistory $existing 'became-transition' $Target.release
            Write-VantaWindowsTransition $existing $Root
        }
        return $existing
    }
    $lift = @{}
    foreach ($blocker in @(Get-VantaWindowsUpdateBlocker)) { $lift[$blocker.Id] = $true }
    $items = foreach ($item in Get-VantaWindowsTransitionItem) {
        if ($Kind -eq 'access' -and $item.Group -eq 'pin') { continue }
        New-VantaTransitionEntry $item ([bool]$lift.ContainsKey($item.Id))
    }
    $journal = [pscustomobject][ordered]@{
        schema = 1; kind = $Kind; phase = 'lifted'; source = $Source
        userSid = $UserSid; createdAt = [DateTime]::UtcNow.ToString('o')
        items = @($items); vantaPackages = @($VantaPackages)
        installed = $null; commitBoot = $null; commitRetried = $false; history = @()
    }
    if ($Kind -eq 'transition') {
        $journal | Add-Member -NotePropertyName target -NotePropertyValue $Target
        if ($null -ne $Carry) { $journal | Add-Member -NotePropertyName carry -NotePropertyValue $Carry }
    }
    foreach ($entry in @($items)) {
        $shown = if ($entry.present) { "$($entry.kind) $($entry.data)" } else { 'absent' }
        Write-VantaTransitionEvidence "recorded $($entry.id): $shown$(if ($entry.lifted) { ' (will lift)' })$(if ($entry.ownerRecord) { ' (owner record)' })"
    }
    Add-VantaTransitionHistory $journal 'snapshot' "kind=$Kind"
    Write-VantaWindowsTransition $journal $Root
    return $journal
}

function Format-VantaTransitionValue($Value) {
    if ($null -eq $Value -or -not $Value.Present) { return 'absent' }
    return "$($Value.Kind) $($Value.Data)"
}

# Applies the lifted value of every item the journal marks lifted, then reads each
# back. Running it again changes nothing. A value that does not stay put is being
# set by something Vanta does not control, such as an organisation's policy.
function Invoke-VantaWindowsUpdateLift($Journal) {
    $table = @{}
    foreach ($item in Get-VantaWindowsTransitionItem) { $table[$item.Id] = $item }
    foreach ($entry in @($Journal.items | Where-Object { $_.lifted })) {
        $item = $table[[string]$entry.id]
        $before = Get-VantaTransitionLive $item
        if ($item.Rule -eq 'task') {
            # Windows Update searches and installs without these tasks, so one
            # that can't be turned on doesn't stop the update.
            if ($before.Present -and $before.Data -ne $item.Lift) {
                try { Set-VantaTransitionTask $item.Path $item.Name $item.Lift }
                catch { Write-VantaTransitionEvidence "could not turn on task $($item.Name): $($_.Exception.Message)" }
            }
            Write-VantaTransitionEvidence "lifted $($item.Id): $(Format-VantaTransitionValue $before) -> $(Format-VantaTransitionValue (Get-VantaTransitionLive $item))"
            continue
        }
        if ($item.Id -like 'service.*') {
            $service = $item.Path.Split('\')[-1]
            if (-not ($before.Present -and [int64]$before.Data -eq $item.Lift)) {
                Set-VantaTransitionServiceStart $service $item.Lift
            }
            try { Start-VantaTransitionService $service }
            catch { Write-VantaTransitionEvidence "could not start ${service}: $($_.Exception.Message)" }
        }
        elseif ($null -eq $item.Lift) {
            if ($before.Present) { Remove-VantaTransitionValue $item.Path $item.Name }
        }
        elseif (-not ($before.Present -and $before.Kind -eq 'DWord' -and [int64]$before.Data -eq $item.Lift)) {
            Set-VantaTransitionValue $item.Path $item.Name 'DWord' $item.Lift
        }
        $after = Get-VantaTransitionLive $item
        Write-VantaTransitionEvidence "lifted $($item.Id): $(Format-VantaTransitionValue $before) -> $(Format-VantaTransitionValue $after)"
        $stuck = if ($null -eq $item.Lift) { $after.Present } else { -not ($after.Present -and [int64]$after.Data -eq $item.Lift) }
        if ($stuck) {
            throw (New-VantaTransitionFailure "$($item.Id) went back to $(Format-VantaTransitionValue $after) after Vanta changed it." 'feature-policy' @{ setting = $item.Name })
        }
    }
}

# The one writer of the feature-update target, for the worker and the Vanta pin
# tweak. It retargets; it never removes the pin and never touches safeguard
# policies. The key is created only when missing: recreating it would drop the
# other policy values beside it.
function Set-VantaFeatureUpdateTarget([Parameter(Mandatory = $true)][ValidatePattern('^\d{2}H\d$')][string]$Release) {
    $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name 'TargetReleaseVersion' -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $path -Name 'ProductVersion' -Value 'Windows 11' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $path -Name 'TargetReleaseVersionInfo' -Value $Release -PropertyType String -Force | Out-Null
    $written = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
    $names = @($written.PSObject.Properties.Name)
    if ($names -notcontains 'TargetReleaseVersion' -or $written.TargetReleaseVersion -ne 1 -or
        $names -notcontains 'ProductVersion' -or $written.ProductVersion -cne 'Windows 11' -or
        $names -notcontains 'TargetReleaseVersionInfo' -or $written.TargetReleaseVersionInfo -cne $Release) {
        throw "Windows did not keep the feature-update target $Release."
    }
}

function Test-VantaTransitionLiveMatches($Item, $Live, $Entry) {
    if (-not $Entry.present) { return -not $Live.Present }
    return $Live.Present -and $Live.Kind -eq $Entry.kind -and [string]$Live.Data -ceq [string]$Entry.data
}

# Puts back what the journal says Vanta changed, deciding item by item from the
# code table, never from the journal alone:
#   Installed: the Vanta install has replayed the user's recorded toggles, so items
#     whose owner had a record are left to it; the pin stays as the install wrote it.
#   Moved: Windows has moved; everything else comes back and the new pin stays.
#   Abandoned: Windows did not move; everything comes back, the pin exactly.
# An item is restored only while it still holds the lifted value: if something else
# changed it since, that change stays. The journal goes last, then the result.
function Restore-VantaWindowsTransition {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Installed', 'Moved', 'Abandoned')][string]$Outcome,
        [string]$Root = (Get-VantaWindowsTransitionRoot)
    )
    $journal = Read-VantaWindowsTransition $Root
    if ($null -eq $journal) { return $null }
    $entries = @{}
    foreach ($entry in @($journal.items)) { $entries[[string]$entry.id] = $entry }
    $restored = @(); $changed = @(); $owned = @(); $failed = @()
    foreach ($item in Get-VantaWindowsTransitionItem | Where-Object Group -ne 'pin') {
        if (-not $entries.ContainsKey($item.Id)) { continue }
        $entry = $entries[$item.Id]
        if (-not $entry.lifted) { continue }
        if ($Outcome -eq 'Installed' -and $entry.ownerRecord -and (Get-VantaTransitionOwnerRecord $item.Owner)) {
            $owned += $item.Id
            Write-VantaTransitionEvidence "left $($item.Id) to the replayed $($item.Owner) choice"
            continue
        }
        $live = Get-VantaTransitionLive $item
        $holdsLift = if ($null -eq $item.Lift) { -not $live.Present }
        elseif ($item.Rule -eq 'task') { $live.Present -and $live.Data -eq $item.Lift }
        else { $live.Present -and [int64]$live.Data -eq $item.Lift }
        if (-not $holdsLift) {
            $changed += $item.Id
            Write-VantaTransitionEvidence "left $($item.Id): changed since to $(Format-VantaTransitionValue $live)"
            continue
        }
        # One item that can't be put back doesn't stop the others, and only it
        # stays in the record. A task follows its service, as when lifting: one
        # that can't be put back is logged and left.
        try {
            if ($item.Rule -eq 'task') {
                if ($entry.present) { Set-VantaTransitionTask $item.Path $item.Name ([string]$entry.data) }
            }
            elseif ($item.Id -like 'service.*') {
                $service = $item.Path.Split('\')[-1]
                if ($entry.present) {
                    Set-VantaTransitionServiceStart $service ([int]$entry.data)
                    if ([int]$entry.data -eq 4) {
                        try { Stop-VantaTransitionService $service }
                        catch { Write-VantaTransitionEvidence "could not stop ${service}: $($_.Exception.Message)" }
                    }
                }
            }
            elseif ($entry.present) { Set-VantaTransitionValue $item.Path $item.Name ([string]$entry.kind) $entry.data }
            else { Remove-VantaTransitionValue $item.Path $item.Name }
        }
        catch {
            Write-VantaTransitionEvidence "could not put back $($item.Id): $($_.Exception.Message)"
            if ($item.Rule -ne 'task') { $failed += $item.Id }
            continue
        }
        # A later try puts back only what this one couldn't.
        $entry.lifted = $false
        $restored += $item.Id
        Write-VantaTransitionEvidence "restored $($item.Id): $(Format-VantaTransitionValue $live) -> $(if ($entry.present) { "$($entry.kind) $($entry.data)" } else { 'absent' })"
    }
    if ($failed.Count -gt 0) {
        Add-VantaTransitionHistory $journal 'restore' "outcome=$Outcome restored=$($restored.Count) failed=$($failed -join ',')"
        Write-VantaWindowsTransition $journal $Root
        throw (New-VantaTransitionFailure "Vanta couldn't put back $($failed -join ', ')." 'feature-restore' @{ setting = $failed -join ', ' })
    }
    $pin = 'kept'
    if ($Outcome -eq 'Abandoned' -and $journal.kind -eq 'transition') {
        $pinItems = @(Get-VantaWindowsTransitionItem | Where-Object Group -eq 'pin')
        $live = @{}; foreach ($item in $pinItems) { $live[$item.Id] = Get-VantaTransitionLive $item }
        $original = $true
        foreach ($item in $pinItems) {
            if ($entries.ContainsKey($item.Id) -and -not (Test-VantaTransitionLiveMatches $item $live[$item.Id] $entries[$item.Id])) { $original = $false }
        }
        $ours = $live['pin.TargetReleaseVersion'].Present -and $live['pin.TargetReleaseVersion'].Kind -eq 'DWord' -and [int64]$live['pin.TargetReleaseVersion'].Data -eq 1 -and
            [string]$live['pin.ProductVersion'].Data -ceq 'Windows 11' -and [string]$live['pin.TargetReleaseVersionInfo'].Data -ceq [string]$journal.target.release
        if ($original) { $pin = 'unchanged' }
        elseif (-not $ours) {
            $pin = 'changed'
            Write-VantaTransitionEvidence 'left the feature-update target: changed since'
        }
        else {
            foreach ($item in $pinItems) {
                if (-not $entries.ContainsKey($item.Id)) { continue }
                $entry = $entries[$item.Id]
                if ($entry.present) { Set-VantaTransitionValue $item.Path $item.Name ([string]$entry.kind) $entry.data }
                else { Remove-VantaTransitionValue $item.Path $item.Name }
                Write-VantaTransitionEvidence "restored $($item.Id): $(Format-VantaTransitionValue $live[$item.Id]) -> $(if ($entry.present) { "$($entry.kind) $($entry.data)" } else { 'absent' })"
            }
            $pin = 'restored'
        }
    }
    Add-VantaTransitionHistory $journal 'restore' "outcome=$Outcome restored=$($restored.Count) changed=$($changed.Count) owned=$($owned.Count) pin=$pin"
    $windows = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $result = [pscustomobject][ordered]@{
        schema = 1; closedAt = [DateTime]::UtcNow.ToString('o'); outcome = $Outcome; kind = [string]$journal.kind
        restored = @($restored); changed = @($changed); owned = @($owned); pin = $pin
        build = if ($windows) { [int]$windows.CurrentBuildNumber } else { 0 }
        ubr = if ($windows -and $null -ne $windows.PSObject.Properties['UBR']) { [int]$windows.UBR } else { 0 }
        history = @($journal.history)
    }
    Remove-VantaWindowsTransition $Root
    Set-VantaTransitionValue $Root 'LastResult' 'String' ($result | ConvertTo-Json -Depth 6 -Compress)
    return $result
}

# The install's closing step: after the Vanta install has replayed the user's
# choices and written its own pin, everything else comes back. A Rebase install that
# got here has put Vanta back on the rebuilt Windows, so the record says so first: a
# setting that can't be put back then keeps the record open for that alone, and a
# later install isn't taken for another Rebase.
function Complete-VantaWindowsTransition([string]$Root = (Get-VantaWindowsTransitionRoot), [switch]$Rebased) {
    $open = Test-VantaWindowsTransitionOpen $Root
    if ($null -eq $open) { return 'No Windows Update settings were changed for an update; nothing to put back.' }
    if (-not $open.Readable) { throw "The Windows Update record could not be read, so nothing was put back: $($open.Error)" }
    if ($Rebased -and $null -ne (Get-VantaWindowsTransitionRebase $Root)) {
        $journal = Read-VantaWindowsTransition $Root
        $journal.rebuild.rebuilt = $false
        Add-VantaTransitionHistory $journal 'rebase' 'Vanta was put back on the rebuilt Windows'
        Write-VantaWindowsTransition $journal $Root
        'Vanta was put back on the rebuilt Windows.'
    }
    $result = Restore-VantaWindowsTransition -Outcome Installed -Root $Root
    "Windows Update settings put back: $(@($result.restored) -join ', ')"
    if (@($result.owned).Count -gt 0) { "Left as the replayed choices set them: $(@($result.owned) -join ', ')" }
    if (@($result.changed).Count -gt 0) { "Left because they changed since: $(@($result.changed) -join ', ')" }
}

# Toggling Windows Update or its pause by hand while Vanta has it turned on for an
# update would mix a new choice into what the restore puts back. The install's own
# replay does not come through here.
function Assert-VantaToggleAllowedDuringTransition([string]$Name, [string]$Root = (Get-VantaWindowsTransitionRoot)) {
    if (@('ToggleWindowsUpdates', 'PauseUpdates') -notcontains $Name) { return }
    if ($null -ne (Test-VantaWindowsTransitionOpen $Root)) {
        throw 'Vanta Manager is updating Windows and has turned Windows Update on for now. Finish or stop that update in Vanta Manager, then change this setting.'
    }
}
