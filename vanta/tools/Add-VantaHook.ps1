# Gancho das fases Vanta no orquestrador do Vanta (ADR-2: o fonte de package/ não é editado).
# O Build-VantaPackage aplica estas trocas de texto na ÁRVORE DE STAGING, nunca no repositório:
#   1. Entry\Invoke-VantaInstall.ps1: 'Vanta' entra na lista de fases conhecidas ($phaseTargets).
#   2. Install\Install-Plan.ps1: passo Key='Vanta' (todos os modos) logo depois de Tweak/scripts/set-power-settings,
#      isto é, depois de todos os tweaks do Vanta e antes de WindowsTransition.
#   3. Tweaks\tweaks.manifest.psd1: o ajuste de phishing do Vanta sai de 'privacy' e vai para 'Disabled'. Sem isso o
#      Vanta o grava em toda instalação, antes de qualquer escolha. A fase Protections o aplica só com a opção marcada.
#   4. Install\Invoke-VantaInstallSession.ps1: com 'manter as escolhas' o Vanta troca as opções pedidas pelo que a máquina mostra;
#      o Vanta devolve o que o usuário pediu para Defender e mitigações (a escolha do usuário vai para o estado gravado e
#      para a retomada, mesmo que a máquina indique desligado).
# Cada troca exige o trecho esperado exatamente uma vez. Depois de aplicar, Test-VantaHookApplied confere o BLOCO
# INTEIRO, único e na posição esperada; senão o build falha. O build repete a conferência no pacote final.

$script:VantaPhishingSlug = 'privacy/telemetry/disable-phishing-protection'
$script:VantaPlanBlock = "        [pscustomobject][ordered]@{`n            # Fases Vanta (vanta/modules): depois de todos os tweaks do Vanta, que algumas desfazem por escolha.`n            Key = 'Vanta'; Modes = `$allModes`n            Replay = 'Once'`n        }`n"
$script:VantaPlanAnchor = "            Key = 'Tweak/scripts/set-power-settings'; Modes = @('Fresh')`n            Replay = 'Once'`n        }`n"
$script:VantaPhaseList = "'Services', 'Components', 'AppxSupport', 'Choices', 'Defaults', 'Vanta'"
$script:VantaDisabledEntry = "        @{ Slug = '$script:VantaPhishingSlug'; Reason = 'Vanta applies it only when the user ticks Turn off Enhanced Phishing Protection (Phases\Protections.ps1).' }`n"
$script:VantaManifestCategoryLines = "                'telemetry/disable-input-telemetry'`n                'telemetry/disable-phishing-protection'`n                'telemetry/disallow-data-collection'`n"
$script:VantaManifestCategoryFixed = "                'telemetry/disable-input-telemetry'`n                'telemetry/disallow-data-collection'`n"
$script:VantaKeptAnchor = '        $options = Assert-VantaInstallOptionSet -Options @($kept.Options) -Groups $groups' + "`n"
$script:VantaKeptBlock = ('        # Vanta: ''manter'' nunca troca o que o usuário pediu para Defender e mitigações pelo que a máquina mostra.' + "`n" +
    '        $vantaAsked = @($request.Options | Where-Object { $_ -cmatch ''^(defender|mitigations)-'' })' + "`n" +
    '        if ($vantaAsked.Count -gt 0) { $options = Assert-VantaInstallOptionSet -Options @(@($options | Where-Object { $_ -cnotmatch ''^(defender|mitigations)-'' }) + $vantaAsked) -Groups $groups }' + "`n")
$script:VantaManifestTail = "        @{ Slug = 'qol/startup-shutdown/force-end-shutdown-apps'; Reason = 'Closing apps without a prompt can lose unsaved work.' }`n    )`n}"

function Read-VantaText {
    param([string]$Path)
    $raw = [IO.File]::ReadAllText($Path)
    $head = [IO.File]::ReadAllBytes($Path) | Select-Object -First 3
    return [pscustomobject]@{
        Text = ($raw -replace "`r`n", "`n")
        Crlf = $raw.Contains("`r`n")
        Bom  = (($head -join ',') -eq '239,187,191')
    }
}

