# Shell refresh phase, in every install mode after pre-install. TrustedInstaller only
# orchestrates: stopping the shell and starting Explorer run as the installing user, in
# that user's Windows session, so other console or remote sessions are never affected.

Assert-VantaPrivilege -TrustedInstaller

$context = Get-VantaContext -Refresh
if (-not $context.IsInstallStateBacked) {
    throw 'Shell refresh requires an active Vanta install state.'
}
$interactiveUserSid = [string]$context.InteractiveUserSid
if ([string]::IsNullOrWhiteSpace($interactiveUserSid)) {
    throw 'Shell refresh requires the install-state user SID.'
}

$scriptsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$shellRefreshScript = Join-Path -Path $scriptsRoot `
    -ChildPath 'Operations\Invoke-VantaUserShellRefresh.ps1'
if (-not [IO.File]::Exists($shellRefreshScript)) {
    throw "The exact-user shell refresh helper is missing at '$shellRefreshScript'."
}

$powerShellPath = [IO.Path]::Combine(
    [Environment]::SystemDirectory,
    'WindowsPowerShell',
    'v1.0',
    'powershell.exe'
)

$arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -ExpectedUserSid "{1}"' -f `
    $shellRefreshScript,
    $interactiveUserSid
$exitCode = Invoke-VantaAsUser -FilePath $powerShellPath -Arguments $arguments `
    -WorkingDirectory ([string]$context.WinDir)
if ($exitCode -ne 0) {
    $failureStage = Get-VantaUserSessionHelperStage -ExitCode $exitCode
    if ($null -eq $failureStage) {
        $failureStage = 'unknown stage'
    }
    throw "Exact-user shell refresh failed during $failureStage (exit code $exitCode)."
}
