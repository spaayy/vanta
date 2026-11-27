# Vanta.Appx domain: installed and provisioned package-family removal.
#
# Patterns match package family names (Name_PublisherId), not only the Name that
# Get-AppxPackage shows, so exact family names such as Edge's *_8wekyb3d8bbwe match.
#
# Remove-AppxPackage -AllUsers can report success yet leave a package registered to
# another account, SYSTEM or an account that no longer exists, and running it again
# doesn't change that. So a removal fails only on what reaches a person: a package
# still installed for the installing user, or still provisioned for new accounts.
# Every other leftover is a warning that names the package and its accounts, as is a
# removal Windows has accepted but finishes only when the app closes or the account
# signs out.
# https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/package-identity-overview
# https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage
# https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage

# Families the removal plans in this session matched, for Set-VantaAppxDeprovisioned.
$script:VantaAppxMatchedFamilies = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

# How long a removal may take to show in the inventory before leftovers are judged.
$script:VantaAppxRemovalSettleSeconds = 5

function Get-VantaAppxRemovalDefinition {
    <#
    .SYNOPSIS
        Returns the ordered package-family removal list the AppxSupport phase applies.
    #>
    # Paint, Camera, Clock, Sticky Notes, To Do, OneNote and Quick Assist stay: work apps are never removed by default.
    # Outlook and Teams stay too; removing them is a Tools choice.
    return @(
        [pscustomobject]@{ Name = 'Microsoft.MicrosoftEdge_8wekyb3d8bbwe';        Option = 'uninstall-edge';      IgnoreErrors = $true }
        [pscustomobject]@{ Name = 'Microsoft.MicrosoftEdge.Stable_8wekyb3d8bbwe'; Option = 'uninstall-edge';      IgnoreErrors = $true }
        [pscustomobject]@{ Name = 'Microsoft.Edge.GameAssist*';                   Option = 'uninstall-edge';      IgnoreErrors = $true }
        [pscustomobject]@{ Name = 'Microsoft.Copilot*';                           Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'MicrosoftWindows.Client.WebExperience*';       Option = $null;                 IgnoreErrors = $true }
        [pscustomobject]@{ Name = 'Microsoft.WidgetsPlatformRuntime*';            Option = $null;                 IgnoreErrors = $true }
        [pscustomobject]@{ Name = 'Clipchamp.Clipchamp*';                         Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Disney.37853FC22B2CE*';                        Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'SpotifyAB.SpotifyMusic*';                      Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.549981C3F5F10*';                     Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.XboxApp*';                           Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'microsoft.windowscommunicationsapps*';          Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.Getstarted*';                        Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.WindowsBackup*';                     Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.ZuneVideo*';                         Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.ZuneMusic*';                         Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'MicrosoftCorporationII.MicrosoftFamily*';       Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.MixedReality.Portal*';               Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.Windows.DevHome*';                   Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.BingWeather*';                       Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.BingNews*';                          Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.BingFinance*';                       Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.BingSports*';                        Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.BingSearch*';                        Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.GetHelp*';                           Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.Microsoft3DViewer*';                 Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.MicrosoftOfficeHub*';                Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.MicrosoftSolitaireCollection*';       Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.OneConnect*';                        Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.People*';                            Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.PowerAutomateDesktop*';              Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.ScreenSketch*';                      Option = 'remove-snipping-tool'; IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.SkypeApp*';                          Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.Wallet*';                            Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.Whiteboard*';                        Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.WindowsFeedbackHub*';                Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.WindowsMaps*';                       Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.WindowsSoundRecorder*';              Option = $null;                 IgnoreErrors = $false }
        [pscustomobject]@{ Name = 'Microsoft.StartExperiencesApp*';               Option = $null;                 IgnoreErrors = $false }
        # Every language's copy, not only en-US. A leftover only warns: Windows can keep
        # a language's handwriting package provisioned, and it isn't worth a failed install.
        [pscustomobject]@{ Name = 'Ink.Handwriting.Main.Store*';                  Option = $null;                 IgnoreErrors = $true }
    )
}

