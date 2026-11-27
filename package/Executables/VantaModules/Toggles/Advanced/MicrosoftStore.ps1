# Companion for the MicrosoftStore toggle: removes Microsoft Store for every user, or
# registers it again for one account. Remove-VantaMicrosoftStore runs as Administrator when
# you run Disable and when an update replays the recorded state. Register-VantaMicrosoftStore
# runs in your own unelevated process when you run Enable, and is replayed for each new
# account at first sign-in.

function Remove-VantaMicrosoftStore {
    param($Toggle)

    if (-not $Toggle.Silent) {
        Write-VantaStep -Text 'Removing Microsoft Store for all users...'
    }
    $packages = @(Get-AppxPackage -AllUsers Microsoft.WindowsStore -ErrorAction Stop)
    foreach ($package in $packages) {
        $package | Remove-AppxPackage -AllUsers -ErrorAction Stop
    }

    if (-not $Toggle.Silent) {
        Write-VantaNote -Text 'Enable Microsoft Store restores it for your account and may download it again.'
    }
}

function Register-VantaMicrosoftStore {
    param($Toggle)

    $packages = @(Get-AppxPackage -Name Microsoft.WindowsStore -ErrorAction Stop | Where-Object { [string]$_.Status -eq 'Ok' })
    if ($packages.Count -eq 0) {
        try {
            # Windows resolves the staged family, including a package not registered
            # to any current user. Never register into an alternate administrator.
            Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.WindowsStore_8wekyb3d8bbwe' -ErrorAction Stop
        }
        catch {
            if (-not $Toggle.Silent) {
                Write-VantaStep -Text 'Microsoft Store is not available on this PC. Downloading it from Microsoft...'
            }
            Import-VantaModule -Name Vanta.Download
            $wingetPath = Get-VantaTrustedWingetPath
            Assert-VantaTrustedWingetSource -WingetPath $wingetPath -Name msstore
            [void](Invoke-VantaToggleNativeCommand -FilePath $wingetPath `
                    -ArgumentList ([string[]]@(
                            'install', '--exact', '--id', '9WZDNCRFJBMP', '--source', 'msstore',
                            '--silent', '--accept-source-agreements', '--accept-package-agreements',
                            '--disable-interactivity'
                        )) `
                    -AllowedExitCodes ([int[]]@(0)))
        }
    }
    if (@(Get-AppxPackage -Name Microsoft.WindowsStore -ErrorAction Stop | Where-Object { [string]$_.Status -eq 'Ok' }).Count -eq 0) {
        throw 'Microsoft Store registration did not produce a healthy package for this user.'
    }

    if (-not $Toggle.Silent) {
        Write-VantaSuccess -Text 'Microsoft Store is registered for your account.'
        Write-VantaNextStep -Text 'Open Microsoft Store to confirm it works.'
    }
}
