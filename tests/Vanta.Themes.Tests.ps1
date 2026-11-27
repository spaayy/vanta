BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $modulesRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\package\Executables\VantaModules\Scripts\Modules'
    Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath 'Vanta.Themes\Vanta.Themes.psd1') -Force
}

Describe 'Set-VantaThemeMru' {
    BeforeAll {
        $script:themeMruNames = @(
            'vanta-dark.theme'
            'dark.theme'
            'aero.theme'
        )
    }

    BeforeEach {
        # No ParameterFilter, so nothing reaches HKCU or stops a real process.
        Mock Set-ItemProperty -ModuleName Vanta.Themes
        Mock Stop-ThemeProcesses -ModuleName Vanta.Themes
    }

    It 'writes the ThemeMRU list to the CurrentVersion\Themes key' {
        $expected = -join @($script:themeMruNames | ForEach-Object { "$env:SystemRoot\resources\Themes\$_;" })

        Set-VantaThemeMru

        Should -Invoke Set-ItemProperty -ModuleName Vanta.Themes -Times 1 -Exactly -ParameterFilter {
            $Path -ceq 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes' -and
            $Name -ceq 'ThemeMRU' -and
            $Value -ceq $expected -and
            $Type -eq 'String'
        }
        Should -Invoke Stop-ThemeProcesses -ModuleName Vanta.Themes -Times 1 -Exactly
    }

    It 'lists only Vanta themes that the Vanta package installs' {
        # Copy-VantaPackage.ps1 copies these to Resources\Themes; the other entries are inbox themes.
        $themesRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\package\Executables\Themes'
        foreach ($name in @($script:themeMruNames -like 'vanta-*')) {
            Join-Path -Path $themesRoot -ChildPath $name | Should -Exist
        }
    }
}

Describe 'Set-VantaTheme' {
    # Applying a theme goes through a native COM call that cannot be mocked and would change
    # this machine, so only the input guard is tested.
    It 'refuses <File> before applying anything' -TestCases @(
        @{ File = 'notatheme.txt'; Create = $true }
        @{ File = 'missing.theme'; Create = $false }
    ) {
        $path = Join-Path -Path $TestDrive -ChildPath $File
        if ($Create) { Set-Content -LiteralPath $path -Value 'x' -NoNewline }

        { Set-VantaTheme -Path $path } | Should -Throw -ExpectedMessage '*not a valid path to a theme file*'
    }
}

Describe 'Set-VantaLockscreenImage' {
    # Success calls the WinRT LockScreen API, which changes this user's lock screen.
    It 'throws when the source image path does not exist' {
        $missing = Join-Path -Path $TestDrive -ChildPath 'no-such-image.png'

        { Set-VantaLockscreenImage -Path $missing } | Should -Throw -ExpectedMessage '*not found*'
    }
}
