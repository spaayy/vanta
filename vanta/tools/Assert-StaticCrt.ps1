#Requires -Version 7.0
Set-StrictMode -Version 3.0

function Find-Dumpbin {
    [CmdletBinding()]
    param()

    $onPath = Get-Command dumpbin -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
        $vsPath = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
        if ($vsPath) {
            $found = Get-ChildItem -Path (Join-Path $vsPath 'VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe') -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }

    throw 'dumpbin.exe nao encontrado no PATH nem no Visual Studio/BuildTools (VC.Tools.x86.x64).'
}

function Read-PeImportedDll {
    <# Lê a tabela de imports do PE (PE32+) direto dos bytes: não depende de dumpbin, então roda também no Linux. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $b = [IO.File]::ReadAllBytes($Path)
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    if ([Text.Encoding]::ASCII.GetString($b, $pe, 4) -ne "PE`0`0") { throw "'$Path' nao e um PE." }
    $sections = [BitConverter]::ToUInt16($b, $pe + 6)
    $optSize = [BitConverter]::ToUInt16($b, $pe + 20)
    $opt = $pe + 24
    if ([BitConverter]::ToUInt16($b, $opt) -ne 0x20B) { throw "'$Path' nao e PE32+ (x64)." }
    $importRva = [BitConverter]::ToUInt32($b, $opt + 0x78)
    if ($importRva -eq 0) { return ,@() }
    $table = $opt + $optSize
    $toOffset = {
        param([uint32]$rva)
        for ($i = 0; $i -lt $sections; $i++) {
            $s = $table + 40 * $i
            $va = [BitConverter]::ToUInt32($b, $s + 12)
            $span = [Math]::Max([BitConverter]::ToUInt32($b, $s + 8), [BitConverter]::ToUInt32($b, $s + 16))
            if ($rva -ge $va -and $rva -lt $va + $span) { return [int]($rva - $va + [BitConverter]::ToUInt32($b, $s + 20)) }
        }
        throw "RVA $rva fora das secoes de '$Path'."
    }
    $names = [Collections.Generic.List[string]]::new()
    for ($d = & $toOffset $importRva; [BitConverter]::ToUInt32($b, $d + 12) -ne 0; $d += 20) {
        $n = & $toOffset ([BitConverter]::ToUInt32($b, $d + 12))
        $end = $n
        while ($b[$end] -ne 0) { $end++ }
        $names.Add([Text.Encoding]::ASCII.GetString($b, $n, $end - $n))
    }
    return ,$names.ToArray()
}

function Get-PeImportedDlls {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$DumpbinPath
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Executavel nao encontrado: $Path"
    }
    if (-not $DumpbinPath) { $DumpbinPath = try { Find-Dumpbin } catch { $null } }
    if (-not $DumpbinPath) {
        # Sem dumpbin (Linux, ou Windows sem Visual Studio): o leitor de PE faz o mesmo trabalho.
        $names = @(Read-PeImportedDll -Path $Path | Sort-Object -Unique)
        if ($names.Count -eq 0) { throw "Nenhuma DLL encontrada na tabela de imports de '$Path'." }
        return ,$names
    }

    $output = & $DumpbinPath /nologo /imports $Path 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "dumpbin /imports falhou ($LASTEXITCODE) em '$Path': $($output -join "`n")"
    }

    $inImports = $false
    $dlls = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($line in $output) {
        $text = [string]$line
        if ($text -match '^\s*Section contains the following .*imports:\s*$') {
            $inImports = $true
            continue
        }
        if ($text -match '^\s*Summary\s*$') {
            $inImports = $false
            continue
        }
        if ($inImports -and $text -match '^\s{4}([^\s]+\.dll)\s*$') {
            $dll = $Matches[1]
            if ($seen.Add($dll)) { $dlls.Add($dll) }
        }
    }

    if ($dlls.Count -eq 0) {
        throw "Nenhuma DLL encontrada na tabela de imports de '$Path' (saida inesperada do dumpbin)."
    }

    return ,$dlls.ToArray()
}

function Assert-StaticCrt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Path,
        [string]$DumpbinPath,
        [string[]]$ForbiddenPatterns = @('^VCRUNTIME', '^MSVCP', '^api-ms-win-crt-')
    )

    if (-not $DumpbinPath) { $DumpbinPath = try { Find-Dumpbin } catch { $null } }

    $results = foreach ($exe in $Path) {
        $imports = Get-PeImportedDlls -Path $exe -DumpbinPath $DumpbinPath
        $forbidden = @($imports | Where-Object {
            $dll = $_
            foreach ($pat in $ForbiddenPatterns) {
                if ($dll -match $pat) { return $true }
            }
            return $false
        })
        if ($forbidden.Count -gt 0) {
            throw "CRT dinamico detectado em '$exe': $($forbidden -join ', ')"
        }
        [pscustomobject]@{
            Path      = $exe
            Imports   = $imports
            Forbidden = @()
        }
    }

    return ,@($results)
}
