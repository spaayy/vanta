BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $repoRoot = $script:VantaTestRepoRoot
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force
    $handlerPath = Join-Path $repoRoot `
        'package\Executables\VantaModules\Scripts\Operations\Invoke-VantaPriorityLaunch.ps1'

    $script:definition = Get-VantaToggleDefinition -Name RunWithPriority `
        -TogglesRoot (Join-Path $repoRoot 'package\Executables\VantaModules\Toggles')
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Shell\Vanta.Shell.psd1') -Force
    . $handlerPath -Priority Normal -TargetPath 'C:\not-used.exe'

    if (-not ('VantaPriorityTestCommandLine' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class VantaPriorityTestCommandLine
{
    [DllImport("shell32.dll", SetLastError = true)]
    private static extern IntPtr CommandLineToArgvW(
        [MarshalAs(UnmanagedType.LPWStr)] string commandLine,
        out int argumentCount);

    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr memory);

    public static string[] Split(string commandLine)
    {
        int count;
        IntPtr arguments = CommandLineToArgvW(commandLine, out count);
        if (arguments == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error());

        try
        {
            string[] result = new string[count];
            for (int index = 0; index < count; index++)
                result[index] = Marshal.PtrToStringUni(
                    Marshal.ReadIntPtr(arguments, index * IntPtr.Size));
            return result;
        }
        finally
        {
            LocalFree(arguments);
        }
    }
}
'@ -ErrorAction Stop
    }

    # Runs one companion function through the engine's own runner (module scope, strict
    # mode) with the Vanta.Registry writes captured by the module-scoped mocks declared
    # in the Describe's BeforeEach.
    function Invoke-PriorityToggleAction {
        param(
            [Parameter(Mandatory = $true)]
            [string]$FunctionName
        )

        $script:priorityWrites = [Collections.Generic.List[object]]::new()
        $script:priorityRemovals = [Collections.Generic.List[string]]::new()
        $script:priorityOrder = [Collections.Generic.List[string]]::new()
        $toggle = [pscustomobject]@{
            Name           = 'RunWithPriority'
            State          = 'Enable'
            StateValue     = 1
            Silent         = $true
            OperationsPath = 'C:\VantaModules\Scripts\Operations'
        }
        InModuleScope Vanta.Toggles {
            Invoke-VantaToggleFunction -Definition $d -FunctionName $f -Toggle $t -Label 'test'
        } -Parameters @{ d = $script:definition; f = $FunctionName; t = $toggle }

        return [pscustomobject]@{
            Writes   = @($script:priorityWrites)
            Removals = @($script:priorityRemovals)
            Order    = @($script:priorityOrder)
        }
    }
}

