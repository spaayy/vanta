# Helpers that Setup.ps1 and Desktop.ps1 dot-source on a PC installed from Vanta
# media: Setup.ps1 runs as SYSTEM or as the setup account at its first sign-in, and
# Desktop.ps1 as that account's before-desktop shell. Callers validate the setup root.
function Get-VantaPowerShellPath {
    return Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
}

# The shell command Setup.ps1 registers. Cleanup compares the registry value
# with it exactly, so both scripts must build it here.
function Get-VantaDesktopShell([string]$Root) {
    return '"' + (Get-VantaPowerShellPath) + '" -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $Root 'Desktop.ps1') + '"'
}

function Get-VantaDesktopTaskName([string]$Sid) {
    $validated = New-Object Security.Principal.SecurityIdentifier($Sid)
    return 'Vanta ISO desktop cleanup ' + $validated.Value
}

function Get-VantaTaskService {
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    return $service
}

function Register-VantaDesktopCleanup([string]$Sid, [string]$Root) {
    $taskCreate = 2 # TASK_CREATE: never replaces an existing task
    $serviceAccount = 5 # TASK_LOGON_SERVICE_ACCOUNT
    $service = Get-VantaTaskService
    # NewTask's flags are reserved and must be 0.
    $task = $service.NewTask(0)
    $task.RegistrationInfo.Description = 'Removes the Vanta ISO setup shell for its setup account.'
    $task.Principal.UserId = 'S-1-5-18'
    $task.Principal.LogonType = $serviceAccount
    $task.Settings.AllowDemandStart = $true
    $task.Settings.DisallowStartIfOnBatteries = $false
    $task.Settings.StopIfGoingOnBatteries = $false
    $task.Settings.ExecutionTimeLimit = 'PT1M'
    $action = $task.Actions.Create(0) # TASK_ACTION_EXEC
    $action.Path = Get-VantaPowerShellPath
    $action.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + (Join-Path $Root 'Setup.ps1') + '" -RestoreDesktopPolicy'
    $name = Get-VantaDesktopTaskName $Sid
    # The setup account may only read and run (GRGX) this fixed action. The first
    # sign-in run is an elevated administrator, which cannot assign SYSTEM
    # ownership; Administrators already have full control of the task.
    $sddl = 'O:BAG:SYD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;' + $Sid + ')'
    [void]$service.GetFolder('\').RegisterTaskDefinition($name, $task, $taskCreate, 'S-1-5-18', $null, $serviceAccount, $sddl)
}

function Test-VantaOwnedShell([Microsoft.Win32.RegistryKey]$Key, [string]$Shell) {
    return ($null -ne $Key -and [string]::Equals([string]$Key.GetValue('Shell'), $Shell, [StringComparison]::Ordinal))
}

function Remove-VantaOwnedShell([Microsoft.Win32.RegistryKey]$Key, [string]$Shell) {
    # Never restore an old DACL or overwrite a shell installed by another tool.
    if (Test-VantaOwnedShell $Key $Shell) { $Key.DeleteValue('Shell', $false) }
}

function Request-VantaDesktopCleanup([string]$Sid) {
    [void](Get-VantaTaskService).GetFolder('\').GetTask((Get-VantaDesktopTaskName $Sid)).Run($null)
}

function Unregister-VantaDesktopCleanup([string]$Sid) {
    # Microsoft documents DeleteTask's flags as unsupported, so they stay 0.
    (Get-VantaTaskService).GetFolder('\').DeleteTask((Get-VantaDesktopTaskName $Sid), 0)
}

# Appends, so a failed recovery does not overwrite the error that caused it.
function Write-VantaDesktopRecoveryLog($ErrorRecord) {
    [IO.File]::AppendAllText((Join-Path $env:LOCALAPPDATA 'Vanta-desktop-recovery.log'), ($ErrorRecord | Out-String))
}
