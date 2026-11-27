# Vanta.Software domain: CBS package (CAB) install/uninstall.
#
# Adapted from online-sxs by he3als (GPL-3.0-only).
#
# Install-VantaPackage.ps1 is the optional interactive shell around these functions;
# install phases call them directly with -NonInteractive semantics.

$cbsRetryHelper = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\Operations\CbsRetry.ps1'
if (-not [IO.File]::Exists($cbsRetryHelper) -or
    (([IO.File]::GetAttributes($cbsRetryHelper) -band
            [IO.FileAttributes]::ReparsePoint) -ne 0)) {
    throw "Required CBS retry helper '$cbsRetryHelper' is missing or a reparse point."
}
. $cbsRetryHelper -LibraryOnly

function Get-VantaCbsArchitecture {
    <#
    .SYNOPSIS
        Returns the CBS architecture name of the PC: 'arm64' or 'amd64'.
    .DESCRIPTION
        A wrong-architecture CAB breaks servicing, so this uses the strict CIM check
        from Installers.ps1, never PROCESSOR_ARCHITECTURE.
    #>
    if (Test-VantaSoftwareArm64) { return 'arm64' }
    return 'amd64'
}

function Initialize-VantaCbsEnvironment {
    <#
    .SYNOPSIS
        Puts the Windows system folders at the front of PATH, because DISM and
        servicing can misbehave under TrustedInstaller with a minimal PATH.
    #>
    $windir = [Environment]::GetFolderPath('Windows')
    $sys32 = [Environment]::GetFolderPath('System')
    $env:Path = "$windir;$sys32;$sys32\Wbem;$sys32\WindowsPowerShell\v1.0;" + $env:Path
}

function Select-VantaCbsPackage {
    <#
    .SYNOPSIS
        Matches candidate package names/paths against wildcard patterns, keeping only
        candidates for the current architecture (pure matching helper, kept separate
        for testability).
    .PARAMETER SingleUsePatterns
        When set (CAB install matching), each pattern is consumed by its first match.
        When not set (uninstall matching), one pattern may match multiple candidates.
    #>
    param(
        [AllowEmptyCollection()]
        [string[]]$Candidates = @(),

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Patterns,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Architecture,

        [switch]$SingleUsePatterns
    )

    $matched = @()
    $remainingPatterns = @($Patterns)

    foreach ($candidate in $Candidates) {
        $patternPool = if ($SingleUsePatterns) { $remainingPatterns } else { $Patterns }
        foreach ($pattern in $patternPool) {
            if (($candidate -like $pattern) -and ($candidate -match $Architecture)) {
                $matched += $candidate
                $remainingPatterns = @($remainingPatterns -ne $pattern)
                break
            }
        }
    }

    return [pscustomobject]@{
        Matched           = $matched
        UnmatchedPatterns = $remainingPatterns
    }
}

# The one identity the Vanta CBS packages are signed with: a self-signed certificate made for each build, whose private
# key is deleted right after signing. Compared exactly (no partial match); anything else, including a certificate that
# names Microsoft or Windows, is refused.
$script:VantaCbsSignerName = 'CN=Vanta CBS Packages, O=Vanta'
$script:VantaCbsComponentEku = '1.3.6.1.4.1.311.10.3.6' # Windows System Component Verification
# HKLM\SOFTWARE\Vanta, value CbsRoot (REG_MULTI_SZ): the thumbprints of the roots Vanta itself put in
# Cert:\LocalMachine\Root, so an uninstall removes exactly those and nothing else.
$script:VantaCbsRootKey = 'HKLM:\SOFTWARE\Vanta'
$script:VantaCbsRootValue = 'CbsRoot'

