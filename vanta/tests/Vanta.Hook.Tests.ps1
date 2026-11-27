BeforeAll {
    $script:repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:vantaScripts = Join-Path $repo 'package\Executables\VantaModules\Scripts'
    . (Join-Path $repo 'vanta\tools\Add-VantaHook.ps1')
    $script:vanta = Get-Content (Join-Path $repo 'vanta\vanta.json') -Raw -Encoding UTF8 | ConvertFrom-Json

    function New-StagedScripts {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        foreach ($rel in 'Entry\Invoke-VantaInstall.ps1', 'Install\Install-Plan.ps1', 'Tweaks\tweaks.manifest.psd1', 'Install\Invoke-VantaInstallSession.ps1') {
            $target = Join-Path $root $rel
            New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
            Copy-Item (Join-Path $vantaScripts $rel) $target
        }
        return $root
    }
}

Describe 'Hook into the Vanta orchestrator (ADR-2: only the staging copy changes)' {
    It 'finds both anchors exactly once in the Vanta source (fails loudly if Vanta moves them)' {
        $staged = New-StagedScripts
        { Add-VantaHook -ScriptsRoot $staged } | Should -Not -Throw
    }
    It 'adds Vanta to the known phases and to the plan after the Vanta power tweak, before the Windows transition' {
        $staged = New-StagedScripts
        Add-VantaHook -ScriptsRoot $staged
        (Get-Content (Join-Path $staged 'Entry\Invoke-VantaInstall.ps1') -Raw) | Should -Match "'Choices', 'Defaults', 'Vanta'"
        . (Join-Path $staged 'Install\Install-Plan.ps1')
        foreach ($mode in 'Fresh', 'Upgrade', 'Reapply', 'Rebase') {
            $keys = @(Get-VantaInstallPlan -Mode $mode | ForEach-Object { $_.Key })
            $keys | Should -Contain 'Vanta'
            $keys.IndexOf('Vanta') | Should -BeLessThan $keys.IndexOf('Checkpoint/WindowsTransition')
            $keys.IndexOf('Vanta') | Should -BeGreaterThan $keys.IndexOf('Tweaks/misc')
        }
        $fresh = @(Get-VantaInstallPlan -Mode Fresh | ForEach-Object { $_.Key })
        $fresh.IndexOf('Vanta') | Should -Be ($fresh.IndexOf('Tweak/scripts/set-power-settings') + 1)
    }
    It 'is idempotent' {
        $staged = New-StagedScripts
        Add-VantaHook -ScriptsRoot $staged
        $first = Get-Content (Join-Path $staged 'Install\Install-Plan.ps1') -Raw
        Add-VantaHook -ScriptsRoot $staged
        (Get-Content (Join-Path $staged 'Install\Install-Plan.ps1') -Raw) | Should -Be $first
    }
    It 'keeps both patched files valid PowerShell' {
        $staged = New-StagedScripts
        Add-VantaHook -ScriptsRoot $staged
        foreach ($rel in 'Entry\Invoke-VantaInstall.ps1', 'Install\Install-Plan.ps1', 'Tweaks\tweaks.manifest.psd1', 'Install\Invoke-VantaInstallSession.ps1') {
            $errors = $null
            [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $staged $rel), [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty
        }
    }
    It 'never edits the Vanta source tree in the repository' {
        (Get-Content (Join-Path $vantaScripts 'Install\Install-Plan.ps1') -Raw) | Should -Not -Match "Key = 'Vanta'"
        (Get-Content (Join-Path $vantaScripts 'Entry\Invoke-VantaInstall.ps1') -Raw) | Should -Not -Match "'Vanta'"
        # ADR-2v2: o Nathan liberou editar package/ (rebrand Vanta->Vanta); o gancho continua só na árvore de staging, como as duas linhas acima provam.
    }
    It 'moves the Vanta phishing tweak out of the plan so it only runs when the user ticks the option' {
        $staged = New-StagedScripts
        $before = Import-PowerShellDataFile (Join-Path $staged 'Tweaks\tweaks.manifest.psd1')
        Add-VantaHook -ScriptsRoot $staged
        $after = Import-PowerShellDataFile (Join-Path $staged 'Tweaks\tweaks.manifest.psd1')
        $slug = 'privacy/telemetry/disable-phishing-protection'
        $planned = @($after.Categories | ForEach-Object { $c = $_.Name; $_.Tweaks | ForEach-Object { "$c/$_" } })
        $planned | Should -Not -Contain $slug
        @($before.Categories | ForEach-Object { $c = $_.Name; $_.Tweaks | ForEach-Object { "$c/$_" } }) | Should -Contain $slug
        $entry = @($after.Disabled | Where-Object { $_.Slug -ceq $slug })
        $entry.Count | Should -Be 1
        $entry[0].Reason | Should -Not -BeNullOrEmpty
        @($after.Categories.Tweaks).Count | Should -Be (@($before.Categories.Tweaks).Count - 1)
        $after.Disabled.Count | Should -Be ($before.Disabled.Count + 1)
        # o motor do Vanta exige que o arquivo siga classificado: Disabled conta
        Test-Path (Join-Path $vantaScripts 'Tweaks\privacy\telemetry\disable-phishing-protection.psd1') | Should -BeTrue
    }
    It 'Test-VantaHookApplied is false on the Vanta source and true only after the hook' {
        $staged = New-StagedScripts
        Test-VantaHookApplied -ScriptsRoot $staged | Should -BeFalse
        Add-VantaHook -ScriptsRoot $staged
        Test-VantaHookApplied -ScriptsRoot $staged | Should -BeTrue
    }
    It 'fails when the block is duplicated' {
        $staged = New-StagedScripts
        Add-VantaHook -ScriptsRoot $staged
        $plan = Join-Path $staged 'Install\Install-Plan.ps1'
        $text = [IO.File]::ReadAllText($plan).Replace("`r`n", "`n")
        [IO.File]::WriteAllText($plan, $text.Replace($script:VantaPlanBlock, $script:VantaPlanBlock + $script:VantaPlanBlock))
        Test-VantaHookApplied -ScriptsRoot $staged | Should -BeFalse
        { Add-VantaHook -ScriptsRoot $staged } | Should -Throw '*Gancho Vanta*'
    }
    It 'fails when only a marker is there without the whole block (partial insertion)' {
        $staged = New-StagedScripts
        $install = Join-Path $staged 'Entry\Invoke-VantaInstall.ps1'
        $text = [IO.File]::ReadAllText($install)
        [IO.File]::WriteAllText($install, $text.Replace("'Choices', 'Defaults'", "'Choices', 'Defaults', 'Vanta'"))
        Test-VantaHookApplied -ScriptsRoot $staged | Should -BeFalse
        { Add-VantaHook -ScriptsRoot $staged } | Should -Throw '*Gancho Vanta*'
    }
    It 'fails when the Vanta step is out of position (after WindowsTransition)' {
        $staged = New-StagedScripts
        Add-VantaHook -ScriptsRoot $staged
        $plan = Join-Path $staged 'Install\Install-Plan.ps1'
        $text = [IO.File]::ReadAllText($plan).Replace("`r`n", "`n")
        $text = $text.Replace($script:VantaPlanBlock, '')
        $marker = "    )`n`n    foreach (`$step in `$steps) {"
        $text.Contains($marker) | Should -BeTrue
        [IO.File]::WriteAllText($plan, $text.Replace($marker, $script:VantaPlanBlock + $marker))
        (@(Get-VantaHookProblems -ScriptsRoot $staged) -join ' ') | Should -Match 'posição|depois de set-power-settings|logo depois'
    }
    It 'fails when the manifest block moved or changed' {
        $staged = New-StagedScripts
        $manifest = Join-Path $staged 'Tweaks\tweaks.manifest.psd1'
        [IO.File]::WriteAllText($manifest, [IO.File]::ReadAllText($manifest).Replace('Closing apps without a prompt can lose unsaved work.', 'outro texto'))
        { Add-VantaHook -ScriptsRoot $staged } | Should -Throw '*Gancho Vanta*'
    }
    It 'fails when an anchor is missing' {
        $staged = New-StagedScripts
        Set-Content (Join-Path $staged 'Install\Install-Plan.ps1') 'nada aqui'
        { Add-VantaHook -ScriptsRoot $staged } | Should -Throw '*Gancho Vanta*'
    }
}

Describe 'Keep my choices never replaces what the user asked for Defender and mitigations (finding B)' {
    BeforeAll {
        # Roda o trecho que o gancho insere, como ele fica no script do Vanta, com o que o Vanta dá por perto.
        function Invoke-KeptBlock {
            param([string[]]$Requested, [string[]]$FromMachine)
            $block = [scriptblock]::Create($script:VantaKeptBlock)
            $request = [pscustomobject]@{ Options = $Requested }
            $options = $FromMachine
            $groups = @()
            function Assert-VantaInstallOptionSet { param([string[]]$Options, $Groups) return @($Options) }
            . $block
            return @($options)
        }
    }
    It 'is part of the staged Vanta script exactly once, right after the machine-evidence merge' {
        $staged = New-StagedScripts
        Add-VantaHook -ScriptsRoot $staged
        $text = ([IO.File]::ReadAllText((Join-Path $staged 'Install\Invoke-VantaInstallSession.ps1'))).Replace("`r`n", "`n")
        $text.Contains($script:VantaKeptAnchor + $script:VantaKeptBlock) | Should -BeTrue
        $keep = $text.IndexOf('Resolve-VantaKeptOption -Requested', [StringComparison]::Ordinal)
        $block = $text.IndexOf('$vantaAsked =', [StringComparison]::Ordinal)
        $start = $text.IndexOf('Start-VantaInstallState', [StringComparison]::Ordinal)
        ($keep -ge 0 -and $block -gt $keep -and $start -gt $block) | Should -BeTrue
    }
    It 'a defender-enable request reaches the recorded options intact even if the machine shows Defender removed' {
        $out = Invoke-KeptBlock -Requested @('defender-enable', 'auto-updates-disable') -FromMachine @('defender-disable', 'auto-updates-disable')
        $out | Should -Contain 'defender-enable'
        $out | Should -Not -Contain 'defender-disable'
        $out | Should -Contain 'auto-updates-disable'
    }
    It 'mitigations-default survives a machine that shows the mitigations off' {
        $out = Invoke-KeptBlock -Requested @('mitigations-default') -FromMachine @('mitigations-disable', 'keyboard-single')
        $out | Should -Contain 'mitigations-default'
        $out | Should -Not -Contain 'mitigations-disable'
        $out | Should -Contain 'keyboard-single'
    }
    It 'a request that does not name the group leaves the machine reading alone' {
        $out = Invoke-KeptBlock -Requested @('keyboard-single') -FromMachine @('defender-enable', 'keyboard-single')
        $out | Should -Be @('defender-enable', 'keyboard-single')
    }
    It 'an explicit disable request is also kept exactly as asked' {
        $out = Invoke-KeptBlock -Requested @('defender-disable') -FromMachine @('defender-enable')
        $out | Should -Contain 'defender-disable'
        $out | Should -Not -Contain 'defender-enable'
    }
    It 'the phishing choice is not touched by the block' {
        $out = Invoke-KeptBlock -Requested @('defender-enable', 'disable-phishing-protection') -FromMachine @('defender-disable', 'disable-phishing-protection')
        $out | Should -Contain 'disable-phishing-protection'
    }
    It 'the hook fails when the block is missing from the final staging tree' {
        $staged = New-StagedScripts
        Add-VantaHook -ScriptsRoot $staged
        $session = Join-Path $staged 'Install\Invoke-VantaInstallSession.ps1'
        [IO.File]::WriteAllText($session, ([IO.File]::ReadAllText($session)).Replace($script:VantaKeptBlock, '').Replace($script:VantaKeptBlock.Replace("`n", "`r`n"), ''))
        (@(Get-VantaHookProblems -ScriptsRoot $staged) -join ' ') | Should -Match 'Defender e mitigações'
    }
}

Describe 'Choices in vanta.json' {
    BeforeAll {
        $script:ids = @($vanta.choices | ForEach-Object { $_.id })
        $script:allOptions = @($vanta.choices | ForEach-Object { $_.options } | ForEach-Object { $_.id })
    }
    It 'keeps Defender, mitigations and phishing protection on by default' {
        ($vanta.choices | Where-Object id -eq 'defender').default | Should -Be 'defender-enable'
        ($vanta.choices | Where-Object id -eq 'mitigations').default | Should -Be 'mitigations-default'
        $protections = $vanta.choices | Where-Object id -eq 'protections'
        $protections.kind | Should -Be 'multiple'
        $protections.options.id | Should -Contain 'disable-phishing-protection'
        $protections.options.id | Should -Contain 'disable-gamebar'
        $protections.PSObject.Properties.Name | Should -Not -Contain 'default'   # nada marcado de saída
    }
    It 'offers the optional Vanta 1 steps as unticked choices' {
        $extra = $vanta.choices | Where-Object id -eq 'vanta'
        $extra.kind | Should -Be 'multiple'
        $extra.options.id | Should -Be @('remove-store', 'vanta-power', 'vanta-memory', 'tools-on-logon')
    }
    It 'has unique choice and option ids' {
        $ids.Count | Should -Be (@($ids | Select-Object -Unique).Count)
        $allOptions.Count | Should -Be (@($allOptions | Select-Object -Unique).Count)
    }
    It 'every single choice defaults to one of its own options' {
        foreach ($choice in $vanta.choices | Where-Object kind -eq 'single') { $choice.options.id | Should -Contain $choice.default }
    }
    It 'the nathan preset does not force Defender, mitigations or phishing protection, and names real options' {
        $preset = $vanta.vanta.presets | Where-Object id -eq 'nathan'
        $preset.choices.PSObject.Properties.Name | Should -Not -Contain 'defender'
        $preset.choices.PSObject.Properties.Name | Should -Not -Contain 'mitigations'
        @($preset.choices.PSObject.Properties.Value) | Should -Not -Contain 'disable-phishing-protection'
        foreach ($property in $preset.choices.PSObject.Properties) {
            $choice = $vanta.choices | Where-Object id -eq $property.Name
            $choice | Should -Not -BeNullOrEmpty
            foreach ($option in @($property.Value)) { $choice.options.id | Should -Contain $option }
        }
    }
    It 'carries a real Tools version' {
        $vanta.vanta.toolsVersion | Should -Match '^\d+\.\d+\.\d+$'
        $vanta.vanta.toolsVersion | Should -Not -Be '0.0.0'
    }
    It 'every option id the phases read exists in the manifest' {
        $read = 'remove-store', 'vanta-power', 'vanta-memory', 'tools-on-logon', 'disable-phishing-protection', 'disable-gamebar'
        foreach ($id in $read) { $allOptions | Should -Contain $id }
        $phaseText = (Get-ChildItem (Join-Path $repo 'vanta\modules\Phases') -Filter *.ps1 | Get-Content -Raw) -join "`n"
        foreach ($id in $read) { $phaseText | Should -Match ([regex]::Escape("'$id'")) }
    }
}
