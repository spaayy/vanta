# Companion for the Indexing toggle: sets Windows Search indexing to off, minimal or full
# through the installed indexing helper. Its machine functions run in the silent
# TrustedInstaller broker when you run a launcher, when the install applies the toggle and
# when an update replays the recorded state. Select-VantaFullIndexingState runs first, in the
# administrator window, and picks the internal state that carries your power mode choice to
# the broker.

function Disable-VantaSearchIndexing {
    param($Toggle)

    [void]$Toggle
    Import-VantaModule -Name Vanta.Search
    Set-VantaIndexingMachineState -State Disable
}

function Set-VantaMinimalSearchIndexing {
    param($Toggle)

    [void]$Toggle
    Import-VantaModule -Name Vanta.Search
    Set-VantaIndexingMachineState -State Minimal
}

function Enable-VantaSearchIndexing {
    param($Toggle)

    # TrustedInstaller work always runs silently, so the interactive power-mode
    # question is Select-VantaFullIndexingState.
    [void]$Toggle
    Import-VantaModule -Name Vanta.Search
    Set-VantaIndexingMachineState -State Full -PreservePowerModes
}

function Select-VantaFullIndexingState {
    param($Toggle)

    if ($Toggle.Silent) { throw 'Interactive indexing selection cannot run silently.' }
    if (Read-VantaYesNo -Question 'Pause indexing while on battery power or gaming?') {
        return 'EnableRespectPowerModes'
    }
    return 'EnableIgnorePowerModes'
}

function Set-VantaSelectedFullIndexing {
    param($Toggle)

    $value = switch -CaseSensitive ($Toggle.State) {
        'EnableRespectPowerModes' { 1 }
        'EnableIgnorePowerModes' { 0 }
        default { throw "Unexpected full indexing choice '$($Toggle.State)'." }
    }
    Import-VantaModule -Name Vanta.Search
    Set-VantaIndexingMachineState -State Full -RespectPowerModes $value
    # Both interactive variants become the existing replayable Full choice. Only
    # record after the preset and its selected power-mode setting both succeed.
    Set-VantaToggleState -Name Indexing -State 2 -StateRoot $Toggle.StateRoot
}
