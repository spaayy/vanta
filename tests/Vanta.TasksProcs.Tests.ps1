BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $modulesRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\package\Executables\VantaModules\Scripts\Modules'
    Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.TasksProcs\Vanta.TasksProcs.psd1') -Force

    $script:missingTask = '\VantaRewriteTest\TaskThatDoesNotExist'
}

Describe 'Scheduled-task wrappers with a missing task' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.TasksProcs
    }

    It '<Command> warns when the task does not exist' -ForEach @(
        @{ Command = 'Disable-VantaScheduledTask' }
        @{ Command = 'Enable-VantaScheduledTask' }
        @{ Command = 'Remove-VantaScheduledTask' }
    ) {
        { & $Command -Path $script:missingTask } | Should -Not -Throw

        Should -Invoke Write-VantaLog -ModuleName Vanta.TasksProcs -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -like '*was not found*'
        }
    }

    It '<Command> stays silent about a missing task with -IgnoreMissing' -ForEach @(
        @{ Command = 'Disable-VantaScheduledTask' }
        @{ Command = 'Enable-VantaScheduledTask' }
        @{ Command = 'Remove-VantaScheduledTask' }
    ) {
        { & $Command -Path $script:missingTask -IgnoreMissing } | Should -Not -Throw

        Should -Invoke Write-VantaLog -ModuleName Vanta.TasksProcs -Times 0 -Exactly
    }
}

Describe 'Scheduled-task command failure and postcondition checks' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.TasksProcs
        Mock Get-VantaScheduledTaskState -ModuleName Vanta.TasksProcs { 'Enabled' }
        $fake = Join-Path $TestDrive 'schtasks.cmd'
        Mock Get-VantaSchtasksPath -ModuleName Vanta.TasksProcs { $fake }
    }

    It 'does not treat exit code 1 for a present task as missing, even with IgnoreMissing' {
        Set-Content -LiteralPath $fake -Value "@echo off`r`necho Access is denied.`r`nexit /b 1"
        { Disable-VantaScheduledTask -Path '\Vanta\Task' -IgnoreMissing } |
            Should -Throw '*exited with code 1*Access is denied*'
        Should -Invoke Write-VantaLog -ModuleName Vanta.TasksProcs -Times 0
    }

    It 'rejects a successful native exit when the requested state did not take effect' {
        Set-Content -LiteralPath $fake -Value "@echo off`r`nexit /b 0"
        { Disable-VantaScheduledTask -Path '\Vanta\Task' } |
            Should -Throw "*remained 'Enabled'*expected 'Disabled'*"
    }

    It 'logs the verified state after a successful change' {
        $script:stateReads = 0
        Mock Get-VantaScheduledTaskState -ModuleName Vanta.TasksProcs {
            $script:stateReads++
            if ($script:stateReads -eq 1) { 'Enabled' } else { 'Disabled' }
        }
        Set-Content -LiteralPath $fake -Value "@echo off`r`nexit /b 0"
        Disable-VantaScheduledTask -Path '\Vanta\Task'
        Should -Invoke Get-VantaScheduledTaskState -ModuleName Vanta.TasksProcs -Times 2 -Exactly
        Should -Invoke Write-VantaLog -ModuleName Vanta.TasksProcs -Times 1 -Exactly -ParameterFilter {
            $Message -like '*Verified scheduled task*Enabled -> Disabled*'
        }
    }

    It 'skips native changes when the task is already <State>' -ForEach @(
        @{ State = 'Disabled'; Command = 'Disable-VantaScheduledTask' }
        @{ State = 'Enabled'; Command = 'Enable-VantaScheduledTask' }
    ) {
        $script:desiredTaskState = $State
        Mock Get-VantaScheduledTaskState -ModuleName Vanta.TasksProcs { $script:desiredTaskState }
        Mock Get-VantaSchtasksPath -ModuleName Vanta.TasksProcs { throw 'native command must not run' }
        & $Command -Path '\Vanta\Task'
        Should -Invoke Get-VantaSchtasksPath -ModuleName Vanta.TasksProcs -Times 0 -Exactly
        Should -Invoke Get-VantaScheduledTaskState -ModuleName Vanta.TasksProcs -Times 1 -Exactly
    }

    It 'does not treat a failed state query as an already satisfied task' {
        Mock Get-VantaScheduledTaskState -ModuleName Vanta.TasksProcs { throw 'scheduler unavailable' }
        { Disable-VantaScheduledTask -Path '\Vanta\Task' } | Should -Throw '*scheduler unavailable*'
        Should -Invoke Get-VantaSchtasksPath -ModuleName Vanta.TasksProcs -Times 0 -Exactly
    }
}

