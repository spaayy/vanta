[CmdletBinding()]
param()

$scriptsRoot = [IO.Path]::GetFullPath([IO.Path]::GetDirectoryName($PSScriptRoot))
$bootstrap = [IO.Path]::Combine($scriptsRoot, 'Initialize-VantaPowerShell.ps1')
if (-not [IO.File]::Exists($bootstrap)) { throw "The PowerShell bootstrap is missing at '$bootstrap'." }
. $bootstrap

$ErrorActionPreference = 'Stop'

try {
    $scriptsRoot = [IO.Path]::GetDirectoryName($PSScriptRoot)
    $downloadManifest = [IO.Path]::Combine($scriptsRoot, 'Modules', 'Vanta.Download', 'Vanta.Download.psd1')
    if (-not [IO.File]::Exists($downloadManifest)) {
        throw "The Vanta download module manifest is missing at '$downloadManifest'."
    }
    Import-Module -Name $downloadManifest -Force -ErrorAction Stop

    $wingetPath = Get-VantaTrustedWingetPath
    Assert-VantaTrustedWingetSource -WingetPath $wingetPath -Name winget
    & $wingetPath show --exact --id 'Microsoft.VisualStudioCode' --source winget --accept-source-agreements --disable-interactivity *> $null
    if ($LASTEXITCODE -ne 0) {
        exit 1
    }
    exit 0
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
