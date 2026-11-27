<#
.SYNOPSIS
    Restores Vanta service defaults through the typed TrustedInstaller broker.
.DESCRIPTION
    The broker always applies the closed Vanta service-default plan first. An optional
    fixed Windows or Vanta snapshot is imported afterwards. No command text, path or
    caller-authored registry data reaches the TrustedInstaller process.

    Interactive runs present themselves through the Vanta.Core console vocabulary and
    own the single exit pause; -Silent keeps the one-line output its callers capture.
#>
[CmdletBinding()]
param(
    [switch]$Silent,

    [ValidateSet('ToggleDefaults', 'WindowsBackup', 'VantaBackup')]
    [string]$RestoreSource = 'ToggleDefaults',

    [switch]$NoRestartPrompt
)

$scriptsRoot = [IO.Path]::GetFullPath([IO.Path]::GetDirectoryName($PSScriptRoot))
$bootstrap = [IO.Path]::Combine($scriptsRoot, 'Initialize-VantaPowerShell.ps1')
if (-not [IO.File]::Exists($bootstrap)) { throw "The PowerShell bootstrap is missing at '$bootstrap'." }
. $bootstrap

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$scriptsRoot = Split-Path -Parent $PSScriptRoot
$coreManifest = Join-Path -Path $scriptsRoot -ChildPath 'Modules\Vanta.Core\Vanta.Core.psd1'
Import-Module -Name $coreManifest -Force -ErrorAction Stop

$title = 'Set services to defaults'
$completionText = 'Vanta service defaults were restored. A restart is required to apply every change.'

if (-not $Silent) {
    Set-VantaLogConsoleStyle -Style Interactive
    Write-VantaTitle -Text $title -Explanation @(
        'Restores the service configuration exposed in the Vanta folder. It can repair'
        'features broken by disabled services.'
    )

    if (-not (Read-VantaYesNo -Question 'Restore the Vanta service defaults now?')) {
        Write-VantaNote -Text 'Nothing was changed.'
        Wait-VantaExit
        return
    }

    if (-not $PSBoundParameters.ContainsKey('RestoreSource')) {
        $windowsRoot = [Environment]::GetFolderPath('Windows')
        $otherRoot = Join-Path -Path $windowsRoot -ChildPath 'VantaModules\Other'
        $windowsSnapshot = Join-Path -Path $otherRoot -ChildPath 'winServices.reg'
        $vantaSnapshot = Join-Path -Path $otherRoot -ChildPath 'vantaServices.reg'
        if ((Test-Path -LiteralPath $windowsSnapshot -PathType Leaf) -and
            (Test-Path -LiteralPath $vantaSnapshot -PathType Leaf)) {
            $snapshotChoice = Read-VantaChoice `
                -Question 'Also apply a fixed service snapshot after the defaults?' `
                -Option @(
                    'The Windows service snapshot'
                    'The Vanta service snapshot'
                    'No snapshot, only the Vanta defaults'
                ) `
                -DefaultIndex 3
            $RestoreSource = @('WindowsBackup', 'VantaBackup', 'ToggleDefaults')[$snapshotChoice - 1]
        }
    }
}

$detailsPath = $null
try {
    if (-not (Test-VantaAdmin)) {
        $context = Get-VantaContext
        $powershellPath = Join-Path $context.WinDir 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $argumentString = ConvertTo-VantaWindowsArgumentString -ArgumentList @(
            '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', $PSCommandPath,
            '-Silent', '-NoRestartPrompt', '-RestoreSource', $RestoreSource
        )
        if (-not $Silent) {
            Write-VantaStep -Text 'Asking for administrator permission...'
        }
        try {
            # Process.Start, not Start-Process: in Windows PowerShell 5.1 Start-Process hides
            # a declined prompt's Win32Exception behind an InvalidOperationException.
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $powershellPath
            $startInfo.Arguments = $argumentString
            $startInfo.WorkingDirectory = [Environment]::GetFolderPath('System')
            $startInfo.UseShellExecute = $true
            $startInfo.Verb = 'runas'
            $elevatedProcess = [Diagnostics.Process]::Start($startInfo)
            $elevatedProcess.WaitForExit()
        }
        catch [Management.Automation.MethodInvocationException] {
            $cause = $_.Exception.InnerException
            if ($cause -is [ComponentModel.Win32Exception] -and $cause.NativeErrorCode -eq 1223) {
                throw 'The administrator permission prompt was cancelled, so nothing was changed.'
            }
            throw
        }
        if ($elevatedProcess.ExitCode -ne 0) {
            # The elevated run logged its reason to the machine log, not this user's.
            $detailsPath = Join-Path -Path $context.LogsPath -ChildPath 'install\vanta-install.log'
            throw "The elevated service reset exited with code $($elevatedProcess.ExitCode)."
        }
    }
    else {
        if (-not $Silent) {
            Write-VantaStep -Text 'Restoring the Vanta service defaults...'
        }
        Invoke-VantaTrustedInstaller `
            -Operation ResetServices `
            -RestoreSource $RestoreSource | Out-Null
    }
}
catch {
    # Log before a -Silent rethrow too: that run is often the elevated half of an
    # interactive one, whose window closes as soon as it exits.
    Write-VantaLog -Level Error -Message "Resetting services failed: $($_.Exception.Message)" -ErrorRecord $_ -NoConsole:(-not $Silent)
    if ($Silent) {
        throw
    }
    if ($null -eq $detailsPath) { $detailsPath = Get-VantaInstallLogPath }
    Write-VantaNotApplied -Title $title -Reason $_.Exception.Message -DetailsPath $detailsPath
    Wait-VantaExit
    exit 1
}

if ($Silent) {
    Write-Output $completionText
    return
}

Write-VantaCompletion -Title $title
if (-not $NoRestartPrompt) {
    Write-VantaRestartNotice -Kind Required
    if (Read-VantaYesNo -Question 'Restart Windows now?') {
        $windowsRoot = [Environment]::GetFolderPath('Windows')
        $shutdown = Join-Path -Path $windowsRoot -ChildPath 'System32\shutdown.exe'
        Write-VantaStep -Text 'Restarting Windows...'
        & $shutdown /r /t 0
        if ($LASTEXITCODE -ne 0) {
            throw "shutdown.exe failed with exit code $LASTEXITCODE."
        }
    }
}
Wait-VantaExit