function Get-VantaCbsSignerProfile {
    <#
    .SYNOPSIS
        The signer a package set is built for, from Vanta-CbsHashes.psd1: 'Signer' (the exact subject and issuer, default
        the Vanta identity) and 'TrustMode' ('Root', the default: the signer is trusted in the machine root store and
        taken back on removal; 'LegacyKey': the older mechanism of the not-distributed personal build, which trusts
        no new root). The file is part of the hash-pinned package, never of the user's profile.
    #>
    param([Parameter(Mandatory = $true)][string]$PackagesPath)
    $manifest = Get-VantaCbsExpectedHashes -PackagesPath $PackagesPath
    $signer = $script:VantaCbsSignerName
    if ($manifest.ContainsKey('Signer') -and -not [string]::IsNullOrWhiteSpace([string]$manifest['Signer'])) { $signer = [string]$manifest['Signer'] }
    $mode = 'Root'
    if ($manifest.ContainsKey('TrustMode')) { $mode = [string]$manifest['TrustMode'] }
    if ($mode -cnotin 'Root', 'LegacyKey') { throw "Unknown CBS trust mode '$mode'." }
    return [pscustomobject]@{ Signer = $signer; TrustMode = $mode }
}

function Test-VantaCbsPackagesAvailable {
    <#
    .SYNOPSIS
        Whether this package carries CBS packages (CABs) for the PC's architecture. The public edition carries none, and
        no ARM64 CAB is shipped: then telemetry's CAB is skipped and removing Defender isn't offered.
    #>
    param([string]$PackagesPath = (Join-Path -Path (Get-VantaContext).VantaModulesPath -ChildPath 'Packages'))
    $architecture = Get-VantaCbsArchitecture
    $cabs = @(Get-ChildItem -LiteralPath $PackagesPath -File -Filter '*.cab' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $architecture })
    return ($cabs.Count -gt 0)
}

function Assert-VantaCbsCertificate {
    <#
    .SYNOPSIS
        Accepts a CAB only when its pinned SHA-256 matches Vanta-CbsHashes.psd1 and it is signed by exactly
        'CN=Vanta CBS Packages, O=Vanta' (subject and issuer, self-signed) with the Windows component EKU.
        Returns the signer certificate.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CabPath
    )

    # The content hash first: the signature of a CAB that differs from the one that was reviewed means nothing.
    $null = Assert-VantaCbsHash -CabPath $CabPath
    $expectedSigner = (Get-VantaCbsSignerProfile -PackagesPath (Split-Path -Path $CabPath -Parent)).Signer

    $signature = Get-AuthenticodeSignature -LiteralPath $CabPath
    $cert = $signature.SignerCertificate
    # A self-signed Vanta CAB reports UnknownError until its root is trusted, which happens just after this check;
    # a damaged or unsigned file is refused here.
    if ($null -eq $cert -or
        $signature.Status -eq [System.Management.Automation.SignatureStatus]::HashMismatch -or
        $signature.Status -eq [System.Management.Automation.SignatureStatus]::NotSigned) {
        throw "The CAB component signature is not intact (status '$($signature.Status)')."
    }
    $subject = [string]$cert.Subject
    $issuer = [string]$cert.Issuer
    if ($subject -cne $expectedSigner -or $issuer -cne $expectedSigner) {
        throw "The CAB is not signed by '$expectedSigner' (subject '$subject', issuer '$issuer')."
    }

    $ekuValues = @(
        $cert.Extensions |
            Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension] } |
            ForEach-Object { $_.EnhancedKeyUsages | ForEach-Object { $_.Value } }
    )
    if ($ekuValues -notcontains $script:VantaCbsComponentEku) {
        throw 'The CAB signer lacks the Windows component EKU.'
    }
    return $cert
}

function Register-VantaCbsLegacyRootKey {
    <# The mechanism of the personal build (not distributed): an empty key under the machine root store, left in place
       because the alternative repair source needs it. No certificate is added and none is ever removed. #>
    $certRegPath = 'HKLM:\Software\Microsoft\SystemCertificates\ROOT\Certificates\8A334AA8052DD244A647306A76B8178FA215F344'
    if (-not (Test-Path -LiteralPath $certRegPath)) { New-Item -Path $certRegPath -Force | Out-Null }
}

