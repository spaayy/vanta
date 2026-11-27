# Companion for the ToggleWindowsUpdates toggle: stops and disables the Windows Update
# services and tasks and sets the policies that block updates, or lifts them all. Its
# functions run in the silent TrustedInstaller broker when you choose a state from the menu
# and when an update replays the recorded state.

function Get-VantaWindowsUpdateTaskPaths {
    return @(
        'Microsoft\Windows\WindowsUpdate\sih'
        'Microsoft\Windows\WindowsUpdate\sihboot'
        'Microsoft\Windows\UpdateOrchestrator\Schedule Scan'
        'Microsoft\Windows\UpdateOrchestrator\USO_UxBroker'
        'Microsoft\Windows\UpdateOrchestrator\Reboot'
    )
}

function Set-VantaWindowsUpdateTaskState {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    # The UpdateOrchestrator tasks refuse changes from Administrators and accept
    # SYSTEM, which is why this toggle runs as TrustedInstaller.
    Import-Module -Name ScheduledTasks -ErrorAction Stop
    $allTasks = @(Get-ScheduledTask -ErrorAction Stop)
    foreach ($taskPath in (Get-VantaWindowsUpdateTaskPaths)) {
        $task = $allTasks | Where-Object {
            ([string]::Concat([string]$_.TaskPath, [string]$_.TaskName)).Trim([char]'\') -ieq $taskPath
        } | Select-Object -First 1
        if ($null -eq $task) {
            Write-Verbose "ToggleWindowsUpdates: optional scheduled task '$taskPath' is not present on this Windows build."
            continue
        }

        if ($Enabled) {
            Enable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
        }
        else {
            Disable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
        }
    }
}

function Disable-VantaWindowsUpdates {
    param($Toggle)

    [void]$Toggle
    foreach ($serviceName in @('wuauserv', 'UsoSvc', 'WaaSMedicSvc')) {
        $service = Get-Service -Name $serviceName -ErrorAction Stop
        if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
            Stop-Service -Name $serviceName -Force -ErrorAction Stop
        }
        Set-VantaServiceStartup -Name $serviceName -StartupType 4
    }
    Set-VantaWindowsUpdateTaskState -Enabled $false

    $wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    Set-VantaRegistryValue -Path $wu -Name 'DisableWindowsUpdateAccess' -Type DWord -Data 1
    Set-VantaRegistryValue -Path $wu -Name 'DoNotConnectToWindowsUpdateInternetLocations' -Type DWord -Data 1
    Set-VantaRegistryValue -Path "$wu\AU" -Name 'NoAutoUpdate' -Type DWord -Data 1

    Import-VantaModule -Name Vanta.Shell
    Set-VantaSettingsPageVisibility -Operation hide -Page windowsupdate
}

function Enable-VantaWindowsUpdates {
    param($Toggle)

    [void]$Toggle
    # Lift the blocking policies first, so a failure later in the run can't leave
    # updates blocked, and the services start without them.
    $wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    Remove-VantaRegistryValue -Path $wu -Name 'DisableWindowsUpdateAccess'
    Remove-VantaRegistryValue -Path $wu -Name 'DoNotConnectToWindowsUpdateInternetLocations'
    Remove-VantaRegistryValue -Path "$wu\AU" -Name 'NoAutoUpdate'

    Import-VantaModule -Name Vanta.Shell
    Set-VantaSettingsPageVisibility -Operation unhide -Page windowsupdate

    foreach ($serviceName in @('wuauserv', 'UsoSvc', 'WaaSMedicSvc')) {
        Set-VantaServiceStartup -Name $serviceName -StartupType 3
        $service = Get-Service -Name $serviceName -ErrorAction Stop
        if ($service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
            Start-Service -Name $serviceName -ErrorAction Stop
        }
    }
    Set-VantaWindowsUpdateTaskState -Enabled $true
}
