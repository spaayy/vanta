# Vanta.Privacy domain: DiagTrack log cleanup during install and the interactive
# NoTelemetry package menu behind the Telemetry Components troubleshooting toggle.

# Z-Vanta-* is what ships; Z-Atlas-* is what older builds installed, which an uninstall must still find.
$script:VantaTelemetryPackagePattern = '*Z-[AV]*-NoTelemetry-Package*'

function Clear-VantaTelemetryLogFiles {
    <#
    .SYNOPSIS
        Removes Vanta's two fixed DiagTrack log-file sets (AutoLogger and
        ShutdownLogger) during an active install. Requires TrustedInstaller and
        refuses reparse points.
    #>
    param(
        # Tests can supply an isolated common application-data root.
        [string]$ProgramDataPath = [Environment]::GetFolderPath('CommonApplicationData')
    )

    Assert-VantaPrivilege -TrustedInstaller
    $context = Get-VantaContext -Refresh
    if (-not $context.IsInstallStateBacked) {
        throw 'Telemetry-log cleanup requires active Vanta install state.'
    }

    if ([string]::IsNullOrWhiteSpace($ProgramDataPath) -or
        -not [IO.Path]::IsPathRooted($ProgramDataPath)) {
        throw 'Windows did not return a rooted common application-data directory.'
    }

    $etlLogsRoot = [IO.Path]::Combine(
        [IO.Path]::GetFullPath($ProgramDataPath),
        'Microsoft\Diagnosis\ETLLogs'
    )
    $logDirectories = @(
        [IO.Path]::Combine($etlLogsRoot, 'AutoLogger')
        [IO.Path]::Combine($etlLogsRoot, 'ShutdownLogger')
    )

    $removed = 0
    foreach ($directoryPath in $logDirectories) {
        if (-not [IO.Directory]::Exists($directoryPath)) {
            continue
        }

        $directory = Get-Item -LiteralPath $directoryPath -Force -ErrorAction Stop
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Telemetry-log directory '$directoryPath' is a reparse point."
        }

        $files = @(Get-ChildItem -LiteralPath $directoryPath `
                -Filter 'DiagTrack*' -File -Force -ErrorAction Stop)
        foreach ($file in $files) {
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Telemetry-log file '$($file.FullName)' is a reparse point."
            }

            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $removed++
        }
    }
    Write-VantaLog -Message "Removed $removed DiagTrack log file(s)."
}

function Get-VantaTelemetryPackageInstalled {
    <#
    .SYNOPSIS
        Reports whether the Vanta NoTelemetry CBS package is present online.
    #>
    try {
        $packages = @(Get-WindowsPackage -Online -ErrorAction Stop |
                Where-Object { $_.PackageName -like $script:VantaTelemetryPackagePattern })
    }
    catch {
        throw "Failed to get packages! $($_.Exception.Message)"
    }
    return $packages.Count -ne 0
}

function Invoke-VantaTelemetryPackageOperation {
    <#
    .SYNOPSIS
        Adds or removes the NoTelemetry package through the fixed package entry
        script under a checked Windows PowerShell child.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Install', 'Uninstall')]
        [string]$Action,

        # The package installer asks about restarting on its own; the Vanta run that
        # owns the console asks instead.
        [switch]$NoInteraction
    )

    $windir = [Environment]::GetFolderPath('Windows')
    $packageInstall = Join-Path -Path $windir -ChildPath 'VantaModules\Scripts\Entry\Install-VantaPackage.ps1'
    if (-not (Test-Path -LiteralPath $packageInstall -PathType Leaf)) {
        throw "Missing package install script '$packageInstall', can't continue."
    }
    $packagePowerShell = Join-Path -Path ([Environment]::GetFolderPath('System')) `
        -ChildPath 'WindowsPowerShell\v1.0\powershell.exe'

    $parameterName = if ($Action -eq 'Install') { '-InstallPackages' } else { '-UninstallPackages' }
    $arguments = @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $packageInstall,
        $parameterName, $script:VantaTelemetryPackagePattern
    )
    if ($NoInteraction) {
        $arguments += '-NoInteraction'
    }
    & $packagePowerShell @arguments
    $packageExitCode = $LASTEXITCODE
    if ($packageExitCode -ne 0) {
        $verb = if ($Action -eq 'Install') { 'installation' } else { 'removal' }
        throw "Package $verb failed with exit code $packageExitCode."
    }
}

function Read-VantaTelemetryPackageChoice {
    <#
    .SYNOPSIS
        Explains the NoTelemetry package and asks whether to add or remove it. The
        currently applied choice is shown as '(current)' and cannot be re-selected.
        Returns 'Add' or 'Remove'.
    #>
    [CmdletBinding()]
    param()

    $telemetryDisabled = Get-VantaTelemetryPackageInstalled
    Write-VantaNote -Text @(
        'The Vanta NoTelemetry package removes some Windows telemetry components.'
        '  - Removing the package restores those components, which can help with'
        '    troubleshooting. If that fixes a problem, please report it to Vanta.'
        '  - Vanta keeps policies that disable telemetry even without the package.'
        '    Those policies do not apply on Windows Home.'
        '  - The package is not needed on Education or Enterprise editions.'
    )
    Write-VantaBlankLine
    $choice = Read-VantaChoice -Question 'What would you like to do?' `
        -Option @('Add the NoTelemetry package', 'Remove the NoTelemetry package') `
        -CurrentIndex $(if ($telemetryDisabled) { 1 } else { 2 })
    if ($choice -eq 1) { return 'Add' }
    return 'Remove'
}

function Set-VantaTelemetryPackageState {
    <#
    .SYNOPSIS
        Adds (Installed) or removes (Removed) the NoTelemetry package without asking
        anything; the caller has already chosen.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Installed', 'Removed')]
        [string]$State,

        [switch]$Silent
    )

    if ($State -ceq 'Installed') {
        if (-not $Silent) {
            Write-VantaStep -Text 'Adding the NoTelemetry package. This can take a few minutes...'
        }
        Invoke-VantaTelemetryPackageOperation -Action Install -NoInteraction:$Silent
        Write-VantaLog -Message 'Added the NoTelemetry package.'
    }
    else {
        if (-not $Silent) {
            Write-VantaStep -Text 'Removing the NoTelemetry package. This can take a few minutes...'
        }
        Invoke-VantaTelemetryPackageOperation -Action Uninstall -NoInteraction:$Silent
        Write-VantaLog -Message 'Removed the NoTelemetry package.'
    }
}