function Get-VantaCbsRootRecord {
    <# The thumbprints Vanta recorded in HKLM\SOFTWARE\Vanta\CbsRoot (empty when none). Tests mock this. #>
    $value = Get-ItemProperty -LiteralPath $script:VantaCbsRootKey -Name $script:VantaCbsRootValue -ErrorAction SilentlyContinue
    if ($null -eq $value) { return @() }
    return @($value.($script:VantaCbsRootValue) | Where-Object { $_ })
}

function Set-VantaCbsRootRecord {
    <# Writes (or, for an empty list, deletes) the CbsRoot record. Tests mock this. #>
    param([AllowEmptyCollection()][string[]]$Thumbprint = @())
    if ($Thumbprint.Count -eq 0) {
        Remove-ItemProperty -LiteralPath $script:VantaCbsRootKey -Name $script:VantaCbsRootValue -ErrorAction SilentlyContinue
        return
    }
    if (-not (Test-Path -LiteralPath $script:VantaCbsRootKey)) { New-Item -Path $script:VantaCbsRootKey -Force | Out-Null }
    New-ItemProperty -LiteralPath $script:VantaCbsRootKey -Name $script:VantaCbsRootValue -PropertyType MultiString -Value $Thumbprint -Force | Out-Null
}

function Test-VantaCbsRootCertificate {
    param([Parameter(Mandatory = $true)][string]$Thumbprint)
    return (Test-Path -LiteralPath "Cert:\LocalMachine\Root\$Thumbprint")
}

function Add-VantaCbsRootCertificate {
    param([Parameter(Mandatory = $true)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', 'LocalMachine')
    $store.Open('ReadWrite')
    try { $store.Add($Certificate) } finally { $store.Close() }
}

function Remove-VantaCbsRootCertificate {
    param([Parameter(Mandatory = $true)][string]$Thumbprint)
    Remove-Item -LiteralPath "Cert:\LocalMachine\Root\$Thumbprint" -Force
}

function Install-VantaCbsRoot {
    <#
    .SYNOPSIS
        Trusts the (already validated) signer of a Vanta CAB in Cert:\LocalMachine\Root and records its thumbprint,
        unless the PC already trusted that exact certificate before Vanta (then Vanta did not add it and never removes it).
    #>
    param([Parameter(Mandatory = $true)]$Certificate)
    $thumbprint = ([string]$Certificate.Thumbprint).ToUpperInvariant()
    if ($thumbprint -notmatch '^[0-9A-F]{40}$') { throw "The CAB signer has an invalid thumbprint '$thumbprint'." }
    if (Test-VantaCbsRootCertificate -Thumbprint $thumbprint) { return $false }
    $recorded = @(Get-VantaCbsRootRecord)
    Add-VantaCbsRootCertificate -Certificate $Certificate
    # Recorded straight away: if anything after this fails, an uninstall still knows what to take back.
    Set-VantaCbsRootRecord -Thumbprint @($recorded + $thumbprint | Select-Object -Unique)
    return $true
}

function Remove-VantaCbsRoot {
    <#
    .SYNOPSIS
        Takes back exactly the roots Vanta recorded (by thumbprint, never by name), then clears the record.
        Run after the packages are removed. Returns the thumbprints removed.
    #>
    $removed = @()
    $kept = @()
    foreach ($thumbprint in @(Get-VantaCbsRootRecord)) {
        $thumbprint = ([string]$thumbprint).ToUpperInvariant()
        if ($thumbprint -notmatch '^[0-9A-F]{40}$') { Write-Host "[WARN] Ignoring the malformed CbsRoot entry '$thumbprint'." -ForegroundColor Yellow; continue }
        try {
            if (Test-VantaCbsRootCertificate -Thumbprint $thumbprint) { Remove-VantaCbsRootCertificate -Thumbprint $thumbprint }
            $removed += $thumbprint
        }
        catch {
            Write-Host "[WARN] Could not remove the Vanta CBS root ${thumbprint}: $($_.Exception.Message)" -ForegroundColor Yellow
            $kept += $thumbprint
        }
    }
    Set-VantaCbsRootRecord -Thumbprint $kept
    return $removed
}

$script:VantaCbsExpectedHashes = $null

function Get-VantaCbsExpectedHashes {
    <#
    .SYNOPSIS
        Loads Vanta-CbsHashes.psd1 (the SHA-256 of every included CAB) from the packages
        folder. The CAB signing cert is regenerated on every build, so its thumbprint is
        not stable and cannot be pinned; the content hash is what we verify against.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackagesPath
    )

    if ($null -ne $script:VantaCbsExpectedHashes) {
        return $script:VantaCbsExpectedHashes
    }

    $hashFile = Join-Path -Path $PackagesPath -ChildPath 'Vanta-CbsHashes.psd1'
    if (-not (Test-Path -LiteralPath $hashFile -PathType Leaf)) {
        throw "The CBS package hash manifest '$hashFile' is missing; refusing to install unverified packages."
    }

    $script:VantaCbsExpectedHashes = Import-VantaDataFile -LiteralPath $hashFile
    return $script:VantaCbsExpectedHashes
}

function Assert-VantaCbsHash {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CabPath
    )

    $fileName = Split-Path -Path $CabPath -Leaf
    $expected = Get-VantaCbsExpectedHashes -PackagesPath (Split-Path -Path $CabPath -Parent)
    if (-not $expected.ContainsKey($fileName)) {
        throw "No expected SHA256 is recorded for '$fileName' in the CBS hash manifest; refusing to install an unlisted package."
    }

    $actual = (Get-FileHash -LiteralPath $CabPath -Algorithm SHA256).Hash
    if ($actual -ne $expected[$fileName]) {
        throw "SHA256 mismatch for '$fileName' (got '$actual'); the package may have been modified. Refusing to install it."
    }
    return ([string]$expected[$fileName]).ToUpperInvariant()
}

