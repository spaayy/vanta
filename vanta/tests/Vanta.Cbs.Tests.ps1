BeforeAll {
    $script:modulesRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\package\Executables\VantaModules')).Path
    $script:packages = Join-Path $modulesRoot 'Packages'
    # CbsPackages.ps1 lives in a module; the few functions it takes from the rest of the module are stubbed here.
    function Import-VantaDataFile { param([string]$LiteralPath) Import-PowerShellDataFile -LiteralPath $LiteralPath }
    function Assert-VantaPrivilege { param([switch]$TrustedInstaller) }
    function Test-VantaSoftwareArm64 { $false }
    . (Join-Path $modulesRoot 'Scripts\Modules\Vanta.Software\Domain\CbsPackages.ps1')

    function New-TestCertificate {
        param([string]$Subject = 'CN=Vanta CBS Packages, O=Vanta', [string]$Issuer = $Subject, [string[]]$Eku = @('1.3.6.1.4.1.311.10.3.6'))
        $rsa = [Security.Cryptography.RSA]::Create(2048)
        $name = [Security.Cryptography.X509Certificates.X500DistinguishedName]::new($Subject)
        $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new($name, $rsa, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
        if ($Eku.Count) {
            $usages = [Security.Cryptography.OidCollection]::new()
            foreach ($oid in $Eku) { [void]$usages.Add([Security.Cryptography.Oid]::new($oid)) }
            $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($usages, $false))
        }
        $request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1), [DateTimeOffset]::UtcNow.AddYears(1))
    }
    function Set-SignedCab {
        <# A stand-in CAB whose pinned hash is right, signed (as far as the mocked reader says) by $Certificate. #>
        param($Certificate, [string]$Status = 'UnknownError', [switch]$WrongHash)
        $cab = Join-Path $TestDrive ('Z-Test-' + [guid]::NewGuid().ToString('N') + '.cab')
        Set-Content -LiteralPath $cab 'cab bytes'
        $hash = if ($WrongHash) { 'A' * 64 } else { (Get-FileHash -LiteralPath $cab -Algorithm SHA256).Hash }
        $script:expectedHashes = @{ (Split-Path $cab -Leaf) = $hash }
        $script:signature = [pscustomobject]@{ Status = $Status; SignerCertificate = $Certificate }
        return $cab
    }
}

Describe 'CBS signer identity' {
    BeforeEach {
        Mock Get-VantaCbsExpectedHashes { $script:expectedHashes }
        Mock Get-AuthenticodeSignature { $script:signature }
    }
    It 'accepts the exact Vanta signer: self-signed, with the Windows component EKU' {
        $cab = Set-SignedCab (New-TestCertificate)
        (Assert-VantaCbsCertificate -CabPath $cab).Subject | Should -BeExactly 'CN=Vanta CBS Packages, O=Vanta'
    }
    It 'refuses CN=Microsoft Windows, O=Microsoft Corporation' {
        $cab = Set-SignedCab (New-TestCertificate -Subject 'CN=Microsoft Windows, O=Microsoft Corporation')
        { Assert-VantaCbsCertificate -CabPath $cab } | Should -Throw '*not signed by*Vanta CBS Packages*'
    }
    It 'refuses a near miss: a longer subject, another issuer, another organisation' -ForEach @(
        @{ Subject = 'CN=Vanta CBS Packages, O=Vanta, C=US'; Issuer = $null }
        @{ Subject = 'CN=Vanta CBS Packages, O=Vanta'; Issuer = 'CN=Somebody Else, O=Vanta' }
        @{ Subject = 'CN=Vanta CBS Packages, O=Vanta Inc'; Issuer = $null }
        @{ Subject = 'cn=vanta cbs packages, o=vanta'; Issuer = $null }
    ) {
        $certificate = if ($Issuer) {
            # the issuer cannot differ in a real self-signed certificate; the reader is mocked to report it
            [pscustomobject]@{ Subject = $Subject; Issuer = $Issuer; Extensions = (New-TestCertificate).Extensions; Thumbprint = ('B' * 40) }
        } else { New-TestCertificate -Subject $Subject }
        $cab = Set-SignedCab $certificate
        { Assert-VantaCbsCertificate -CabPath $cab } | Should -Throw '*not signed by*'
    }
    It 'refuses a signer without the Windows component EKU, or with another EKU' -ForEach @(
        @{ Eku = @() }
        @{ Eku = @('1.3.6.1.5.5.7.3.3') }
    ) {
        $cab = Set-SignedCab (New-TestCertificate -Eku $Eku)
        { Assert-VantaCbsCertificate -CabPath $cab } | Should -Throw '*lacks the Windows component EKU*'
    }
    It 'refuses a CAB whose SHA-256 differs from Vanta-CbsHashes.psd1, however good the signature' {
        $cab = Set-SignedCab (New-TestCertificate) -WrongHash
        { Assert-VantaCbsCertificate -CabPath $cab } | Should -Throw '*SHA256 mismatch*'
    }
    It 'refuses an unsigned or altered CAB' -ForEach @(@{ Status = 'NotSigned' }, @{ Status = 'HashMismatch' }) {
        $cab = Set-SignedCab (New-TestCertificate) -Status $Status
        { Assert-VantaCbsCertificate -CabPath $cab } | Should -Throw '*not intact*'
    }
    It 'takes the signer from the package profile when it carries one, and still compares it exactly' {
        $legacy = New-TestCertificate -Subject 'CN=Other Signer, O=Test'
        $cab = Set-SignedCab $legacy
        $script:expectedHashes['Signer'] = 'CN=Other Signer, O=Test'
        $script:expectedHashes['TrustMode'] = 'LegacyKey'
        (Assert-VantaCbsCertificate -CabPath $cab).Subject | Should -BeExactly 'CN=Other Signer, O=Test'
        (Get-VantaCbsSignerProfile -PackagesPath (Split-Path $cab -Parent)).TrustMode | Should -Be 'LegacyKey'
        $script:expectedHashes['Signer'] = 'CN=Other Signer, O=Test, C=US'
        { Assert-VantaCbsCertificate -CabPath $cab } | Should -Throw '*not signed by*'
    }
    It 'refuses an unknown trust mode' {
        $cab = Set-SignedCab (New-TestCertificate)
        $script:expectedHashes['TrustMode'] = 'Anything'
        { Get-VantaCbsSignerProfile -PackagesPath (Split-Path $cab -Parent) } | Should -Throw '*Unknown CBS trust mode*'
    }
}

