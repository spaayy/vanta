# Fase Tools: copia o Vanta Tools para C:\Vanta\Tools e confere o SHA-256 de cada arquivo copiado.
# Por enquanto a pasta de origem (VantaModules\Tools) leva só um LEIA-ME; o vanta-tools.exe (Rust) chega na F5.

function Invoke-VantaTools {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [string]$Source = (Join-Path (Get-VantaModulesRoot) 'Tools'),
        [string]$Destination = (Get-VantaToolsRoot)
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Tools: a pasta de origem '$Source' não existe."
    }
    # "C:\Vanta" pode ter sido criada por um usuário comum: só se usa pasta que não é link e é do sistema/administradores.
    Assert-VantaTrustedFolder -Path (Split-Path -Path $Destination -Parent) -What 'Tools: pasta pai'
    Assert-VantaTrustedFolder -Path $Destination -What 'Tools: destino'
    $parent = Split-Path -Path $Destination -Parent
    $null = New-Item -ItemType Directory -Force -Path $parent
    # A cadeia inteira (a pasta pai e o destino) só aceita escrita, remoção e troca de SYSTEM/Administrators: a tarefa 2B
    # executa este exe elevada, e quem pode renomear a pasta pai pode trocar o exe por baixo dela.
    Protect-VantaFolder -Path $parent
    Assert-VantaToolsFileHardened -Path $parent
    $files = @(Get-ChildItem -LiteralPath $Source -Recurse -File)
    $wanted = @($files | ForEach-Object { $_.FullName.Substring($Source.TrimEnd('\').Length + 1) })
    # Nada de apagar C:\Vanta\Tools antes de ter a cópia nova pronta; arquivo que o pacote não conhece é colisão: aborta.
    if (Test-Path -LiteralPath $Destination) {
        $unknown = @(Get-ChildItem -LiteralPath $Destination -Recurse -Force -File | ForEach-Object { $_.FullName.Substring($Destination.TrimEnd('\').Length + 1) } | Where-Object { $_ -notin $wanted })
        if ($unknown.Count -gt 0) { throw "Tools: '$Destination' tem arquivo(s) que o pacote não conhece ($($unknown -join ', ')); colisão, nada foi trocado." }
    }
    # Monta e confere a cópia numa área de staging protegida desde o início; só então troca.
    $staging = Join-Path -Path $parent -ChildPath ('.staging-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $staging
    try {
        Protect-VantaFolder -Path $staging
        foreach ($file in $files) {
            $relative = $file.FullName.Substring($Source.TrimEnd('\').Length + 1)
            $target = Join-Path -Path $staging -ChildPath $relative
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Path $target -Parent)
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
            $want = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            $got = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            if ($want -ne $got) { throw "Tools: '$relative' foi copiado com SHA-256 diferente (origem $want, destino $got)." }
            Assert-VantaToolsFileHardened -Path $target
        }
        Assert-VantaToolsFileHardened -Path $staging
        if (Test-Path -LiteralPath $Destination) {
            $old = Join-Path -Path $parent -ChildPath ('.old-' + [guid]::NewGuid().ToString('N'))
            Move-Item -LiteralPath $Destination -Destination $old
            try { Move-Item -LiteralPath $staging -Destination $Destination }
            catch {
                Move-Item -LiteralPath $old -Destination $Destination
                throw
            }
            Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            Move-Item -LiteralPath $staging -Destination $Destination
        }
        Assert-VantaToolsFileHardened -Path $Destination
    }
    finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $hasBinary = Test-Path -LiteralPath (Join-Path $Destination 'vanta-tools.exe') -PathType Leaf
    Write-VantaPhaseLog -Message ("Tools: {0} arquivo(s) em {1}, SHA-256 conferido{2}." -f $files.Count, $Destination, $(if ($hasBinary) { '' } else { ' (ainda sem vanta-tools.exe: chega na F5)' }))
}
