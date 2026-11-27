# Companion for the Widgets toggle: lifts the Widgets policies and installs the Widgets app
# for Enable. Enable-VantaWidgetsMachine runs as Administrator when you run Enable and when an
# update replays the recorded state. Install-VantaWidgetsUser runs in your own unelevated
# process afterwards, and is replayed for each new account at first sign-in.

function Enable-VantaWidgetsMachine {
    param($Toggle)

    # The policy values are removed only after the interactive Edge/WebView step
    # succeeds, so a declined Edge install leaves Widgets disabled.
    if (-not $Toggle.Silent) {
        $programFilesX86 = [Environment]::GetFolderPath(
            [Environment+SpecialFolder]::ProgramFilesX86
        )
        if ([string]::IsNullOrWhiteSpace($programFilesX86) -or
            -not [IO.Directory]::Exists($programFilesX86)) {
            throw 'Widgets: the 32-bit Program Files directory is unavailable.'
        }

        $edgePath = [IO.Path]::Combine(
            $programFilesX86,
            'Microsoft\Edge\Application\msedge.exe'
        )
        $installEdge = -not (Test-Path -LiteralPath $edgePath -PathType Leaf)

        if ($installEdge) {
            Write-VantaNote -Text 'Widgets needs Microsoft Edge, which is not installed.'
            if (-not (Read-VantaYesNo -Question 'Install Microsoft Edge now?')) {
                throw 'Microsoft Edge is not installed and its installation was declined.'
            }
        }

        $edgeHelper = Join-Path -Path $Toggle.OperationsPath -ChildPath 'Remove-Edge.ps1'
        if (-not [IO.File]::Exists($edgeHelper)) {
            throw "Widgets: the Edge helper is missing at '$edgeHelper'."
        }

        $windowsPowerShell = [IO.Path]::Combine(
            $Toggle.WinDir,
            'System32\WindowsPowerShell\v1.0\powershell.exe'
        )
        if (-not [IO.File]::Exists($windowsPowerShell)) {
            throw "Widgets: Windows PowerShell is missing at '$windowsPowerShell'."
        }

        [string[]]$edgeArguments = @(
            '-NoLogo',
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', $edgeHelper,
            '-NonInteractive',
            '-InstallWebView'
        )
        if ($installEdge) {
            $edgeArguments += '-InstallEdge'
            Write-VantaStep -Text 'Installing Microsoft Edge and the Edge WebView2 runtime. This can take a few minutes...'
        }
        else {
            Write-VantaStep -Text 'Updating the Edge WebView2 runtime. This can take a few minutes...'
        }
        [void](Invoke-VantaToggleNativeCommand `
                -FilePath $windowsPowerShell `
                -ArgumentList $edgeArguments `
                -AllowedExitCodes ([int[]]@(0)))

        Write-VantaStep -Text 'Enabling the Widgets policies...'
    }

    Set-VantaMachineDwordPolicy -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Data 1
    foreach ($valueName in 'DisableWidgetsOnLockScreen', 'DisableWidgetsBoard') {
        Remove-VantaRegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name $valueName -AllowOsProtected
    }
}

function Install-VantaWidgetsUser {
    param($Toggle)

    # The board and its news feed are separate apps. Restoring only WebExperience
    # leaves the board reporting that the feed provider was uninstalled.
    $packages = @(
        @{ Name = 'MicrosoftWindows.Client.WebExperience'; ProductId = '9MSSGKG348SP'; Label = 'Windows Web Experience Pack' }
        @{ Name = 'Microsoft.StartExperiencesApp'; ProductId = '9PC1H9VN18CM'; Label = 'Start Experiences App' }
    )
    $wingetPath = $null
    foreach ($package in $packages) {
        if (@(Get-AppxPackage -Name $package.Name -ErrorAction Stop | Where-Object { [string]$_.Status -eq 'Ok' }).Count -eq 0) {
            if (-not $wingetPath) {
                Import-VantaModule -Name Vanta.Download
                $wingetPath = Get-VantaTrustedWingetPath
                Assert-VantaTrustedWingetSource -WingetPath $wingetPath -Name msstore
            }
            if (-not $Toggle.Silent) {
                Write-VantaStep -Text "Installing the $($package.Label) from the Microsoft Store..."
            }
            [void](Invoke-VantaToggleNativeCommand -FilePath $wingetPath -ArgumentList ([string[]]@(
                        'install', '--exact', '--id', $package.ProductId, '--source', 'msstore',
                        '--silent', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity'
                    )) -AllowedExitCodes ([int[]]@(0)))
        }
        if (@(Get-AppxPackage -Name $package.Name -ErrorAction Stop | Where-Object { [string]$_.Status -eq 'Ok' }).Count -eq 0) {
            throw "$($package.Label) is not healthy for this user after installation."
        }
    }
    if (-not $Toggle.Silent) {
        Write-VantaSuccess -Text 'The Widgets board and its news feed app are installed for your account.'
        Write-VantaStep -Text 'Opening Settings > Personalization > Taskbar...'
        Start-Process 'ms-settings:taskbar' -ErrorAction Stop
        Write-VantaNextStep -Text 'Turn on Widgets in the Taskbar settings that just opened. The button can take a few minutes to appear.'
    }
}
