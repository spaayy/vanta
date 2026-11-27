#Requires -RunAsAdministrator

# Adapted from online-sxs by he3als (GPL-3.0-only).
#
# Interactive shell around the Vanta.Software CBS package engine
# (Install-VantaCbsPackage / Uninstall-VantaCbsPackage). This script stays at this
# exact path because toggles start it: Vanta.Security's Set-VantaDefenderState (through
# Invoke-VantaDefenderPackageInstaller) and Vanta.Privacy's Set-VantaTelemetryPackageState
# (through Invoke-VantaTelemetryPackageOperation). Install phases call the module
# functions directly instead.

param (
	[array]$InstallPackages,
	[array]$UninstallPackages,
	[string]$PackagesPath = "$([Environment]::GetFolderPath('Windows'))\VantaModules\Packages",
	[switch]$NoInteraction
)

$scriptsRoot = [IO.Path]::GetFullPath([IO.Path]::GetDirectoryName($PSScriptRoot))
$bootstrap = [IO.Path]::Combine($scriptsRoot, 'Initialize-VantaPowerShell.ps1')
if (-not [IO.File]::Exists($bootstrap)) { throw "The PowerShell bootstrap is missing at '$bootstrap'." }
. $bootstrap

Set-StrictMode -Version 3.0

if (!([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18')) {
	throw 'This script must be run as TrustedInstaller or SYSTEM.'
}

$windir = [Environment]::GetFolderPath('Windows')
$modulesRoot = Join-Path -Path $scriptsRoot -ChildPath 'Modules'
$cbsRetryScript = Join-Path -Path $scriptsRoot -ChildPath 'Operations\CbsRetry.ps1'
if (!(Test-Path -LiteralPath $cbsRetryScript -PathType Leaf)) {
	throw "Required CBS retry helper '$cbsRetryScript' is missing."
}
$helperItem = Get-Item -LiteralPath $cbsRetryScript -Force -ErrorAction Stop
if (($helperItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
	throw "Required CBS retry helper '$cbsRetryScript' is a reparse point."
}
. $cbsRetryScript -LibraryOnly

Import-Module -Name (Join-Path $modulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force -ErrorAction Stop
Import-Module -Name (Join-Path $modulesRoot 'Vanta.Software\Vanta.Software.psd1') -Force -ErrorAction Stop
$sys32 = [Environment]::GetFolderPath('System')
$env:path = "$windir;$sys32;$sys32\Wbem;$sys32\WindowsPowerShell\v1.0;" + $env:path
$script:errorLevel = 0
$script:warningLevel = 0
$script:retryPackages = @()
$literalPackages = $null

function Restart {
	shutdown /f /r /t 0 *>$null
	Start-Sleep 2
	Restart-Computer
	Start-Sleep 2
	Write-VantaFailure -Text 'Windows did not restart automatically. Restart it yourself to finish.'
	if (!$NoInteraction) { Wait-VantaExit }
	exit 9000
}

function Finish($failedPackages) {
	$failedPackages = @($failedPackages | Where-Object { $_ })

	Write-Host ''
	if ($failedPackages.Count -gt 0) {
		Write-VantaPartial -Text "$($failedPackages.Count) package(s) failed to install:"
		Write-VantaNote -Text ([string[]]@($failedPackages | ForEach-Object { "  - $_" }))

		function NoRestart {
			Write-VantaRestartNotice -Kind Required
			Write-VantaNote -Text 'Packages that did install apply after the next restart.'
			if (!$NoInteraction) { Wait-VantaExit }
		}

		if (@($script:retryPackages).Count -eq 0) {
			Write-VantaNote -Text 'The failed packages are not eligible for a Safe Mode retry.'
			NoRestart
			exit $script:errorLevel
		}
		if ($NoInteraction) {
			NoRestart
			exit $script:errorLevel
		}
		if (Read-VantaYesNo -Question 'Arm a Safe Mode retry for the failed packages and restart now?') {
			$retryPaths = @($script:retryPackages | ForEach-Object { [string]$_.Path })
			[void](Enable-VantaCbsRetry -Packages $retryPaths)
			Write-VantaNextStep -Text "Safe Mode retry armed. $(Get-VantaCbsRetryInstruction)"
			# The retry is armed already, so there's nothing to cancel; this only gives
			# the user time to note the command before Windows restarts into Safe Mode.
			Wait-VantaContinue -Message 'Press Enter to restart Windows.'
			Write-VantaStep -Text 'Restarting Windows...'
			Restart
		} else {
			NoRestart
		}

		exit $script:errorLevel
	}

	if ($script:warningLevel -gt 0) {
		Write-VantaPartial -Text "The package change completed with $script:warningLevel warning(s); see above."
	} else {
		Write-VantaSuccess -Text 'The package change completed.'
	}
	if ($NoInteraction) { exit $script:errorLevel }
	Write-VantaRestartNotice -Kind Required
	if (Read-VantaYesNo -Question 'Restart Windows now?') {
		Write-VantaStep -Text 'Restarting Windows...'
		Restart
	} else {
		Wait-VantaExit
		exit $script:errorLevel
	}
}

if ($UninstallPackages) {
	$uninstallResult = Uninstall-VantaCbsPackage -Packages $UninstallPackages
	$script:errorLevel += @($uninstallResult.FailedPackages).Count
	if ((@($uninstallResult.RemovedPackages).Count + @($uninstallResult.FailedPackages).Count) -eq 0) {
		$script:warningLevel++
	} elseif (@($uninstallResult.UnmatchedPatterns).Count -gt 0) {
		$script:warningLevel++
	}

	if (!$InstallPackages) {
		Finish
	}
}

if (!$InstallPackages -and !$literalPackages) {
	Write-VantaTitle -Text 'Install CBS package' -Explanation 'Installs the CBS packages you choose online, into the running Windows installation.'
	Wait-VantaContinue

	Write-VantaStep -Text 'Opening the file dialog to choose CBS package files...'
	Add-Type -AssemblyName System.Windows.Forms
	$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
	$openFileDialog.Multiselect = $true
	$openFileDialog.Filter = "CBS Package Files (*.cab)|*.cab"
	$openFileDialog.Title = "Select a CBS Package File"
	if ($openFileDialog.ShowDialog() -ne 'OK') {
		exit
	}
	$literalPackages = @($openFileDialog.FileNames)
}

try {
	if ($literalPackages) {
		$installResult = Install-VantaCbsPackage -Packages $literalPackages -LiteralPaths -NonInteractive:$NoInteraction
	} else {
		$installResult = Install-VantaCbsPackage -Packages $InstallPackages -PackagesPath $PackagesPath -NonInteractive:$NoInteraction
	}
} catch {
	# Zero CABs matched, or a NoInteraction failure after the module armed a retry.
	Write-VantaFailure -Text $_.Exception.Message
	$script:errorLevel++
	if (!$NoInteraction) { Wait-VantaExit }
	exit $script:errorLevel
}

$script:errorLevel += @($installResult.FailedPackages).Count
$script:warningLevel += @($installResult.UnmatchedPatterns).Count
$script:retryPackages = @($installResult.RetryPackages)

Finish $installResult.FailedPackages
