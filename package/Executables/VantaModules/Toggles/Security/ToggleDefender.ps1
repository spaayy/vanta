# Companion for the ToggleDefender toggle: removes or restores Windows Defender through the
# NoDefender package. Select-VantaDefenderToggleState runs first, in the administrator window:
# it shows the menu and its warning and picks an internal state, the same pattern as Enable
# Search Indexing. That state's function then runs in the silent TrustedInstaller broker.
# Nothing is recorded.

function Select-VantaDefenderToggleState {
    param($Toggle)

    if ($Toggle.Silent) {
        throw 'Choosing whether to enable or disable Windows Defender needs an interactive window.'
    }
    Import-VantaModule -Name Vanta.Security
    return Read-VantaDefenderStateChoice
}

function Invoke-VantaDefenderToggle {
    param($Toggle)

    # Reached only by a direct silent request for the public state, which has no
    # choice to apply; the interactive path never runs this action.
    [void]$Toggle
    throw 'Toggle Defender needs an interactive window to choose between enabling and disabling Windows Defender.'
}

function Disable-VantaDefenderToggle {
    param($Toggle)

    Import-VantaModule -Name Vanta.Security
    Set-VantaDefenderState -State Disable -Silent:$Toggle.Silent
    Set-VantaDefenderToggleChoice -Option 'defender-disable'
}

function Enable-VantaDefenderToggle {
    param($Toggle)

    Import-VantaModule -Name Vanta.Security
    Set-VantaDefenderState -State Enable -Silent:$Toggle.Silent
    Set-VantaDefenderToggleChoice -Option 'defender-enable'
}

function Set-VantaDefenderToggleChoice {
    param([string]$Option)

    # The Defender install choice now describes this change, which takes effect at the
    # restart the toggle asks for. Defender has already changed, so a record that
    # can't be written is a warning; the next install records what the PC has.
    Import-VantaModule -Name Vanta.State
    try {
        $null = Set-VantaStateChoice -Option $Option
    }
    catch {
        Write-VantaLog -Level Warning -Message "Couldn't record '$Option' in the Vanta state document: $($_.Exception.Message)" -ErrorRecord $_
    }
}
