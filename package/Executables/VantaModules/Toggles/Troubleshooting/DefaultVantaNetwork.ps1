# Companion for the DefaultVantaNetwork toggle: resets the network adapter settings to the
# Vanta or Windows defaults. Set-VantaNetworkDefaultState runs as Administrator when you run a
# launcher and when the install applies the Vanta defaults; nothing is recorded.

function Set-VantaNetworkDefaultState {
    param($Toggle)

    Import-VantaModule -Name Vanta.Network
    $mode = if ($Toggle.State -ceq 'Enable') { 'Vanta' } else { 'Windows' }
    if (-not $Toggle.Silent) {
        if ($mode -ceq 'Vanta') {
            Write-VantaStep -Text 'Applying the Vanta network adapter defaults...'
        }
        else {
            Write-VantaStep -Text 'Resetting the network stack and adapters to the Windows defaults. This can take a minute...'
        }
    }
    [void](Set-VantaNetworkDefaults -Mode $mode)
}
