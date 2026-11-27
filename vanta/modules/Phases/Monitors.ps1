# Fase Monitors: agenda, no próximo logon do usuário que instalou, o script que põe cada monitor na taxa máxima
# da resolução atual (detectada no destino; nunca os Hz do PC de origem). Não roda aqui: esta fase executa como
# TrustedInstaller, sem sessão gráfica e talvez antes do driver da placa de vídeo. Só em Fresh e Rebase, para não
# trocar a taxa que o usuário já escolheu numa atualização. O mesmo script pode ser chamado pelo Vanta Tools depois do driver.

function Invoke-VantaMonitors {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    if ([string]$Context.Mode -notin @('Fresh', 'Rebase')) {
        Write-VantaPhaseLog -Message "Monitores: ignorado no modo $($Context.Mode)."
        return
    }
    $script = Join-Path ([string]$Context.WinDir) 'VantaModules\Vanta\Scripts\Set-VantaMaxRefresh.ps1'
    $powerShell = Join-Path ([string]$Context.WinDir) 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $command = '"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f $powerShell, $script
    if (Set-VantaUserRunOnce -Sid ([string]$Context.InteractiveUserSid) -Name 'VantaMonitors' -Command $command) {
        Write-VantaPhaseLog -Message 'Monitores: taxa máxima será aplicada no próximo logon.'
    }
}
