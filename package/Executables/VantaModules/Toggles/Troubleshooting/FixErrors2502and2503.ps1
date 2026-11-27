# Companion for the FixErrors2502and2503 toggle: resets the permissions of the Windows TEMP
# folder. Show-VantaWindowsTempRepairNote runs first, in the administrator window, to explain
# the repair; Invoke-VantaWindowsTempPermissionsRepair then runs in the silent
# TrustedInstaller broker. Nothing is recorded.

function Show-VantaWindowsTempRepairNote {
    param($Toggle)

    # The repair runs in the silent TrustedInstaller broker, so the explanation is
    # shown here, in the administrator window, before the broker starts.
    if ($Toggle.Silent) {
        throw 'The 2502 and 2503 explanation needs an interactive window.'
    }
    Write-VantaNote -Text @(
        'Installer errors 2502 and 2503 come from wrong permissions on the Windows TEMP folder.'
        'They are not caused by Vanta; this resets those permissions.'
    )
    return 'Run'
}

function Invoke-VantaWindowsTempPermissionsRepair {
    param($Toggle)

    [void]$Toggle
    Import-VantaModule -Name Vanta.Security
    Repair-VantaWindowsTempPermissions
}
