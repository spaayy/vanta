<#
.SYNOPSIS
    Retries, or gives up, the CBS packages Windows refused outside Safe Mode.
.DESCRIPTION
    When Windows refuses a component (CBS) package, Vanta can record it in
    %windir%\VantaOS\Recovery\CbsRetry.json and set Windows to start in Safe Mode with
    Command Prompt. At that prompt, an administrator runs Invoke-VantaCbsRetry.cmd, which
    starts this script with -Recover or -Discard. Recover hands the packages to the
    TrustedInstaller broker's CbsRetry operation, which runs this script again with
    -Recover under the TrustedInstaller token to install them.

    The install, Install-VantaPackage.ps1, SafeMode.ps1 and Vanta.Software dot-source it
    with -LibraryOnly to arm, read or clear the retry.
.PARAMETER Recover
    Installs the armed packages again. Windows starts normally from the next restart.
.PARAMETER Discard
    Gives up the retry: leaves Safe Mode and removes the retry state.
.PARAMETER LibraryOnly
    Only defines the functions, for callers that dot-source the script.
.NOTES
    Exit codes:
    0  The packages installed, the retry was given up, or no retry was waiting.
    1  The retry failed, or neither -Recover nor -Discard was given.
#>
[CmdletBinding()]
param(
    [switch]$Recover,
    [switch]$Discard,
    [switch]$LibraryOnly
)

Set-StrictMode -Version 3.0
$script:VantaCbsRetryMutexName = 'Global\Vanta.CbsRetry'

function Get-VantaCbsRetryStatePath {
    Join-Path ([Environment]::GetFolderPath('Windows')) 'VantaOS\Recovery\CbsRetry.json'
}

