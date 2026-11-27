# Vanta.Privacy domain: the machine-owned part of the Location toggle. Service state,
# the Find My Device policy and Settings-page visibility live here so installation and
# the public toggle share one fail-stop implementation; user consent and the optional
# Find My Device prompt remain in the toggle companion.

Add-Type -AssemblyName System.ServiceProcess -ErrorAction Stop

$script:VantaLocationFindMyDevicePolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice'

function Get-VantaLocationServiceController {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    return New-Object System.ServiceProcess.ServiceController($Name)
}

function Invoke-VantaLocationServiceState {
    <#
    .SYNOPSIS
        Configures one location service through SCM and moves it to the requested
        runtime status within 30 seconds.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('lfsvc', 'MapsBroker')]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateRange(2, 4)]
        [int]$StartupType,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Running', 'Stopped')]
        [string]$Status
    )

    # A registry-only Start write can leave SCM treating the service as disabled when
    # Start follows immediately (1058, ERROR_SERVICE_DISABLED). Update its configuration
    # through SCM.
    $startup = switch ($StartupType) {
        2 { 'Automatic' }
        3 { 'Manual' }
        4 { 'Disabled' }
    }
    Set-Service -Name $Name -StartupType $startup -ErrorAction Stop

    $desiredStatus = if ($Status -ceq 'Running') {
        [System.ServiceProcess.ServiceControllerStatus]::Running
    }
    else {
        [System.ServiceProcess.ServiceControllerStatus]::Stopped
    }

    $service = Get-VantaLocationServiceController -Name $Name
    try {
        $service.Refresh()
        if ($service.Status -ne $desiredStatus) {
            if ($desiredStatus -eq
                [System.ServiceProcess.ServiceControllerStatus]::Running) {
                $service.Start()
            }
            else {
                $service.Stop()
            }
            $service.WaitForStatus($desiredStatus, [TimeSpan]::FromSeconds(30))
        }
    }
    finally {
        $service.Dispose()
    }
}

function Set-VantaLocationSettingsPageVisibility {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('hide', 'unhide')]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [ValidateSet('privacy-location', 'findmydevice')]
        [string]$Page
    )

    Import-VantaModule -Name Vanta.Shell
    Set-VantaSettingsPageVisibility -Operation $Operation -Page $Page -NoProcessCleanup
}

function Set-VantaLocationMachineState {
    <#
    .SYNOPSIS
        Applies the Location machine state. Disable stops and disables lfsvc and
        MapsBroker, locks Find My Device by policy and hides both settings pages.
        Enable restores the services and reveals the location page; Find My Device
        stays locked unless the interactive toggle opts in.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Disable', 'Enable')]
        [string]$State
    )

    if (Test-VantaTrustedInstaller) {
        Assert-VantaPrivilege -TrustedInstaller
    }
    else {
        Assert-VantaPrivilege -Administrator
    }

    if ($State -ceq 'Disable') {
        Invoke-VantaLocationServiceState -Name lfsvc -StartupType 4 -Status Stopped
        Invoke-VantaLocationServiceState -Name MapsBroker -StartupType 4 -Status Stopped

        foreach ($valueName in @('AllowFindMyDevice', 'LocationSyncEnabled')) {
            Set-VantaRegistryValue -Path $script:VantaLocationFindMyDevicePolicy -Name $valueName `
                -Type DWord -Data 0
        }

        Set-VantaLocationSettingsPageVisibility -Operation hide -Page privacy-location
        Set-VantaLocationSettingsPageVisibility -Operation hide -Page findmydevice
        Write-VantaLog -Message 'Disabled location services, locked Find My Device and hid the location settings pages.'
        return
    }

    Invoke-VantaLocationServiceState -Name lfsvc -StartupType 3 -Status Running
    Invoke-VantaLocationServiceState -Name MapsBroker -StartupType 2 -Status Running

    # Find My Device stays locked unless the interactive public toggle opts in.
    Set-VantaLocationSettingsPageVisibility -Operation unhide -Page privacy-location
    Write-VantaLog -Message 'Enabled location services and revealed the location settings page.'
}