Describe 'Vanta CBS root: trusted on install, taken back on uninstall by thumbprint' {
    BeforeEach {
        $script:record = @()
        $script:rootStore = [Collections.Generic.List[string]]::new()
        $script:removedFromRoot = [Collections.Generic.List[string]]::new()
        Mock Get-VantaCbsRootRecord { @($script:record) }
        Mock Set-VantaCbsRootRecord { param([string[]]$Thumbprint = @()) $script:record = @($Thumbprint) }
        Mock Test-VantaCbsRootCertificate { param($Thumbprint) $script:rootStore -contains $Thumbprint }
        Mock Add-VantaCbsRootCertificate { param($Certificate) $script:rootStore.Add($Certificate.Thumbprint.ToUpperInvariant()) }
        Mock Remove-VantaCbsRootCertificate { param($Thumbprint) [void]$script:rootStore.Remove($Thumbprint); $script:removedFromRoot.Add($Thumbprint) }
    }
    It 'trusts the signer once and records exactly its thumbprint' {
        $cert = New-TestCertificate
        Install-VantaCbsRoot -Certificate $cert | Should -BeTrue
        Install-VantaCbsRoot -Certificate $cert | Should -BeFalse
        $script:record | Should -Be @($cert.Thumbprint.ToUpperInvariant())
        Should -Invoke Add-VantaCbsRootCertificate -Times 1 -Exactly
    }
    It 'does not record, and so never removes, a root the PC already trusted before Vanta' {
        $cert = New-TestCertificate
        $script:rootStore.Add($cert.Thumbprint.ToUpperInvariant())
        Install-VantaCbsRoot -Certificate $cert | Should -BeFalse
        $script:record | Should -BeNullOrEmpty
    }
    It 'removal touches only the recorded thumbprint, leaving every other root alone' {
        $ours = New-TestCertificate
        $other = New-TestCertificate -Subject 'CN=Vanta CBS Packages, O=Vanta'   # same name, another certificate
        [void](Install-VantaCbsRoot -Certificate $ours)
        $script:rootStore.Add($other.Thumbprint.ToUpperInvariant())
        $removed = @(Remove-VantaCbsRoot)
        $removed | Should -Be @($ours.Thumbprint.ToUpperInvariant())
        $script:removedFromRoot.Count | Should -Be 1
        $script:removedFromRoot[0] | Should -BeExactly $ours.Thumbprint.ToUpperInvariant()
        $script:rootStore | Should -Contain $other.Thumbprint.ToUpperInvariant()
        $script:record | Should -BeNullOrEmpty
    }
    It 'ignores a malformed record entry instead of removing anything by it' {
        $script:record = @('*', 'Vanta')
        @(Remove-VantaCbsRoot).Count | Should -Be 0
        Should -Invoke Remove-VantaCbsRootCertificate -Times 0
    }
    It 'keeps the record of a root that could not be removed, to try again' {
        $cert = New-TestCertificate
        [void](Install-VantaCbsRoot -Certificate $cert)
        Mock Remove-VantaCbsRootCertificate { throw 'access denied' }
        @(Remove-VantaCbsRoot).Count | Should -Be 0
        $script:record | Should -Be @($cert.Thumbprint.ToUpperInvariant())
    }
}

