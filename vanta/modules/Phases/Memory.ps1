# Fase Memory: perfil de memória do Vanta, só se o usuário escolheu 'vanta-memory'.
# Compressão ligada, PageCombining e ApplicationPreLaunch desligados. O arquivo de paginação continua gerenciado
# pelo sistema (não é alterado). Ganho de FPS/latência não verificado.
# Falha parcial é falha da fase: o erro lista os ajustes PENDENTES pelo nome. É retomável: ao rodar de novo, só os
# ajustes que ainda não estão como o perfil pede são aplicados.

function Get-VantaMemoryState {
    # Estado atual do MMAgent (os testes fazem mock aqui).
    $agent = Get-MMAgent
    return [pscustomobject]@{
        MemoryCompression    = [bool]$agent.MemoryCompression
        PageCombining        = [bool]$agent.PageCombining
        ApplicationPreLaunch = [bool]$agent.ApplicationPreLaunch
    }
}

function Invoke-VantaMemory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    if (-not (Test-VantaPhaseOption -Context $Context -Id 'vanta-memory')) {
        Write-VantaPhaseLog -Message 'Memória: ajustes do Windows mantidos (escolha do usuário).'
        return
    }
    $state = Get-VantaMemoryState
    $steps = @(
        @{ Name = 'compressão ligada'; Done = $state.MemoryCompression; Apply = { Enable-MMAgent -MemoryCompression -ErrorAction Stop } }
        @{ Name = 'PageCombining desligado'; Done = (-not $state.PageCombining); Apply = { Disable-MMAgent -PageCombining -ErrorAction Stop } }
        @{ Name = 'ApplicationPreLaunch desligado'; Done = (-not $state.ApplicationPreLaunch); Apply = { Disable-MMAgent -ApplicationPreLaunch -ErrorAction Stop } }
    )
    $pending = New-Object Collections.Generic.List[string]
    foreach ($step in $steps) {
        if ($step.Done) { Write-VantaPhaseLog -Message "Memória: $($step.Name) (já estava)."; continue }
        try { & $step.Apply; Write-VantaPhaseLog -Message "Memória: $($step.Name)." }
        catch {
            $pending.Add($step.Name)
            Write-VantaPhaseLog -Level Warning -Message "Memória: '$($step.Name)' falhou: $($_.Exception.Message)"
        }
    }
    if ($pending.Count -gt 0) {
        throw "Memória: ajustes pendentes (rode de novo para retomar): $($pending -join '; ')."
    }
}