function Install-VantaCbsCab {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CabPath
    )

    $fileName = Split-Path -Path $CabPath -Leaf
    Write-Host "`nInstalling $fileName..." -ForegroundColor Cyan
    Write-Host ('-' * 84) -ForegroundColor Magenta

    Write-Host '[INFO] Verifying package hash...'
    $expectedSha256 = $null
    try {
        $expectedSha256 = Assert-VantaCbsHash -CabPath $CabPath
    }
    catch {
        Write-Host "[ERROR] Hash verification failed for '$CabPath': $($_.Exception.Message)" -ForegroundColor Red
        return [pscustomobject]@{
            Path = $CabPath; Success = $false; RetryEligible = $false; Sha256 = $null; FailureKind = 'Integrity'
        }
    }

    Write-Host '[INFO] Checking certificate...'
    try {
        $signer = Assert-VantaCbsCertificate -CabPath $CabPath
        if ((Get-VantaCbsSignerProfile -PackagesPath (Split-Path -Path $CabPath -Parent)).TrustMode -ceq 'Root') {
            [void](Install-VantaCbsRoot -Certificate $signer)
        }
        else {
            Register-VantaCbsLegacyRootKey
        }
    }
    catch {
        Write-Host "[ERROR] Cert error from '$CabPath': $($_.Exception.Message)" -ForegroundColor Red
        return [pscustomobject]@{
            Path = $CabPath; Success = $false; RetryEligible = $false; Sha256 = $expectedSha256; FailureKind = 'Signature'
        }
    }

    Write-Host '[INFO] Adding package...'
    # -LogLevel 1 writes only errors to the DISM log.
    try {
        Add-WindowsPackage -Online -PackagePath $CabPath -NoRestart -IgnoreCheck -LogLevel 1 *>$null
    }
    catch {
        Write-Host "[ERROR] Error when adding package '$CabPath': $($_.Exception.Message)" -ForegroundColor Red
        return [pscustomobject]@{
            Path = $CabPath; Success = $false; RetryEligible = $true; Sha256 = $expectedSha256; FailureKind = 'Servicing'
        }
    }

    Write-Host '[INFO] Completed successfully.'
    return [pscustomobject]@{
        Path = $CabPath; Success = $true; RetryEligible = $false; Sha256 = $expectedSha256; FailureKind = $null
    }
}

