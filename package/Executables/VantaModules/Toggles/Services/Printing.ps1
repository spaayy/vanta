# Companion for the Printing toggle: turns the printing services, the Windows printing
# features and the Print context menu entries off or on. Set-VantaPrintContextMenu runs first,
# and alone with /justcontext; Set-VantaPrintingMachineState runs after it. Both run as
# Administrator when you run a launcher and when an update replays the recorded state.

function Set-VantaPrintContextMenu {
    param($Toggle)

    $enable = $Toggle.State -ceq 'Enable'
    if ($enable) {
        if ($Toggle.Silent) {
            return
        }
        if (-not (Read-VantaYesNo -Question "Add 'Print' to the file context menu?")) {
            return
        }
    }

    if (-not $Toggle.Silent) {
        if ($enable) {
            Write-VantaStep -Text "Adding 'Print' to the file context menu..."
        }
        else {
            Write-VantaStep -Text "Removing 'Print' from the file context menu..."
        }
    }

    $classesRoot = 'HKLM:\SOFTWARE\Classes'
    $printKeys = @("$classesRoot\SystemFileAssociations\image\shell\print")
    foreach ($fileType in @(
            'batfile', 'cmdfile', 'docxfile', 'fonfile', 'htmlfile', 'inffile', 'inifile',
            'JSEFile', 'otffile', 'pfmfile', 'regfile', 'rtffile', 'ttcfile', 'ttffile',
            'txtfile', 'VBEFile', 'VBSFile', 'WSFFile'
        )) {
        $printKeys += "$classesRoot\$fileType\shell\print"
    }
    foreach ($key in $printKeys) {
        if ($enable) {
            Remove-VantaRegistryValue -Path $key -Name 'ProgrammaticAccessOnly'
        }
        else {
            Set-VantaRegistryValue -Path $key -Name 'ProgrammaticAccessOnly' -Type String -Data ''
        }
    }

    foreach ($key in @(
            "$classesRoot\AppX4ztfk9wxr86nxmzzq47px0nh0e58b8fw\Shell\Print"
            "$classesRoot\AppX4ztfk9wxr86nxmzzq47px0nh0e58b8fw\Shell\PrintTo"
        )) {
        if ($enable) {
            foreach ($valueName in @('LegacyDisable', 'ProgrammaticAccessOnly', 'HideBasedOnVelocityId')) {
                Remove-VantaRegistryValue -Path $key -Name $valueName
            }
        }
        else {
            Set-VantaRegistryValue -Path $key -Name 'LegacyDisable' -Type String -Data ''
            Set-VantaRegistryValue -Path $key -Name 'ProgrammaticAccessOnly' -Type String -Data ''
            Set-VantaRegistryValue -Path $key -Name 'HideBasedOnVelocityId' -Type DWord -Data 6527944
        }
    }
}

function Add-VantaPrintingCapability {
    # These optional tools are downloaded from Windows Update, which can be off or
    # unreachable. Printing already works without them, so a failed add is reported
    # and the state is still recorded; upgrade replay and the service reset carry on.
    param(
        [Parameter(Mandatory = $true)]
        $Toggle,

        [Parameter(Mandatory = $true)]
        [string]$Dism,

        [Parameter(Mandatory = $true)]
        [string]$CapabilityName,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    try {
        Invoke-VantaToggleNativeCommand -FilePath $Dism `
            -ArgumentList ([string[]]@('/Online', '/Add-Capability', "/CapabilityName:$CapabilityName", '/NoRestart')) `
            -AllowedExitCodes ([int[]]@(0, 3010)) | Out-Null
    }
    catch {
        Write-VantaLog -Level Warning -Message "Printing: $CapabilityName could not be added: $($_.Exception.Message)" `
            -ErrorRecord $_ -NoConsole:(-not $Toggle.Silent)
        if (-not $Toggle.Silent) {
            Write-VantaPartial -Text @(
                "Printing is enabled, but $Label couldn't be added. Windows Update may be off or unreachable;"
                'you can add it later from Optional features in Settings.'
            )
        }
    }
}

function Set-VantaPrintingMachineState {
    param($Toggle)

    $enable = $Toggle.State -ceq 'Enable'
    $verb = if ($enable) { 'Enabling' } else { 'Disabling' }

    if (-not $Toggle.Silent) {
        Write-VantaStep -Text "$verb the printing services..."
    }
    Set-VantaServiceStartup -Name 'Spooler' -StartupType $(if ($enable) { 2 } else { 4 })
    Set-VantaServiceStartup -Name 'PrintWorkFlowUserSvc' -StartupType $(if ($enable) { 3 } else { 4 }) -AllowMissing

    Import-VantaModule -Name Vanta.Shell
    $visibility = if ($enable) { 'unhide' } else { 'hide' }
    Set-VantaSettingsPageVisibility -Operation $visibility -Page printers

    if (-not $Toggle.Silent) {
        Write-VantaStep -Text "$verb the Windows printing features. This can take a while..."
    }
    $dism = Join-Path -Path $Toggle.WinDir -ChildPath 'System32\dism.exe'
    $featureOperation = if ($enable) { '/Enable-Feature' } else { '/Disable-Feature' }
    foreach ($feature in @(
            'Printing-Foundation-Features'
            'Printing-Foundation-InternetPrinting-Client'
            'Printing-XPSServices-Features'
            'Printing-PrintToPDFServices-Features'
        )) {
        Invoke-VantaToggleNativeCommand -FilePath $dism `
            -ArgumentList ([string[]]@('/Online', $featureOperation, "/FeatureName:$feature", '/NoRestart')) `
            -AllowedExitCodes ([int[]]@(0, 3010)) | Out-Null
    }

    if (-not $enable) {
        return
    }

    if (-not $Toggle.Silent) {
        Write-VantaStep -Text 'Adding the Print Management console. This can take a while...'
    }
    Add-VantaPrintingCapability -Toggle $Toggle -Dism $dism `
        -CapabilityName 'Print.Management.Console~~~~0.0.1.0' -Label 'the Print Management console'

    if (-not $Toggle.Silent -and (Read-VantaYesNo -Question 'Also add Windows Fax and Scan?')) {
        Write-VantaStep -Text 'Adding Windows Fax and Scan...'
        Add-VantaPrintingCapability -Toggle $Toggle -Dism $dism `
            -CapabilityName 'Print.Fax.Scan~~~~0.0.1.0' -Label 'Windows Fax and Scan'
    }
}
