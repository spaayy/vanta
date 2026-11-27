BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $modulesRoot = Join-Path $repoRoot 'package\Executables\VantaModules\Scripts\Modules'

    Import-Module (Join-Path $modulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module (Join-Path $modulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force

    $script:commandProcessor = [IO.Path]::Combine(
        [Environment]::GetFolderPath('System'),
        'cmd.exe'
    )
}

Describe 'Invoke-VantaToggleNativeCommand' {
    It 'returns output and process details for an allowed exit code' {
        $result = Invoke-VantaToggleNativeCommand `
            -FilePath $script:commandProcessor `
            -ArgumentList ([string[]]@('/d', '/c', 'echo vanta-native-ok')) `
            -AllowedExitCodes ([int[]]@(0)) `
            -PassThru

        $result.FilePath | Should -BeExactly $script:commandProcessor
        $result.ExitCode | Should -Be 0
        ($result.Output -join "`n").Trim() | Should -BeExactly 'vanta-native-ok'
    }

    It 'accepts an explicitly allowed nonzero exit even when stderr is written under Stop' {
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Stop'
            $result = Invoke-VantaToggleNativeCommand `
                -FilePath $script:commandProcessor `
                -ArgumentList ([string[]]@(
                        '/d'
                        '/c'
                        'echo expected-absence 1>&2 & exit /b 37'
                    )) `
                -AllowedExitCodes ([int[]]@(37)) `
                -PassThru
        }
        finally {
            $ErrorActionPreference = $previousPreference
        }

        $result.ExitCode | Should -Be 37
        ($result.Output -join "`n") | Should -Match 'expected-absence'
    }

    It 'throws with native diagnostics when the exit code is not allowed' {
        {
            Invoke-VantaToggleNativeCommand `
                -FilePath $script:commandProcessor `
                -ArgumentList ([string[]]@(
                        '/d'
                        '/c'
                        'echo native-failure & exit /b 37'
                    )) `
                -AllowedExitCodes ([int[]]@(0, 1))
        } | Should -Throw '*exited with code 37*allowed exit codes: 0, 1*native-failure*'
    }

    It 'rejects unsafe paths and ambiguous exit-code contracts before invocation' {
        {
            Invoke-VantaToggleNativeCommand `
                -FilePath 'cmd.exe' `
                -ArgumentList ([string[]]@()) `
                -AllowedExitCodes ([int[]]@(0))
        } | Should -Throw '*must be fully qualified*'

        {
            Invoke-VantaToggleNativeCommand `
                -FilePath (Join-Path $TestDrive 'missing.exe') `
                -ArgumentList ([string[]]@()) `
                -AllowedExitCodes ([int[]]@(0))
        } | Should -Throw '*does not exist*'

        {
            Invoke-VantaToggleNativeCommand `
                -FilePath $script:commandProcessor `
                -ArgumentList ([string[]]@()) `
                -AllowedExitCodes ([int[]]@(0, 0))
        } | Should -Throw '*duplicate exit code 0*'
    }
}

Describe 'Remove-VantaToggleBcdValue' {
    BeforeEach {
        $script:bcdOutput = @(
            'Global Settings'
            '---------------'
            'identifier              {globalsettings}'
            'locale                  en-US'
            'advancedoptions         Yes'
            'custom:16000067         Yes'
        )
        Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles { $script:bcdOutput } -ParameterFilter {
            $ArgumentList[0] -eq '/enum'
        }
        Mock Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles {} -ParameterFilter {
            $ArgumentList[0] -eq '/deletevalue'
        }
    }

    It 'deletes <Element> when bcdedit lists it' -ForEach @(
        @{ Element = 'advancedoptions' }
        @{ Element = 'custom:16000067' }
    ) {
        InModuleScope Vanta.Toggles {
            Remove-VantaToggleBcdValue -WinDir 'C:\Windows' -Identifier '{globalsettings}' -Element $e
        } -Parameters @{ e = $Element }

        Should -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $ArgumentList[0] -eq '/deletevalue' -and
            ($ArgumentList -join '|') -ceq "/deletevalue|{globalsettings}|$Element" -and
            $FilePath -ceq 'C:\Windows\System32\bcdedit.exe' -and
            ($AllowedExitCodes -join ',') -ceq '0'
        }
    }

    # /deletevalue fails for an element that isn't set, and a prefix isn't the element.
    It 'leaves <Element> alone when bcdedit does not list it' -ForEach @(
        @{ Element = 'optionsedit' }
        @{ Element = 'advanced' }
        @{ Element = 'custom:16000069' }
    ) {
        InModuleScope Vanta.Toggles {
            Remove-VantaToggleBcdValue -WinDir 'C:\Windows' -Identifier '{globalsettings}' -Element $e
        } -Parameters @{ e = $Element }

        Should -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles -Times 0 -Exactly -ParameterFilter {
            $ArgumentList[0] -eq '/deletevalue'
        }
        Should -Invoke Invoke-VantaToggleNativeCommand -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $ArgumentList[0] -eq '/enum'
        }
    }
}
