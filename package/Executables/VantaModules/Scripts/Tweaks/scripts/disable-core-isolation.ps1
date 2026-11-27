# Companion of disable-core-isolation.psd1.
$ErrorActionPreference = 'Stop'

# On an update, a choice made since with the Core Isolation (VBS) launchers stays, as
# every recorded toggle does: Defaults has already replayed it.
if ((Get-VantaContext).IsUpgrade) {
    Import-VantaModule -Name Vanta.Toggles
    $record = Get-VantaToggleState -Name VbsState
    if ($null -ne $record -and $null -ne $record.State) {
        Write-VantaLog -Message "Keeping the recorded VbsState choice (state $($record.State)) instead of disabling VBS."
        return
    }
}
Import-VantaModule -Name Vanta.Security
Set-VantaVbsConfiguration -State Disable -SkipWhenPolicyConflicts
