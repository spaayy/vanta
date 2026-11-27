BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Registry\Vanta.Registry.psd1') -Force
    # The companions resolve these commands after Import-VantaModule (mocked below); load
    # the real modules once so the mocks have a command to shadow inside Vanta.Toggles.
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Appx\Vanta.Appx.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Download\Vanta.Download.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force

    $togglesRoot = Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules\Toggles'
    $script:copilot = Get-VantaToggleDefinition -Name Copilot -TogglesRoot $togglesRoot
    $script:widgets = Get-VantaToggleDefinition -Name Widgets -TogglesRoot $togglesRoot

    # Companions reach Operations scripts through $Toggle.OperationsPath only.
    $script:operationsPath = Join-Path $TestDrive 'Operations'
    New-Item -Path $script:operationsPath -ItemType Directory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $script:operationsPath 'Remove-Edge.ps1') -Value '' -Encoding Ascii

    $script:fakeWinget = Join-Path $TestDrive 'winget.exe'
    Set-Content -LiteralPath $script:fakeWinget -Value '' -Encoding Ascii

    # Builds the $Toggle context the engine hands to a companion function.
    function New-ToggleContext {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][string]$State,
            [bool]$Silent = $true
        )

        return [pscustomobject]@{
            Name              = $Name
            State             = $State
            StateValue        = $null
            Silent            = $Silent
            JustContext       = $false
            NoExplorerRestart = $false
            ResetServices     = $false
            StateRoot         = 'HKCU:\Software\VantaRewriteTest\Services'
            LauncherPath      = $null
            WinDir            = $env:SystemRoot
            VantaModulesPath  = $TestDrive
            ScriptsPath       = (Join-Path $TestDrive 'Scripts')
            ModulesPath       = (Join-Path $TestDrive 'Scripts\Modules')
            OperationsPath    = $script:operationsPath
            WindowsBuild      = 26100
        }
    }

    # Runs one companion function exactly as the engine does (dot-sourced into the
    # module scope under strict mode), so module-scoped mocks apply to it.
    function Invoke-CompanionFunction {
        param(
            [Parameter(Mandatory = $true)]$Definition,
            [Parameter(Mandatory = $true)][string]$FunctionName,
            [Parameter(Mandatory = $true)]$Toggle
        )

        InModuleScope Vanta.Toggles {
            Invoke-VantaToggleFunction -Definition $d -FunctionName $f -Toggle $t -Label 'test'
        } -Parameters @{ d = $Definition; f = $FunctionName; t = $Toggle }
    }

    function Find-RegistryEntry {
        param(
            [Parameter(Mandatory = $true)]$State,
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string]$Name
        )

        # The comma keeps a single matching hashtable wrapped as an array.
        return , @($State['Registry'] | Where-Object { $_.Path -ceq $Path -and $_.Name -ceq $Name })
    }
}