Describe 'Stop-VantaProcess' {
    It 'silently skips processes that are not running' {
        { Stop-VantaProcess -Name 'VantaRewriteTestNoSuchProcess*', 'AnotherMissingProcess*' } | Should -Not -Throw
    }

    It 'force-stops a matching process' {
        Mock Get-Process -ModuleName Vanta.TasksProcs -ParameterFilter { $Name -eq 'msteams*' } -MockWith {
            [pscustomobject]@{ ProcessName = 'msteams'; Id = 4242 }
        }
        Mock Invoke-VantaProcessStop -ModuleName Vanta.TasksProcs

        Stop-VantaProcess -Name 'msteams*'

        Should -Invoke Invoke-VantaProcessStop -ModuleName Vanta.TasksProcs -Times 1 -Exactly -ParameterFilter {
            $Process.Id -eq 4242
        }
    }

    It 'warns but does not throw when a process cannot be stopped' {
        Mock Get-Process -ModuleName Vanta.TasksProcs -ParameterFilter { $Name -eq 'msteams*' } -MockWith {
            [pscustomobject]@{ ProcessName = 'msteams'; Id = 4242 }
        }
        Mock Invoke-VantaProcessStop -ModuleName Vanta.TasksProcs -MockWith { throw 'Access is denied.' }
        Mock Write-VantaLog -ModuleName Vanta.TasksProcs

        { Stop-VantaProcess -Name 'msteams*' } | Should -Not -Throw

        Should -Invoke Write-VantaLog -ModuleName Vanta.TasksProcs -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -like "*msteams*"
        }
    }

    It 'stops only processes in the explicitly requested Windows session' {
        Mock Get-Process -ModuleName Vanta.TasksProcs -ParameterFilter { $Name -eq 'explorer' } -MockWith {
            @(
                [pscustomobject]@{ ProcessName = 'explorer'; Id = 7001; SessionId = 7 }
                [pscustomobject]@{ ProcessName = 'explorer'; Id = 8001; SessionId = 8 }
            )
        }
        Mock Invoke-VantaProcessStop -ModuleName Vanta.TasksProcs

        Stop-VantaProcess -Name 'explorer' -SessionId 7 -StopOnError

        Should -Invoke Invoke-VantaProcessStop -ModuleName Vanta.TasksProcs -Times 1 -Exactly `
            -ParameterFilter { $Process.Id -eq 7001 }
        Should -Invoke Invoke-VantaProcessStop -ModuleName Vanta.TasksProcs -Times 0 -Exactly `
            -ParameterFilter { $Process.Id -eq 8001 }
    }

    It 'fails closed when a requested-session process cannot be stopped' {
        Mock Get-Process -ModuleName Vanta.TasksProcs -ParameterFilter { $Name -eq 'explorer' } -MockWith {
            [pscustomobject]@{ ProcessName = 'explorer'; Id = 7001; SessionId = 7 }
        }
        Mock Invoke-VantaProcessStop -ModuleName Vanta.TasksProcs -MockWith { throw 'injected stop failure' }

        { Stop-VantaProcess -Name 'explorer' -SessionId 7 -StopOnError } |
            Should -Throw -ExpectedMessage '*injected stop failure*'
    }

    It 'tolerates the checked process exiting naturally before termination' {
        Mock Get-Process -ModuleName Vanta.TasksProcs -ParameterFilter { $Name -eq 'explorer' } -MockWith {
            [pscustomobject]@{
                ProcessName = 'explorer'; Id = 7001; SessionId = 7; HasExited = $true
            }
        }
        Mock Invoke-VantaProcessStop -ModuleName Vanta.TasksProcs -MockWith { throw 'process already exited' }

        { Stop-VantaProcess -Name 'explorer' -SessionId 7 -StopOnError } |
            Should -Not -Throw
    }

    It 'requires the retained stopped process to reach a time-limited exit postcondition' {
        Mock Get-Process -ModuleName Vanta.TasksProcs -ParameterFilter { $Name -eq 'explorer' } -MockWith {
            [pscustomobject]@{ ProcessName = 'explorer'; Id = 7001; SessionId = 7 }
        }
        Mock Invoke-VantaProcessStop -ModuleName Vanta.TasksProcs
        Mock Wait-VantaProcessExit -ModuleName Vanta.TasksProcs

        Stop-VantaProcess -Name explorer -SessionId 7 -StopOnError `
            -WaitTimeoutMilliseconds 5000

        Should -Invoke Wait-VantaProcessExit -ModuleName Vanta.TasksProcs `
            -Times 1 -Exactly -ParameterFilter {
                $Process.Id -eq 7001 -and $TimeoutMilliseconds -eq 5000
            }
    }

    It 'fails closed when a stopped process misses its time-limited exit postcondition' {
        Mock Get-Process -ModuleName Vanta.TasksProcs -ParameterFilter { $Name -eq 'msteams*' } -MockWith {
            [pscustomobject]@{
                ProcessName = 'msteams'; Id = 7002; SessionId = 7; HasExited = $false
            }
        }
        Mock Invoke-VantaProcessStop -ModuleName Vanta.TasksProcs
        Mock Wait-VantaProcessExit -ModuleName Vanta.TasksProcs -MockWith { throw 'wait timed out' }

        {
            Stop-VantaProcess -Name 'msteams*' -SessionId 7 -StopOnError `
                -WaitTimeoutMilliseconds 5000
        } | Should -Throw -ExpectedMessage '*wait timed out*'
    }

    It 'accepts Explorer only when it owns the shell window in the requested session' {
        Mock Get-VantaShellWindowProcessId -ModuleName Vanta.TasksProcs -MockWith { 7002 }
        Mock Get-Process -ModuleName Vanta.TasksProcs -ParameterFilter { $Id -eq 7002 } -MockWith {
            [pscustomobject]@{
                Id = 7002; ProcessName = 'explorer'; SessionId = 7; HasExited = $false
            }
        }

        $result = Wait-VantaExplorerShellRecovery -SessionId 7 -TimeoutSeconds 1

        $result.Id | Should -Be 7002
        $result.SessionId | Should -Be 7
    }

    It 'waits past a shell-window owner from another session' {
        $script:processRead = 0
        Mock Get-VantaShellWindowProcessId -ModuleName Vanta.TasksProcs -MockWith { 7002 }
        Mock Get-Process -ModuleName Vanta.TasksProcs -ParameterFilter { $Id -eq 7002 } -MockWith {
            $script:processRead++
            [pscustomobject]@{
                Id = 7002
                ProcessName = 'explorer'
                SessionId = if ($script:processRead -eq 1) { 8 } else { 7 }
                HasExited = $false
            }
        }
        Mock Start-Sleep -ModuleName Vanta.TasksProcs

        $result = Wait-VantaExplorerShellRecovery -SessionId 7 -TimeoutSeconds 1

        $result.SessionId | Should -Be 7
        Should -Invoke Get-Process -ModuleName Vanta.TasksProcs -Times 2 -Exactly
    }
}

Describe 'Scheduled-task wrappers build the correct schtasks command' {
    BeforeEach {
        Mock Invoke-VantaScheduledTaskCommand -ModuleName Vanta.TasksProcs
    }

    It '<Command> issues <Argv>' -ForEach @(
        @{ Command = 'Disable-VantaScheduledTask'; Label = 'disable'; Argv = '/Change /TN \Microsoft\Windows\Defrag\ScheduledDefrag /DISABLE' }
        @{ Command = 'Enable-VantaScheduledTask'; Label = 'enable'; Argv = '/Change /TN \Microsoft\Windows\Defrag\ScheduledDefrag /ENABLE' }
        @{ Command = 'Remove-VantaScheduledTask'; Label = 'delete'; Argv = '/Delete /TN \Microsoft\Windows\Defrag\ScheduledDefrag /F' }
    ) {
        $script:expectedTaskCommand = @{ Label = $Label; Argv = $Argv }
        & $Command -Path '\Microsoft\Windows\Defrag\ScheduledDefrag'
        & $Command -Path '\Microsoft\Windows\Defrag\ScheduledDefrag' -IgnoreMissing

        foreach ($ignoreMissing in @($false, $true)) {
            $script:expectedTaskCommand.IgnoreMissing = $ignoreMissing
            Should -Invoke Invoke-VantaScheduledTaskCommand -ModuleName Vanta.TasksProcs -Times 1 -Exactly -ParameterFilter {
                $Path -eq '\Microsoft\Windows\Defrag\ScheduledDefrag' -and
                $OperationLabel -eq $script:expectedTaskCommand.Label -and
                ($Arguments -join ' ') -eq $script:expectedTaskCommand.Argv -and
                [bool]$IgnoreMissing -eq $script:expectedTaskCommand.IgnoreMissing
            }
        }
    }
}

Describe 'Invoke-VantaScheduledTaskEntries' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.TasksProcs
        Mock Disable-VantaScheduledTask -ModuleName Vanta.TasksProcs
        Mock Enable-VantaScheduledTask -ModuleName Vanta.TasksProcs
    }

    It 'disables by default and enables on request, in declaration order' {
        Invoke-VantaScheduledTaskEntries -Entries @(
            @{ Path = '\Microsoft\Windows\Test\First' }
            @{ Path = '\Microsoft\Windows\Test\Second'; Operation = 'Enable' }
            @{ Path = '\Microsoft\Windows\Test\Third'; Operation = 'Disable' }
        )

        Should -Invoke Disable-VantaScheduledTask -ModuleName Vanta.TasksProcs -Times 2 -Exactly
        Should -Invoke Disable-VantaScheduledTask -ModuleName Vanta.TasksProcs -Times 1 -Exactly -ParameterFilter {
            $Path -ceq '\Microsoft\Windows\Test\First' -and -not $IgnoreMissing
        }
        Should -Invoke Disable-VantaScheduledTask -ModuleName Vanta.TasksProcs -Times 1 -Exactly -ParameterFilter {
            $Path -ceq '\Microsoft\Windows\Test\Third'
        }
        Should -Invoke Enable-VantaScheduledTask -ModuleName Vanta.TasksProcs -Times 1 -Exactly -ParameterFilter {
            $Path -ceq '\Microsoft\Windows\Test\Second' -and -not $IgnoreMissing
        }
    }

    It 'rejects malformed entries before changing any task' -TestCases @(
        @{ Entry = @{ Operation = 'Disable' }; Message = '*has no Path*' }
        @{ Entry = @{ Path = ' ' }; Message = '*has no Path*' }
        @{ Entry = @{ Path = '\Some\Task'; Operation = 'Delete' }; Message = "*Unknown scheduled task operation 'Delete'*" }
    ) {
        { Invoke-VantaScheduledTaskEntries -Entries @($Entry) } | Should -Throw $Message

        Should -Invoke Disable-VantaScheduledTask -ModuleName Vanta.TasksProcs -Times 0 -Exactly
        Should -Invoke Enable-VantaScheduledTask -ModuleName Vanta.TasksProcs -Times 0 -Exactly
    }

    It 'propagates a required change failure and stops at the failing entry' {
        Mock Disable-VantaScheduledTask -ModuleName Vanta.TasksProcs -ParameterFilter {
            $Path -ceq '\Microsoft\Windows\Test\Second'
        } -MockWith { throw 'schtasks failed for Second' }

        {
            Invoke-VantaScheduledTaskEntries -Entries @(
                @{ Path = '\Microsoft\Windows\Test\First' }
                @{ Path = '\Microsoft\Windows\Test\Second' }
                @{ Path = '\Microsoft\Windows\Test\Third' }
            )
        } | Should -Throw '*schtasks failed for Second*'

        Should -Invoke Disable-VantaScheduledTask -ModuleName Vanta.TasksProcs -Times 1 -Exactly -ParameterFilter {
            $Path -ceq '\Microsoft\Windows\Test\First'
        }
        Should -Invoke Disable-VantaScheduledTask -ModuleName Vanta.TasksProcs -Times 0 -Exactly -ParameterFilter {
            $Path -ceq '\Microsoft\Windows\Test\Third'
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.TasksProcs -Times 0 -Exactly
    }

    It 'turns a failure into a warning and continues when the entry ignores errors' {
        Mock Enable-VantaScheduledTask -ModuleName Vanta.TasksProcs -MockWith { throw 'cannot enable' }

        Invoke-VantaScheduledTaskEntries -Entries @(
            @{ Path = '\Microsoft\Windows\Test\First'; Operation = 'Enable'; IgnoreErrors = $true }
            @{ Operation = 'Disable'; IgnoreErrors = $true }
            @{ Path = '\Microsoft\Windows\Test\Third' }
        )

        Should -Invoke Disable-VantaScheduledTask -ModuleName Vanta.TasksProcs -Times 1 -Exactly -ParameterFilter {
            $Path -ceq '\Microsoft\Windows\Test\Third'
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.TasksProcs -Times 2 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -like 'Ignored scheduled task entry failure*'
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.TasksProcs -Times 1 -Exactly -ParameterFilter {
            $Message -like "*(task: '\Microsoft\Windows\Test\First')*cannot enable*"
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.TasksProcs -Times 1 -Exactly -ParameterFilter {
            $Message -like "*(task: '<no path>')*has no Path*"
        }
    }

    It 'accepts an empty entry list' {
        { Invoke-VantaScheduledTaskEntries -Entries @() } | Should -Not -Throw
        Should -Invoke Disable-VantaScheduledTask -ModuleName Vanta.TasksProcs -Times 0 -Exactly
    }
}

Describe 'Root-scoped cleanup helpers' {
    It 'keeps TI root cleanup inside the explicitly requested Windows session' {
        Mock Get-Process -ModuleName Vanta.TasksProcs -MockWith {
            @(
                [pscustomobject]@{
                    Id = 100; Path = 'C:\Windows\VantaModules\Tools\machine.exe'; SessionId = 0
                }
                [pscustomobject]@{
                    Id = 101; Path = 'C:\Windows\VantaModules\Tools\user.exe'; SessionId = 7
                }
            )
        }
        Mock Invoke-VantaProcessStop -ModuleName Vanta.TasksProcs
        Mock Wait-VantaProcessExit -ModuleName Vanta.TasksProcs

        Stop-VantaProcessUnderRoot -RootsLower @('c:\windows\vantamodules\') -SessionId 0

        Should -Invoke Invoke-VantaProcessStop -ModuleName Vanta.TasksProcs -Times 1 -Exactly `
            -ParameterFilter { $Process.Id -eq 100 }
        Should -Invoke Invoke-VantaProcessStop -ModuleName Vanta.TasksProcs -Times 0 -Exactly `
            -ParameterFilter { $Process.Id -eq 101 }
    }

    It 'stops only the scheduled tasks whose action runs under a root' {
        $vantaModules = Join-Path ([Environment]::GetFolderPath('Windows')) 'VantaModules'
        $script:rootTasks = @(
            [pscustomobject]@{
                TaskName = 'Vanta tool'; TaskPath = '\'
                Actions  = @([pscustomobject]@{ Execute = "$vantaModules\Tools\tool.exe" })
            }
            [pscustomobject]@{
                TaskName = 'Lookalike'; TaskPath = '\Vendor\'
                Actions  = @([pscustomobject]@{ Execute = "${vantaModules}Old\tool.exe" })
            }
            [pscustomobject]@{
                TaskName = 'Elsewhere'; TaskPath = '\Vendor\'
                Actions  = @([pscustomobject]@{ Execute = 'C:\Program Files\Vendor\tool.exe' })
            }
        )
        Mock Get-ScheduledTask -ModuleName Vanta.TasksProcs -MockWith { $script:rootTasks }
        Mock Stop-ScheduledTask -ModuleName Vanta.TasksProcs
        Mock Invoke-VantaBestEffortScheduledTaskEnd -ModuleName Vanta.TasksProcs

        Stop-VantaScheduledTaskUnderRoot -RootsLower @("$vantaModules\".ToLowerInvariant())

        Should -Invoke Stop-ScheduledTask -ModuleName Vanta.TasksProcs -Times 1 -Exactly
        Should -Invoke Stop-ScheduledTask -ModuleName Vanta.TasksProcs -Times 1 -Exactly -ParameterFilter {
            $TaskName -ceq 'Vanta tool' -and $TaskPath -ceq '\'
        }
    }

    It 'stops a task whose quoted %windir% program lies under a root given in any case' {
        # Get-ScheduledTask returns the Command element of
        # VantaModules\Other\Force Timer Resolution.xml as written, quotes included.
        Mock Get-ScheduledTask -ModuleName Vanta.TasksProcs -MockWith {
            @(
                [pscustomobject]@{
                    TaskName = 'Force Timer Resolution'; TaskPath = '\'
                    Actions  = @([pscustomobject]@{ Execute = '"%windir%\VantaModules\Tools\SetTimerResolution.exe"' })
                }
                [pscustomobject]@{
                    TaskName = 'Elsewhere'; TaskPath = '\'
                    Actions  = @([pscustomobject]@{ Execute = '"C:\Program Files\Other\other.exe"' })
                }
            )
        }
        Mock Stop-ScheduledTask -ModuleName Vanta.TasksProcs
        Mock Invoke-VantaBestEffortScheduledTaskEnd -ModuleName Vanta.TasksProcs

        $root = Join-Path -Path ([Environment]::GetFolderPath('Windows')) -ChildPath 'VantaModules'
        Stop-VantaScheduledTaskUnderRoot -RootsLower @($root.ToUpperInvariant()) -EndTaskName @()

        Should -Invoke Stop-ScheduledTask -ModuleName Vanta.TasksProcs -Times 1 -Exactly
        Should -Invoke Stop-ScheduledTask -ModuleName Vanta.TasksProcs -Times 1 -Exactly -ParameterFilter {
            $TaskName -ceq 'Force Timer Resolution' -and $TaskPath -ceq '\'
        }
    }

    It 'skips a task whose program is a bare name, even from a current directory under the root' {
        $root = (New-Item -ItemType Directory -Path (Join-Path $TestDrive 'Root')).FullName
        Mock Get-ScheduledTask -ModuleName Vanta.TasksProcs -MockWith {
            [pscustomobject]@{
                TaskName = 'Bare Name'; TaskPath = '\'
                Actions  = @([pscustomobject]@{ Execute = 'tool.exe' })
            }
        }
        Mock Stop-ScheduledTask -ModuleName Vanta.TasksProcs
        Mock Invoke-VantaBestEffortScheduledTaskEnd -ModuleName Vanta.TasksProcs

        # Resolved against the current directory, the name would land under the root.
        $currentDirectory = [Environment]::CurrentDirectory
        try {
            [Environment]::CurrentDirectory = $root
            Stop-VantaScheduledTaskUnderRoot -RootsLower @($root) -EndTaskName @()
        }
        finally {
            [Environment]::CurrentDirectory = $currentDirectory
        }

        Should -Invoke Stop-ScheduledTask -ModuleName Vanta.TasksProcs -Times 0 -Exactly
    }

    It 'ends a named fallback task and tolerates it disappearing first, under the engine Stop preference' {
        $argumentsLog = Join-Path $TestDrive 'schtasks-arguments.txt'
        $fakeSchtasks = Join-Path $TestDrive 'schtasks-race.cmd'
        Set-Content -LiteralPath $fakeSchtasks -Encoding Ascii -Value @(
            "@>>`"$argumentsLog`" echo %*"
            '@echo ERROR: The system cannot find the file specified. 1>&2'
            '@exit /b 1'
        )
        Mock Get-ScheduledTask -ModuleName Vanta.TasksProcs -MockWith { @() }
        Mock Get-VantaSchtasksPath -ModuleName Vanta.TasksProcs `
            -MockWith { $fakeSchtasks }

        # Native stderr becomes a terminating error under Stop unless the call guards it.
        {
            InModuleScope Vanta.TasksProcs {
                $ErrorActionPreference = 'Stop'
                Stop-VantaScheduledTaskUnderRoot -RootsLower @('c:\windows\vantamodules\') `
                    -EndTaskName 'Force Timer Resolution'
            }
        } | Should -Not -Throw

        Get-Content -LiteralPath $argumentsLog |
            Should -BeExactly '/End /TN "Force Timer Resolution"'
    }
}
