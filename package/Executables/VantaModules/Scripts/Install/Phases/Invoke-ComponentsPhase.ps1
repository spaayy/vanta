# Components phase, on a first installation and a Rebase.
# Removes Windows components: the Security Center startup item, Smart App Control,
# Microsoft Edge (option gated), OneDrive, the Teams chat auto-install policy and the
# CBS component packages (option gated). Runs as TrustedInstaller. Child-script and
# CBS package failures throw to the install plan, which fails the Run phase with a
# single nonzero exit code.
#
# Not handled here: Edge's installed/provisioned package-family removal (the AppxSupport phase).

Assert-VantaPrivilege -TrustedInstaller

$scriptsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulesRoot = Join-Path -Path $scriptsRoot -ChildPath 'Modules'
Import-Module -Name (Join-Path $modulesRoot 'Vanta.Services\Vanta.Services.psd1') -Force -ErrorAction Stop
Import-Module -Name (Join-Path $modulesRoot 'Vanta.TasksProcs\Vanta.TasksProcs.psd1') -Force -ErrorAction Stop
Import-Module -Name (Join-Path $modulesRoot 'Vanta.Software\Vanta.Software.psd1') -Force -ErrorAction Stop
Import-Module -Name (Join-Path $modulesRoot 'Vanta.Security\Vanta.Security.psd1') -Force -ErrorAction Stop
# Shared with the Choices phase, which applies the same choices on a Choose again update.
. (Join-Path $scriptsRoot 'Install\Tasks\Set-VantaDefenderChoice.ps1')
. (Join-Path $scriptsRoot 'Install\Tasks\Invoke-VantaEdgeRemoval.ps1')

$powerShellExe = [IO.Path]::Combine(
    [Environment]::SystemDirectory,
    'WindowsPowerShell',
    'v1.0',
    'powershell.exe'
)

# A Rebase leaves Edge and OneDrive when they were installed before Windows moved:
# someone, on any account, kept or put them back and may use them. Without the
# record, both are left.
$keepEdge = $false
$keepOneDrive = $false
if ((Get-VantaContext).IsRebase) {
    . (Join-Path $scriptsRoot 'Preparation\WindowsTransition.ps1')
    $rebase = Get-VantaWindowsTransitionRebase
    $keepEdge = $null -eq $rebase -or [bool]$rebase.Carry.edge
    $keepOneDrive = $null -eq $rebase -or [bool]$rebase.Carry.oneDrive
    if ($keepEdge -and (Test-VantaOption -Name 'uninstall-edge')) { Write-VantaLog -Message 'Left Edge: it was installed before Windows moved.' }
    if ($keepOneDrive) { Write-VantaLog -Message 'Left OneDrive: it was installed before Windows moved.' }
}
# OneDrive stays by default (work PCs sync documents with it); removing it is a Tools choice. Only a context that
# sets RemoveOneDrive (no screen does today) removes it here.
$wantsOneDriveRemoved = $null -ne (Get-VantaContext).PSObject.Properties['RemoveOneDrive'] -and [bool](Get-VantaContext).RemoveOneDrive
if (-not $wantsOneDriveRemoved) { $keepOneDrive = $true }
$removeEdge = (Test-VantaOption -Name 'uninstall-edge') -and -not $keepEdge

if ($removeEdge) {
    Invoke-VantaEdgeRemoval -ScriptsRoot $scriptsRoot -Context (Get-VantaContext)
}

Remove-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'SecurityHealth' -Force -ErrorAction SilentlyContinue

# Turn off Smart App Control: it slows app loading and sends data to Microsoft.
$ciPolicyKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy'
if (-not (Test-Path -LiteralPath $ciPolicyKey)) {
    New-Item -Path $ciPolicyKey -Force | Out-Null
}
Set-ItemProperty -LiteralPath $ciPolicyKey -Name 'VerifiedAndReputablePolicyState' -Value 0 -Type DWord -Force

# Windows keeps the inbox OneDriveSetup.exe; Vanta doesn't strip it at component level.
# Uninstall and machine cleanup run here as TrustedInstaller; HKCU and profile leftovers
# are cleaned only in the installing user's own token.
try {
    if (-not $keepOneDrive) { Remove-VantaOneDrive }
}
catch {
    $containmentUnconfirmed = $false
    for ($exception = $_.Exception; $null -ne $exception; $exception = $exception.InnerException) {
        if ($exception.Data.Contains('VantaProcessMayStillBeRunning') -and
            [bool]$exception.Data['VantaProcessMayStillBeRunning']) {
            $containmentUnconfirmed = $true
            break
        }
    }
    if ($containmentUnconfirmed) {
        throw
    }
    Write-VantaLog -Level Warning -Message "Removing OneDrive failed: $($_.Exception.Message)"
}

$oneDriveContext = Get-VantaContext
if (-not $keepOneDrive) {
    $interactiveUserSid = [string]$oneDriveContext.InteractiveUserSid
    if ([string]::IsNullOrWhiteSpace($interactiveUserSid)) {
        throw 'OneDrive current-user cleanup requires the install-state user SID.'
    }
    $oneDriveUserScript = Join-Path -Path $scriptsRoot `
        -ChildPath 'Operations\Remove-OneDriveCurrentUserData.ps1'
    $oneDriveUserArguments = ConvertTo-VantaWindowsArgumentString -ArgumentList ([string[]]@(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $oneDriveUserScript,
        '-ExpectedUserSid', $interactiveUserSid, '-DeferFileCleanup'
    ))
    $oneDriveCleanupStarted = [datetime]::UtcNow
    $oneDriveUserExitCode = Invoke-VantaAsUser -FilePath $powerShellExe `
        -Arguments $oneDriveUserArguments
    if ($oneDriveUserExitCode -ne 0) {
        # OneDrive can leave locked cache files or profile-specific state that its
        # own uninstaller cannot remove. Machine removal is already complete here;
        # optional user-owned leftovers must not make the Vanta install fail.
        . (Join-Path $scriptsRoot 'Install\Tasks\Get-VantaUserFailureDetail.ps1')
        $failureDetail = Get-VantaUserFailureDetail -UserSid $interactiveUserSid `
            -TranscriptPattern '*-onedrive-cleanup-*.log' -NotBefore $oneDriveCleanupStarted
        Write-VantaLog -Level Warning -Message `
            "Exact-user OneDrive leftover cleanup exited with code $oneDriveUserExitCode; continuing because only user-owned cleanup remains.$failureDetail"
    }
}

# Windows components and Telemetry (CBS packages)
# Install-VantaCbsPackage throws on failure after registering the Safe Mode retry
# fallback, making this ordered step fail so the orchestrator returns nonzero. A
# Rebase is a first installation too: the Windows that rebuilt itself lost Vanta's
# packages, so both choices put NoTelemetry back as a Fresh install does.
if (Test-VantaOption -Name 'defender-disable') {
    $null = Set-VantaDefenderChoice -State Disable -Fresh
}
if (Test-VantaOption -Name 'defender-enable') {
    $null = Set-VantaDefenderChoice -State Enable -Fresh
}

# Prevent Teams chat from being reinstalled. This key is TrustedInstaller-protected,
# which is why the write belongs in this phase rather than the AppX snapshot phase.
$communicationsKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications'
if (-not (Test-Path -LiteralPath $communicationsKey)) {
    New-Item -Path $communicationsKey -Force | Out-Null
}
Set-ItemProperty -LiteralPath $communicationsKey -Name 'ConfigureChatAutoInstall' -Value 0 -Type DWord -Force
