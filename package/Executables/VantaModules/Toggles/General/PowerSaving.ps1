# Companion for the PowerSaving toggle: applies the Vanta power settings or restores the
# earlier power plan. Invoke-VantaPowerSavingToggle runs as Administrator when you run a
# launcher, when the install applies your power-saving choice and when an update replays the
# recorded state.

function Invoke-VantaPowerSavingToggle {
    param($Toggle)

    switch -CaseSensitive ([string]$Toggle.State) {
        'Disable' {
            $mode = 'Vanta'
            $message = 'The Vanta AC power policy is active.'
        }
        'Enable' {
            $mode = 'Default'
            $message = 'The previous power plan, or Balanced when none was saved, is active and the Vanta plan was removed.'
        }
        default { throw "PowerSaving: unsupported state '$($Toggle.State)'." }
    }

    Import-VantaModule -Name Vanta.Hardware
    Set-VantaPowerSavingState -Mode $mode -Silent:$Toggle.Silent

    # CPU idle and sleep settings belong to a plan, and both modes leave a different
    # plan active, so the recorded choices are applied to it again. The plan change
    # stands even when a record can't be read or applied.
    $planFolders = @{ CpuIdle = 'CPU Idle'; Sleep = 'Sleep' }
    foreach ($planToggle in @('CpuIdle', 'Sleep')) {
        try {
            $record = Get-VantaToggleState -Name $planToggle -StateRoot $Toggle.StateRoot
            if ($null -eq $record -or $record.State -notin @(0, 1)) {
                continue
            }
            $planState = @('Disable', 'Enable')[[int]$record.State]
            # Upgrade replay skips a choice this PC can't take, such as disabling CPU
            # idle with SMT on, so it isn't a failure here either.
            $planDefinition = Get-VantaToggleDefinition -Name $planToggle
            if (-not (Test-VantaToggleReplayApplicable -Definition $planDefinition -StateName $planState `
                        -StateRoot $Toggle.StateRoot)) {
                Write-VantaLog -Message "PowerSaving left the recorded $planToggle choice: it doesn't apply on this PC."
                continue
            }
            Invoke-VantaToggleMachineState -Name $planToggle -State $planState -StateRoot $Toggle.StateRoot
        }
        catch {
            Write-VantaLog -Level Warning -NoConsole:(-not $Toggle.Silent) -ErrorRecord $_ -Message `
                "PowerSaving couldn't apply the recorded $planToggle choice to the new power plan: $($_.Exception.Message)"
            if (-not $Toggle.Silent) {
                $planFolder = $planFolders[$planToggle]
                Write-VantaPartial -Text "The power plan changed, but your $planFolder choice couldn't be applied to it. Run its launcher in the $planFolder folder again."
            }
        }
    }

    if (-not $Toggle.Silent) {
        Write-VantaSuccess -Text $message
    }
}
