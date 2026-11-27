# AppxSupport phase. Runs as TrustedInstaller, in this order: snapshot, stop the
# installing user's package processes, remove installed and provisioned packages,
# clean up Phone Link, write deprovision markers, then clear the user's caches.
# Required package failures are collected so cleanup still runs before the phase
# returns nonzero.
#
# Machine AppX work stays in this token and every package query and removal uses
# AllUsers. User-controlled cache trees are cleared by a child running as the
# installing user, never through a privileged token, and profile roots are never
# enumerated here.
# https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage

Assert-VantaPrivilege -TrustedInstaller

$modulesRoot = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'Modules'
Import-Module -Name (Join-Path $modulesRoot 'Vanta.Appx\Vanta.Appx.psd1') -Force -ErrorAction Stop

# Get current AppX packages to deprovision removed ones afterwards. A failed snapshot is
# fatal before mutation because cleanup could not safely determine what Vanta removed.
Save-VantaAppxSnapshot

# Quiesce Teams/Search in the exact install-state user's nonzero session before
# removal. This checked launch is process-only; cache mutation remains after removal
# and deprovisioning. This strict TI process never enumerates or terminates UI.
Invoke-VantaUserAppxCacheCleanup -Mode AppxQuiesce

$requiredFailures = [System.Collections.Generic.List[string]]::new()
# A Rebase removes only what Windows brought back: an app that was installed before
# Windows moved was kept or reinstalled by the user, and removing it deletes its data.
$definitions = @(Get-VantaAppxRemovalDefinition)
$context = Get-VantaContext
if ($context.IsRebase) {
    . (Join-Path (Split-Path -Parent $modulesRoot) 'Preparation\WindowsTransition.ps1')
    $rebase = Get-VantaWindowsTransitionRebase
    if ($null -eq $rebase) { throw 'A Rebase install needs Vanta Manager''s record of the Windows move.' }
    $before = @($rebase.Carry.appx)
    $selection = @(Select-VantaRebaseAppxRemoval $definitions $before)
    if ($before.Count -eq 0) {
        Write-VantaLog -Message 'Left every AppX family: the record of the Windows move has no list of the apps installed before it.'
    }
    else {
        foreach ($entry in @($selection | Where-Object Kept)) {
            Write-VantaLog -Message "Left AppX family '$($entry.Definition.Name)': it was installed before Windows moved."
        }
    }
    $definitions = @($selection | Where-Object { -not $_.Kept } | ForEach-Object { $_.Definition })
}
try {
    if ($definitions.Count -gt 0) { Invoke-VantaAppxRemovalPlan -Definition $definitions }
}
catch {
    $requiredFailures.Add($_.Exception.Message)
}

# Phone Link is removed on its own and best effort: removing it with the other
# packages broke Cross Device Experience Host installation.
try {
    Remove-VantaPhoneLinkAppx
}
catch {
    Write-VantaLog -Level Warning -Message "Removing Phone Link failed: $($_.Exception.Message)"
}

# Prevent removed provisioned applications from being restored by a feature update.
# https://learn.microsoft.com/en-us/windows/application-management/remove-provisioned-apps-during-update
try {
    Set-VantaAppxDeprovisioned
}
catch {
    $message = "Deprovisioning removed AppX packages failed: $($_.Exception.Message)"
    $requiredFailures.Add($message)
    Write-VantaLog -Level Error -Message $message
}

# Clear caches of Client.CBS and more (Start menu cache is cleared later).
try {
    Invoke-VantaUserAppxCacheCleanup -Mode AppxSupport
}
catch {
    $message = "Clearing AppX caches failed: $($_.Exception.Message)"
    $requiredFailures.Add($message)
    Write-VantaLog -Level Error -Message $message
}

if ($requiredFailures.Count -gt 0) {
    throw "The AppX removal plan failed after cleanup: $($requiredFailures -join ' | ')"
}
