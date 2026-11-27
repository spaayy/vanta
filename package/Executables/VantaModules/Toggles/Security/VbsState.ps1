# Companion for the VbsState toggle: turns Virtualisation-Based Security and Memory Integrity
# on or off. Set-VantaVbsState runs as Administrator when you run a launcher and when an
# update replays the recorded state. Test-VantaVbsStateReplayApplicable decides during update
# replay whether the recorded state still applies.

function Set-VantaVbsState {
    param($Toggle)

    # The state name is the Set-VantaVbsConfiguration -State value: Disable or Enable.
    Import-VantaModule -Name Vanta.Security
    Set-VantaVbsConfiguration -State $Toggle.State
}

function Test-VantaVbsStateReplayApplicable {
    param($Toggle)

    # A choice that policy or a UEFI lock now refuses would fail every update that
    # replays it, so its record is cleared instead. The reason goes to the log.
    Import-VantaModule -Name Vanta.Security
    $reason = Test-VantaVbsChange -State $Toggle.State
    if ($null -ne $reason) {
        $change = if ($Toggle.State -ceq 'Disable') { 'turned off' } else { 'turned on' }
        Write-VantaLog -Message "VBS can't be ${change}: $reason."
    }
    return $null -eq $reason
}