function New-VantaCbsRepairSource {
    <#
    .SYNOPSIS
        Hardlinks the Vanta package manifests into a local repair source and registers
        it, fixing the RestoreHealth/SFC 'Sources' error.
        https://learn.microsoft.com/windows-hardware/manufacture/desktop/configure-a-windows-repair-source
        the upstream issue tracker, issue 1103
    #>
    $windir = [Environment]::GetFolderPath('Windows')
    # The version every Vanta package manifest carries.
    $version = '38655.38527.65535.65535'
    $srcPath = '%SystemRoot%\VantaModules\Packages\WinSxS'
    $srcPathExpanded = [System.Environment]::ExpandEnvironmentVariables($srcPath)

    Write-Host "`nMaking repair source..." -ForegroundColor Cyan
    Write-Host ('-' * 84) -ForegroundColor Magenta

    Write-Host '[INFO] Getting manifests...'
    $manifests = @(Get-ChildItem -Path "$windir\WinSxS\Manifests" -File -Filter "*$version*")
    if ($manifests.Count -eq 0) {
        Write-Host "[WARN] No manifests found! Can't create repair source." -ForegroundColor Yellow
        return $false
    }

    if (Test-Path -LiteralPath $srcPathExpanded -PathType Container) {
        Write-Host '[INFO] Deleting old RepairSrc...'
        Remove-Item -LiteralPath $srcPathExpanded -Force -Recurse
    }
    Write-Host '[INFO] Creating RepairSrc path...'
    New-Item -Path "$srcPathExpanded\Manifests" -Force -ItemType Directory | Out-Null

    Write-Host '[INFO] Hard linking manifests...'
    foreach ($manifest in $manifests) {
        New-Item -ItemType HardLink -Path "$srcPathExpanded\Manifests\$($manifest.Name)" -Target $manifest.FullName | Out-Null
    }

    $servicingPolicyKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Servicing'
    if (-not (Test-Path -LiteralPath $servicingPolicyKey)) {
        New-Item -Path $servicingPolicyKey -Force | Out-Null
    }
    Set-ItemProperty -Path $servicingPolicyKey -Name 'LocalSourcePath' -Value $srcPath -Type ExpandString -Force
    return $true
}

function Get-VantaCbsRepairSourcePolicy {
    $value = Get-ItemProperty -LiteralPath 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Servicing' -Name 'LocalSourcePath' -ErrorAction SilentlyContinue
    if ($null -eq $value) { return $null }
    return [string]$value.LocalSourcePath
}

function Remove-VantaCbsRepairSourcePolicy {
    Remove-ItemProperty -LiteralPath 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Servicing' -Name 'LocalSourcePath' -ErrorAction Stop
}

function Update-VantaCbsRepairSource {
    <#
    .SYNOPSIS
        Keeps the repair source the Vanta packages need. An update replaces
        %windir%\VantaModules, and the repair source in it, without installing the
        packages again: recreate it while they are installed, and never leave
        LocalSourcePath naming a folder that is gone. Returns what it did.
    #>
    param([AllowEmptyCollection()][string[]]$VantaPackages = @())

    if ($VantaPackages.Count -gt 0 -and (New-VantaCbsRepairSource)) { return 'recreated' }
    # Reading the policy expands its %SystemRoot%, so both sides are compared expanded.
    $vantaSource = [Environment]::ExpandEnvironmentVariables('%SystemRoot%\VantaModules\Packages\WinSxS')
    $policy = Get-VantaCbsRepairSourcePolicy
    if ($null -eq $policy -or [Environment]::ExpandEnvironmentVariables($policy) -ne $vantaSource) { return 'unchanged' }
    if (Test-Path -LiteralPath $vantaSource -PathType Container) { return 'unchanged' }
    Remove-VantaCbsRepairSourcePolicy
    return 'removed'
}