Describe 'Run with priority' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Toggles
        Mock Set-VantaRegistryValue -ModuleName Vanta.Toggles {
            $script:priorityOrder.Add('Set')
            $script:priorityWrites.Add([pscustomobject]@{
                    Path = $Path
                    Name = $Name
                    Type = $Type
                    Data = $Data
                })
        }
        Mock Remove-VantaRegistryKey -ModuleName Vanta.Toggles {
            $script:priorityOrder.Add('Remove')
            $script:priorityRemovals.Add($Path)
        }
    }

    It 'maps the six menu labels to the documented Windows priority classes' {
        $expected = [ordered]@{
            Low         = [uint32]0x00000040
            BelowNormal = [uint32]0x00004000
            Normal      = [uint32]0x00000020
            AboveNormal = [uint32]0x00008000
            High        = [uint32]0x00000080
            Realtime    = [uint32]0x00000100
        }

        foreach ($entry in $expected.GetEnumerator()) {
            Get-VantaPriorityClass -Name $entry.Key | Should -Be $entry.Value
        }
        { Get-VantaPriorityClass -Name 'TimeCritical' } | Should -Throw
    }

    It 'accepts an existing local executable and rejects invalid targets' {
        $target = Join-Path $TestDrive `
            ('Vanta priority {0} tool.exe' -f [char]0x03A9)
        Copy-Item -LiteralPath (Join-Path ([Environment]::SystemDirectory) 'where.exe') `
            -Destination $target

        Resolve-VantaPriorityTarget -Path $target |
            Should -BeExactly ([IO.Path]::GetFullPath($target))
        { Resolve-VantaPriorityTarget -Path '.\relative.exe' } |
            Should -Throw '*absolute path*'
        { Resolve-VantaPriorityTarget -Path '\\server\share\tool.exe' } |
            Should -Throw '*absolute path*'
        { Resolve-VantaPriorityTarget -Path ($target + '.txt') } |
            Should -Throw '*executable file*'
        { Resolve-VantaPriorityTarget -Path (Join-Path $TestDrive 'missing.exe') } |
            Should -Throw '*does not exist*'
    }

    It 'round-trips the fixed handler, the chosen priority and the target through the UAC relaunch arguments' {
        $handler = 'C:\Windows\VantaModules\Scripts\Operations\Invoke-VantaPriorityLaunch.ps1'
        $target = 'C:\Program Files\Vanta & games\Unicode {0} app.exe' -f [char]0x03A9
        $arguments = @(Get-VantaPriorityRelaunchArgumentList `
                -HandlerPath $handler -ExecutablePath $target -Priority 'High')
        $parsed = [VantaPriorityTestCommandLine]::Split($arguments -join ' ')

        $parsed.Count | Should -Be 12
        $parsed[6] | Should -BeExactly $handler
        $parsed[8] | Should -BeExactly 'High'
        $parsed[10] | Should -BeExactly $target
        $parsed[11] | Should -BeExactly '-Elevated'
    }

    It 'loads the native launcher and rejects invalid calls before creating a process' {
        Initialize-VantaNativeType

        { [Vanta.Native.PriorityLauncher]::Start(
                $null,
                '"C:\missing.exe"',
                'C:\',
                [uint32]0x20
            ) } | Should -Throw '*application path is required*'
    }

    It 'rewrites one single-selection machine cascade with the six menu entries in order' {
        $result = Invoke-PriorityToggleAction `
            -FunctionName $script:definition.States['Enable']['MachineAction']
        $root = 'HKLM:\SOFTWARE\Classes\exefile\Shell\Priority'

        $result.Removals | Should -Be @($root)
        $result.Order[0] | Should -Be 'Remove' -Because 'a stale cascade must be gone before the new one is written'
        @($result.Writes | Where-Object {
                $_.Path -eq $root -and $_.Name -eq 'MultiSelectModel' -and
                $_.Type -eq 'String' -and $_.Data -eq 'Single'
            }).Count | Should -Be 1 -Because 'a multi-selection would start one process per file'

        $labels = @($result.Writes | Where-Object {
                $_.Name -eq 'MUIVerb' -and $_.Path -ne $root
            } | ForEach-Object Data)
        $labels | Should -Be @(
            'Realtime', 'High', 'Above normal', 'Normal', 'Below normal', 'Low'
        )
    }

    It 'keeps every selected executable as one argument to the fixed internal script' {
        $result = Invoke-PriorityToggleAction `
            -FunctionName $script:definition.States['Enable']['MachineAction']
        $commands = @($result.Writes | Where-Object {
                $_.Name -eq '' -and $_.Type -eq 'ExpandString'
            })
        $target = 'C:\Program Files\Vanta & games\Unicode {0} app.exe' -f [char]0x03A9
        $priorities = @('Realtime', 'High', 'AboveNormal', 'Normal', 'BelowNormal', 'Low')

        $commands.Count | Should -Be 6
        for ($index = 0; $index -lt $commands.Count; $index++) {
            $parsed = [VantaPriorityTestCommandLine]::Split(
                $commands[$index].Data.Replace('%1', $target)
            )
            $parsed.Count | Should -Be 14
            $parsed[0] | Should -BeExactly `
                '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe'
            $parsed[9] | Should -BeExactly `
                '%SystemRoot%\VantaModules\Scripts\Operations\Invoke-VantaPriorityLaunch.ps1'
            $parsed[11] | Should -BeExactly $priorities[$index]
            $parsed[13] | Should -BeExactly $target
        }
    }

    It 'removes exactly the cascade root that Enable writes' {
        $added = Invoke-PriorityToggleAction `
            -FunctionName $script:definition.States['Enable']['MachineAction']
        $registry = @($script:definition.States['Disable']['Registry'])

        $registry | Should -HaveCount 1
        $registry[0].Operation | Should -BeExactly 'DeleteKey'
        $registry[0].Path | Should -BeExactly $added.Removals[0]
    }
}

