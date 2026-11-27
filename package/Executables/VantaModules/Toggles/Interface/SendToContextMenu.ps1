# Companion for the SendToContextMenu toggle: lets you choose which Send to entries to hide or
# show for your account. Invoke-VantaSendToContextMenuChooser runs in the launcher's own
# process, as you, when you run the launcher; nothing is recorded.

function Invoke-VantaSendToContextMenuChooser {
    param($Toggle)

    Import-VantaModule -Name Vanta.Shell
    if ($Toggle.Silent) {
        Set-VantaSendToContextMenu -DebloatDefaults
        return
    }

    if (-not (Set-VantaSendToContextMenu)) {
        return
    }
    # The engine never restarts Explorer from an elevated process, so asking here would
    # offer a restart that can't happen.
    if ((Test-VantaSystem) -or (Test-VantaAdmin)) {
        Write-VantaLog -NoConsole -Message 'The Send To items changed in an elevated window, so no File Explorer restart was offered.'
        Write-VantaNextStep -Text 'Restart File Explorer from a normal (non-administrator) window, or sign out and back in, to see the change.'
        return
    }
    if (-not (Read-VantaYesNo -Question 'Restart File Explorer now to apply the change?' -DefaultYes)) {
        return
    }
    # The items have already changed, so a failed refresh leaves the run partly done
    # rather than not applied.
    try {
        Write-VantaStep -Text 'Restarting File Explorer...'
        Invoke-VantaToggleCurrentSessionShellRefresh -Operation ExplorerRefresh
    }
    catch {
        Write-VantaLog -Level Warning -NoConsole -Message "The Send To Explorer refresh failed: $($_.Exception.Message)"
        Write-VantaPartial -Text "The Send To items changed, but File Explorer couldn't be restarted. Restart File Explorer, or sign out and back in."
    }
}
