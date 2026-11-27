# Fase Protections: duas escolhas do usuário que o Vanta decide sozinho.
#  - Proteção contra phishing (SmartScreen avançado): o ajuste do Vanta que a desliga fica FORA do plano (o gancho do
#    build o move para Disabled no manifesto). Aqui ele só é aplicado quando o usuário marca
#    'disable-phishing-protection', em Fresh, Upgrade, Reapply e retomada. Sem a opção nada é gravado nem removido
#    nessas políticas (não conhecemos a origem de um valor que já exista).
#  - Game Bar e captura (toggle FSOGameBar do Vanta): padrão manter. Com 'disable-gamebar', desliga pelo toggle do Vanta;
#    sem a opção, só desfaz um Disable que o próprio Vanta registrou.
# Defender e mitigações já são escolhas do Vanta (defender, mitigations). Como um "desligado" do state.json antigo não
# prova quem o escolheu, esta fase grava em HKLM\SOFTWARE\Vanta (ChosenProtections, REG_MULTI_SZ) quais desligamentos
# o USUÁRIO confirmou nesta instalação; o Manager só os trata como escolha se estiverem aqui (senão pergunta, padrão seguro).

$script:VantaPhishingKey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WTDS\Components'
# Os mesmos dois valores do ajuste privacy/telemetry/disable-phishing-protection do Vanta.
$script:VantaPhishingValues = [ordered]@{ ServiceEnabled = 0; CaptureThreatWindow = 0 }

function Set-VantaPolicyValue {
    # Ponto único de escrita da política (os testes fazem mock aqui).
    param([Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][int]$Value)
    if (-not (Test-Path -LiteralPath $Key)) { $null = New-Item -Path $Key -Force }
    New-ItemProperty -LiteralPath $Key -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

$script:VantaChosenProtectionIds = @('defender-disable', 'mitigations-disable')

function Set-VantaChosenProtections {
    # Ponto único de escrita da prova de escolha (os testes fazem mock aqui).
    param([string[]]$Ids = @())
    $key = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Vanta'
    if (-not (Test-Path -LiteralPath $key)) { $null = New-Item -Path $key -Force }
    New-ItemProperty -LiteralPath $key -Name ChosenProtections -PropertyType MultiString -Value @($Ids) -Force | Out-Null
}

function Invoke-VantaProtections {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    # Rebase repõe escolhas antigas sem o usuário confirmá-las de novo: não renova a prova.
    if ($Context.Mode -ne 'Rebase') {
        $chosen = @($script:VantaChosenProtectionIds | Where-Object { Test-VantaPhaseOption -Context $Context -Id $_ })
        Set-VantaChosenProtections -Ids $chosen
        Write-VantaPhaseLog -Message ('Proteções: escolhas registradas como do usuário: ' + $(if ($chosen.Count) { $chosen -join ', ' } else { 'nenhuma' }))
    }

    if (Test-VantaPhaseOption -Context $Context -Id 'disable-phishing-protection') {
        foreach ($name in $script:VantaPhishingValues.Keys) {
            Set-VantaPolicyValue -Key $script:VantaPhishingKey -Name $name -Value $script:VantaPhishingValues[$name]
        }
        Write-VantaPhaseLog -Message 'Phishing: proteção desligada (escolha do usuário).'
    }
    else {
        Write-VantaPhaseLog -Message 'Phishing: proteção mantida; nenhuma política foi gravada ou removida.'
    }

    if (Test-VantaPhaseOption -Context $Context -Id 'disable-gamebar') {
        Invoke-VantaToggleMachineState -Name 'FSOGameBar' -State 'Disable'
        Write-VantaPhaseLog -Message 'Game Bar: desligada (escolha do usuário).'
    }
    else {
        $recorded = Get-VantaToggleState -Name 'FSOGameBar'
        if ($null -ne $recorded -and $null -ne $recorded.State -and [int]$recorded.State -eq 0) {
            Invoke-VantaToggleMachineState -Name 'FSOGameBar' -State 'Enable'
            Write-VantaPhaseLog -Message 'Game Bar: religada (o Vanta a tinha desligado e o usuário quer mantê-la).'
        }
        else {
            Write-VantaPhaseLog -Message 'Game Bar: mantida.'
        }
    }
}