function Get-VantaAppxIdentityCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$Package
    )

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($propertyName in @('Name', 'DisplayName', 'PackageFamilyName', 'PackageFullName', 'PackageName')) {
        $property = $Package.PSObject.Properties[$propertyName]
        if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            $candidates.Add([string]$property.Value)
        }
    }

    # DISM's provisioned-package object does not consistently expose a family-name
    # property; derive Name_PublisherId so exact family patterns keep working.
    $packageNameProperty = $Package.PSObject.Properties['PackageName']
    if ($packageNameProperty) {
        $derivedFamily = ConvertTo-VantaAppxFamilyName -PackageName ([string]$packageNameProperty.Value)
        if ($derivedFamily) {
            $candidates.Add($derivedFamily)
        }
    }

    return @($candidates | Select-Object -Unique)
}

function ConvertTo-VantaAppxFamilyName {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$PackageName
    )

    # Full and provisioned package names follow
    # Name_Version_Architecture_ResourceId_PublisherId.
    $segments = @(([string]$PackageName) -split '_')
    if ($segments.Count -lt 5 -or [string]::IsNullOrWhiteSpace($segments[0])) {
        return $null
    }
    return ('{0}_{1}' -f $segments[0], $segments[$segments.Count - 1])
}

function Get-VantaAppxFamilyName {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$Package
    )

    $familyProperty = $Package.PSObject.Properties['PackageFamilyName']
    if ($familyProperty -and -not [string]::IsNullOrWhiteSpace([string]$familyProperty.Value)) {
        return [string]$familyProperty.Value
    }
    foreach ($propertyName in @('PackageFullName', 'PackageName')) {
        $property = $Package.PSObject.Properties[$propertyName]
        if ($property) {
            $family = ConvertTo-VantaAppxFamilyName -PackageName ([string]$property.Value)
            if ($family) {
                return $family
            }
        }
    }
    return $null
}

function Test-VantaAppxFamilyMatch {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$Package,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    foreach ($candidate in @(Get-VantaAppxIdentityCandidate -Package $Package)) {
        if ($candidate -like $Name) {
            return $true
        }
    }
    return $false
}

function Get-VantaAppxInstalledInventory {
    # Remove-AppxPackage -AllUsers acts on a parent package. Include bundles explicitly
    # as Microsoft documents; Main covers non-bundled app packages.
    return @(Get-AppxPackage -AllUsers -PackageTypeFilter Bundle, Main -ErrorAction Stop)
}

function Get-VantaAppxProvisionedInventory {
    return @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)
}

function Get-VantaAppxProvisionedFamily {
    <#
    .SYNOPSIS
        The family names (Name_PublisherId) of the packages Windows provisions, which it
        installs for each new account and a feature update brings back. A read that
        fails throws.
    #>
    return @(Get-VantaAppxProvisionedInventory | ForEach-Object { Get-VantaAppxFamilyName -Package $_ } |
            Where-Object { $_ } | Sort-Object -Unique)
}

function Test-VantaAppxBundle {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$Package
    )

    $isBundleProperty = $Package.PSObject.Properties['IsBundle']
    return [bool]($isBundleProperty -and [bool]$isBundleProperty.Value)
}

function Get-VantaAppxPackageKey {
    <#
    .SYNOPSIS
        Returns the family and version that tie a Main package to its bundle.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$Package
    )

    $family = Get-VantaAppxFamilyName -Package $Package
    $nameProperty = $Package.PSObject.Properties['Name']
    if (-not $family -and $nameProperty) {
        $family = [string]$nameProperty.Value
    }
    $version = $null
    $versionProperty = $Package.PSObject.Properties['Version']
    $fullNameProperty = $Package.PSObject.Properties['PackageFullName']
    if ($versionProperty -and -not [string]::IsNullOrWhiteSpace([string]$versionProperty.Value)) {
        $version = [string]$versionProperty.Value
    }
    elseif ($fullNameProperty) {
        $segments = @(([string]$fullNameProperty.Value) -split '_')
        if ($segments.Count -ge 5) {
            $version = $segments[1]
        }
    }
    return [pscustomobject]@{ Family = $family; Version = $version }
}

