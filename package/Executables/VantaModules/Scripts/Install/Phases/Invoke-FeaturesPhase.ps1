# Features phase.
# Windows optional-feature work via DISM: enable DirectPlay, remove the Steps Recorder
# capability (fresh installs only), clean the component store while that is safe (a
# failure there only warns), and keep the Vanta packages' repair source. Runs as
# TrustedInstaller and requires online component sources.
Assert-VantaPrivilege -TrustedInstaller

$context = Get-VantaContext
$dism = Join-Path -Path $context.WinDir -ChildPath 'System32\dism.exe'

function Get-VantaDismExitDisposition {
    param(
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [int[]]$DeferredExitCode = @()
    )

    if ($ExitCode -eq 0 -or $ExitCode -eq 3010) {
        return 'Success'
    }
    if ($DeferredExitCode -contains $ExitCode) {
        return 'Deferred'
    }
    return 'Failure'
}

function Get-VantaDismOutputDetail {
    # What DISM said, without its banner and progress bars: the bars differ on every
    # run, so the same failure would never read the same twice.
    param([object[]]$Output = @())

    $lines = foreach ($line in @($Output)) {
        $text = ([string]$line).Trim()
        if ($text -eq '' -or $text -match '^\[[=\s\d.%]*\]$' -or
            $text -match '^(Deployment Image Servicing and Management tool|Version:|Image Version:)') { continue }
        $text
    }
    return (@($lines) -join ' ')
}

function Invoke-VantaDism {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Description,
        [int[]]$DeferredExitCode = @(),
        # Work the install can do without: a failure is a warning instead of a stop.
        [switch]$Optional
    )

    Write-VantaLog -Message "DISM: $Description"
    $output = & $dism @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $disposition = Get-VantaDismExitDisposition `
        -ExitCode $exitCode -DeferredExitCode $DeferredExitCode
    if ($disposition -ceq 'Deferred') {
        Write-VantaLog -Level Warning -Message (
            "DISM '$Description' was deferred because Windows has pending operations " +
            "(exit code $exitCode). Component cleanup can complete after reboot."
        )
        return
    }
    if ($disposition -ceq 'Failure') {
        $detail = Get-VantaDismOutputDetail -Output $output
        if ($Optional) {
            Write-VantaLog -Level Warning -Message "DISM '$Description' failed with exit code $exitCode; continuing without it. $detail"
            return
        }
        throw "DISM '$Description' failed with exit code $exitCode. $detail"
    }
}

function Remove-VantaStepsRecorder {
    # Enumerate instead of querying a hard-coded name: Windows can remove the
    # capability from its catalog altogether, making that name an error (87).
    $capabilities = @(Dism\Get-WindowsCapability -Online -ErrorAction Stop | Where-Object {
        $_.Name -like 'App.StepsRecorder~~~~*'
    })
    if ($capabilities.Count -eq 0) {
        Write-VantaLog -Message 'Steps Recorder is not listed as a Windows capability; skipping removal.'
        return
    }
    foreach ($capability in $capabilities) {
        if ([string]$capability.State -eq 'NotPresent') {
            Write-VantaLog -Message "Steps Recorder capability '$($capability.Name)' is already absent; skipping removal."
            continue
        }
        if ([string]$capability.State -ne 'Installed') {
            throw "Steps Recorder capability '$($capability.Name)' has unexpected state '$($capability.State)'. Complete pending Windows servicing and restart before retrying."
        }
        Invoke-VantaDism -Description 'Removing the Steps Recorder capability' -Arguments @(
            '/Online', '/Remove-Capability', "/CapabilityName:$($capability.Name)", '/NoRestart'
        )
    }
}

function Enable-VantaDirectPlay {
    $feature = Dism\Get-WindowsOptionalFeature -Online -FeatureName DirectPlay -ErrorAction Stop
    if ([string]$feature.State -eq 'Enabled') {
        Write-VantaLog -Message 'DirectPlay is already enabled; skipping change.'
        return
    }
    Invoke-VantaDism -Description 'Enabling DirectPlay' -Arguments @(
        '/Online', '/Enable-Feature', '/FeatureName:DirectPlay', '/NoRestart', '/All'
    )
}

Enable-VantaDirectPlay

# A Rebase repeats it: a rebuilt Windows brings Steps Recorder back.
if (-not $context.IsUpgrade -or $context.IsRebase) {
    Remove-VantaStepsRecorder
}

$scriptsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $scriptsRoot 'Preparation\WindowsTransition.ps1')
Import-Module -Name (Join-Path $scriptsRoot 'Modules\Vanta.Software\Vanta.Software.psd1') -Force -ErrorAction Stop
$vantaPackages = @(Get-VantaInstalledVantaPackage)

# A fresh install cleans the store here, before the Components phase installs the
# Vanta packages. It must never run after them: see Get-VantaComponentCleanupBlocker.
# The cleanup only frees space, and Windows can refuse it on PCs whose servicing has
# been changed, so a failure is a warning and the install carries on.
$cleanupBlocker = Get-VantaComponentCleanupBlocker -IsUpgrade ([bool]$context.IsUpgrade) -VantaPackages $vantaPackages
if ($cleanupBlocker) {
    Write-VantaLog -Message "Skipped cleaning the component store: $cleanupBlocker."
}
else {
    Invoke-VantaDism -Description 'Cleaning the component store' -Arguments @(
        '/Online', '/Cleanup-Image', '/StartComponentCleanup'
    ) -DeferredExitCode @(-2146498554) -Optional # 0x800f0806: pending operations
}

Write-VantaLog -Message "Vanta packages' repair source: $(Update-VantaCbsRepairSource -VantaPackages $vantaPackages)."
