# Tweaks phase: applies declarative tweaks in ordered scopes. Machine work and the
# narrowly allowed live-user policy roots run as TrustedInstaller, ordinary HKCU work as
# the exact installing user, then the default hive. The install plan runs it once for
# each tweak category, and once for each Standalone tweak it places.
#
# -Category applies one manifest category. -Slug applies one Standalone manifest tweak
# that the install plan places outside the category order; such a tweak may declare only
# machine and default-user work, because its live-user passes are never run.
[CmdletBinding(DefaultParameterSetName = 'Category')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Category')]
    [ValidateSet('networking', 'performance', 'privacy', 'qol', 'security', 'debloat', 'scripts', 'misc')]
    [string]$Category,

    [Parameter(Mandatory = $true, ParameterSetName = 'Slug')]
    [ValidatePattern('^[a-z0-9-]+(/[a-z0-9-]+)+$', Options = [Text.RegularExpressions.RegexOptions]::None)]
    [string]$Slug
)

Assert-VantaPrivilege -TrustedInstaller

$context = Get-VantaContext -Refresh
if (-not $context.IsInstallStateBacked) {
    throw 'Tweaks phase requires active Vanta install state.'
}
if ([string]::IsNullOrWhiteSpace([string]$context.TransactionId)) {
    throw 'Tweaks phase requires the Vanta transaction id.'
}
if ([string]::IsNullOrWhiteSpace([string]$context.InteractiveUserSid)) {
    throw 'Tweaks require the install-state user SID.'
}

$scriptsRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$modulesRoot = Join-Path -Path $scriptsRoot -ChildPath 'Modules'
Import-Module -Name (Join-Path $modulesRoot 'Vanta.Registry\Vanta.Registry.psd1') -Force -ErrorAction Stop
Import-Module -Name (Join-Path $modulesRoot 'Vanta.Tweaks\Vanta.Tweaks.psd1') -Force -ErrorAction Stop
. (Join-Path $scriptsRoot 'Install\Tasks\Get-VantaUserFailureDetail.ps1')

