# Fase Shortcuts: atalhos do Vanta Tools (Desktop e Iniciar) e RunOnce, no usuário que instalou (não no SYSTEM).
# Só age se o vanta-tools.exe existir. O RunOnce (abrir o Tools no primeiro logon) é escolha: 'tools-on-logon'.

function Invoke-VantaShortcuts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [string]$ToolsRoot = (Get-VantaToolsRoot),
        [string]$PackageToolsRoot = (Join-Path (Get-VantaModulesRoot) 'Tools')
    )

    $exe = Join-Path -Path $ToolsRoot -ChildPath 'vanta-tools.exe'
    # Pessoal -> Pública: uma tarefa 2B de antes ainda abriria o Tools sem UAC; a pública nunca a mantém. Só a tarefa do
    # Vanta é removida; colisão ou qualquer erro do agendador interrompe a fase (sem "talvez tenha sumido").
    if ((Get-VantaEdition) -ceq 'publico') {
        try { if (Remove-VantaToolsTask -Exe $exe -Sid ([string]$Context.InteractiveUserSid)) { Write-VantaPhaseLog -Message 'Atalhos: tarefa elevada \Vanta\VantaTools de uma instalação anterior removida (edição pública).' } }
        catch { throw "Atalhos: a tarefa elevada \Vanta\VantaTools não pôde ser removida ($($_.Exception.Message)); a edição pública não pode deixá-la." }
    }
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        Write-VantaPhaseLog -Level Warning -Message 'Atalhos: vanta-tools.exe ainda não existe; atalhos e RunOnce não criados.'
        return
    }
    # Só confia no executável desta entrega: o hash esperado vem do PACOTE (tools.sha256 e vanta-tools.exe da pasta de
    # origem, que o build gravou), nunca do tools.sha256 ao lado do executável no destino. O destino tem de bater com ele.
    $sums = Join-Path -Path $PackageToolsRoot -ChildPath 'tools.sha256'
    $expected = if (Test-Path -LiteralPath $sums -PathType Leaf) {
        @(Get-Content -LiteralPath $sums | Where-Object { $_ -match '^[0-9a-fA-F]{64}\s+\*?vanta-tools\.exe\s*$' } | ForEach-Object { ($_ -split '\s+')[0] })[0]
    }
    $packageExe = Join-Path -Path $PackageToolsRoot -ChildPath 'vanta-tools.exe'
    $packageOk = $expected -and (Test-Path -LiteralPath $packageExe -PathType Leaf) -and ((Get-FileHash -LiteralPath $packageExe -Algorithm SHA256).Hash -eq $expected)
    if (-not $packageOk -or (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $expected) {
        Write-VantaPhaseLog -Level Warning -Message 'Atalhos: vanta-tools.exe não confere com o hash do pacote; atalhos e RunOnce não criados.'
        return
    }
    $sid = [string]$Context.InteractiveUserSid
    $profilePath = Get-VantaUserProfile -Sid $sid
    if (-not $profilePath) {
        Write-VantaPhaseLog -Level Warning -Message "Atalhos: perfil do usuário '$sid' não encontrado; nada criado."
        return
    }

    $desktop = Get-VantaUserShellFolder -Sid $sid -Name Desktop -ProfilePath $profilePath
    $programs = Get-VantaUserShellFolder -Sid $sid -Name Programs -ProfilePath $profilePath
    # Modelo 2B: a tarefa agendada elevada abre o Tools sem pedir UAC. Se não der para registrar/conferir, o atalho aponta
    # direto para o exe (o manifesto requireAdministrator pede o UAC ao abrir).
    # Só a edição pessoal (o PC do Nathan) ganha a tarefa; a pública fica sem nada rodando elevado: o Tools pede o UAC a cada abertura.
    $useTask = $false
    if ((Get-VantaEdition) -ceq 'pessoal') {
        try {
            Register-VantaToolsTask -Exe $exe -Sid $sid
            $useTask = Test-VantaToolsTask -Exe $exe
        }
        catch { Write-VantaPhaseLog -Level Warning -Message "Atalhos: tarefa elevada \Vanta\VantaTools não registrada ($($_.Exception.Message)); o atalho abre o exe direto." }
    }
    else { Write-VantaPhaseLog -Message 'Atalhos: edição pública, sem tarefa elevada; o Tools pede permissão a cada abertura.' }
    if ($useTask) { Write-VantaPhaseLog -Message 'Atalhos: tarefa elevada \Vanta\VantaTools registrada; o atalho a dispara.' }
    $made = 0
    foreach ($folder in @(@('Desktop', $desktop), @('Iniciar', $programs))) {
        if (-not $folder[1]) {
            Write-VantaPhaseLog -Level Warning -Message "Atalhos: não foi possível resolver a pasta '$($folder[0])' do usuário (hive não carregado ou variável sem valor); atalho omitido."
            continue
        }
        if ($useTask) {
            # Dispara a tarefa elevada (sem UAC a cada abertura); janela minimizada, sem foco.
            New-VantaPhaseShortcut -Path (Join-Path $folder[1] 'Vanta Tools.lnk') -Target "$env:SystemRoot\System32\schtasks.exe" -Arguments '/run /tn "\Vanta\VantaTools"' -WorkingDirectory $ToolsRoot -IconLocation "$exe,0" -WindowStyle 7
        }
        else {
            New-VantaPhaseShortcut -Path (Join-Path $folder[1] 'Vanta Tools.lnk') -Target $exe -WorkingDirectory $ToolsRoot
        }
        $made++
    }
    Write-VantaPhaseLog -Message "Atalhos: $made criado(s) para $profilePath."

    if (Test-VantaPhaseOption -Context $Context -Id 'tools-on-logon') {
        if (Set-VantaUserRunOnce -Sid $sid -Name 'VantaTools' -Command $(if ($useTask) { '"{0}\System32\schtasks.exe" /run /tn "\Vanta\VantaTools"' -f $env:SystemRoot } else { '"{0}"' -f $exe })) {
            Write-VantaPhaseLog -Message 'Atalhos: o Vanta Tools abre no próximo logon (RunOnce).'
        }
    }
}
