[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedUserSid
)

$ErrorActionPreference = 'Stop'

$windowsRoot = [Environment]::GetFolderPath('Windows')
Import-Module -Name (Join-Path -Path $windowsRoot -ChildPath 'VantaModules\Scripts\Modules\Vanta.Shell\Vanta.Shell.psd1') -ErrorAction Stop

Set-VantaFileAssociations -ExpectedUserSid $ExpectedUserSid