function Write-VantaText {
    param([string]$Path, $Doc, [string]$Text)
    if ($Doc.Crlf) { $Text = $Text -replace "`n", "`r`n" }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($Doc.Bom)))
}

function Get-VantaCount {
    param([string]$Text, [string]$Needle)
    if ([string]::IsNullOrEmpty($Needle)) { return 0 }
    $count = 0; $at = 0
    while (($at = $Text.IndexOf($Needle, $at, [StringComparison]::Ordinal)) -ge 0) { $count++; $at += $Needle.Length }
    return $count
}

function Get-VantaHookPaths {
    param([string]$ScriptsRoot)
    return [pscustomobject]@{
        Install  = Join-Path $ScriptsRoot 'Entry\Invoke-VantaInstall.ps1'
        Plan     = Join-Path $ScriptsRoot 'Install\Install-Plan.ps1'
        Manifest = Join-Path $ScriptsRoot 'Tweaks\tweaks.manifest.psd1'
        Session  = Join-Path $ScriptsRoot 'Install\Invoke-VantaInstallSession.ps1'
    }
}

function Get-VantaHookProblems {
    <# Lista o que está errado no estado atual das 3 árvores (vazia = gancho aplicado inteiro, único e no lugar). #>
    param([Parameter(Mandatory = $true)][string]$ScriptsRoot)
    $paths = Get-VantaHookPaths -ScriptsRoot $ScriptsRoot
    $problems = New-Object Collections.Generic.List[string]

    $install = (Read-VantaText $paths.Install).Text
    if ((Get-VantaCount $install $script:VantaPhaseList) -ne 1) { $problems.Add('Invoke-VantaInstall.ps1: a lista de fases com Vanta deve aparecer exatamente uma vez.') }
    if ((Get-VantaCount $install "'Vanta'") -ne 1) { $problems.Add("Invoke-VantaInstall.ps1: 'Vanta' deve aparecer exatamente uma vez.") }

    $plan = (Read-VantaText $paths.Plan).Text
    if ((Get-VantaCount $plan ($script:VantaPlanAnchor + $script:VantaPlanBlock)) -ne 1) { $problems.Add('Install-Plan.ps1: o bloco Vanta deve aparecer exatamente uma vez, logo depois de Tweak/scripts/set-power-settings.') }
    if ((Get-VantaCount $plan "Key = 'Vanta'") -ne 1) { $problems.Add("Install-Plan.ps1: Key = 'Vanta' deve aparecer exatamente uma vez.") }
    $power = $plan.IndexOf("Key = 'Tweak/scripts/set-power-settings'", [StringComparison]::Ordinal)
    $vanta = $plan.IndexOf("Key = 'Vanta'", [StringComparison]::Ordinal)
    $transition = $plan.IndexOf("Key = 'Checkpoint/WindowsTransition'", [StringComparison]::Ordinal)
    if (-not ($power -ge 0 -and $vanta -gt $power -and $transition -gt $vanta)) { $problems.Add('Install-Plan.ps1: Vanta deve ficar depois de set-power-settings e antes de WindowsTransition.') }

    $manifest = (Read-VantaText $paths.Manifest).Text
    $disabledAt = $manifest.IndexOf('Disabled = @(', [StringComparison]::Ordinal)
    if ($disabledAt -lt 0) { $problems.Add('tweaks.manifest.psd1: a lista Disabled não foi achada.') }
    else {
        $categories = $manifest.Substring(0, $disabledAt)
        $disabled = $manifest.Substring($disabledAt)
        if ((Get-VantaCount $categories 'disable-phishing-protection') -ne 0) { $problems.Add('tweaks.manifest.psd1: o ajuste de phishing ainda está em Categories.') }
        if ((Get-VantaCount $disabled $script:VantaDisabledEntry) -ne 1) { $problems.Add('tweaks.manifest.psd1: a entrada Disabled do phishing deve aparecer exatamente uma vez.') }
    }
    $session = (Read-VantaText $paths.Session).Text
    if ((Get-VantaCount $session ($script:VantaKeptAnchor + $script:VantaKeptBlock)) -ne 1) { $problems.Add('Invoke-VantaInstallSession.ps1: o bloco que preserva a escolha de Defender e mitigações deve aparecer exatamente uma vez, logo depois de Resolve-VantaKeptOption.') }
    return $problems.ToArray()
}