Describe 'Uninstall-VantaCbsPackage and the root' {
    BeforeEach {
        $script:remaining = @()
        Mock Initialize-VantaCbsEnvironment {}
        Mock Get-VantaCbsArchitecture { 'amd64' }
        Mock Get-WindowsPackage { @($script:remaining | ForEach-Object { [pscustomobject]@{ PackageName = $_ } }) }
        Mock Remove-WindowsPackage {}
        Mock Remove-VantaCbsRoot { @('X') }
    }
    It 'takes the root back only when no Vanta package is left' {
        $script:remaining = @('Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~5.0.0.0')
        $result = Uninstall-VantaCbsPackage -Packages @('*Z-[AV]*-NoDefender-Package*')
        @($result.RemovedPackages).Count | Should -Be 1
        Should -Invoke Remove-VantaCbsRoot -Times 1 -Exactly
    }
    It 'keeps the root while another Vanta package is still installed' {
        $script:remaining = @('Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~5.0.0.0', 'Z-Vanta-NoTelemetry-Package~31bf3856ad364e35~amd64~~5.0.0.0')
        [void](Uninstall-VantaCbsPackage -Packages @('*Z-[AV]*-NoDefender-Package*'))
        Should -Invoke Remove-VantaCbsRoot -Times 0
    }
    It 'keeps the root when a package failed to come off' {
        $script:remaining = @('Z-Vanta-NoDefender-Package~31bf3856ad364e35~amd64~~5.0.0.0')
        Mock Remove-WindowsPackage { throw 'busy' }
        $result = Uninstall-VantaCbsPackage -Packages @('*Z-[AV]*-NoDefender-Package*')
        @($result.FailedPackages).Count | Should -Be 1
        Should -Invoke Remove-VantaCbsRoot -Times 0
    }
}

Describe 'The repository carries no CBS package and no Microsoft identity' {
    It 'has no CAB and no hash manifest under package/ (the personal build fetches its own at build time)' {
        $repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        @(Get-ChildItem -LiteralPath (Join-Path $repo 'package') -Recurse -File -Include *.cab, Vanta-CbsHashes.psd1).Count | Should -Be 0
    }
    It 'names the Microsoft Windows publisher only in tests that expect it to be refused' {
        $repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $hits = @(Get-ChildItem -LiteralPath (Join-Path $repo 'package'), (Join-Path $repo 'vanta') -Recurse -File -Include *.ps1, *.psd1, *.psm1, *.json, *.md, *.yaml |
            Where-Object { $_.FullName -notmatch '[\/](out|target)[\/]' } |
            Select-String -Pattern 'CN=Microsoft Windows' -SimpleMatch)
        @($hits | Where-Object { $_.Path -notlike '*Vanta.Cbs.Tests.ps1' }) | Should -BeNullOrEmpty
    }
}

Describe 'Test-VantaCbsPackagesAvailable' {
    It 'is false for a package without CABs (the public edition) and true with a CAB for the architecture' -ForEach @(
        @{ Cabs = @(); Arch = 'amd64'; Expected = $false }
        @{ Cabs = @('Z-Vanta-NoTelemetry-Package31bf3856ad364e35amd645.0.0.0.cab'); Arch = 'amd64'; Expected = $true }
        @{ Cabs = @('Z-Vanta-NoTelemetry-Package31bf3856ad364e35amd645.0.0.0.cab'); Arch = 'arm64'; Expected = $false }
    ) {
        $dir = Join-Path $TestDrive ('pk' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        foreach ($cab in $Cabs) { Set-Content (Join-Path $dir $cab) 'x' }
        $script:arch = $Arch
        Mock Get-VantaCbsArchitecture { $script:arch }
        Test-VantaCbsPackagesAvailable -PackagesPath $dir | Should -Be $Expected
        Test-VantaCbsPackagesAvailable -PackagesPath (Join-Path $dir 'missing') | Should -BeFalse
    }
}
