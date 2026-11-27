BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    foreach ($module in 'Vanta.Core', 'Vanta.Registry', 'Vanta.Toggles', 'Vanta.Tweaks') {
        Import-Module (Join-Path $script:VantaTestModulesRoot "$module\$module.psd1") -Force
    }
}

Describe 'Applied toggle defaults' {
    It 'applies and records the three privacy defaults through the toggle engine' {
        Mock -ModuleName Vanta.Tweaks Invoke-VantaToggleMachineState {}
        Mock -ModuleName Vanta.Tweaks Write-VantaLog {}
        $context = [pscustomobject]@{ IsUpgrade = $false; IsArm64 = $false; WindowsBuild = 26200 }
        $root = Join-Path $script:VantaTestScriptsRoot 'Tweaks'
        $manifest = Get-VantaTweakManifest -Path (Join-Path $root 'tweaks.manifest.psd1')
        @($manifest.Categories | Where-Object Name -eq 'privacy').Tweaks | Should -Contain 'apply-privacy-toggle-defaults'
        $path = Join-Path $root 'privacy\apply-privacy-toggle-defaults.psd1'
        @(Test-VantaTweakSchema -Path $path).Count | Should -Be 0
        Invoke-VantaTweak -Path $path -Context $context
        Should -Invoke -ModuleName Vanta.Tweaks Invoke-VantaToggleMachineState -Times 3 -Exactly
        foreach ($toggleName in 'PhoneLink', 'RecentItems', 'WebSearch') {
            Should -Invoke -ModuleName Vanta.Tweaks Invoke-VantaToggleMachineState -Times 1 -Exactly -ParameterFilter {
                $Name -ceq $toggleName -and $State -ceq 'Disable'
            }
        }
    }
}