function Get-VantaAppxBundleOwner {
    <#
    .SYNOPSIS
        Returns the bundle a Main package belongs to, or $null when it has none.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$Package,

        [AllowEmptyCollection()]
        [psobject[]]$Bundle = @()
    )

    $key = Get-VantaAppxPackageKey -Package $Package
    if ([string]::IsNullOrWhiteSpace($key.Family)) {
        return $null
    }
    $sameFamily = @($Bundle | Where-Object {
            $bundleFamily = (Get-VantaAppxPackageKey -Package $_).Family
            $bundleFamily -and $bundleFamily.Equals($key.Family, [StringComparison]::OrdinalIgnoreCase)
        })
    if ($key.Version) {
        $sameVersion = @($sameFamily | Where-Object { (Get-VantaAppxPackageKey -Package $_).Version -eq $key.Version })
        if ($sameVersion.Count -gt 0) {
            return $sameVersion[0]
        }
    }
    # A bundle often numbers its version apart from the app inside it (Calculator's
    # 2021.x bundle holds an 11.x app), so the family's only bundle owns the package.
    # With several, it belongs to none of them: two accounts on different versions.
    if ($sameFamily.Count -eq 1) {
        return $sameFamily[0]
    }
    return $null
}

function Get-VantaAppxParentInstalledPackage {
    param(
        [AllowEmptyCollection()]
        [psobject[]]$Package = @()
    )

    # Get-AppxPackage returns both a bundle and its architecture-specific Main child
    # when Bundle,Main is requested. Remove-AppxPackage -AllUsers must act on the
    # parent bundle; attempting the child afterwards produces a false failure.
    $bundles = @($Package | Where-Object { Test-VantaAppxBundle -Package $_ })
    foreach ($item in $Package) {
        if ((Test-VantaAppxBundle -Package $item) -or
            $null -eq (Get-VantaAppxBundleOwner -Package $item -Bundle $bundles)) {
            $item
        }
    }
}

function Add-VantaAppxRemovalFailure {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Failures,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    if ([bool]$Definition.IgnoreErrors) {
        Write-VantaLog -Level Warning -Message "Ignoring AppX removal failure for '$($Definition.Name)': $Message"
        return
    }

    $Failures.Add("$($Definition.Name): $Message")
    Write-VantaLog -Level Error -Message "AppX removal failed for '$($Definition.Name)': $Message"
}

function Get-VantaAppxPropertyText {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$Package,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $property = $Package.PSObject.Properties[$Name]
    if (-not $property -or $null -eq $property.Value -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        return '(unknown)'
    }
    return [string]$property.Value
}

function ConvertTo-VantaAppxSentence {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    # Failures are joined into one message and logged one per line, so each is a
    # single line that ends its own sentence.
    $sentence = (([string]$Text) -replace '\s+', ' ').Trim()
    if ($sentence -and $sentence -notmatch '[.!?]$') {
        $sentence += '.'
    }
    return $sentence
}