Describe 'Run with priority launch' {
    BeforeAll {
        $script:launch = @{
            ExecutablePath = 'C:\Program Files\Vanta\setup.exe'
            Priority       = 'High'
            PriorityClass  = [uint32]0x80
            PowerShellPath = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
            HandlerPath    = 'C:\Windows\VantaModules\Scripts\Operations\Invoke-VantaPriorityLaunch.ps1'
        }
    }

    BeforeEach {
        Mock Start-VantaPriorityProcess {}
        Mock Start-VantaPriorityElevatedHandler {}
    }

    It 'starts the target directly at the chosen priority' {
        Start-VantaPriorityTarget @script:launch -IsAdministrator $false

        Should -Invoke Start-VantaPriorityProcess -Times 1 -Exactly -ParameterFilter {
            $ExecutablePath -ceq 'C:\Program Files\Vanta\setup.exe' -and $PriorityClass -eq 0x80
        }
        Should -Invoke Start-VantaPriorityElevatedHandler -Times 0
    }

    It 'sends Realtime through UAC without trying a direct start' {
        $realtime = $script:launch.Clone()
        $realtime.Priority = 'Realtime'
        $realtime.PriorityClass = [uint32]0x100

        Start-VantaPriorityTarget @realtime -IsAdministrator $false

        Should -Invoke Start-VantaPriorityProcess -Times 0
        Should -Invoke Start-VantaPriorityElevatedHandler -Times 1 -Exactly -ParameterFilter { $Priority -ceq 'Realtime' }
    }

    It 'relaunches through UAC with the same priority when the executable asks for administrator rights' {
        Mock Start-VantaPriorityProcess { throw [ComponentModel.Win32Exception]::new(740) }

        Start-VantaPriorityTarget @script:launch -IsAdministrator $false

        Should -Invoke Start-VantaPriorityElevatedHandler -Times 1 -Exactly -ParameterFilter {
            $Priority -ceq 'High' -and
            $ExecutablePath -ceq 'C:\Program Files\Vanta\setup.exe' -and
            $HandlerPath -ceq 'C:\Windows\VantaModules\Scripts\Operations\Invoke-VantaPriorityLaunch.ps1'
        }
    }

    It 'rethrows other launch failures, and elevation failures in the elevated handler' {
        Mock Start-VantaPriorityProcess { throw [ComponentModel.Win32Exception]::new(193) }
        { Start-VantaPriorityTarget @script:launch -IsAdministrator $false } | Should -Throw

        Mock Start-VantaPriorityProcess { throw [ComponentModel.Win32Exception]::new(740) }
        { Start-VantaPriorityTarget @script:launch -IsAdministrator $true -Elevated } | Should -Throw

        Should -Invoke Start-VantaPriorityElevatedHandler -Times 0
    }

    It 'accepts -Elevated only from the installed handler' {
        $target = Join-Path $TestDrive 'tool.exe'
        Copy-Item -LiteralPath (Join-Path ([Environment]::SystemDirectory) 'where.exe') -Destination $target

        { Invoke-VantaPriorityLaunch -Priority High -TargetPath $target -Elevated } |
            Should -Throw '*only through the installed Vanta handler*'
        Should -Invoke Start-VantaPriorityProcess -Times 0
    }

    It 'names the Windows reason for a failed native launch' {
        Initialize-VantaNativeType
        $record = $null
        try {
            [Vanta.Native.PriorityLauncher]::Start($null, 'x', 'C:\', [uint32]0x20)
        }
        catch {
            $record = $_
        }
        Get-VantaPriorityFailureReason -ErrorRecord $record -FileName 'tool.exe' |
            Should -BeLike '*application path is required*'

        $native = [Management.Automation.ErrorRecord]::new(
            [ComponentModel.Win32Exception]::new(193, 'CreateProcessW failed for the selected executable'),
            'NativeFailure', [Management.Automation.ErrorCategory]::NotSpecified, $null)
        $reason = Get-VantaPriorityFailureReason -ErrorRecord $native -FileName 'tool.exe'
        $reason | Should -BeLike '*tool.exe*(Windows error 193).'
        $reason | Should -Not -BeLike '*%1*'
    }
}
