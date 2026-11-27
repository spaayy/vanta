# Fase Power: importa e ativa o plano de energia Vanta se o usuário escolheu 'vanta-power'.
# Só em PC sem bateria (o plano é de desktop na tomada; em notebook o Vanta 0.6.0 mantém o Equilibrado na bateria).
# Ordem segura: importa para um GUID NOVO, valida, só então ativa. O plano que estava ativo não é tocado até lá, e se
# algo falha só o plano que acabamos de importar é apagado. Só apagamos o plano cujo GUID a própria instalação registrou (o de uma instalação
# anterior que ESTA instalação registrou), e só depois de o novo estar ativo. Idempotente: se um plano Vanta já está ativo, não faz nada.

$script:VantaPlanName = 'Vanta'
$script:VantaGuidPattern = '[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'

$script:VantaPowerStateKey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Vanta'

function Get-VantaRecordedPlanGuid {
    <# O GUID do plano que a instalação anterior do Vanta importou e registrou ($null se nunca registrou). #>
    $item = Get-ItemProperty -LiteralPath $script:VantaPowerStateKey -Name PowerPlanGuid -ErrorAction SilentlyContinue
    $value = if ($null -ne $item) { [string]$item.PowerPlanGuid } else { '' }
    if ($value -match ('^' + $script:VantaGuidPattern + '$')) { return $value.ToLowerInvariant() }
    return $null
}

function Set-VantaRecordedPlanGuid {
    param([Parameter(Mandatory = $true)][string]$Guid)
    if (-not (Test-Path -LiteralPath $script:VantaPowerStateKey)) { $null = New-Item -Path $script:VantaPowerStateKey }
    New-ItemProperty -LiteralPath $script:VantaPowerStateKey -Name PowerPlanGuid -Value $Guid.ToLowerInvariant() -PropertyType String -Force | Out-Null
}

function Get-VantaPowerPlans {
    <# De `powercfg /list`: um objeto { Guid; Name } por plano (independe do idioma do Windows). #>
    $list = Invoke-VantaPhasePowerCfg -Arguments @('/list')
    foreach ($line in @($list.Output)) {
        if ([string]$line -match "($script:VantaGuidPattern)\s*\(([^)]*)\)") {
            [pscustomobject]@{ Guid = $Matches[1].ToLowerInvariant(); Name = $Matches[2].Trim() }
        }
    }
}

function Get-VantaActivePlanGuid {
    $active = Invoke-VantaPhasePowerCfg -Arguments @('/getactivescheme')
    if (($active.Output -join ' ') -match "($script:VantaGuidPattern)") { return $Matches[1].ToLowerInvariant() }
    return $null
}

