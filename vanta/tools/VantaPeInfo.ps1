# Leitura de recursos de um executável PE (x64) e nomes de arquivo para o 7-Zip. Sem dependência de ferramenta externa,
# então roda igual no Windows e no Linux (build-rc.sh).

function ConvertTo-SevenZipName {
    <# O 7-Zip do Linux espera "/" nos nomes que se pedem para extrair; no Windows os "\" servem. #>
    param([string[]]$Name, [switch]$Unix = (-not $IsWindows))
    if (-not $Unix) { return $Name }
    return @($Name | ForEach-Object { $_.Replace([string][char]92, '/') })
}

function Read-VantaPeResource {
    <# Os bytes do recurso `Type` (id numérico: 16 = RT_VERSION, 24 = RT_MANIFEST) do PE, lidos da tabela de recursos
       (diretório de recursos -> tipo -> nome -> idioma -> dados). $null se o PE não tem esse recurso. #>
    param([Parameter(Mandatory = $true)][byte[]]$Bytes, [Parameter(Mandatory = $true)][int]$Type)
    $u16 = { param($o) [int][BitConverter]::ToUInt16($Bytes, $o) }
    $u32 = { param($o) [long][BitConverter]::ToUInt32($Bytes, $o) }
    if ($Bytes.Length -lt 0x40 -or [Text.Encoding]::ASCII.GetString($Bytes, 0, 2) -ne 'MZ') { throw 'Nao e um executavel PE.' }
    $pe = [int](& $u32 0x3C)
    if ([Text.Encoding]::ASCII.GetString($Bytes, $pe, 4) -ne "PE`0`0") { throw 'Assinatura PE ausente.' }
    $sections = & $u16 ($pe + 6)
    $optSize = & $u16 ($pe + 20)
    $opt = $pe + 24
    if ((& $u16 $opt) -ne 0x20B) { throw 'Nao e PE32+ (x64).' }
    $resRva = & $u32 ($opt + 0x80)
    if ($resRva -eq 0) { return $null }
    $table = $opt + $optSize
    $toOffset = {
        param([long]$rva)
        for ($i = 0; $i -lt $sections; $i++) {
            $s = $table + 40 * $i
            $va = & $u32 ($s + 12)
            $span = [Math]::Max((& $u32 ($s + 8)), (& $u32 ($s + 16)))
            if ($rva -ge $va -and $rva -lt $va + $span) { return [int]($rva - $va + (& $u32 ($s + 20))) }
        }
        throw "RVA $rva fora das secoes do PE."
    }
    $root = & $toOffset $resRva
    # Um diretório: 16 bytes de cabeçalho e entradas de 8 bytes (nomeadas primeiro, depois por id).
    $entries = {
        param([int]$dir)
        $named = & $u16 ($dir + 12)
        $ids = & $u16 ($dir + 14)
        for ($i = 0; $i -lt $named + $ids; $i++) {
            $e = $dir + 16 + 8 * $i
            [pscustomobject]@{ Id = (& $u32 $e); Named = ((& $u32 $e) -band 0x80000000) -ne 0; Target = ((& $u32 ($e + 4)) -band 0x7FFFFFFF); IsDir = ((& $u32 ($e + 4)) -band 0x80000000) -ne 0 }
        }
    }
    $typeEntry = @(& $entries $root | Where-Object { -not $_.Named -and $_.Id -eq $Type -and $_.IsDir }) | Select-Object -First 1
    if (-not $typeEntry) { return $null }
    $byName = @(& $entries ($root + $typeEntry.Target)) | Select-Object -First 1
    if (-not $byName -or -not $byName.IsDir) { return $null }
    $byLanguage = @(& $entries ($root + $byName.Target)) | Select-Object -First 1
    if (-not $byLanguage -or $byLanguage.IsDir) { return $null }
    $data = $root + $byLanguage.Target
    $offset = & $toOffset (& $u32 $data)
    $size = [int](& $u32 ($data + 4))
    $slice = New-Object byte[] $size
    [Array]::Copy($Bytes, $offset, $slice, 0, $size)
    return , $slice
}

function Get-VantaVersionStrings {
    <# Os pares nome/valor das tabelas de texto (StringFileInfo) de um recurso RT_VERSION: VS_VERSIONINFO -> StringFileInfo
       -> StringTable -> String, cada bloco com wLength, wValueLength, wType, chave UTF-16 e preenchimento de 4 bytes. #>
    param([Parameter(Mandatory = $true)][byte[]]$Resource)
    $align = { param([int]$n) ($n + 3) -band (-bnot 3) }
    $block = {
        param([int]$off)
        $length = [int][BitConverter]::ToUInt16($Resource, $off)
        $valueLength = [int][BitConverter]::ToUInt16($Resource, $off + 2)
        $type = [int][BitConverter]::ToUInt16($Resource, $off + 4)
        $p = $off + 6
        while ($p + 1 -lt $Resource.Length -and [BitConverter]::ToUInt16($Resource, $p) -ne 0) { $p += 2 }
        $key = [Text.Encoding]::Unicode.GetString($Resource, $off + 6, $p - $off - 6)
        $valueAt = & $align ($p + 2)
        $valueBytes = if ($type -eq 1) { 2 * $valueLength } else { $valueLength }
        [pscustomobject]@{ Key = $key; Off = $off; End = $off + $length; ValueAt = $valueAt; ValueLength = $valueLength; ValueBytes = $valueBytes; Type = $type; Children = (& $align ($valueAt + $valueBytes)) }
    }
    $children = {
        param($parent)
        for ($c = $parent.Children; $c + 6 -lt $parent.End; ) {
            $b = & $block $c
            $b
            if ($b.End -le $c) { break }
            $c = & $align $b.End
        }
    }
    $root = & $block 0
    if ($root.Key -ne 'VS_VERSION_INFO') { throw 'Recurso RT_VERSION sem VS_VERSION_INFO.' }
    $strings = [ordered]@{}
    foreach ($info in @(& $children $root | Where-Object { $_.Key -eq 'StringFileInfo' })) {
        foreach ($tableBlock in @(& $children $info)) {
            foreach ($entry in @(& $children $tableBlock)) {
                $text = [Text.Encoding]::Unicode.GetString($Resource, $entry.ValueAt, [Math]::Max(0, $entry.ValueBytes)).TrimEnd([char]0)
                $strings[$entry.Key] = $text
            }
        }
    }
    return $strings
}

function Get-VantaToolsExeInfo {
    <# InternalName e OriginalFilename do recurso RT_VERSION e o `level` do requestedExecutionLevel no XML do RT_MANIFEST. #>
    param([Parameter(Mandatory = $true)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $version = Read-VantaPeResource -Bytes $bytes -Type 16
    $manifest = Read-VantaPeResource -Bytes $bytes -Type 24
    if (-not $version) { throw "O PE '$Path' nao tem recurso RT_VERSION." }
    if (-not $manifest) { throw "O PE '$Path' nao tem recurso RT_MANIFEST." }
    $strings = Get-VantaVersionStrings -Resource $version
    $xml = New-Object Xml.XmlDocument
    $xml.LoadXml([Text.Encoding]::UTF8.GetString($manifest).TrimStart([char]0xFEFF))
    $node = @($xml.GetElementsByTagName('requestedExecutionLevel')) | Select-Object -First 1
    [pscustomobject]@{
        InternalName     = $strings['InternalName']
        OriginalFilename = $strings['OriginalFilename']
        ExecutionLevel   = $(if ($node) { $node.GetAttribute('level') } else { $null })
    }
}
