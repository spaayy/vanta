@{
    Name        = 'Configure OEM Information'
    Description = 'Sets the OEM information in Settings to show the Vanta version.'
    Registry    = @(
        @{ Path = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation'; Name = 'Manufacturer'; Type = 'String'; Data = 'Vanta' }
    )
    # Fills in the dynamic values (Vanta version/model) that cannot be expressed declaratively.
    Script      = 'config-oem-information.ps1'
}
