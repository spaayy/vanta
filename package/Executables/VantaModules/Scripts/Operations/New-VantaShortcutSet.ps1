<#
.SYNOPSIS
    Creates the services restore shortcut (no Vanta/Vanta folder shortcut goes on the Desktop or Start menu).
.DESCRIPTION
    Links "Set services to defaults" into the Services folder of the VantaDesktop folder.

    The install's 'Create Shortcuts' tweak runs it with the call operator as
    TrustedInstaller. It throws on failure.
#>
$windir = [Environment]::GetFolderPath('Windows')
. (Join-Path -Path $windir -ChildPath 'VantaModules\Scripts\Initialize-VantaPowerShell.ps1')

Write-VantaStep -Text 'Creating the services restore shortcut...'
$desktop = "$windir\VantaDesktop"
New-VantaShortcut -Source "$desktop\9. Troubleshooting\Set services to defaults.cmd" -Destination "$desktop\6. Advanced Configuration\Services\Set services to defaults.lnk"
