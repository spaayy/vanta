# Fase Vanta do plano de instalação (Key = 'Vanta'), depois de Tweak/scripts/set-power-settings.
# Fica em Install\Phases\ no pacote (o Build-VantaPackage a copia) e roda as fases de
# VantaModules\Vanta\Phases, uma por uma, como TrustedInstaller, no mesmo log do Vanta.
# Todas são idempotentes. Uma fase que falha não impede as outras; no fim, se alguma falhou, o erro sobe
# e o Vanta oferece tentar de novo.

Assert-VantaPrivilege -TrustedInstaller

$scriptsRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$vantaRoot = Join-Path -Path (Split-Path -Path $scriptsRoot -Parent) -ChildPath 'Vanta'
Import-Module -Name (Join-Path $scriptsRoot 'Modules\Vanta.Toggles\Vanta.Toggles.psd1') -Force -ErrorAction Stop

. (Join-Path $vantaRoot 'Phases\Common.ps1')
# Devices (config de hardware do PC do Nathan) e Perfil (o perfil dele) só vão no pacote PESSOAL; o público não leva os arquivos.
$hasDevices = Test-Path -LiteralPath (Join-Path $vantaRoot 'Phases\Devices.ps1') -PathType Leaf
$hasPerfil = Test-Path -LiteralPath (Join-Path $vantaRoot 'Personal\Perfil.ps1') -PathType Leaf
foreach ($name in 'Store', 'Tools', 'Licenses', 'Shortcuts', 'Power', 'Memory', 'Monitors', 'Protections') {
    . (Join-Path $vantaRoot "Phases\$name.ps1")
}
if ($hasDevices) { . (Join-Path $vantaRoot 'Phases\Devices.ps1') }
if ($hasPerfil) { . (Join-Path $vantaRoot 'Personal\Perfil.ps1') }

$context = Get-VantaContext
Write-VantaPhaseLog -Message "Fases Vanta: modo $($context.Mode), $(@($context.Options).Count) opção(ões)."

# Ordem: Tools antes dos atalhos; Protections depois dos tweaks do Vanta (que são o que ela desfaz).
$failed = @()
foreach ($step in @(
        @{ Name = 'Protections'; Run = { Invoke-VantaProtections -Context $context } }
        @{ Name = 'Store'; Run = { Invoke-VantaStore -Context $context } }
        @{ Name = 'Tools'; Run = { Invoke-VantaTools -Context $context } }
        @{ Name = 'Licenses'; Run = { Invoke-VantaLicenses -Context $context } }
        @{ Name = 'Shortcuts'; Run = { Invoke-VantaShortcuts -Context $context } }
        @{ Name = 'Power'; Run = { Invoke-VantaPower -Context $context } }
        @{ Name = 'Memory'; Run = { Invoke-VantaMemory -Context $context } }
        @{ Name = 'Devices'; Run = { Invoke-VantaDevices -Context $context } }
        @{ Name = 'Perfil'; Run = { Invoke-VantaPerfil -Context $context } }
        @{ Name = 'Monitors'; Run = { Invoke-VantaMonitors -Context $context } }
    )) {
    if (($step.Name -ceq 'Devices' -and -not $hasDevices) -or ($step.Name -ceq 'Perfil' -and -not $hasPerfil)) {
        Write-VantaPhaseLog -Message "Fase '$($step.Name)' não faz parte desta edição do pacote."
        continue
    }
    $skip = Get-VantaPhaseSkipReason -Name $step.Name -Failed $failed
    if ($skip) {
        $failed += "$($step.Name) (pulada)"
        Write-VantaPhaseLog -Level Warning -Message "Fase '$($step.Name)' pulada: $skip"
        continue
    }
    try { & $step.Run }
    catch {
        $failed += $step.Name
        Write-VantaPhaseLog -Level Warning -Message "Fase '$($step.Name)' falhou: $($_.Exception.Message)"
    }
}
if ($failed.Count -gt 0) { throw "As fases Vanta a seguir falharam: $($failed -join ', '). Veja o log." }
Write-VantaPhaseLog -Message 'Fases Vanta concluídas.'
