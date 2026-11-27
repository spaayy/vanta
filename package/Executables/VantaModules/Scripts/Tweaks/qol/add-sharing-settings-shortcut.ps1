# Companion of add-sharing-settings-shortcut.psd1: creates the 'Sharing Settings'
# shortcut in the Vanta File Sharing folder.
$ErrorActionPreference = 'Stop'

Import-VantaModule -Name Vanta.Shortcuts

$destination = Join-Path -Path ([Environment]::GetFolderPath('Windows')) -ChildPath 'VantaDesktop\3. General Configuration\File Sharing\Sharing Settings.lnk'
$controlPanel = Join-Path -Path ([Environment]::GetFolderPath('System')) -ChildPath 'control.exe'
New-VantaShortcut -Source $controlPanel -Destination $destination -Arguments '/name Microsoft.NetworkAndSharingCenter /page Advanced'
