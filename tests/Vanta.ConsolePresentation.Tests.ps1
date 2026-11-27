BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force

    # Every helper prints through Write-Host; capture the lines so the tests assert on
    # the words a user reads, not on colours.
    function Get-ConsoleLine {
        param([Parameter(Mandatory = $true)][scriptblock]$Action)

        $script:ConsoleLines = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host -ModuleName Vanta.Core {
            $text = if ($null -eq $Object) { '' } else { [string]$Object }
            if ($NoNewline) {
                $script:ConsoleLines.Add($text + '<no newline>')
            }
            else {
                $script:ConsoleLines.Add($text)
            }
        }
        & $Action
        return @($script:ConsoleLines)
    }
}

Describe 'Console vocabulary' {
    It 'prints the Vanta heading with an underline, explanation and blank line' {
        $lines = Get-ConsoleLine { Write-VantaTitle -Text 'Enable Sleep' -Explanation 'Restores the Windows sleep timers.' }

        $lines | Should -Be @(
            'Vanta - Enable Sleep'
            '--------------------'
            'Restores the Windows sleep timers.'
            ''
        )
    }

    It 'carries meaning in words for every prefixed kind and indents continuation lines' {
        $lines = Get-ConsoleLine {
            Write-VantaWarning -Text "first line`nsecond line"
            Write-VantaFailure -Text 'boom'
            Write-VantaNextStep -Text 'open Store'
            Write-VantaManualStep -Text @('finish in Settings', 'and close it')
            Write-VantaPartial -Text 'half'
        }

        $lines | Should -Be @(
            'Warning: first line'
            '         second line'
            'Error: boom'
            'Next step: open Store'
            'To finish: finish in Settings'
            '           and close it'
            'Partly done: half'
        )
    }

    It 'uses one fixed sentence per restart notice' {
        $lines = Get-ConsoleLine {
            foreach ($kind in 'Recommended', 'Required', 'SignOut', 'ExplorerRestarted', 'ExplorerRestartNeeded') {
                Write-VantaRestartNotice -Kind $kind
            }
        }

        $lines.Count | Should -Be 5
        $lines[0] | Should -BeLike 'Restart recommended: *'
        $lines[1] | Should -BeLike 'Restart required: *'
        $lines[2] | Should -BeLike 'Sign out required: *'
        $lines[3] | Should -BeLike 'File Explorer was restarted*'
        $lines[4] | Should -BeLike 'Restart File Explorer, or sign out*'
    }

    It 'prints the standard failure block with the log location' {
        $lines = Get-ConsoleLine {
            Write-VantaNote -Text 'Checking Edge...'
            Write-VantaNotApplied -Title 'Enable Widgets' -Reason 'Edge missing' -DetailsPath 'C:\logs\vanta-install.log'
        }

        $lines | Should -Be @(
            'Checking Edge...'
            ''
            'Not applied: Enable Widgets.'
            'Error: Edge missing'
            'Details: C:\logs\vanta-install.log'
        )
    }
}

Describe 'Run outcome and closing line' {
    BeforeEach { Reset-VantaRunOutcome }

    It 'starts as Applied and prints Done' {
        Get-VantaRunOutcome | Should -BeExactly 'Applied'
        $lines = Get-ConsoleLine {
            Write-VantaStep -Text 'Applying...'
            Write-VantaCompletion -Title 'Enable Sleep'
        }
        $lines | Should -Be @('Applying...', '', 'Done: Enable Sleep.')
    }

    It 'separates the closing line with one blank line, not two' {
        $lines = Get-ConsoleLine {
            Write-VantaTitle -Text 'Enable Sleep'
            Write-VantaCompletion -Title 'Enable Sleep'
        }
        $lines | Should -Be @('Vanta - Enable Sleep', '--------------------', '', 'Done: Enable Sleep.')
    }

    It 'becomes Manual after a manual step so the closing line does not claim success' {
        $lines = Get-ConsoleLine {
            Write-VantaManualStep -Text 'turn on Location services in Settings'
            Write-VantaCompletion -Title 'Enable Location'
        }

        Get-VantaRunOutcome | Should -BeExactly 'Manual'
        $lines[-1] | Should -BeExactly 'Not finished yet: complete the step above.'
    }

    It 'lets Partial outrank Manual and never downgrades' {
        $null = Get-ConsoleLine {
            Write-VantaManualStep -Text 'finish'
            Write-VantaPartial -Text 'one of two'
            Write-VantaManualStep -Text 'finish again'
        }
        Get-VantaRunOutcome | Should -BeExactly 'Partial'
        Set-VantaRunOutcome -Outcome Applied
        Get-VantaRunOutcome | Should -BeExactly 'Partial'

        $lines = Get-ConsoleLine { Write-VantaCompletion -Title 'Install Software' }
        $lines[-1] | Should -BeExactly 'Partly done: Install Software. Review the warnings above.'
    }

    It 'advisory next steps keep the run Applied' {
        $null = Get-ConsoleLine { Write-VantaNextStep -Text 'open Store' }
        Get-VantaRunOutcome | Should -BeExactly 'Applied'
    }
}

