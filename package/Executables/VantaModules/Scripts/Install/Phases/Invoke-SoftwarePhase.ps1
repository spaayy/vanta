# Software phase, in every install mode.
# Installs machine-wide initial utilities and the selected browser and apps. Runs as
# TrustedInstaller; downloads happen here at install time.
# Every selected component is attempted. Optional app failures are warnings;
# other failures are reported together after the remaining installation attempts.

Assert-VantaPrivilege -TrustedInstaller

$scriptsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulesRoot = Join-Path -Path $scriptsRoot -ChildPath 'Modules'
Import-Module -Name (Join-Path $modulesRoot 'Vanta.Software\Vanta.Software.psd1') -Force -ErrorAction Stop

$context = Get-VantaContext
$requestedComponents = New-Object 'Collections.Generic.List[string]'
$failedComponents = New-Object 'Collections.Generic.List[string]'

# Initial software: Visual C++ Runtimes, NanaZip, DirectX (fresh installs only)
if (-not $context.IsUpgrade) {
    foreach ($component in @('VCRedist', 'SevenZip', 'DirectX')) {
        $requestedComponents.Add($component)
    }
}

if (Test-VantaOption -Name 'install-eclean') {
    $requestedComponents.Add('Eclean')
}

# Browsers. A 'browser-*' option is only set with 'install-another-browser': the
# capture refuses an option whose page depends on one the request didn't choose.
if (Test-VantaOption -Name 'browser-brave') {
    $requestedComponents.Add('Brave')
}
if (Test-VantaOption -Name 'browser-firefox') {
    $requestedComponents.Add('Firefox')
}
if (Test-VantaOption -Name 'browser-librewolf') {
    $requestedComponents.Add('LibreWolf')
}
if (Test-VantaOption -Name 'browser-chrome') {
    $requestedComponents.Add('Chrome')
}

foreach ($component in $requestedComponents) {
    try {
        $componentInstalled = [bool](Install-VantaSoftware -Component $component)
        if (-not $componentInstalled) {
            throw "The '$component' installer reported an unsuccessful outcome."
        }

        if ($component -ceq 'LibreWolf') {
            $interactiveUserSid = [string]$context.InteractiveUserSid
            if ([string]::IsNullOrWhiteSpace($interactiveUserSid)) {
                throw 'LibreWolf user integration requires the install-state user SID.'
            }

            $powerShellPath = [IO.Path]::Combine(
                [Environment]::SystemDirectory,
                'WindowsPowerShell',
                'v1.0',
                'powershell.exe'
            )
            $userIntegration = Join-Path -Path $scriptsRoot `
                -ChildPath 'Operations\Initialize-VantaLibreWolfUser.ps1'
            if (-not (Test-Path -LiteralPath $userIntegration -PathType Leaf)) {
                throw "The LibreWolf user-integration helper is missing at '$userIntegration'."
            }
            $arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -ExpectedUserSid "{1}"' -f `
                $userIntegration,
                $interactiveUserSid
            $exitCode = Invoke-VantaAsUser -FilePath $powerShellPath -Arguments $arguments
            if ($exitCode -ne 0) {
                throw "Exact-user LibreWolf integration failed with exit code $exitCode."
            }
        }
    }
    catch {
        if ($component -ceq 'Eclean') {
            Write-VantaLog -Level Warning -Message `
                "Optional app 'eclean' could not be installed; Vanta setup will continue. You can install it later from https://eclean.gg. Details: $($_.Exception.Message)"
            continue
        }
        if ($component -ceq 'DirectX') {
            Write-VantaLog -Level Warning -Message `
                "Optional legacy DirectX runtime was not installed; continuing: $($_.Exception.Message)"
            continue
        }
        if (-not $failedComponents.Contains($component)) {
            $failedComponents.Add($component)
        }
        Write-VantaLog -Level Warning -Message `
            "Software phase component '$component' failed: $($_.Exception.Message)"
    }
}

if ($failedComponents.Count -gt 0) {
    throw "Software phase failed for components: $($failedComponents -join ', ')."
}