function Get-VantaAppxRemovalAccount {
    <#
    .SYNOPSIS
        Returns the account whose own registrations decide whether a removal failed:
        its Sid, how messages name it, and, when Sid is $null, why there is none.
    #>
    $context = Get-VantaContext
    if ([bool]$context.IsInstallStateBacked) {
        $description = 'the installing user'
        if ([string]::IsNullOrWhiteSpace([string]$context.InteractiveUserSid)) {
            return [pscustomobject]@{
                Sid = $null; Description = $description
                Absence = 'The install recorded no installing user to check it against'
            }
        }
        # The check the cache cleanup applies to the same SID earlier in the phase.
        $sid = ConvertTo-VantaAppxCacheSid -Value ([string]$context.InteractiveUserSid) `
            -Label 'Install-state AppX removal user SID'
        return [pscustomobject]@{ Sid = $sid; Description = $description; Absence = $null }
    }

    # Outside an install, a toggle runs elevated as the account that chose it.
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $sid = $identity.User
        if ($null -eq $sid -or $sid.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
            return [pscustomobject]@{
                Sid = $null; Description = 'this account'
                Absence = 'This change runs as a service account, with no user to check it against'
            }
        }
        return [pscustomobject]@{ Sid = $sid.Value; Description = 'this account'; Absence = $null }
    }
    finally {
        $identity.Dispose()
    }
}

function Get-VantaAppxPackageRegistration {
    <#
    .SYNOPSIS
        Returns one Sid/UserName/InstallState record per PackageUserInformation entry
        that Get-AppxPackage -AllUsers reported for the package.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$Package
    )

    $informationProperty = $Package.PSObject.Properties['PackageUserInformation']
    if (-not $informationProperty -or $null -eq $informationProperty.Value) {
        return
    }

    foreach ($entry in @($informationProperty.Value)) {
        if ($null -eq $entry) {
            continue
        }
        $sid = $null
        $userName = $null
        $identityProperty = $entry.PSObject.Properties['UserSecurityId']
        if ($identityProperty -and $null -ne $identityProperty.Value) {
            $sidProperty = $identityProperty.Value.PSObject.Properties['Sid']
            $userNameProperty = $identityProperty.Value.PSObject.Properties['Username']
            if ($sidProperty) { $sid = [string]$sidProperty.Value }
            if ($userNameProperty) { $userName = [string]$userNameProperty.Value }
        }
        $stateProperty = $entry.PSObject.Properties['InstallState']
        [pscustomobject]@{
            Sid          = $sid
            UserName     = $userName
            InstallState = if ($stateProperty) { [string]$stateProperty.Value } else { $null }
        }
    }
}

function Get-VantaAppxRegistrationKind {
    <#
    .SYNOPSIS
        Classifies a PackageUserInformation InstallState as Installed, PendingRemoval
        or NotInstalled.
    #>
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$InstallState
    )

    # Get-AppxPackage appends '(pending removal)' to the state of a registration whose
    # removal Windows has accepted and finishes once the app closes or the account
    # signs out. A staged package has its files on disk but isn't installed for that
    # account. Any other state, including one a later Windows adds, counts as installed.
    $state = ([string]$InstallState).Trim()
    $baseState = ($state -replace '\s*\([^)]*\)$', '')
    if ($baseState -in @('Staged', 'NotInstalled')) {
        return 'NotInstalled'
    }
    if ($state -match '\(pending removal\)$') {
        return 'PendingRemoval'
    }
    return 'Installed'
}

function Format-VantaAppxRegistration {
    param(
        [AllowEmptyCollection()]
        [psobject[]]$Registration = @()
    )

    if ($Registration.Count -eq 0) {
        return 'no account has it registered'
    }
    $parts = foreach ($entry in $Registration) {
        $sid = if ([string]::IsNullOrWhiteSpace([string]$entry.Sid)) { '(unknown account)' } else { [string]$entry.Sid }
        $state = if ([string]::IsNullOrWhiteSpace([string]$entry.InstallState)) { '(unknown state)' } else { [string]$entry.InstallState }
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.UserName) -and
            -not ([string]$entry.UserName).Equals($sid, [StringComparison]::OrdinalIgnoreCase)) {
            '{0} ({1}): {2}' -f $sid, $entry.UserName, $state
        }
        else {
            '{0}: {1}' -f $sid, $state
        }
    }
    return ($parts -join '; ')
}

function Get-VantaAppxInstalledLeftover {
    <#
    .SYNOPSIS
        Groups installed packages that remain into one leftover per parent package, so
        a bundle and its Main child count once and carry both packages' registrations.
    #>
    param(
        [AllowEmptyCollection()]
        [psobject[]]$Package = @()
    )

    $bundles = @($Package | Where-Object { Test-VantaAppxBundle -Package $_ })
    foreach ($parent in @(Get-VantaAppxParentInstalledPackage -Package $Package)) {
        $members = [System.Collections.Generic.List[psobject]]::new()
        $members.Add($parent)
        $parentFullName = Get-VantaAppxPropertyText -Package $parent -Name PackageFullName
        if ((Test-VantaAppxBundle -Package $parent) -and $parentFullName -ne '(unknown)') {
            foreach ($item in $Package) {
                if (Test-VantaAppxBundle -Package $item) {
                    continue
                }
                $owner = Get-VantaAppxBundleOwner -Package $item -Bundle $bundles
                if ($null -ne $owner -and
                    (Get-VantaAppxPropertyText -Package $owner -Name PackageFullName) -eq $parentFullName) {
                    $members.Add($item)
                }
            }
        }

        $registrations = [System.Collections.Generic.List[psobject]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($member in $members) {
            foreach ($registration in @(Get-VantaAppxPackageRegistration -Package $member)) {
                if ($seen.Add("$($registration.Sid)|$($registration.InstallState)")) {
                    $registrations.Add($registration)
                }
            }
        }

        $fullNameProperty = $parent.PSObject.Properties['PackageFullName']
        $nonRemovable = $false
        foreach ($member in $members) {
            $nonRemovableProperty = $member.PSObject.Properties['NonRemovable']
            if ($nonRemovableProperty -and [bool]$nonRemovableProperty.Value) {
                $nonRemovable = $true
            }
        }
        [pscustomobject]@{
            FullName      = if ($fullNameProperty) { [string]$fullNameProperty.Value } else { $null }
            Packages      = $members.ToArray()
            Registrations = $registrations.ToArray()
            NonRemovable  = $nonRemovable
        }
    }
}

function Get-VantaAppxRemovalLeftover {
    <#
    .SYNOPSIS
        Returns, for each definition with anything left, its remaining installed
        leftovers and provisioned packages.
    #>
    param(
        [AllowEmptyCollection()]
        [psobject[]]$Definition = @(),

        [AllowEmptyCollection()]
        [psobject[]]$Installed = @(),

        [AllowEmptyCollection()]
        [psobject[]]$Provisioned = @()
    )

    foreach ($item in $Definition) {
        $installedMatches = @($Installed | Where-Object {
                Test-VantaAppxFamilyMatch -Package $_ -Name ([string]$item.Name)
            })
        $provisionedMatches = @($Provisioned | Where-Object {
                Test-VantaAppxFamilyMatch -Package $_ -Name ([string]$item.Name)
            })
        if ($installedMatches.Count -eq 0 -and $provisionedMatches.Count -eq 0) {
            continue
        }
        [pscustomobject]@{
            Definition  = $item
            Installed   = @(Get-VantaAppxInstalledLeftover -Package $installedMatches)
            Provisioned = $provisionedMatches
        }
    }
}

function Invoke-VantaAppxPerUserRemoval {
    <#
    .SYNOPSIS
        Best effort: removes each leftover once more for every account it is still
        installed for. Never fails; the inventory taken afterwards decides.
    #>
    param(
        [AllowEmptyCollection()]
        [psobject[]]$Leftover = @()
    )

    $attempted = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($result in $Leftover) {
        foreach ($package in @($result.Installed)) {
            if ([string]::IsNullOrWhiteSpace([string]$package.FullName)) {
                continue
            }
            # Windows refuses to remove a NonRemovable package for any account.
            if ($package.NonRemovable) {
                continue
            }
            # A removal Windows already accepted only waits for the app or account.
            foreach ($registration in @($package.Registrations)) {
                if ([string]::IsNullOrWhiteSpace([string]$registration.Sid) -or
                    (Get-VantaAppxRegistrationKind -InstallState $registration.InstallState) -ne 'Installed' -or
                    -not $attempted.Add("$($package.FullName)|$($registration.Sid)")) {
                    continue
                }
                try {
                    Remove-AppxPackage -Package $package.FullName -User $registration.Sid -Confirm:$false -ErrorAction Stop
                    Write-VantaLog -Message "Removed AppX package '$($package.FullName)' for account '$($registration.Sid)'."
                }
                catch {
                    Write-VantaLog -Message `
                        "Removing AppX package '$($package.FullName)' for account '$($registration.Sid)' reported an error: $($_.Exception.Message)"
                }
            }
        }
    }
}