function Invoke-VantaTweakUserScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description script is missing at '$Path'."
    }
    $hostArguments = [string[]]@(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $Path
    ) + $ArgumentList
    $arguments = ConvertTo-VantaWindowsArgumentString -ArgumentList $hostArguments
    $started = Get-Date
    $exitCode = Invoke-VantaAsUser -FilePath $script:powerShellPath `
        -Arguments $arguments -WorkingDirectory ([string]$context.WinDir)
    if ($exitCode -ne 0) {
        # The child logs why in the user's own log; name it here so the install's
        # error says which change failed.
        throw "$Description exited with code $exitCode.$(Get-VantaUserLogError -UserSid ([string]$context.InteractiveUserSid) -NotBefore $started)"
    }
}

function Invoke-VantaTweakCategoryPasses {
    param([Parameter(Mandatory = $true)][string]$Name)

    # Companion scripts execute in this machine pass. RegistryScope keeps HKCU out of it.
    Invoke-VantaTweakCategory -Name $Name -RegistryScope Machine

    $optionSnapshot = [string[]]@($context.Options)
    $optionsJson = ConvertTo-Json -Compress -InputObject $optionSnapshot
    $optionsBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($optionsJson))

    $policyArguments = [string[]]@(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $scriptsRoot 'Install\Tasks\Invoke-VantaInstallingUserPolicyRegistry.ps1'),
        '-Category', $Name,
        '-ExpectedUserSid', [string]$context.InteractiveUserSid,
        '-TransactionId', [string]$context.TransactionId,
        '-OptionsBase64', $optionsBase64,
        '-WindowsBuild', [string]$context.WindowsBuild
    )
    if ($context.IsUpgrade) { $policyArguments += '-IsUpgrade' }
    if ($context.IsRebase) { $policyArguments += '-IsRebase' }
    if ($context.IsArm64) { $policyArguments += '-IsArm64' }
    Invoke-VantaHiddenProcess -FilePath $script:powerShellPath -ArgumentList $policyArguments -Wait | Out-Null

    $registryArguments = @(
        '-Category', $Name,
        '-ExpectedUserSid', [string]$context.InteractiveUserSid,
        '-OptionsBase64', $optionsBase64,
        '-WindowsBuild', [string]$context.WindowsBuild
    )
    if ($context.IsUpgrade) { $registryArguments += '-IsUpgrade' }
    if ($context.IsRebase) { $registryArguments += '-IsRebase' }
    if ($context.IsArm64) { $registryArguments += '-IsArm64' }

    Invoke-VantaTweakUserScript `
        -Path (Join-Path $scriptsRoot 'Install\Tasks\Invoke-VantaInstallingUserRegistry.ps1') `
        -ArgumentList $registryArguments `
        -Description "Installing-user registry category '$Name'"

    $refreshOperations = @(Get-VantaTweakCategoryPostUserRegistryRefresh -Name $Name -Context $context)
    foreach ($operation in $refreshOperations) {
        Invoke-VantaTweakUserScript `
            -Path (Join-Path $scriptsRoot 'Operations\Invoke-VantaUserShellRefresh.ps1') `
            -ArgumentList @(
                '-Operation', [string]$operation,
                '-ExpectedUserSid', [string]$context.InteractiveUserSid
            ) `
            -Description "Post-registry shell refresh '$operation' for '$Name'"
    }

    # Default-user data is applied only after any live-user work succeeds.
    $null = Initialize-VantaRegistryIdentityContext -DefaultUserOnly -TransactionId ([string]$context.TransactionId)
    Invoke-VantaTweakCategory -Name $Name -RegistryScope DefaultUser -RegistryOnly
}

function Invoke-VantaStandaloneTweakPasses {
    param([Parameter(Mandatory = $true)][string]$Slug)

    $tweaksRoot = Join-Path -Path $scriptsRoot -ChildPath 'Tweaks'
    $manifest = Get-VantaTweakManifest -Path (Join-Path -Path $tweaksRoot -ChildPath 'tweaks.manifest.psd1')
    $standalone = @($manifest['Standalone'] | Where-Object { [string]$_['Slug'] -ceq $Slug })
    if ($standalone.Count -ne 1) {
        throw "Tweak '$Slug' is not declared once under the manifest's Standalone list."
    }

    $path = Join-Path -Path $tweaksRoot -ChildPath (($Slug -replace '/', '\') + '.psd1')
    $tweak = Import-VantaDataFile -LiteralPath $path
    foreach ($entry in @($tweak['Registry'])) {
        if ($null -eq $entry -or -not $entry.ContainsKey('Path')) {
            continue
        }
        $scope = Get-VantaRegistryEntryTargetScope -Path ([string]$entry['Path'])
        if ($scope -in @('CurrentUser', 'ProtectedCurrentUser')) {
            throw "Standalone tweak '$Slug' declares live-user registry entry '$($entry['Path'])'; standalone tweaks run only machine and default-user passes."
        }
    }

    Invoke-VantaTweak -Path $path -RegistryScope Machine
    $null = Initialize-VantaRegistryIdentityContext -DefaultUserOnly -TransactionId ([string]$context.TransactionId)
    Invoke-VantaTweak -Path $path -RegistryScope DefaultUser -RegistryOnly
}

$script:powerShellPath = Join-Path -Path ([string]$context.WinDir) -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $script:powerShellPath -PathType Leaf)) {
    throw "Windows PowerShell is missing at '$script:powerShellPath'."
}

if ($PSCmdlet.ParameterSetName -ceq 'Slug') {
    Invoke-VantaStandaloneTweakPasses -Slug $Slug
}
else {
    Invoke-VantaTweakCategoryPasses -Name $Category
}