function Get-VantaComponentCleanupBlocker {
    <#
    .SYNOPSIS
        Why the component store cleanup must not run now, or $null. With an Vanta
        package installed, the cleanup rebuilds the inbox component the package
        replaces from its oldest version and can't rebuild all of its files, which
        leaves the store reporting damage. Fresh installs run it before the Vanta
        packages are installed; once they are, it never runs.
    #>
    param(
        [bool]$IsUpgrade,
        [AllowEmptyCollection()][string[]]$VantaPackages = @()
    )

    if ($VantaPackages.Count -gt 0) { return "the Vanta servicing packages are installed ($($VantaPackages -join ', '))" }
    if ($IsUpgrade) { return 'this updates an earlier Vanta install' }
    return $null
}

function Register-VantaCbsFailureFallback {
    <#
    .SYNOPSIS
        Arms the compact Safe Mode retry for integrity-checked CAB failures.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$RetryPackages
    )

    $packagePaths = @($RetryPackages | ForEach-Object {
        if ($null -eq $_.PSObject.Properties['Path']) {
            throw 'A CBS retry package did not provide its verified path.'
        }
        [string]$_.Path
    })
    Write-Host 'Arming the failed CBS packages for a Safe Mode retry.'
    [void](Enable-VantaCbsRetry -Packages $packagePaths)
}

function Install-VantaCbsPackage {
    <#
    .SYNOPSIS
        Installs Vanta CBS packages (CABs) online. Patterns (e.g.
        '*Z-Vanta-NoDefender-Package*') are matched against the CABs in
        VantaModules\Packages, filtered by architecture. Must run as
        SYSTEM/TrustedInstaller.
    .PARAMETER LiteralPaths
        Treat -Packages as literal CAB paths instead of patterns (used by the Safe Mode
        retry and the file-picker flow of Install-VantaPackage.ps1).
    .PARAMETER NonInteractive
        On failure, register the Safe Mode retry fallback and throw so the ordered
        Components step fails and the orchestrator returns a single nonzero status,
        instead of returning the failures for an interactive prompt.
    .OUTPUTS
        PSCustomObject with SuccessPackages, FailedPackages and UnmatchedPatterns.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Packages,

        [ValidateNotNullOrEmpty()]
        [string]$PackagesPath = (Join-Path -Path (Get-VantaContext).VantaModulesPath -ChildPath 'Packages'),

        [switch]$LiteralPaths,

        [switch]$NonInteractive
    )

    Assert-VantaPrivilege -TrustedInstaller
    Initialize-VantaCbsEnvironment

    $unmatchedPatterns = @()
    if ($LiteralPaths) {
        $packagesToProcess = @($Packages)
    }
    else {
        $architecture = Get-VantaCbsArchitecture
        $candidates = @(Get-ChildItem -Path $PackagesPath -File -Filter '*.cab' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName | Sort-Object -Descending)
        $selection = Select-VantaCbsPackage -Candidates $candidates -Patterns $Packages -Architecture $architecture -SingleUsePatterns

        if (@($selection.Matched).Count -eq 0) {
            throw "The specified CABs ($Packages) to install weren't found."
        }
        if (@($selection.UnmatchedPatterns).Count -gt 0) {
            Write-Host "[WARN] These CABs to install weren't found: $($selection.UnmatchedPatterns)" -ForegroundColor Yellow
        }

        $packagesToProcess = @($selection.Matched)
        $unmatchedPatterns = @($selection.UnmatchedPatterns)
    }

    $successPackages = @()
    $failedPackages = @()
    $retryPackages = @()
    foreach ($cabPath in $packagesToProcess) {
        $cabResult = Install-VantaCbsCab -CabPath $cabPath
        if ($cabResult.Success) {
            $successPackages += $cabPath
        }
        else {
            $failedPackages += $cabPath
            if ($cabResult.RetryEligible) {
                $retryPackages += [pscustomobject]@{
                    Path = [IO.Path]::GetFullPath([string]$cabResult.Path)
                    Sha256 = [string]$cabResult.Sha256
                }
            }
        }
    }

    if ($successPackages.Count -ne 0) {
        New-VantaCbsRepairSource | Out-Null
    }

    if (($failedPackages.Count -gt 0) -and $NonInteractive) {
        $failure = "These CBS packages failed to install: $($failedPackages -join ', ')."
        if ($retryPackages.Count -gt 0) {
            Register-VantaCbsFailureFallback -RetryPackages $retryPackages
            # This failure ends the install, so it's where the user learns of the retry.
            $failure += " $(Get-VantaCbsRetryInstruction)"
        }
        throw $failure
    }

    return [pscustomobject]@{
        SuccessPackages   = $successPackages
        FailedPackages    = $failedPackages
        RetryPackages     = $retryPackages
        UnmatchedPatterns = $unmatchedPatterns
    }
}