function Read-VantaAppxRemainingInventory {
    <#
    .SYNOPSIS
        Re-reads both inventories. A read that fails keeps what the previous read
        found, so leftovers are still named, and is returned in Failures.
    #>
    param(
        [psobject]$Previous
    )

    $installed = @()
    $provisioned = @()
    if ($Previous) {
        $installed = @($Previous.Installed)
        $provisioned = @($Previous.Provisioned)
    }
    $failures = [System.Collections.Generic.List[string]]::new()
    try {
        $installed = @(Get-VantaAppxInstalledInventory)
    }
    catch {
        $failures.Add((ConvertTo-VantaAppxSentence -Text "Installed-package verification failed: $($_.Exception.Message)"))
    }

    try {
        $provisioned = @(Get-VantaAppxProvisionedInventory)
    }
    catch {
        $failures.Add((ConvertTo-VantaAppxSentence -Text "Provisioned-package verification failed: $($_.Exception.Message)"))
    }

    return [pscustomobject]@{
        Installed   = $installed
        Provisioned = $provisioned
        Failures    = $failures.ToArray()
    }
}

function Resolve-VantaAppxRemovalLeftover {
    <#
    .SYNOPSIS
        Logs every leftover in full and turns those that reach a person into required
        failures; the rest become warnings. Returns whether a required failure is an
        app still installed for the account, which that person can uninstall.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Failures,

        [AllowEmptyCollection()]
        [psobject[]]$Leftover = @(),

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [psobject]$Account
    )

    $userSid = [string]$Account.Sid
    $installedForAccount = $false
    foreach ($result in $Leftover) {
        $definition = $result.Definition
        foreach ($package in @($result.Installed)) {
            foreach ($member in @($package.Packages)) {
                Write-VantaLog -Message (
                    "AppX package '$(Get-VantaAppxPropertyText -Package $member -Name PackageFullName)' " +
                    "for '$($definition.Name)' is still registered: " +
                    "Status=$(Get-VantaAppxPropertyText -Package $member -Name Status), " +
                    "IsPartiallyStaged=$(Get-VantaAppxPropertyText -Package $member -Name IsPartiallyStaged), " +
                    "NonRemovable=$(Get-VantaAppxPropertyText -Package $member -Name NonRemovable), " +
                    "SignatureKind=$(Get-VantaAppxPropertyText -Package $member -Name SignatureKind); " +
                    "accounts: $(Format-VantaAppxRegistration -Registration @(Get-VantaAppxPackageRegistration -Package $member))."
                )
            }

            $fullName = if ([string]::IsNullOrWhiteSpace([string]$package.FullName)) { '(no full name)' } else { [string]$package.FullName }
            $accounts = Format-VantaAppxRegistration -Registration @($package.Registrations)
            $userKinds = @()
            if (-not [string]::IsNullOrWhiteSpace($userSid)) {
                $userKinds = @($package.Registrations | Where-Object {
                        -not [string]::IsNullOrWhiteSpace([string]$_.Sid) -and
                        ([string]$_.Sid).Equals($userSid, [StringComparison]::OrdinalIgnoreCase)
                    } | ForEach-Object { Get-VantaAppxRegistrationKind -InstallState $_.InstallState })
            }
            if ($userKinds -contains 'Installed') {
                Add-VantaAppxRemovalFailure -Failures $Failures -Definition $definition `
                    -Message "'$fullName' is still installed for $($Account.Description) ($userSid)."
                if (-not [bool]$definition.IgnoreErrors) {
                    $installedForAccount = $true
                }
            }
            elseif ([string]::IsNullOrWhiteSpace($userSid)) {
                Write-VantaLog -Level Warning -Message (
                    "AppX package '$fullName' for '$($definition.Name)' is still registered ($accounts). " +
                    "$($Account.Absence), so Vanta continues."
                )
            }
            elseif ($userKinds -contains 'PendingRemoval') {
                Write-VantaLog -Level Warning -Message (
                    "AppX package '$fullName' for '$($definition.Name)' is still registered, but Windows finishes " +
                    "removing it for $($Account.Description) when the app closes or the account signs out " +
                    "($accounts), so Vanta continues."
                )
            }
            else {
                Write-VantaLog -Level Warning -Message (
                    "AppX package '$fullName' for '$($definition.Name)' is still registered, " +
                    "but not installed for $($Account.Description) ($accounts), so Vanta continues."
                )
            }
        }

        $provisionedNames = @($result.Provisioned | ForEach-Object {
                $packageNameProperty = $_.PSObject.Properties['PackageName']
                if ($packageNameProperty -and -not [string]::IsNullOrWhiteSpace([string]$packageNameProperty.Value)) {
                    "'$($packageNameProperty.Value)'"
                }
                else {
                    "'$(Get-VantaAppxPropertyText -Package $_ -Name DisplayName)'"
                }
            })
        if ($provisionedNames.Count -gt 0) {
            Add-VantaAppxRemovalFailure -Failures $Failures -Definition $definition `
                -Message "Still provisioned for new accounts: $($provisionedNames -join ', ')."
        }
    }
    return $installedForAccount
}

