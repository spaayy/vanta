# Transactional publication for the pinned Open-Shell theme files: every file is
# checked, replaced with a backup, and rolled back together if any step fails.
# Install-OpenShellTheme.ps1 dot-sources it in Install-OpenShell.ps1's elevated process.

function Get-VantaOpenShellThemeFileSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Assert-VantaOpenShellThemeDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (-not [IO.Directory]::Exists($Path)) {
        throw "$Description directory is missing at '$Path'."
    }
}

function Assert-VantaOpenShellThemeFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][long]$ExpectedBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    if (-not [IO.File]::Exists($Path)) {
        throw "The required Open-Shell theme file is missing at '$Path'."
    }
    if ((Get-Item -LiteralPath $Path -Force -ErrorAction Stop).Length -ne $ExpectedBytes) {
        throw "The Open-Shell theme file '$Path' failed its length check."
    }
    if (-not (Get-VantaOpenShellThemeFileSha256 -Path $Path).Equals(
            $ExpectedSha256,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        throw "The Open-Shell theme file '$Path' failed its SHA-256 check."
    }
}

function Test-VantaOpenShellThemeExpectedFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][long]$ExpectedBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    if (-not [IO.File]::Exists($Path)) { return $false }
    $file = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($file.Length -ne $ExpectedBytes) { return $false }
    return (Get-VantaOpenShellThemeFileSha256 -Path $Path).Equals(
        $ExpectedSha256,
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Assert-VantaOpenShellThemeReplaceableFile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([IO.Directory]::Exists($Path)) {
        throw "The Open-Shell theme target '$Path' is a directory."
    }
    if ([IO.File]::Exists($Path) -and
        -not (Test-VantaProtectedExecutionAcl -Acl (
                Get-Acl -LiteralPath $Path -ErrorAction Stop
            ))) {
        throw "The Open-Shell theme target '$Path' has an untrusted owner or writable principal."
    }
}

function Invoke-VantaOpenShellThemeFileTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$SkinsDirectory,
        [Parameter(Mandatory = $true)][object[]]$ExpectedFiles
    )

    Assert-VantaOpenShellThemeDirectory -Path $SourceDirectory -Description 'Extracted theme'
    Assert-VantaOpenShellThemeDirectory -Path $SkinsDirectory -Description 'Open-Shell skins'

    $sourceItems = @(Get-ChildItem -LiteralPath $SourceDirectory -Force -ErrorAction Stop)
    if ($sourceItems.Count -ne $ExpectedFiles.Count) {
        throw 'The extracted Open-Shell theme archive contains an unexpected number of entries.'
    }

    $expectedNames = @{}
    foreach ($expected in $ExpectedFiles) {
        $name = [string]$expected.Name
        $key = $name.ToUpperInvariant()
        if ([string]::IsNullOrWhiteSpace($name) -or
            $name -ne [IO.Path]::GetFileName($name) -or
            $expectedNames.ContainsKey($key)) {
            throw "The Open-Shell theme manifest contains an invalid or duplicate file name '$name'."
        }
        $expectedNames[$key] = $true
        Assert-VantaOpenShellThemeFile `
            -Path (Join-Path -Path $SourceDirectory -ChildPath $name) `
            -ExpectedBytes ([long]$expected.Length) `
            -ExpectedSha256 ([string]$expected.Sha256)
    }
    foreach ($sourceItem in $sourceItems) {
        if ($sourceItem.PSIsContainer -or
            -not $expectedNames.ContainsKey($sourceItem.Name.ToUpperInvariant())) {
            throw "The extracted Open-Shell theme archive contains unexpected entry '$($sourceItem.Name)'."
        }
    }

    $transactionId = [guid]::NewGuid().ToString('N')
    $records = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($expected in $ExpectedFiles) {
            $name = [string]$expected.Name
            $length = [long]$expected.Length
            $sha256 = [string]$expected.Sha256
            $sourcePath = Join-Path -Path $SourceDirectory -ChildPath $name
            $targetPath = Join-Path -Path $SkinsDirectory -ChildPath $name

            if (Test-VantaOpenShellThemeExpectedFile `
                    -Path $targetPath `
                    -ExpectedBytes $length `
                    -ExpectedSha256 $sha256) {
                continue
            }

            Assert-VantaOpenShellThemeReplaceableFile -Path $targetPath
            $targetExisted = [IO.File]::Exists($targetPath)
            $candidatePath = "$targetPath.vanta-$transactionId.new"
            $backupPath = "$targetPath.vanta-$transactionId.bak"
            $record = [pscustomobject]@{
                Name          = $name
                Target        = $targetPath
                Candidate     = $candidatePath
                Backup        = $backupPath
                TargetExisted = $targetExisted
                Length        = $length
                Sha256        = $sha256
            }
            $records.Add($record)

            [IO.File]::Copy($sourcePath, $candidatePath, $false)
            Assert-VantaOpenShellThemeFile `
                -Path $candidatePath `
                -ExpectedBytes $length `
                -ExpectedSha256 $sha256

            if ($targetExisted) {
                [IO.File]::Replace($candidatePath, $targetPath, $backupPath)
            }
            else {
                [IO.File]::Move($candidatePath, $targetPath)
            }
            Assert-VantaOpenShellThemeFile `
                -Path $targetPath `
                -ExpectedBytes $length `
                -ExpectedSha256 $sha256
        }
    }
    catch {
        $originalFailure = $_.Exception.Message
        $rollbackFailures = New-Object System.Collections.Generic.List[string]
        for ($index = $records.Count - 1; $index -ge 0; $index--) {
            $record = $records[$index]
            try {
                $published = Test-VantaOpenShellThemeExpectedFile `
                    -Path $record.Target `
                    -ExpectedBytes $record.Length `
                    -ExpectedSha256 $record.Sha256
                if ($published) {
                    if ($record.TargetExisted) {
                        if (-not [IO.File]::Exists($record.Backup)) {
                            throw 'the original target backup is missing'
                        }
                        [IO.File]::Replace(
                            $record.Backup,
                            $record.Target,
                            $record.Candidate
                        )
                    }
                    else {
                        [IO.File]::Delete($record.Target)
                    }
                }
                elseif ([IO.File]::Exists($record.Backup)) {
                    throw 'the target changed after publication; its backup was retained'
                }
                elseif (-not $record.TargetExisted -and
                    ([IO.File]::Exists($record.Target) -or
                        [IO.Directory]::Exists($record.Target))) {
                    throw 'a first-install target now contains unknown data'
                }

                if ([IO.File]::Exists($record.Candidate)) {
                    [IO.File]::Delete($record.Candidate)
                }
            }
            catch {
                $rollbackFailures.Add("$($record.Name): $($_.Exception.Message)")
            }
        }
        if ($rollbackFailures.Count -ne 0) {
            throw "Open-Shell theme publication failed: $originalFailure; rollback was incomplete: $($rollbackFailures -join '; ')."
        }
        throw "Open-Shell theme publication failed and was rolled back: $originalFailure"
    }

    $cleanupFailures = New-Object System.Collections.Generic.List[string]
    foreach ($record in $records) {
        foreach ($artifact in @($record.Candidate, $record.Backup)) {
            if (-not [IO.File]::Exists($artifact)) { continue }
            try {
                [IO.File]::Delete($artifact)
            }
            catch {
                $cleanupFailures.Add("${artifact}: $($_.Exception.Message)")
            }
        }
    }
    if ($cleanupFailures.Count -ne 0) {
        Write-Warning "Open-Shell theme files were published, but transaction cleanup was incomplete: $($cleanupFailures -join '; ')"
    }
}
