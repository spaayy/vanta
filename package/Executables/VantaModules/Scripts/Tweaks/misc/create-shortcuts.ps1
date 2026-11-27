# Companion of create-shortcuts.psd1.
$ErrorActionPreference = 'Stop'
& (Join-Path -Path ([Environment]::GetFolderPath('Windows')) -ChildPath 'VantaModules\Scripts\Operations\New-VantaShortcutSet.ps1')
