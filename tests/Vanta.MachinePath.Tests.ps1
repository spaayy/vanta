BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')

    # Lift Add-VantaPath out of the task, which edits the machine PATH when it runs.
    $taskPath = Join-Path $script:VantaTestScriptsRoot 'Install\Tasks\Initialize-VantaPath.ps1'
    $ast = [Management.Automation.Language.Parser]::ParseFile($taskPath, [ref]$null, [ref]$null)
    $definition = $ast.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Add-VantaPath'
        }, $true)
    . ([scriptblock]::Create($definition.Extent.Text))

    $script:pathSubKey = "Software\VantaMachinePathTest\$([guid]::NewGuid().ToString('N'))"

    function Set-TestPathValue {
        param([string]$Value, [Microsoft.Win32.RegistryValueKind]$Kind)
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:pathSubKey)
        try { $key.SetValue('Path', $Value, $Kind) }
        finally { $key.Dispose() }
    }

    function Get-TestPathValue {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:pathSubKey)
        try {
            [pscustomobject]@{
                Value = $key.GetValue('Path', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                Kind  = $key.GetValueKind('Path')
            }
        }
        finally { $key.Dispose() }
    }
}

AfterAll {
    Remove-Item -LiteralPath 'HKCU:\Software\VantaMachinePathTest' -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Machine PATH entries' {
    BeforeEach {
        $script:vantaPaths = @(
            (New-Item -Path (Join-Path $TestDrive 'VantaModules') -ItemType Directory -Force).FullName
            (New-Item -Path (Join-Path $TestDrive 'VantaModules\Tools') -ItemType Directory -Force).FullName
        )
    }

    It 'appends the Vanta entries and leaves every existing entry unexpanded' {
        $existing = '%SystemRoot%\system32;%SystemRoot%;C:\Windows;C:\WINDOWS;%JAVA_HOME%\bin'
        Set-TestPathValue -Value $existing -Kind ExpandString

        Add-VantaPath -Paths $script:vantaPaths -Hive CurrentUser -SubKey $script:pathSubKey

        $path = Get-TestPathValue
        $path.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
        $path.Value | Should -BeExactly ((@($existing) + $script:vantaPaths) -join ';')
    }

    It 'adds nothing an existing entry already names, and makes a REG_SZ value expandable again' {
        $env:VANTA_MACHINE_PATH_TEST = $TestDrive
        try {
            $existing = "%VANTA_MACHINE_PATH_TEST%\vantamodules\;$($script:vantaPaths[1].ToUpperInvariant())"
            Set-TestPathValue -Value $existing -Kind String

            Add-VantaPath -Paths $script:vantaPaths -Hive CurrentUser -SubKey $script:pathSubKey

            $path = Get-TestPathValue
            $path.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
            $path.Value | Should -BeExactly $existing
        }
        finally { Remove-Item -LiteralPath Env:\VANTA_MACHINE_PATH_TEST -ErrorAction SilentlyContinue }
    }
}