function Get-VantaCbsRetryLauncher {
    '"{0}"' -f (Join-Path ([Environment]::GetFolderPath('Windows')) `
            'VantaModules\Scripts\Entry\Invoke-VantaCbsRetry.cmd')
}

function Get-VantaCbsRetryInstruction {
    <#
    .SYNOPSIS
        What to tell the user about a CBS retry in the given phase. Every message about
        the retry uses this or Get-VantaCbsRetryLauncher, so they all name the same command.
    #>
    param([ValidateSet('Pending', 'Armed')][string]$Phase = 'Armed')

    $launcher = Get-VantaCbsRetryLauncher
    if ($Phase -ceq 'Armed') {
        return "Windows starts in Safe Mode with Command Prompt until the retry is done. At that command prompt, run $launcher to retry the packages, or $launcher /discard to give up the retry."
    }
    return "Run $launcher /discard as an administrator to give up the retry and use Vanta's Safe Mode tools again."
}

function Get-VantaCbsRetryPromptPaths {
    [pscustomobject]@{
        SavedPrompt    = Join-Path ([Environment]::GetFolderPath('Windows')) 'VantaOS\Recovery\CbsRetryPrompt.json'
        EnvironmentKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    }
}

function Set-VantaCbsRetryPrompt {
    <#
    .SYNOPSIS
        Shows the retry's instruction at the Safe Mode command prompt. Safe Mode with
        Command Prompt starts only a bare program name as its shell: a command with
        arguments, or a script, gets the Explorer desktop instead. So cmd.exe stays the
        shell and the machine-wide PROMPT carries the instruction. The value it replaces
        is saved once, so arming again never saves Vanta's own prompt.
    #>
    param($Paths = (Get-VantaCbsRetryPromptPaths))

    if (![IO.File]::Exists($Paths.SavedPrompt)) {
        $property = (Get-ItemProperty -LiteralPath $Paths.EnvironmentKey -ErrorAction Stop).PSObject.Properties['PROMPT']
        $saved = [ordered]@{
            Present = $null -ne $property
            Value   = if ($null -ne $property) { [string]$property.Value } else { '' }
        }
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Paths.SavedPrompt))
        [IO.File]::WriteAllText($Paths.SavedPrompt, ($saved | ConvertTo-Json -Compress),
            (New-Object Text.UTF8Encoding($false)))
    }
    # In PROMPT, $_ is a line break and $P$G the usual path prompt; a literal $ is $$.
    $launcher = (Get-VantaCbsRetryLauncher).Replace('$', '$$')
    $prompt = 'Vanta: Safe Mode package retry$_Run {0} to retry the packages, or add /discard to give up the retry.$_$_$P$G' -f $launcher
    Set-ItemProperty -LiteralPath $Paths.EnvironmentKey -Name PROMPT -Type String -Value $prompt -ErrorAction Stop
}

function Restore-VantaCbsRetryPrompt {
    <#
    .SYNOPSIS
        Puts back the machine-wide PROMPT Set-VantaCbsRetryPrompt replaced. Without a
        saved value there is nothing of Vanta's to undo; an unreadable one removes
        Vanta's prompt, so cmd.exe shows its default again.
    #>
    param($Paths = (Get-VantaCbsRetryPromptPaths))

    if (![IO.File]::Exists($Paths.SavedPrompt)) { return }
    $saved = try {
        Get-Content -LiteralPath $Paths.SavedPrompt -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch { $null }
    $value = ''
    if ($null -ne $saved -and $null -ne $saved.PSObject.Properties['Present'] -and
        $null -ne $saved.PSObject.Properties['Value'] -and [bool]$saved.Present) {
        $value = [string]$saved.Value
    }
    if ($value) {
        Set-ItemProperty -LiteralPath $Paths.EnvironmentKey -Name PROMPT -Type String -Value $value -ErrorAction Stop
    }
    elseif ($null -ne (Get-ItemProperty -LiteralPath $Paths.EnvironmentKey -ErrorAction Stop).PSObject.Properties['PROMPT']) {
        Remove-ItemProperty -LiteralPath $Paths.EnvironmentKey -Name PROMPT -ErrorAction Stop
    }
    [IO.File]::Delete($Paths.SavedPrompt)
}

function Get-VantaLegacyCbsRetryStatePath {
    Join-Path ([Environment]::GetFolderPath('Windows')) `
        'System32\safeModePackagesToInstall.vantamodule'
}

function Get-VantaLegacyCbsRetryShell {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
        'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon', $false)
    if ($null -eq $key) { return '' }
    try {
        return [string]$key.GetValue('Shell', '',
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    }
    finally { $key.Dispose() }
}

function Remove-VantaLegacyCbsRetryList {
    <#
    .SYNOPSIS
        Removes the Safe Mode package list Vanta 0.5 left in System32. 0.5 never deleted
        it, so it records a past component failure, not a retry to resume. It's kept
        only while 0.5's own retry is still set to run, which replacing Vanta's files
        would break.
    #>
    param([string]$Path = (Get-VantaLegacyCbsRetryStatePath))

    if (![IO.File]::Exists($Path)) { return }
    # 0.5 armed its retry by adding packageInstall.ps1 -SafeMode to the Winlogon shell,
    # and that run put the shell back.
    if ((Get-VantaLegacyCbsRetryShell) -like '*packageInstall.ps1*-SafeMode*') {
        throw 'Vanta 0.5 is still set to retry installing its Windows component packages when Windows next starts. Restart Windows to let it finish, then update Vanta again.'
    }
    $packages = try {
        @(Get-Content -LiteralPath $Path -ErrorAction Stop |
                ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) -join ', '
    }
    catch { "unreadable: $($_.Exception.Message)" }
    if ([string]::IsNullOrEmpty($packages)) { $packages = 'none' }
    Write-Output "Removing the Safe Mode package list Vanta 0.5 left at '$Path' (packages: $packages)."
    try { [IO.File]::Delete($Path) }
    catch {
        Write-Warning "The Vanta 0.5 Safe Mode package list '$Path' couldn't be removed: $($_.Exception.Message)"
    }
}

function Read-VantaCbsRetryState {
    param([string]$Path = (Get-VantaCbsRetryStatePath))
    if (![IO.File]::Exists($Path)) { return $null }
    $state = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($state.Version -ne 1 -or [string]$state.Phase -notin @('Pending', 'Armed') -or
        @($state.Packages).Count -eq 0) {
        throw "CBS retry state '$Path' is invalid."
    }
    foreach ($package in @($state.Packages)) {
        if ([string]::IsNullOrWhiteSpace([string]$package) -or ![IO.Path]::IsPathRooted([string]$package)) {
            throw "CBS retry state '$Path' contains a non-absolute package path."
        }
    }
    return $state
}

function Write-VantaCbsRetryState {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Pending', 'Armed')][string]$Phase,
        [Parameter(Mandatory = $true)][string[]]$Packages,
        [string]$Path = (Get-VantaCbsRetryStatePath)
    )
    if ($Packages.Count -eq 0) { throw 'At least one CBS package is required.' }
    $absolute = @($Packages | ForEach-Object {
        if (![IO.Path]::IsPathRooted($_)) { throw "CBS package path '$_' is not absolute." }
        [IO.Path]::GetFullPath($_)
    })
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $state = [ordered]@{
        Version = 1; Phase = $Phase; Packages = $absolute
        UpdatedUtc = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText($Path, ($state | ConvertTo-Json -Compress),
        (New-Object Text.UTF8Encoding($false)))
    return [pscustomobject]$state
}

function Clear-VantaCbsRetryState {
    param([string]$Path = (Get-VantaCbsRetryStatePath))
    if ([IO.File]::Exists($Path)) { [IO.File]::Delete($Path) }
}

function Invoke-WithVantaCbsRetryLock {
    param([Parameter(Mandatory = $true)][scriptblock]$Action)
    $mutex = New-Object Threading.Mutex($false, $script:VantaCbsRetryMutexName)
    $held = $false
    try {
        try { $held = $mutex.WaitOne([TimeSpan]::FromSeconds(30)) }
        catch [Threading.AbandonedMutexException] { $held = $true }
        if (!$held) { throw 'Timed out waiting for the Vanta CBS retry lock.' }
        & $Action
    }
    finally {
        if ($held) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Invoke-VantaCbsRetrySafeMode {
    param([ValidateSet('CommandPrompt', 'Exit')][string]$Mode)
    $requestedMode = $Mode
    if ($null -eq (Get-Command Set-VantaSafeMode -CommandType Function -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'SafeMode.ps1') -LibraryOnly
    }
    Set-VantaSafeMode -Mode $requestedMode -AllowCbsRetryPending:($requestedMode -ceq 'CommandPrompt')
    if ($requestedMode -ceq 'CommandPrompt') { Set-VantaCbsRetryPrompt } else { Restore-VantaCbsRetryPrompt }
}

function Resolve-VantaCbsRetryInstaller {
    <#
    .SYNOPSIS
        Returns Install-VantaCbsPackage once the TrustedInstaller token is confirmed.
        Servicing needs that token. Checking it before Safe Mode or the state changes
        keeps a retry started with any other token armed, so it can run again.
    #>
    $command = Get-Command Install-VantaCbsPackage -CommandType Function -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        $modulePath = Join-Path ([Environment]::GetFolderPath('Windows')) `
            'VantaModules\Scripts\Modules\Vanta.Software\Vanta.Software.psd1'
        if (![IO.File]::Exists($modulePath)) {
            throw "The installed Vanta.Software module is unavailable at '$modulePath'."
        }
        Import-Module -Name $modulePath -Force -ErrorAction Stop
        $command = Get-Command Install-VantaCbsPackage -CommandType Function -ErrorAction Stop
    }
    Assert-VantaPrivilege -TrustedInstaller
    return $command
}

function Invoke-VantaCbsRetryInstaller {
    param([string[]]$Packages, [Parameter(Mandatory = $true)]$Installer)
    $result = & $Installer -Packages $Packages -LiteralPaths
    if ($null -ne $result -and $null -ne $result.PSObject.Properties['FailedPackages'] -and
        @($result.FailedPackages).Count -ne 0) {
        throw "CBS packages still failed in Safe Mode: $(@($result.FailedPackages) -join ', ')"
    }
    return $result
}

function Enable-VantaCbsRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$Packages,
        [string]$StatePath = (Get-VantaCbsRetryStatePath),
        [scriptblock]$SafeModeCommand
    )
    Invoke-WithVantaCbsRetryLock {
        $packagesToArm = @($Packages | ForEach-Object {
            if (![IO.Path]::IsPathRooted($_)) { throw "CBS package path '$_' is not absolute." }
            [IO.Path]::GetFullPath($_)
        })
        $existing = Read-VantaCbsRetryState -Path $StatePath
        if ($null -ne $existing) {
            if ([string]$existing.Phase -ceq 'Armed') { throw 'A CBS retry is already armed.' }
            $existingPackages = @($existing.Packages)
            $samePackages = $existingPackages.Count -eq $packagesToArm.Count
            for ($index = 0; $samePackages -and $index -lt $packagesToArm.Count; $index++) {
                $samePackages = [string]::Equals(
                    [string]$existingPackages[$index], $packagesToArm[$index],
                    [StringComparison]::OrdinalIgnoreCase)
            }
            if (!$samePackages) { throw 'A different CBS retry is already pending.' }
        }
        else {
            [void](Write-VantaCbsRetryState -Phase Pending -Packages $packagesToArm -Path $StatePath)
        }
        if ($SafeModeCommand) { & $SafeModeCommand 'CommandPrompt' }
        else { Invoke-VantaCbsRetrySafeMode -Mode CommandPrompt }
        Write-VantaCbsRetryState -Phase Armed -Packages $packagesToArm -Path $StatePath
    }
}

function Invoke-VantaCbsRetryRecovery {
    [CmdletBinding()]
    param(
        [string]$StatePath = (Get-VantaCbsRetryStatePath),
        [scriptblock]$SafeModeCommand,
        [scriptblock]$Installer
    )
    Invoke-WithVantaCbsRetryLock {
        $state = Read-VantaCbsRetryState -Path $StatePath
        if ($null -eq $state) { throw 'No CBS retry is pending.' }
        if ([string]$state.Phase -cne 'Armed') {
            throw "The CBS retry is pending but has not been armed for Safe Mode. $(Get-VantaCbsRetryInstruction -Phase Pending)"
        }
        $install = if ($Installer) { $Installer } else { Resolve-VantaCbsRetryInstaller }
        if ($SafeModeCommand) { & $SafeModeCommand 'Exit' }
        else { Invoke-VantaCbsRetrySafeMode -Mode Exit }
        [void](Write-VantaCbsRetryState -Phase Pending -Packages @($state.Packages) -Path $StatePath)
        [void](Invoke-VantaCbsRetryInstaller -Packages @($state.Packages) -Installer $install)
        Clear-VantaCbsRetryState -Path $StatePath
    }
}

function Invoke-VantaCbsRetryDiscard {
    <#
    .SYNOPSIS
        Gives up a CBS retry: leaves Safe Mode and removes the retry state, so Vanta can
        be updated and its Safe Mode tools work again. Returns whether there was a retry
        to give up.
    #>
    [CmdletBinding()]
    param(
        [string]$StatePath = (Get-VantaCbsRetryStatePath),
        [scriptblock]$SafeModeCommand
    )
    Invoke-WithVantaCbsRetryLock {
        # Not read first, so damaged state can be given up too. Vanta refuses every other
        # Safe Mode change while retry state exists, so Safe Mode set now is the retry's.
        if (![IO.File]::Exists($StatePath)) { return $false }
        if ($SafeModeCommand) { & $SafeModeCommand 'Exit' }
        else { Invoke-VantaCbsRetrySafeMode -Mode Exit }
        Clear-VantaCbsRetryState -Path $StatePath
        return $true
    }
}

function Clear-VantaUnarmedCbsRetry {
    <#
    .SYNOPSIS
        Gives up a retry that isn't armed, before Vanta's files are replaced. Arming and
        recovery hold the lock while Pending, so Pending found here is left over: a
        failed Safe Mode retry, or Vanta 0.5's list as an earlier build recorded it.
        Nothing resumes it, and it would block every update.
    #>
    param([string]$StatePath = (Get-VantaCbsRetryStatePath))
    Invoke-WithVantaCbsRetryLock {
        $state = Read-VantaCbsRetryState -Path $StatePath
        if ($null -eq $state -or [string]$state.Phase -cne 'Pending') { return }
        Write-Output "Giving up the CBS retry that was never armed (packages: $(@($state.Packages) -join ', '))."
        Clear-VantaCbsRetryState -Path $StatePath
        # Arming that failed after setting the prompt leaves it too.
        Restore-VantaCbsRetryPrompt
    }
}

function Test-VantaCbsRetryInstallUnfinished {
    <#
    .SYNOPSIS
        Whether an install is still unfinished. An install that arms the retry ends at
        its components step, so the rest of it still has to run. Only whether its state
        file exists: reading it, as Get-VantaContext does, can throw on damaged state
        after the retry has worked.
    #>
    [IO.File]::Exists((Join-Path ([Environment]::GetFolderPath('Windows')) 'VantaOS\Install\active.json'))
}

function Test-VantaCbsRetryNormalBoot {
    # A boot state that can't be read counts as Safe Mode.
    $bootState = try {
        [string](Get-CimInstance -ClassName Win32_ComputerSystem -Property BootupState).BootupState
    }
    catch { '' }
    $bootState -eq 'Normal boot'
}

function Request-VantaCbsRetryRestart {
    if (Read-VantaYesNo -Question 'Restart Windows now?') {
        $null = & ([IO.Path]::Combine([Environment]::GetFolderPath('System'), 'shutdown.exe')) /r /t 0
    }
}

function Invoke-VantaCbsRetryCommand {
    <#
    .SYNOPSIS
        Retries the armed packages (Recover) or gives the retry up (Discard), as
        Invoke-VantaCbsRetry.cmd asks at the Safe Mode command prompt. The broker's
        CbsRetry operation runs Recover again with a TrustedInstaller token. Returns
        the exit code.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Recover', 'Discard')][string]$Mode,
        [string]$StatePath = (Get-VantaCbsRetryStatePath)
    )

    if ($Mode -ceq 'Recover' -and (Test-VantaTrustedInstaller)) {
        # The broker's CbsRetry operation gives this process no console, so the
        # transcript and the log keep the outcome.
        try {
            Start-VantaPhase -Phase 'CbsRetry'
            [void](Invoke-VantaCbsRetryRecovery -StatePath $StatePath)
            Stop-VantaPhase
            return 0
        }
        catch {
            Write-VantaLog -Level Error -Message "The Safe Mode retry of the CBS packages failed: $($_.Exception.Message)" -ErrorRecord $_
            Stop-VantaPhase -Failed
            return 1
        }
    }

    $title = 'Safe Mode package retry'
    Set-VantaLogConsoleStyle -Style Interactive
    Write-VantaTitle -Text $title
    try {
        Assert-VantaPrivilege -Administrator
        if ($Mode -ceq 'Discard') {
            if (Invoke-VantaCbsRetryDiscard -StatePath $StatePath) {
                $done = 'The retry was given up. Windows starts normally from the next restart.'
                if (Test-VantaCbsRetryInstallUnfinished) { $done += ' After the restart, open Vanta to try installing again.' }
                Write-VantaSuccess -Text $done
                # Safe Mode's command prompt has no Start menu to restart from.
                if (!(Test-VantaCbsRetryNormalBoot)) { Request-VantaCbsRetryRestart }
            }
            else { Write-VantaNote -Text 'No retry was waiting, so nothing was changed.' }
            return 0
        }
        $state = Read-VantaCbsRetryState -Path $StatePath
        if ($null -eq $state) {
            Write-VantaNote -Text 'No retry is waiting, so nothing was changed.'
            return 0
        }
        if ([string]$state.Phase -cne 'Armed') {
            throw "The retry isn't set to run in Safe Mode. $(Get-VantaCbsRetryInstruction -Phase Pending)"
        }
        # Outside Safe Mode the retry would most likely fail as the first attempt did.
        if (Test-VantaCbsRetryNormalBoot) { throw "The retry runs in Safe Mode. $(Get-VantaCbsRetryInstruction)" }

        Write-VantaStep -Text 'Installing the packages again. This can take several minutes...'
        try { [void](Invoke-VantaTrustedInstaller -Operation CbsRetry -TimeoutSeconds 3600) }
        catch {
            # A retry that reached servicing has already left Safe Mode; say what's left.
            $after = try { Read-VantaCbsRetryState -Path $StatePath } catch { $null }
            $next = if ($null -ne $after) { " $(Get-VantaCbsRetryInstruction -Phase ([string]$after.Phase))" } else { '' }
            throw "The packages didn't install: $($_.Exception.Message)$next"
        }
    }
    catch {
        Write-VantaLog -Level Error -Message "$title failed: $($_.Exception.Message)" -ErrorRecord $_ -NoConsole
        Write-VantaNotApplied -Title $title -Reason $_.Exception.Message -DetailsPath (Get-VantaInstallLogPath)
        return 1
    }

    $done = 'The packages are installed. Windows starts normally from the next restart.'
    if (Test-VantaCbsRetryInstallUnfinished) { $done += ' After the restart, open Vanta to finish installing it.' }
    Write-VantaSuccess -Text $done
    Request-VantaCbsRetryRestart
    return 0
}

if (!$LibraryOnly) {
    if ($Recover -eq $Discard) { throw 'Specify -Recover or -Discard, or use -LibraryOnly.' }
    $scriptsRoot = [IO.Path]::GetDirectoryName($PSScriptRoot)
    $trustBootstrap = [IO.Path]::Combine($scriptsRoot, 'Initialize-VantaPowerShell.ps1')
    if (![IO.File]::Exists($trustBootstrap)) {
        throw "The PowerShell trust bootstrap is missing at '$trustBootstrap'."
    }
    . $trustBootstrap
    $ErrorActionPreference = 'Stop'
    Import-Module -Name ([IO.Path]::Combine($scriptsRoot, 'Modules', 'Vanta.Core', 'Vanta.Core.psd1')) `
        -Force -ErrorAction Stop
    exit (Invoke-VantaCbsRetryCommand -Mode $(if ($Recover) { 'Recover' } else { 'Discard' }))
}
