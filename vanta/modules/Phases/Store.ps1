# Fase Store: remove a Microsoft Store se o usuário escolheu 'remove-store', escopo por escopo, e só onde o winget
# (App Installer) continua garantido:
#  - Usuário interativo: o App Installer precisa estar INSTALADO para o SID dele. Senão a Store fica em todo lugar.
#  - Provisionamento (contas futuras): a Store provisionada só sai se o App Installer também está provisionado.
#  - Outras contas: a Store só sai da conta que também tem o App Installer instalado.
# Idempotente: sem Store, só registra e segue.

function Get-VantaAppxUsers {
    <# Quem tem o pacote INSTALADO: [pscustomobject]@{ Sid; Package } por conta (os testes fazem mock aqui). #>
    param([Parameter(Mandatory = $true)][string]$Name)
    foreach ($package in @(Get-AppxPackage -AllUsers -Name $Name -ErrorAction SilentlyContinue)) {
        foreach ($info in @($package.PackageUserInformation)) {
            if ("$($info.InstallState)" -eq 'Installed') {
                [pscustomobject]@{ Sid = [string]$info.UserSecurityId.Sid; Package = [string]$package.PackageFullName }
            }
        }
    }
}

function Test-VantaAppxProvisioned {
    param([Parameter(Mandatory = $true)][string]$DisplayName)
    return (@(Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $DisplayName }).Count -gt 0)
}

function Invoke-VantaStore {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    if (-not (Test-VantaPhaseOption -Context $Context -Id 'remove-store')) {
        Write-VantaPhaseLog -Message 'Store: mantida (escolha do usuário).'
        return
    }
    $sid = [string]$Context.InteractiveUserSid
    $installerSids = @(Get-VantaAppxUsers -Name 'Microsoft.DesktopAppInstaller' | ForEach-Object { $_.Sid })
    if ($installerSids -notcontains $sid) {
        Write-VantaPhaseLog -Level Warning -Message "Store: o App Installer (winget) não está instalado para o usuário $sid; a Store foi mantida em todos os escopos."
        return
    }

    $removed = 0
    # 1. provisionamento (contas novas)
    if (Test-VantaAppxProvisioned -DisplayName 'Microsoft.DesktopAppInstaller') {
        foreach ($package in @(Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq 'Microsoft.WindowsStore' })) {
            Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName | Out-Null
            $removed++
        }
    }
    else {
        Write-VantaPhaseLog -Level Warning -Message 'Store: o App Installer não está provisionado para contas novas; a Store provisionada foi mantida.'
    }
    # 2. contas que já existem: só onde o App Installer também está instalado
    foreach ($entry in @(Get-VantaAppxUsers -Name 'Microsoft.WindowsStore')) {
        if ($installerSids -contains $entry.Sid) {
            Remove-AppxPackage -Package $entry.Package -User $entry.Sid
            $removed++
        }
        else {
            Write-VantaPhaseLog -Level Warning -Message "Store: a conta $($entry.Sid) não tem o App Installer; a Store dela foi mantida."
        }
    }
    if ($removed -gt 0) { Write-VantaPhaseLog -Message "Store: removida ($removed escopo(s)); App Installer mantido." }
    else { Write-VantaPhaseLog -Message 'Store: já estava removida (ou mantida pelas regras acima).' }
}
