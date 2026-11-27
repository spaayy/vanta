@{
    Name          = 'TimerResolution'
    Description   = 'Adds or removes an Vanta scheduled task that keeps the global timer resolution high.'
    Elevation     = 'Admin'
    NoStateRecord = $true
    Warning       = 'Changes the global timer request policy and an Vanta scheduled task. A forced high timer resolution can increase power use; any latency benefit depends on the workload.'
    Script        = 'TimerResolution.ps1'
    States        = @(
        @{
            Name          = 'Disable'
            Launcher      = '3. General Configuration\Timer Resolution\Disable timer resolution (default).cmd'
            Reboot        = 'None'
            Registry      = @(
                @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'; Name = 'GlobalTimerResolutionRequests'; Operation = 'Delete' }
            )
            MachineAction = 'Unregister-VantaTimerResolutionTask'
        }
        @{
            Name          = 'Enable'
            Launcher      = '3. General Configuration\Timer Resolution\Enable timer resolution.cmd'
            Reboot        = 'Recommend'
            Registry      = @(
                @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'; Name = 'GlobalTimerResolutionRequests'; Type = 'DWord'; Data = 1 }
            )
            MachineAction = 'Register-VantaTimerResolutionTask'
        }
    )
}
