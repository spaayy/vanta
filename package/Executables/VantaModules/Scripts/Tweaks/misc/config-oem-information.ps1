# Companion of config-oem-information.psd1: the logic lives in
# VantaModules\Scripts\Install\Tasks\Set-OemInformation.ps1 because the build stamps the
# Vanta version into that file.
$ErrorActionPreference = 'Stop'

& (Join-Path -Path ([Environment]::GetFolderPath('Windows')) -ChildPath 'VantaModules\Scripts\Install\Tasks\Set-OemInformation.ps1')