Describe 'Copilot toggle' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Toggles
        Mock Import-VantaModule -ModuleName Vanta.Toggles
        Mock Invoke-VantaAppxRemovalPlan -ModuleName Vanta.Toggles
        Mock Set-VantaRegistryValue -ModuleName Vanta.Toggles
        Mock Remove-VantaRegistryValue -ModuleName Vanta.Toggles
        Mock Get-ItemPropertyValue -ModuleName Vanta.Toggles
        Mock Get-VantaTrustedWingetPath -ModuleName Vanta.Toggles { $script:fakeWinget }
        Mock Assert-VantaTrustedWingetSource -ModuleName Vanta.Toggles
        $script:appInstalled = $false
        Mock Get-AppxPackage -ModuleName Vanta.Toggles { if ($script:appInstalled) { [pscustomobject]@{ Status = 'Ok' } } }
        Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles { $script:appInstalled = $true }
    }

    It 'splits Copilot work between the machine and the user' {
        $disable = $script:copilot.States['Disable']

        $policy = @(Find-RegistryEntry -State $disable `
            -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name 'RemoveMicrosoftCopilotApp')
        $policy.Count | Should -Be 1
        $policy[0].Type | Should -BeExactly 'DWord'
        $policy[0].Data | Should -Be 1

        # Without this action, disabling Copilot would stop removing the app.
        $disable['MachineAction'] | Should -BeExactly 'Remove-VantaCopilotApp'

        # The Store install must run as the user, so Enable keeps a separate user action.
        $enable = $script:copilot.States['Enable']
        $enable['MachineAction'] | Should -BeExactly 'Enable-VantaCopilotMachine'
        $enable['UserAction'] | Should -BeExactly 'Enable-VantaCopilotUser'
    }

    It 'removes only the Copilot app in the machine action and leaves registry work to the declarations' {
        $context = New-ToggleContext -Name 'Copilot' -State 'Disable'

        Invoke-CompanionFunction -Definition $script:copilot -FunctionName 'Remove-VantaCopilotApp' -Toggle $context

        Should -Invoke Import-VantaModule -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter { $Name -ceq 'Vanta.Appx' }
        Should -Invoke Invoke-VantaAppxRemovalPlan -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Definition.Count -eq 1 -and
                $Definition[0].Name -ceq 'Microsoft.Copilot*' -and
                -not $Definition[0].IgnoreErrors
        }
        Should -Not -Invoke Set-VantaRegistryValue -ModuleName Vanta.Toggles
        Should -Not -Invoke Remove-VantaRegistryValue -ModuleName Vanta.Toggles
    }

    It 're-shows the taskbar button only on a legacy build with an affirmative marker' {
        Mock Get-ItemPropertyValue -ModuleName Vanta.Toggles { 1 }
        $context = New-ToggleContext -Name 'Copilot' -State 'Enable'
        $context.WindowsBuild = 22631

        Invoke-CompanionFunction -Definition $script:copilot -FunctionName 'Enable-VantaCopilotUser' -Toggle $context

        Should -Invoke Set-VantaRegistryValue -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Path -ceq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -and
                $Name -ceq 'ShowCopilotButton' -and $Type -ceq 'DWord' -and $Data -eq 1
        }
        Should -Not -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles
        Should -Not -Invoke Get-VantaTrustedWingetPath -ModuleName Vanta.Toggles
    }

    It 'installs the Store app only through the trusted msstore source' {
        Mock Get-ItemPropertyValue -ModuleName Vanta.Toggles { 0 }
        $context = New-ToggleContext -Name 'Copilot' -State 'Enable'

        Invoke-CompanionFunction -Definition $script:copilot -FunctionName 'Enable-VantaCopilotUser' -Toggle $context

        Should -Invoke Import-VantaModule -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter { $Name -ceq 'Vanta.Download' }
        Should -Invoke Assert-VantaTrustedWingetSource -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $WingetPath -ceq $script:fakeWinget -and $Name -ceq 'msstore'
        }
        Should -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $FilePath -ceq $script:fakeWinget -and
                ($ArgumentList -join '|') -ceq
                    'install|--exact|--id|9NHT9RB2F4HD|--source|msstore|--uninstall-previous|--silent|--accept-source-agreements|--accept-package-agreements|--disable-interactivity' -and
                $AllowedExitCodes.Count -eq 1 -and $AllowedExitCodes[0] -eq 0
        }
        Should -Not -Invoke Set-VantaRegistryValue -ModuleName Vanta.Toggles
        Should -Not -Invoke Remove-VantaRegistryValue -ModuleName Vanta.Toggles
    }

    It 'installs the app on a legacy build when the taskbar marker is absent' {
        $context = New-ToggleContext -Name 'Copilot' -State 'Enable'
        $context.WindowsBuild = 22631

        Invoke-CompanionFunction -Definition $script:copilot -FunctionName 'Enable-VantaCopilotUser' -Toggle $context

        Should -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles -Times 1 -Exactly
        Should -Not -Invoke Set-VantaRegistryValue -ModuleName Vanta.Toggles
    }

    It 'does not accept a successful installer exit without a healthy app' {
        Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles {}
        $context = New-ToggleContext -Name 'Copilot' -State 'Enable'
        { Invoke-CompanionFunction -Definition $script:copilot -FunctionName 'Enable-VantaCopilotUser' -Toggle $context } | Should -Throw '*healthy*'
    }

    It 'leaves an already healthy app installed without running winget' {
        $script:appInstalled = $true
        $context = New-ToggleContext -Name 'Copilot' -State 'Enable'
        Invoke-CompanionFunction -Definition $script:copilot -FunctionName 'Enable-VantaCopilotUser' -Toggle $context
        Should -Not -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles
    }

    It 'propagates Store installation failure without applying a partial user state' {
        Mock Get-ItemPropertyValue -ModuleName Vanta.Toggles { 0 }
        Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles { throw 'simulated winget failure' }
        $context = New-ToggleContext -Name 'Copilot' -State 'Enable'

        { Invoke-CompanionFunction -Definition $script:copilot -FunctionName 'Enable-VantaCopilotUser' -Toggle $context } |
            Should -Throw '*simulated winget failure*'

        Should -Not -Invoke Set-VantaRegistryValue -ModuleName Vanta.Toggles
        Should -Not -Invoke Remove-VantaRegistryValue -ModuleName Vanta.Toggles
        Should -Invoke Write-VantaLog -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -like "*Copilot*Enable-VantaCopilotUser*simulated winget failure*"
        }
    }
}

Describe 'Widgets toggle' {
    BeforeEach {
        Mock Set-VantaMachineDwordPolicy -ModuleName Vanta.Toggles
        Mock Write-VantaLog -ModuleName Vanta.Toggles
        Mock Write-VantaNote -ModuleName Vanta.Toggles
        Mock Write-VantaStep -ModuleName Vanta.Toggles
        Mock Set-VantaRegistryValue -ModuleName Vanta.Toggles
        Mock Remove-VantaRegistryValue -ModuleName Vanta.Toggles
        Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { $true }
        Mock Start-Process -ModuleName Vanta.Toggles
        # Pin the Edge check so every host takes the branch a test asks for.
        $script:edgeInstalled = $true
        Mock Test-Path -ModuleName Vanta.Toggles { $script:edgeInstalled } -ParameterFilter {
            $LiteralPath -like '*\Microsoft\Edge\Application\msedge.exe'
        }
        $script:expectedPowerShell = [IO.Path]::Combine(
            $env:SystemRoot,
            'System32\WindowsPowerShell\v1.0\powershell.exe'
        )
        $script:expectedHelper = Join-Path $script:operationsPath 'Remove-Edge.ps1'
    }

    It 'enables Widgets through local policy and removes the supplemental restrictions' {
        $script:widgets.States['Enable']['MachineAction'] | Should -BeExactly 'Enable-VantaWidgetsMachine'
        $context = New-ToggleContext -Name 'Widgets' -State 'Enable' -Silent $true

        Invoke-CompanionFunction -Definition $script:widgets -FunctionName 'Enable-VantaWidgetsMachine' -Toggle $context

        Should -Invoke Set-VantaMachineDwordPolicy -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Path -ceq 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -and
                $Name -ceq 'AllowNewsAndInterests' -and $Data -eq 1
        }
        foreach ($valueName in 'DisableWidgetsOnLockScreen', 'DisableWidgetsBoard') {
            Should -Invoke Remove-VantaRegistryValue -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
                $Path -ceq 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -and $Name -ceq $valueName
            }
        }
        Should -Invoke Remove-VantaRegistryValue -ModuleName Vanta.Toggles -Times 2 -Exactly -ParameterFilter {
            $AllowOsProtected
        }
        Should -Not -Invoke Set-VantaRegistryValue -ModuleName Vanta.Toggles
        Should -Not -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles
        Should -Not -Invoke Start-Process -ModuleName Vanta.Toggles
    }

    It 'only updates WebView2 through the bundled helper when Edge is installed' {
        $context = New-ToggleContext -Name 'Widgets' -State 'Enable' -Silent $false

        Invoke-CompanionFunction -Definition $script:widgets -FunctionName 'Enable-VantaWidgetsMachine' -Toggle $context

        # Proves the pinned check above decided the branch, not this host's Edge.
        Should -Invoke Test-Path -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $LiteralPath -like '*\Microsoft\Edge\Application\msedge.exe'
        }
        Should -Not -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles
        Should -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $FilePath -ceq $script:expectedPowerShell -and
                $ArgumentList -contains '-InstallWebView' -and
                $ArgumentList -notcontains '-InstallEdge' -and
                $ArgumentList[([array]::IndexOf($ArgumentList, '-File') + 1)] -ceq $script:expectedHelper -and
                $AllowedExitCodes.Count -eq 1 -and $AllowedExitCodes[0] -eq 0
        }
        Should -Invoke Set-VantaMachineDwordPolicy -ModuleName Vanta.Toggles -Times 1 -Exactly
        Should -Invoke Remove-VantaRegistryValue -ModuleName Vanta.Toggles -Times 2 -Exactly
        Should -Not -Invoke Start-Process -ModuleName Vanta.Toggles
    }

    It 'installs Edge with WebView2 before the policies when Edge is missing and the user agrees' {
        $script:edgeInstalled = $false
        $context = New-ToggleContext -Name 'Widgets' -State 'Enable' -Silent $false

        Invoke-CompanionFunction -Definition $script:widgets -FunctionName 'Enable-VantaWidgetsMachine' -Toggle $context

        Should -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles -Times 1 -Exactly
        Should -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $FilePath -ceq $script:expectedPowerShell -and
                $ArgumentList -contains '-InstallWebView' -and
                $ArgumentList -contains '-InstallEdge'
        }
        Should -Invoke Set-VantaMachineDwordPolicy -ModuleName Vanta.Toggles -Times 1 -Exactly
        Should -Invoke Remove-VantaRegistryValue -ModuleName Vanta.Toggles -Times 2 -Exactly
    }

    It 'leaves Widgets disabled when the Edge install is declined' {
        $script:edgeInstalled = $false
        Mock Read-VantaYesNo -ModuleName Vanta.Toggles { $false }
        $context = New-ToggleContext -Name 'Widgets' -State 'Enable' -Silent $false

        { Invoke-CompanionFunction -Definition $script:widgets -FunctionName 'Enable-VantaWidgetsMachine' -Toggle $context } |
            Should -Throw '*declined*'

        Should -Invoke Read-VantaYesNo -ModuleName Vanta.Toggles -Times 1 -Exactly
        Should -Not -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles
        Should -Not -Invoke Set-VantaMachineDwordPolicy -ModuleName Vanta.Toggles
        Should -Not -Invoke Remove-VantaRegistryValue -ModuleName Vanta.Toggles
    }

    It 'leaves the policies untouched when the Edge helper fails' {
        Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles { throw 'simulated Edge helper failure' }
        $context = New-ToggleContext -Name 'Widgets' -State 'Enable' -Silent $false

        { Invoke-CompanionFunction -Definition $script:widgets -FunctionName 'Enable-VantaWidgetsMachine' -Toggle $context } |
            Should -Throw '*simulated Edge helper failure*'

        Should -Not -Invoke Remove-VantaRegistryValue -ModuleName Vanta.Toggles
        Should -Not -Invoke Set-VantaMachineDwordPolicy -ModuleName Vanta.Toggles
        Should -Not -Invoke Start-Process -ModuleName Vanta.Toggles
    }
}
