BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Registry\Vanta.Registry.psd1') -Force
    $script:searchRoot = 'HKCU:\Software\VantaRewriteTest\SearchPrivacy'
    $script:searchSettings = "$script:searchRoot\SearchSettings"
    $script:searchValues = "$script:searchRoot\Values"
    $script:currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $script:refusal = InModuleScope Vanta.Registry {
        New-VantaRegistryValueRefusedRecord -ProviderPath 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\SearchSettings' `
            -Name IsAADCloudSearchEnabled -Cause ([UnauthorizedAccessException]::new('Access denied'))
    }
}

Describe 'Search privacy on Windows that refuses per-user preferences' {
    BeforeEach {
        New-Item -Path $script:searchValues -Force | Out-Null
        InModuleScope Vanta.Registry { $script:VantaRegistryIdentityContext = $null }
        Initialize-VantaRegistryIdentityContext -CurrentToken -ExpectedUserSid $script:currentSid | Out-Null
        Mock Write-VantaLog -ModuleName Vanta.Registry {}
        Mock Invoke-VantaRegistryTargetOperation -ModuleName Vanta.Registry {
            throw $script:refusal
        } -ParameterFilter { $Path -eq 'HKCU:\Software\VantaRewriteTest\SearchPrivacy\SearchSettings' }
    }
    AfterEach {
        Remove-Item -LiteralPath $script:searchRoot -Recurse -Force
    }

    It 'finishes <Route> and applies its cloud-search policy' -ForEach @(
        @{ Route = 'Privacy tweak' }
        @{ Route = 'Disable Web Search' }
        @{ Route = 'Enable Web Search' }
    ) {
        if ($Route -eq 'Privacy tweak') {
            $definition = Import-PowerShellDataFile (Join-Path $script:VantaTestScriptsRoot 'Tweaks\privacy\search-settings.psd1')
            $entries = $definition.Registry
            $expectedMode = 1
        } else {
            $definition = Import-PowerShellDataFile (Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules\Toggles\General\WebSearch.psd1')
            $stateName = if ($Route -eq 'Enable Web Search') { 'Enable' } else { 'Disable' }
            $entries = @($definition.States | Where-Object Name -eq $stateName)[0].Registry
            $expectedMode = if ($stateName -eq 'Enable') { 2 } else { 1 }
        }
        foreach ($entry in $entries) {
            $entry.Path = if ($entry.Path -like '*\SearchSettings') { $script:searchSettings } else { $script:searchValues }
        }
        Set-ItemProperty -LiteralPath $script:searchValues -Name AllowCloudSearch -Type DWord -Value 1
        { Invoke-VantaRegistryEntries -Entries $entries -IsArm64 $false } | Should -Not -Throw
        $values = Get-Item -LiteralPath $script:searchValues
        $values.GetValue('SearchboxTaskbarMode') | Should -Be $expectedMode
        if ($Route -eq 'Enable Web Search') {
            $values.GetValue('AllowCloudSearch', $null) | Should -BeNullOrEmpty
        } else {
            $values.GetValue('AllowCloudSearch') | Should -Be 0
        }
        $refusedCount = @($entries | Where-Object Path -eq $script:searchSettings).Count
        Should -Invoke Write-VantaLog -ModuleName Vanta.Registry -Times $refusedCount -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -match 'Continuing without'
        }
    }

    It 'finishes <Route> when Windows also refuses the search box key' -ForEach @(
        @{ Route = 'Privacy tweak' }
        @{ Route = 'Disable Web Search' }
        @{ Route = 'Enable Web Search' }
    ) {
        # Windows can protect CurrentVersion\Search as well as SearchSettings.
        $searchBox = "$script:searchRoot\Search"
        if ($Route -eq 'Privacy tweak') {
            $entries = (Import-PowerShellDataFile (Join-Path $script:VantaTestScriptsRoot 'Tweaks\privacy\search-settings.psd1')).Registry
        } else {
            $definition = Import-PowerShellDataFile (Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules\Toggles\General\WebSearch.psd1')
            $stateName = if ($Route -eq 'Enable Web Search') { 'Enable' } else { 'Disable' }
            $entries = @($definition.States | Where-Object Name -eq $stateName)[0].Registry
        }
        foreach ($entry in $entries) {
            $entry.Path = if ($entry.Path -like '*\SearchSettings') { $script:searchSettings }
            elseif ($entry.Path -like '*\CurrentVersion\Search') { $searchBox }
            else { $script:searchValues }
        }
        Mock Invoke-VantaRegistryTargetOperation -ModuleName Vanta.Registry {
            throw $script:refusal
        } -ParameterFilter { $Path -eq 'HKCU:\Software\VantaRewriteTest\SearchPrivacy\Search' }

        { Invoke-VantaRegistryEntries -Entries $entries -IsArm64 $false } | Should -Not -Throw
        $refusedCount = @($entries | Where-Object { $_.Path -in @($script:searchSettings, $searchBox) }).Count
        @($entries | Where-Object Path -eq $searchBox).Count | Should -BeGreaterThan 0
        Should -Invoke Write-VantaLog -ModuleName Vanta.Registry -Times $refusedCount -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -match 'Continuing without'
        }
        # The machine policy that turns off web results still follows the route.
        $present = $null -ne (Get-Item -LiteralPath $script:searchValues).GetValue('DisableSearchBoxSuggestions', $null)
        $present | Should -Be ($Route -ne 'Enable Web Search')
    }

    It 'does not hide a failure to apply the required cloud-search policy' {
        $definition = Import-PowerShellDataFile (Join-Path $script:VantaTestScriptsRoot 'Tweaks\privacy\search-settings.psd1')
        $entries = @($definition.Registry | Where-Object Name -eq AllowCloudSearch)
        $entries[0].Path = $script:searchValues
        Mock Invoke-VantaRegistryTargetOperation -ModuleName Vanta.Registry {
            throw $script:refusal
        } -ParameterFilter { $Path -eq 'HKCU:\Software\VantaRewriteTest\SearchPrivacy\Values' }
        { Invoke-VantaRegistryEntries -Entries $entries -IsArm64 $false } | Should -Throw '*AllowCloudSearch*'
    }

    It 'does not hide other registry failures in optional search preferences' {
        $definition = Import-PowerShellDataFile (Join-Path $script:VantaTestScriptsRoot 'Tweaks\privacy\search-settings.psd1')
        $entries = @($definition.Registry | Where-Object Name -eq IsAADCloudSearchEnabled)
        $entries[0].Path = $script:searchSettings
        Mock Invoke-VantaRegistryTargetOperation -ModuleName Vanta.Registry {
            throw 'Unexpected registry failure'
        } -ParameterFilter { $Path -eq 'HKCU:\Software\VantaRewriteTest\SearchPrivacy\SearchSettings' }
        { Invoke-VantaRegistryEntries -Entries $entries -IsArm64 $false } | Should -Throw '*Unexpected registry failure*'
    }
}
