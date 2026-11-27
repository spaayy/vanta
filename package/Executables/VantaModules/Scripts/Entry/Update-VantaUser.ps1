<#
.SYNOPSIS
    Applies upgraded user settings without resetting the user's desktop layout.
#>
[CmdletBinding()]
param([string]$ExpectedUserSid)

$scriptsRoot = [IO.Path]::GetFullPath([IO.Path]::GetDirectoryName($PSScriptRoot))
$bootstrap = [IO.Path]::Combine($scriptsRoot, 'Initialize-VantaPowerShell.ps1')
if (-not [IO.File]::Exists($bootstrap)) { throw "The PowerShell bootstrap is missing at '$bootstrap'." }
. $bootstrap
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$actualSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
# The install that last changed Vanta stamped this account (Set-VantaUpgradeUserStamp).
$eligible = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Vanta\UpgradeUsers' -Name $actualSid -ErrorAction SilentlyContinue
if (-not $ExpectedUserSid -and $null -eq $eligible) { return }
if ($ExpectedUserSid -and $actualSid -cne $ExpectedUserSid) { throw 'Upgrade user token does not match the installing user.' }
foreach ($module in 'Vanta.Core', 'Vanta.Registry', 'Vanta.Tweaks', 'Vanta.Toggles') {
    Import-Module (Join-Path $scriptsRoot "Modules\$module\$module.psd1") -ErrorAction Stop
}
if ((Test-VantaSystem) -or (Test-VantaAdmin)) { throw 'User upgrade requires the affected non-elevated user.' }
$context = Get-VantaContext -Refresh
$context.IsUpgrade = $true
$version = if ($context.IsInstallStateBacked) { [string]$context.TargetVersion } else { [string]$context.InstalledVersion }
if ([string]::IsNullOrWhiteSpace($version)) { throw 'Installed version is unavailable for user migration.' }
# An account runs once for each stamp: an update's is its version, and a reinstall of
# the same version adds its transaction. The installing user's own pass records the
# stamp as well, so its next sign-in doesn't run again.
$stamp = $version
if ($null -ne $eligible -and $eligible.$actualSid -is [string] -and -not [string]::IsNullOrWhiteSpace($eligible.$actualSid)) {
    $stamp = [string]$eligible.$actualSid
}
$markerPath = 'HKCU:\SOFTWARE\Vanta\UserSetup'
$markerName = 'UpgradeVersion'
$completed = Get-ItemProperty -LiteralPath $markerPath -Name $markerName -ErrorAction SilentlyContinue
if (-not $ExpectedUserSid -and $null -ne $completed -and $completed.$markerName -ceq $stamp) { return }
$logRoot = Join-Path $env:LOCALAPPDATA 'Vanta\Logs'
$null = New-Item -Path $logRoot -ItemType Directory -Force
Start-Transcript -Path (Join-Path $logRoot ('{0:yyyyMMdd-HHmmss}-upgrade-user-{1}.log' -f (Get-Date), $PID)) | Out-Null
try {
    $null = Initialize-VantaRegistryIdentityContext -CurrentToken -ExpectedUserSid $actualSid
    # Each Tweaks/<category> install step already applied the installing user's HKCU
    # entries, protected policy roots included. This pass is for other accounts
    # migrating at their next logon, under their own token, for every category in the
    # manifest Invoke-VantaTweakCategory reads.
    if (-not $ExpectedUserSid) {
        $manifest = Get-VantaTweakManifest -Path (Join-Path $context.VantaModulesPath 'Scripts\Tweaks\tweaks.manifest.psd1')
        foreach ($category in @($manifest['Categories'] | ForEach-Object { [string]$_['Name'] })) {
            Invoke-VantaTweakCategory -Name $category -RegistryScope CurrentUser -RegistryOnly -Context $context
        }
    }
    # As in Initialize-NewUser: a choice whose user part fails stays recorded and shows
    # in the health check, without failing the upgrade after its machine work.
    try { Invoke-VantaToggleUserReapply }
    catch { Write-Warning "Some recorded choices were not applied for this user: $($_.Exception.Message)" }
    # New-Item -Force would recreate an existing key empty, losing Initialize-NewUser's markers.
    if (-not (Test-Path -LiteralPath $markerPath)) { $null = New-Item -Path $markerPath -Force }
    New-ItemProperty -LiteralPath $markerPath -Name $markerName -Value $stamp -PropertyType String -Force | Out-Null
}
finally { Stop-Transcript | Out-Null }