Describe 'Prompts' {
    BeforeEach {
        $script:Answers = New-Object 'System.Collections.Generic.Queue[object]'
        Mock Read-VantaConsoleLine -ModuleName Vanta.Core {
            if ($script:Answers.Count -eq 0) { throw 'no scripted answer left' }
            $script:Answers.Dequeue()
        }
        Mock Write-Host -ModuleName Vanta.Core
    }

    It 'accepts y/yes and n/no in any case and defaults to No on Enter' -ForEach @(
        @{ Answer = 'y'; Expected = $true }
        @{ Answer = 'YES'; Expected = $true }
        @{ Answer = 'n'; Expected = $false }
        @{ Answer = 'No'; Expected = $false }
        @{ Answer = ''; Expected = $false }
        @{ Answer = '   '; Expected = $false }
    ) {
        $script:Answers.Enqueue($Answer)
        Read-VantaYesNo -Question 'Continue?' | Should -Be $Expected
        Should -Invoke Read-VantaConsoleLine -ModuleName Vanta.Core -Times 1 -Exactly -ParameterFilter {
            $Prompt -ceq 'Continue? [y/N] '
        }
    }

    It 'takes Yes on Enter only when the caller declares that default' {
        $script:Answers.Enqueue('')
        Read-VantaYesNo -Question 'Restart File Explorer now?' -DefaultYes | Should -BeTrue
        Should -Invoke Read-VantaConsoleLine -ModuleName Vanta.Core -Times 1 -Exactly -ParameterFilter {
            $Prompt -ceq 'Restart File Explorer now? [Y/n] '
        }
    }

    It 'asks again after an answer that is neither yes nor no' {
        foreach ($answer in 'maybe', 'x', 'yes') { $script:Answers.Enqueue($answer) }
        Read-VantaYesNo -Question 'Continue?' | Should -BeTrue
        Should -Invoke Read-VantaConsoleLine -ModuleName Vanta.Core -Times 3 -Exactly
        Should -Invoke Write-Host -ModuleName Vanta.Core -Times 2 -Exactly -ParameterFilter {
            $Object -ceq 'Please answer y or n.'
        }
    }

    It 'treats a closed input stream as the default answer instead of looping' {
        $script:Answers.Enqueue($null)
        Read-VantaYesNo -Question 'Continue?' | Should -BeFalse
    }

    It 'numbers the options, rejects out-of-range and current choices, and returns the index' {
        foreach ($answer in '0', '3', 'two', '2', '1') { $script:Answers.Enqueue($answer) }

        Read-VantaChoice -Question 'What would you like to do?' -Option @('Disable', 'Enable') -CurrentIndex 2 | Should -Be 1

        Should -Invoke Write-Host -ModuleName Vanta.Core -Times 1 -Exactly -ParameterFilter { $Object -ceq '  [1] Disable' }
        Should -Invoke Write-Host -ModuleName Vanta.Core -Times 1 -Exactly -ParameterFilter { $Object -ceq '  [2] Enable (current)' }
        Should -Invoke Write-Host -ModuleName Vanta.Core -Times 3 -Exactly -ParameterFilter { $Object -ceq 'Please type a number from 1 to 2.' }
        Should -Invoke Write-Host -ModuleName Vanta.Core -Times 1 -Exactly -ParameterFilter { $Object -ceq 'That is already the current setting. Choose another option.' }
        Should -Invoke Read-VantaConsoleLine -ModuleName Vanta.Core -Times 5 -Exactly -ParameterFilter { $Prompt -ceq 'Choose 1-2: ' }
    }

    It 'takes the declared default on Enter and fails closed without one' {
        $script:Answers.Enqueue('')
        Read-VantaChoice -Question 'Snapshot?' -Option @('Windows', 'Vanta', 'None') -DefaultIndex 3 | Should -Be 3
        Should -Invoke Write-Host -ModuleName Vanta.Core -Times 1 -Exactly -ParameterFilter { $Object -ceq '  [3] None (default)' }

        $script:Answers.Enqueue($null)
        { Read-VantaChoice -Question 'Snapshot?' -Option @('Windows', 'Vanta') } | Should -Throw '*no keyboard input*'
    }

    It 'reports a host without keyboard input instead of hanging' {
        # A runspace created without a host has no console to read from.
        $shell = [powershell]::Create()
        try {
            $null = $shell.AddCommand('Import-Module').
                AddParameter('Name', (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1')).
                AddStatement().AddCommand('Read-VantaYesNo').AddParameter('Question', 'Continue?')
            $answer = $shell.Invoke()

            $answer | Should -BeNullOrEmpty
            "$($shell.Streams.Error)" | Should -BeLike '*cannot take keyboard input*'
        }
        finally { $shell.Dispose() }
    }
}

Describe 'Log console styles' {
    BeforeEach {
        Mock Write-VantaLogFile -ModuleName Vanta.Core
        Mock Write-Host -ModuleName Vanta.Core
    }

    AfterEach {
        Set-VantaLogConsoleStyle -Style Diagnostic
    }

    It 'defaults to the diagnostic echo every captured transcript relies on' {
        Get-VantaLogConsoleStyle | Should -BeExactly 'Diagnostic'

        Write-VantaLog -Message 'applied' -NoConsole
        Write-VantaLog -Level Warning -Message 'careful'

        Should -Invoke Write-VantaLogFile -ModuleName Vanta.Core -Times 3 -Exactly
        Should -Invoke Write-Host -ModuleName Vanta.Core -Times 1 -Exactly -ParameterFilter {
            $Object -like '`[*`] `[-`] `[INFO`] applied'
        }
        Should -Invoke Write-Host -ModuleName Vanta.Core -Times 1 -Exactly -ParameterFilter {
            $Object -like '`[*`] `[WARNING`] careful'
        }
    }

    It 'keeps Info in the file and shows Warning and Error in the vocabulary when interactive' {
        Set-VantaLogConsoleStyle -Style Interactive

        Write-VantaLog -Message 'applied'
        Write-VantaLog -Level Warning -Message 'careful'
        Write-VantaLog -Level Error -Message 'broken'
        Write-VantaLog -Level Error -Message 'already shown' -NoConsole

        Should -Invoke Write-VantaLogFile -ModuleName Vanta.Core -Times 1 -Exactly -ParameterFilter { $Line -like '*`[INFO`] applied' }
        Should -Invoke Write-VantaLogFile -ModuleName Vanta.Core -Times 2 -Exactly -ParameterFilter { $Line -like '*already shown' }
        Should -Invoke Write-Host -ModuleName Vanta.Core -Times 0 -Exactly -ParameterFilter { $Object -like '*applied*' }
        Should -Invoke Write-Host -ModuleName Vanta.Core -Times 1 -Exactly -ParameterFilter { $Object -ceq 'Warning: careful' }
        Should -Invoke Write-Host -ModuleName Vanta.Core -Times 1 -Exactly -ParameterFilter { $Object -ceq 'Error: broken' }
        Should -Invoke Write-Host -ModuleName Vanta.Core -Times 0 -Exactly -ParameterFilter { $Object -like '*already shown*' }
    }
}

Describe 'Toggle engine presentation' {
    BeforeAll {
        $script:TogglesRoot = Join-Path $TestDrive 'Toggles'
        $group = Join-Path $script:TogglesRoot 'Demo'
        $null = New-Item -Path $group -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path $group 'DemoMenu.psd1') -Encoding UTF8 -Value @'
@{
    Name          = 'DemoMenu'
    Elevation     = 'None'
    Menu          = $true
    NoStateRecord = $true
    Launcher      = 'Demo\Demo Menu.cmd'
    Script        = 'DemoMenu.ps1'
    States        = @(
        @{ Name = 'Off'; MenuLabel = 'Turn the demo off'; Reboot = 'None'; Action = 'Invoke-VantaDemoMenu' }
        @{ Name = 'On'; MenuLabel = 'Turn the demo on'; Reboot = 'Recommend'; Action = 'Invoke-VantaDemoMenu' }
    )
}
'@
        Set-Content -LiteralPath (Join-Path $group 'DemoMenu.ps1') -Encoding UTF8 -Value @'
function Invoke-VantaDemoMenu {
    param($Toggle)
    Write-VantaStep -Text "Applying $($Toggle.State)..."
}
'@
        Set-Content -LiteralPath (Join-Path $group 'DemoManual.psd1') -Encoding UTF8 -Value @'
@{
    Name          = 'DemoManual'
    Elevation     = 'None'
    NoStateRecord = $true
    Warning       = 'Opens Settings and leaves the choice to you.'
    Script        = 'DemoManual.ps1'
    States        = @(
        @{ Name = 'Run'; Launcher = 'Demo\Demo Manual.cmd'; Reboot = 'None'; Action = 'Invoke-VantaDemoManual' }
    )
}
'@
        Set-Content -LiteralPath (Join-Path $group 'DemoManual.ps1') -Encoding UTF8 -Value @'
function Invoke-VantaDemoManual {
    param($Toggle)
    Write-VantaManualStep -Text 'turn the setting on in Settings'
}
'@
    }

    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Toggles
        Mock Test-VantaTrustedInstaller -ModuleName Vanta.Toggles { $false }
        Mock Test-VantaSystem -ModuleName Vanta.Toggles { $false }
        Mock Test-VantaAdmin -ModuleName Vanta.Toggles { $false }
        $script:Answers = New-Object 'System.Collections.Generic.Queue[object]'
        Mock Read-VantaConsoleLine -ModuleName Vanta.Core {
            if ($script:Answers.Count -eq 0) { throw 'no scripted answer left' }
            $script:Answers.Dequeue()
        }
    }

    It 'shows the heading before a Menu choice, closes with the chosen label and pauses once' {
        $script:Answers.Enqueue('2')
        $script:Answers.Enqueue('')

        $lines = Get-ConsoleLine {
            Invoke-VantaToggle -Name 'DemoMenu' -TogglesRoot $script:TogglesRoot -LauncherPath 'C:\Vanta\Demo Menu.cmd'
        }

        $lines[0] | Should -BeExactly 'Vanta - Demo Menu'
        $lines | Should -Contain '  [2] Turn the demo on'
        $lines | Should -Contain 'Applying On...'
        $lines | Should -Contain 'Done: Turn the demo on.'
        $lines | Should -Contain 'Restart recommended: restart Windows to finish applying this change.'
        @($lines | Where-Object { $_ -ceq 'Vanta - Demo Menu' }).Count | Should -Be 1
        Should -Invoke Read-VantaConsoleLine -ModuleName Vanta.Core -Times 1 -Exactly -ParameterFilter { $Prompt -ceq 'Press Enter to exit. ' }
        [array]::IndexOf($lines, 'Done: Turn the demo on.') | Should -BeGreaterThan ([array]::IndexOf($lines, 'Applying On...'))
    }

    It 'gates a declared warning once and reports a manual outcome instead of Done' {
        $script:Answers.Enqueue('')
        $script:Answers.Enqueue('')

        $lines = Get-ConsoleLine {
            Invoke-VantaToggle -Name 'DemoManual' -State 'Run' -TogglesRoot $script:TogglesRoot -LauncherPath 'C:\Vanta\Demo Manual.cmd'
        }

        $lines[0] | Should -BeExactly 'Vanta - Demo Manual'
        $lines | Should -Contain 'Warning: Opens Settings and leaves the choice to you.'
        Should -Invoke Read-VantaConsoleLine -ModuleName Vanta.Core -Times 1 -Exactly -ParameterFilter { $Prompt -like 'Press Enter to continue, or Ctrl+C to cancel.*' }
        Should -Invoke Read-VantaConsoleLine -ModuleName Vanta.Core -Times 1 -Exactly -ParameterFilter { $Prompt -ceq 'Press Enter to exit. ' }
        $lines | Should -Contain 'To finish: turn the setting on in Settings'
        $lines | Should -Contain 'Not finished yet: complete the step above.'
        $lines | Should -Not -Contain 'Done: Demo Manual.'
    }

    It 'prints nothing and asks nothing in silent mode' {
        $lines = Get-ConsoleLine {
            Invoke-VantaToggle -Name 'DemoManual' -State 'Run' -Silent -TogglesRoot $script:TogglesRoot
        }

        @($lines | Where-Object { $_ -like 'Vanta - *' -or $_ -like 'Done:*' -or $_ -like 'Press Enter*' }).Count | Should -Be 0
        Should -Invoke Read-VantaConsoleLine -ModuleName Vanta.Core -Times 0 -Exactly
    }
}
