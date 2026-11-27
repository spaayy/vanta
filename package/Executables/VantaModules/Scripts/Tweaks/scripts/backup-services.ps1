# Companion of backup-services.psd1.
$ErrorActionPreference = 'Stop'

Import-VantaModule -Name Vanta.Services
Export-VantaServicesBackup -FilePath (Join-Path -Path ([Environment]::GetFolderPath('Windows')) -ChildPath 'VantaModules\Other\vantaServices.reg')
