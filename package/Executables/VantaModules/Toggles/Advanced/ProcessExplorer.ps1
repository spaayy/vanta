# Companion for the ProcessExplorer toggle: installs Sysinternals Process Explorer in place of
# Task Manager, or uninstalls it. The install and uninstall functions run as Administrator
# when you run a launcher and when an update replays the recorded state.
# Set-VantaProcessExplorerUserPreference runs in your own unelevated process after Enable, and
# is replayed for each new account at first sign-in.

function Get-VantaProcessExplorerHelperPath {
    # ProcessExplorer-Package.ps1 is a function library; each action dot-sources it
    # into its own scope before calling the package operations.
    param($Toggle)

    $helper = Join-Path -Path $Toggle.OperationsPath -ChildPath 'ProcessExplorer-Package.ps1'
    if (-not [IO.File]::Exists($helper)) {
        throw "ProcessExplorer: the package helper is missing at '$helper'."
    }

    return $helper
}

function Install-VantaProcessExplorer {
    param($Toggle)

    . (Get-VantaProcessExplorerHelperPath -Toggle $Toggle)

    # Silent upgrades preserve the current driver state. An earlier explicit disable
    # already persists; package ownership metadata remains available for uninstall.
    $disablePcw = $false
    if (-not $Toggle.Silent) {
        $layout = Get-VantaProcessExplorerLayout
        $pcwStart = Get-VantaProcessExplorerPcwStart -PcwPath $layout.PcwPath
        if ($pcwStart -in @(0, 1)) {
            Write-VantaNote -Text 'The Windows boot driver pcw stays enabled.'
        }
        else {
            Write-VantaNote -Text "The 'pcw' service is used by Task Manager and performance counters; disabling it can make some performance tools misbehave."
            $disablePcw = Read-VantaYesNo -Question 'Disable the pcw service anyway?'
        }
        Write-VantaStep -Text 'Downloading and installing Process Explorer...'
    }

    Install-VantaProcessExplorerPackage -DisablePcw:$disablePcw
}

function Set-VantaProcessExplorerUserPreference {
    param($Toggle)

    . (Get-VantaProcessExplorerHelperPath -Toggle $Toggle)
    Write-VantaProcessExplorerUserPreference
}

function Uninstall-VantaProcessExplorer {
    param($Toggle)

    . (Get-VantaProcessExplorerHelperPath -Toggle $Toggle)

    if (-not $Toggle.Silent) {
        Write-VantaStep -Text 'Uninstalling Process Explorer and restoring Task Manager...'
    }
    Uninstall-VantaProcessExplorerPackage
}