function Get-VantaPlanTimeouts {
    <# Tempo (segundos) de AC e de bateria de um ajuste do plano, ou $null se a leitura falhar. As duas últimas linhas 0x........
       de `powercfg /query` são o valor atual em AC e em DC, em qualquer idioma. #>
    param([Parameter(Mandatory = $true)][string]$Guid, [Parameter(Mandatory = $true)][string]$SubGroup, [Parameter(Mandatory = $true)][string]$Setting)
    $query = Invoke-VantaPhasePowerCfg -Arguments @('/query', $Guid, $SubGroup, $Setting)
    $hex = @([regex]::Matches(($query.Output -join "`n"), '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
    if ($query.ExitCode -ne 0 -or $hex.Count -lt 2) { return $null }
    return [pscustomobject]@{ Ac = [Convert]::ToInt64($hex[$hex.Count - 2], 16); Dc = [Convert]::ToInt64($hex[$hex.Count - 1], 16) }
}

function Copy-VantaUserTimeouts {
    <# O plano importado traz tela e suspensão "Nunca" do PC de origem. Copia do plano que estava ativo os tempos de tela e de
       suspensão (AC e bateria) para o plano novo. NADA aqui é melhor esforço: falha de leitura, de qualquer das 4 gravações ou
       divergência na releitura LANÇA erro, e quem chama descarta o plano novo e mantém o anterior ativo. #>
    param([Parameter(Mandatory = $true)][string]$From, [Parameter(Mandatory = $true)][string]$To)
    $expected = [Collections.Generic.List[object]]::new()
    foreach ($setting in @(@('SUB_VIDEO', 'VIDEOIDLE'), @('SUB_SLEEP', 'STANDBYIDLE'))) {
        $original = Get-VantaPlanTimeouts -Guid $From -SubGroup $setting[0] -Setting $setting[1]
        if ($null -eq $original) { throw "não foi possível ler $($setting[1]) do plano atual" }
        foreach ($kind in @(@('/setacvalueindex', $original.Ac, 'Ac'), @('/setdcvalueindex', $original.Dc, 'Dc'))) {
            $write = Invoke-VantaPhasePowerCfg -Arguments @($kind[0], $To, $setting[0], $setting[1], [string]$kind[1])
            if ($write.ExitCode -ne 0) { throw "powercfg $($kind[0]) $($setting[1]) falhou (código $($write.ExitCode))" }
            $expected.Add([pscustomobject]@{ Sub = $setting[0]; Name = $setting[1]; Kind = $kind[2]; Value = [int64]$kind[1] })
        }
    }
    # releitura dos 4 valores antes de ativar: o que foi gravado tem de ser o que se esperava
    foreach ($item in $expected) {
        $now = Get-VantaPlanTimeouts -Guid $To -SubGroup $item.Sub -Setting $item.Name
        if ($null -eq $now -or [int64]$now.($item.Kind) -ne $item.Value) {
            throw "$($item.Name) ($($item.Kind)) divergiu na releitura (esperado $($item.Value))"
        }
    }
}

function Invoke-VantaPower {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [string]$PlanFile = (Join-Path (Get-VantaModulesRoot) 'Data\vanta-power.pow')
    )

    if (-not (Test-VantaPhaseOption -Context $Context -Id 'vanta-power')) {
        Write-VantaPhaseLog -Message 'Energia: plano do Vanta mantido (escolha do usuário).'
        return
    }
    if (Test-VantaBattery) {
        Write-VantaPhaseLog -Level Warning -Message 'Energia: este PC tem bateria; o plano Vanta é para desktop e não foi aplicado.'
        return
    }
    if (-not (Test-Path -LiteralPath $PlanFile -PathType Leaf)) {
        throw "Energia: o arquivo do plano '$PlanFile' não existe."
    }

    $plans = @(Get-VantaPowerPlans)
    $active = Get-VantaActivePlanGuid
    $vantaPlans = @($plans | Where-Object { $_.Name -ceq $script:VantaPlanName })
    $recorded = Get-VantaRecordedPlanGuid
    # só vale como "já ativo" o plano com o nome Vanta E o GUID que a própria instalação registrou
    if ($active -and $recorded -and $active -eq $recorded -and ($vantaPlans | Where-Object { $_.Guid -eq $active })) {
        Write-VantaPhaseLog -Message 'Energia: o plano Vanta já está ativo.'
        return
    }

    # 1. importa para um GUID novo e valida; o plano atual continua intacto
    $new = [guid]::NewGuid().ToString()
    $import = Invoke-VantaPhasePowerCfg -Arguments @('/import', $PlanFile, $new)
    if ($import.ExitCode -ne 0) { throw "Energia: powercfg /import falhou (código $($import.ExitCode)): $($import.Output -join ' ')" }
    $valid = Invoke-VantaPhasePowerCfg -Arguments @('/query', $new)
    $named = Invoke-VantaPhasePowerCfg -Arguments @('/changename', $new, $script:VantaPlanName, 'Plano de energia do Vanta')
    if ($valid.ExitCode -ne 0 -or $named.ExitCode -ne 0) {
        $null = Invoke-VantaPhasePowerCfg -Arguments @('/delete', $new)   # só o que acabamos de importar
        throw "Energia: o plano importado não passou na validação (query $($valid.ExitCode), changename $($named.ExitCode)); nada foi trocado."
    }
    # 1b. tela e suspensão do usuário não são zeradas pelo arquivo do plano
    try {
        if (-not $active) { throw 'o plano ativo não pôde ser identificado' }
        Copy-VantaUserTimeouts -From $active -To $new
    }
    catch {
        $null = Invoke-VantaPhasePowerCfg -Arguments @('/delete', $new)   # só o que acabamos de importar
        throw "Energia: os tempos de tela e suspensão do usuário não foram preservados ($($_.Exception.Message)); o plano anterior continua ativo."
    }
    # 2. ativa; se falhar, descarta o novo e deixa tudo como estava
    $set = Invoke-VantaPhasePowerCfg -Arguments @('/setactive', $new)
    if ($set.ExitCode -ne 0) {
        $null = Invoke-VantaPhasePowerCfg -Arguments @('/delete', $new)
        throw "Energia: powercfg /setactive falhou (código $($set.ExitCode)); o plano anterior continua ativo."
    }
    # 3. só agora apaga o plano antigo que ESTA instalação registrou (nunca o ativo, nunca um plano com o mesmo nome criado
    #    ou personalizado pelo usuário, nunca um GUID que o Vanta não registrou)
    $recorded = Get-VantaRecordedPlanGuid
    if ($recorded -and $recorded -ne $new -and ($vantaPlans | Where-Object { $_.Guid -eq $recorded })) {
        $null = Invoke-VantaPhasePowerCfg -Arguments @('/delete', $recorded)
    }
    Set-VantaRecordedPlanGuid -Guid $new
    Write-VantaPhaseLog -Message "Energia: plano Vanta importado, validado e ativo ($new)."
}
