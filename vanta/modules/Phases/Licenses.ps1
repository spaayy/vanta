# Fase Licenses: grava os avisos de licença em C:\Vanta\Licenses (LICENSE, NOTICE, THIRD-PARTY-NOTICES.txt, Geist-OFL.txt e o
# inventário dos binários do pacote), com o SHA-256 de cada arquivo conferido. Só administradores e o sistema escrevem ali.

function Get-VantaLicensesRoot {
    param([string]$SystemDrive = $env:SystemDrive)
    if ([string]::IsNullOrWhiteSpace($SystemDrive)) { $SystemDrive = 'C:' }
    return (Join-Path -Path $SystemDrive -ChildPath 'Vanta\Licenses')
}

function Invoke-VantaLicenses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [string]$Source = (Join-Path (Get-VantaModulesRoot) 'Licenses'),
        [string]$Destination = (Get-VantaLicensesRoot)
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Licenses: a pasta de origem '$Source' não existe." }
    $files = @(Get-ChildItem -LiteralPath $Source -File)
    foreach ($required in 'LICENSE', 'NOTICE', 'THIRD-PARTY-NOTICES.txt', 'Geist-OFL.txt', 'BINARY-INVENTORY.md') {
        if ($files.Name -cnotcontains $required) { throw "Licenses: o pacote não traz '$required'." }
    }
    $parent = Split-Path -Path $Destination -Parent
    Assert-VantaTrustedFolder -Path $parent -What 'Licenses: pasta pai'
    Assert-VantaTrustedFolder -Path $Destination -What 'Licenses: destino'
    $null = New-Item -ItemType Directory -Force -Path $Destination
    Protect-VantaFolder -Path $Destination
    foreach ($file in $files) {
        $target = Join-Path -Path $Destination -ChildPath $file.Name
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        $want = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $got = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($want -ne $got) { throw "Licenses: '$($file.Name)' foi copiado com SHA-256 diferente (origem $want, destino $got)." }
    }
    Write-VantaPhaseLog -Message ("Licenses: {0} arquivo(s) em {1}, SHA-256 conferido." -f $files.Count, $Destination)
}