function Uninstall-VantaCbsPackage {
    <#
    .SYNOPSIS
        Uninstalls installed Windows packages matching the given wildcard patterns,
        filtered by architecture. Failures are logged as warnings; must run as
        SYSTEM/TrustedInstaller.
    .OUTPUTS
        PSCustomObject with RemovedPackages, FailedPackages and UnmatchedPatterns.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Packages
    )

    Assert-VantaPrivilege -TrustedInstaller
    Initialize-VantaCbsEnvironment

    $architecture = Get-VantaCbsArchitecture
    $candidates = @((Get-WindowsPackage -Online).PackageName)
    $selection = Select-VantaCbsPackage -Candidates $candidates -Patterns $Packages -Architecture $architecture

    $removedPackages = @()
    $failedPackages = @()
    if (@($selection.Matched).Count -eq 0) {
        Write-Host "[WARN] '$Packages' matched no installed packages, nothing to do." -ForegroundColor Yellow
    }
    else {
        if (@($selection.UnmatchedPatterns).Count -gt 0) {
            Write-Host "[WARN] Some packages not found to uninstall: $($selection.UnmatchedPatterns)" -ForegroundColor Yellow
        }

        foreach ($package in $selection.Matched) {
            try {
                Write-Host "[INFO] Uninstalling '$package'..."
                # Stop: the catch sees only terminating errors, and this module doesn't
                # inherit the caller's ErrorActionPreference.
                Remove-WindowsPackage -Online -PackageName $package -NoRestart -LogLevel 1 -ErrorAction Stop *>$null
                $removedPackages += $package
            }
            catch {
                Write-Host "[ERROR] $package failed to uninstall: $($_.Exception.Message)" -ForegroundColor Red
                $failedPackages += $package
            }
        }
    }

    # The root Vanta trusted for these packages goes back only when no Vanta package is left and every removal worked
    # (a package that failed to come off still needs it); then exactly the recorded thumbprints are taken out of ROOT.
    if ($failedPackages.Count -eq 0) {
        $left = @($candidates | Where-Object { $_ -like '*Z-[AV]*-No*-Package*' -and $removedPackages -notcontains $_ })
        if ($left.Count -eq 0) {
            $rootsRemoved = @(Remove-VantaCbsRoot)
            if ($rootsRemoved.Count -gt 0) { Write-Host "[INFO] Removed the Vanta CBS root certificate(s): $($rootsRemoved -join ', ')." }
        }
    }

    return [pscustomobject]@{
        RemovedPackages   = $removedPackages
        FailedPackages    = $failedPackages
        UnmatchedPatterns = @($selection.UnmatchedPatterns)
    }
}