function Invoke-VantaAppxRemovalPlan {
    <#
    .SYNOPSIS
        Removes matching installed registrations for every existing user and matching
        provisioned packages for future users, then verifies both inventories.
    .DESCRIPTION
        All definitions are attempted in order. Command failures remain visible, but
        the fresh inventories taken afterwards determine whether a required removal
        actually failed: a package still installed for the installing user, or still
        provisioned. A package left only for other accounts, SYSTEM or no account, or
        whose removal Windows finishes at sign-out, is a warning. Definitions marked
        IgnoreErrors only warn. Option gates come from the install context.
    #>
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [psobject[]]$Definition = @(Get-VantaAppxRemovalDefinition)
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    $activeDefinitions = [System.Collections.Generic.List[psobject]]::new()
    # Read before any removal, so an unreadable install state stops the plan first.
    $account = Get-VantaAppxRemovalAccount

    try {
        $installedInventory = @(Get-VantaAppxInstalledInventory)
    }
    catch {
        $installedInventory = @()
        $message = ConvertTo-VantaAppxSentence -Text "Installed-package inventory failed: $($_.Exception.Message)"
        $failures.Add($message)
        Write-VantaLog -Level Error -Message $message
    }

    try {
        $provisionedInventory = @(Get-VantaAppxProvisionedInventory)
    }
    catch {
        $provisionedInventory = @()
        $message = ConvertTo-VantaAppxSentence -Text "Provisioned-package inventory failed: $($_.Exception.Message)"
        $failures.Add($message)
        Write-VantaLog -Level Error -Message $message
    }

    $removedInstalled = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $removedProvisioned = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($item in $Definition) {
        foreach ($requiredProperty in @('Name', 'Option', 'IgnoreErrors')) {
            if (-not $item.PSObject.Properties[$requiredProperty]) {
                throw "AppX removal definition is missing required property '$requiredProperty'."
            }
        }
        if ([string]::IsNullOrWhiteSpace([string]$item.Name)) {
            throw 'AppX removal definition Name cannot be empty.'
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$item.Option) -and
            -not (Test-VantaOption -Name ([string]$item.Option))) {
            Write-VantaLog -Message "Skipped AppX family '$($item.Name)' because option '$($item.Option)' is not selected."
            continue
        }

        $activeDefinitions.Add($item)
        Write-VantaLog -Message "Removing AppX family '$($item.Name)'."

        $installedMatches = @($installedInventory | Where-Object {
                Test-VantaAppxFamilyMatch -Package $_ -Name ([string]$item.Name)
            })
        $provisionedMatches = @($provisionedInventory | Where-Object {
                Test-VantaAppxFamilyMatch -Package $_ -Name ([string]$item.Name)
            })
        foreach ($package in @($installedMatches + $provisionedMatches)) {
            $family = Get-VantaAppxFamilyName -Package $package
            if ($family) {
                [void]$script:VantaAppxMatchedFamilies.Add($family)
            }
        }

        foreach ($package in @(Get-VantaAppxParentInstalledPackage -Package $installedMatches)) {
            $fullNameProperty = $package.PSObject.Properties['PackageFullName']
            $fullName = if ($fullNameProperty) { [string]$fullNameProperty.Value } else { $null }
            if ([string]::IsNullOrWhiteSpace($fullName)) {
                Add-VantaAppxRemovalFailure -Failures $failures -Definition $item `
                    -Message 'An installed match did not expose PackageFullName.'
                continue
            }
            if (-not $removedInstalled.Add($fullName)) {
                continue
            }

            try {
                Remove-AppxPackage -Package $fullName -AllUsers -Confirm:$false -ErrorAction Stop
                Write-VantaLog -Message "Removed installed AppX package '$fullName' for all users."
            }
            catch {
                Write-VantaLog -Message `
                    "Installed AppX removal command reported an error for '$fullName'; deferring to final inventory: $($_.Exception.Message)"
            }
        }

        foreach ($package in $provisionedMatches) {
            $packageNameProperty = $package.PSObject.Properties['PackageName']
            $packageName = if ($packageNameProperty) { [string]$packageNameProperty.Value } else { $null }
            if ([string]::IsNullOrWhiteSpace($packageName)) {
                Add-VantaAppxRemovalFailure -Failures $failures -Definition $item `
                    -Message 'A provisioned match did not expose PackageName.'
                continue
            }
            if (-not $removedProvisioned.Add($packageName)) {
                continue
            }

            try {
                Remove-AppxProvisionedPackage -PackageName $packageName -Online -AllUsers `
                    -ErrorAction Stop | Out-Null
                Write-VantaLog -Message "Removed provisioned AppX package '$packageName'."
            }
            catch {
                Write-VantaLog -Message `
                    "Provisioned AppX removal command reported an error for '$packageName'; deferring to final inventory: $($_.Exception.Message)"
            }
        }
    }

    # Re-inventory after every removal attempt. A cmdlet returning without a terminating
    # error is not enough evidence that registration/provisioning state actually changed.
    $remaining = Read-VantaAppxRemainingInventory
    $leftovers = @(Get-VantaAppxRemovalLeftover -Definition $activeDefinitions.ToArray() `
            -Installed $remaining.Installed -Provisioned $remaining.Provisioned)
    if ($leftovers.Count -gt 0 -or $remaining.Failures.Count -gt 0) {
        # Removal can take a moment to show in the inventory, and a read can fail
        # while it settles, so look again before judging, after one more removal for
        # each account a leftover is installed for.
        foreach ($message in $remaining.Failures) {
            Write-VantaLog -Level Warning -Message "$message Vanta looks again shortly."
        }
        Invoke-VantaAppxPerUserRemoval -Leftover $leftovers
        Start-Sleep -Seconds $script:VantaAppxRemovalSettleSeconds
        $remaining = Read-VantaAppxRemainingInventory -Previous $remaining
        $leftovers = @(Get-VantaAppxRemovalLeftover -Definition $activeDefinitions.ToArray() `
                -Installed $remaining.Installed -Provisioned $remaining.Provisioned)
    }
    # Only the last look decides: a read that failed once and then worked proves nothing.
    foreach ($message in $remaining.Failures) {
        $failures.Add($message)
        Write-VantaLog -Level Error -Message $message
    }
    $installedForAccount = Resolve-VantaAppxRemovalLeftover -Failures $failures -Leftover $leftovers -Account $account

    if ($failures.Count -gt 0) {
        $message = "AppX removal completed with $($failures.Count) required failure(s): $($failures -join ' | ')"
        if ($installedForAccount) {
            $message += ' An app still installed for you can be uninstalled in Settings > Apps before you try again.'
        }
        throw $message
    }
}