function Test-VantaHookApplied {
    param([Parameter(Mandatory = $true)][string]$ScriptsRoot)
    return (@(Get-VantaHookProblems -ScriptsRoot $ScriptsRoot).Count -eq 0)
}

function Add-VantaHook {
    param([Parameter(Mandatory = $true)][string]$ScriptsRoot)

    if (Test-VantaHookApplied -ScriptsRoot $ScriptsRoot) { return }   # idempotente: só se o bloco inteiro já está no lugar
    $paths = Get-VantaHookPaths -ScriptsRoot $ScriptsRoot
    $pending = @()

    $install = Read-VantaText $paths.Install
    $phaseAnchor = "'Services', 'Components', 'AppxSupport', 'Choices', 'Defaults'"
    if ((Get-VantaCount $install.Text $phaseAnchor) -ne 1 -or (Get-VantaCount $install.Text "'Vanta'") -ne 0) { throw "Gancho Vanta: a lista de fases não está como o esperado em '$($paths.Install)'. O Vanta mudou? Ajuste Add-VantaHook.ps1." }
    $pending += , @($paths.Install, $install, $install.Text.Replace($phaseAnchor, $script:VantaPhaseList))

    $plan = Read-VantaText $paths.Plan
    if ((Get-VantaCount $plan.Text $script:VantaPlanAnchor) -ne 1 -or (Get-VantaCount $plan.Text "Key = 'Vanta'") -ne 0) { throw "Gancho Vanta: o trecho set-power-settings não existe exatamente uma vez em '$($paths.Plan)'. O Vanta mudou? Ajuste Add-VantaHook.ps1." }
    $pending += , @($paths.Plan, $plan, $plan.Text.Replace($script:VantaPlanAnchor, $script:VantaPlanAnchor + $script:VantaPlanBlock))

    $manifest = Read-VantaText $paths.Manifest
    if ((Get-VantaCount $manifest.Text $script:VantaManifestCategoryLines) -ne 1 -or (Get-VantaCount $manifest.Text $script:VantaManifestTail) -ne 1) { throw "Gancho Vanta: o manifesto de tweaks não está como o esperado em '$($paths.Manifest)'. O Vanta mudou? Ajuste Add-VantaHook.ps1." }
    $edited = $manifest.Text.Replace($script:VantaManifestCategoryLines, $script:VantaManifestCategoryFixed)
    $edited = $edited.Replace($script:VantaManifestTail, $script:VantaManifestTail.Replace("`n    )`n}", "`n" + $script:VantaDisabledEntry + "    )`n}"))
    $pending += , @($paths.Manifest, $manifest, $edited)

    $session = Read-VantaText $paths.Session
    if ((Get-VantaCount $session.Text $script:VantaKeptAnchor) -ne 1 -or (Get-VantaCount $session.Text 'vantaAsked') -ne 0) { throw "Gancho Vanta: o trecho de 'manter as escolhas' não está como o esperado em '$($paths.Session)'. O Vanta mudou? Ajuste Add-VantaHook.ps1." }
    $pending += , @($paths.Session, $session, $session.Text.Replace($script:VantaKeptAnchor, $script:VantaKeptAnchor + $script:VantaKeptBlock))

    foreach ($item in $pending) { Write-VantaText -Path $item[0] -Doc $item[1] -Text $item[2] }
    $problems = @(Get-VantaHookProblems -ScriptsRoot $ScriptsRoot)
    if ($problems.Count -gt 0) { throw ("Gancho Vanta: o resultado não passou na conferência:`n - " + ($problems -join "`n - ")) }
}
