# Companion for the FileSharing toggle: applies file sharing through the Vanta.Network
# functions the fresh install uses. Set-VantaFileSharingMachineState runs as Administrator
# when you run a launcher, when the install applies the toggle and when an update replays the
# recorded state. Add-VantaFileSharingNetworkNavigationPane runs in your own unelevated
# process after Enable, and is replayed for each new account at first sign-in. The engine owns
# the closing line and the restart prompt, and records the state only after the machine part
# completes.

function Set-VantaFileSharingMachineState {
    param($Toggle)

    Import-VantaModule -Name Vanta.Network
    $enable = $Toggle.State -ceq 'Enable'
    $parameters = @{ Silent = [bool]$Toggle.Silent }
    if ($enable) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Toggle.StateRoot)) {
            $parameters['StateRoot'] = [string]$Toggle.StateRoot
        }
        Enable-VantaFileSharing @parameters
    }
    else {
        Disable-VantaFileSharing @parameters
    }
}

function Add-VantaFileSharingNetworkNavigationPane {
    param($Toggle)

    # NetworkNavigationPane owns this independent choice and its first sign-in replay.
    # Replaying FileSharing must not replace it or ask the question again.
    if ($Toggle.Silent -or
        -not (Read-VantaYesNo -Question 'Add Network to the File Explorer navigation pane?')) {
        return
    }
    Invoke-VantaToggle -Name 'NetworkNavigationPane' -State 'Enable' -StateRoot $Toggle.StateRoot `
        -NoExplorerRestart -DeferPostAction
}
