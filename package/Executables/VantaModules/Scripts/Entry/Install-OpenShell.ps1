[CmdletBinding()]
param(
    [switch]$Silent,

    # The non-elevated launcher restarts File Explorer itself after this elevated
    # script returns, so the closing notice must not ask the user to do it.
    [switch]$ShellRefreshByCaller
)

$ErrorActionPreference = 'Stop'

# VantaDesktop's .cmd file is a compatibility shim only. It captures one legacy
# token as data; validate it here and never replay its command text through UAC.
$launcherArgument = [Environment]::GetEnvironmentVariable(
    'VantaLauncherArgument',
    [EnvironmentVariableTarget]::Process
)
[Environment]::SetEnvironmentVariable(
    'VantaLauncherArgument',
    $null,
    [EnvironmentVariableTarget]::Process
)
if (-not [string]::IsNullOrEmpty($launcherArgument)) {
    if (-not $launcherArgument.Equals('/silent', [StringComparison]::OrdinalIgnoreCase) -and
        -not $launcherArgument.Equals('-silent', [StringComparison]::OrdinalIgnoreCase)) {
        [Console]::Error.WriteLine("Unsupported Open-Shell launcher argument '$launcherArgument'.")
        exit 2
    }
    $Silent = $true
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
$identity.Dispose()

if (-not $isAdministrator) {
    [Console]::Error.WriteLine('Administrator privileges are required to install Open-Shell.')
    exit 1
}

$scriptsRoot = [IO.Path]::GetDirectoryName($PSScriptRoot)
$trustBootstrap = [IO.Path]::Combine(
    $scriptsRoot,
    'Initialize-VantaPowerShell.ps1'
)
if (-not [IO.File]::Exists($trustBootstrap)) {
    [Console]::Error.WriteLine("The PowerShell trust bootstrap is missing at '$trustBootstrap'.")
    exit 1
}
. $trustBootstrap

$title = 'Install Open-Shell'
$coreManifest = [IO.Path]::Combine($scriptsRoot, 'Modules', 'Vanta.Core', 'Vanta.Core.psd1')
Import-Module -Name $coreManifest -ErrorAction Stop
if (-not $Silent) {
    Set-VantaLogConsoleStyle -Style Interactive
    Write-VantaTitle -Text $title -Explanation 'Installs Open-Shell with the Vanta Fluent Metro start-menu theme.'
}

try {
    $packageInstaller = [IO.Path]::Combine(
        $scriptsRoot,
        'Operations',
        'Install-OpenShellPackage.ps1'
    )
    $themeInstaller = [IO.Path]::Combine(
        $scriptsRoot,
        'Operations',
        'Install-OpenShellTheme.ps1'
    )
    if (-not [IO.File]::Exists($packageInstaller) -or
        -not [IO.File]::Exists($themeInstaller)) {
        throw 'One or more protected Open-Shell installer helpers are missing.'
    }

    if (-not $Silent) {
        Write-VantaStep -Text 'Downloading and installing Open-Shell...'
    }
    $packageResult = & $packageInstaller
    if ($null -eq $packageResult -or
        $packageResult.PSObject.Properties.Name -notcontains 'RebootRequired') {
        throw 'The Open-Shell package helper did not return its typed installation result.'
    }

    if (-not $Silent) {
        Write-VantaStep -Text 'Installing the Fluent Metro theme...'
    }
    $themeFailure = $null
    try {
        & $themeInstaller
    }
    catch {
        $themeFailure = $_.Exception.Message
        Write-Warning "The pinned Fluent Metro theme could not be installed: $themeFailure"
    }

    if ($null -ne $themeFailure) {
        [Console]::Error.WriteLine(
            "Open-Shell was installed, but its pinned Fluent Metro theme failed transactionally: $themeFailure"
        )
        if (-not $Silent) {
            Write-VantaPartial -Text 'Open-Shell is installed, but its Fluent Metro theme could not be installed.'
            Write-VantaCompletion -Title $title
            Wait-VantaExit
        }
        exit 3
    }

    if (-not $Silent) {
        Write-VantaCompletion -Title $title
        if ([bool]$packageResult.RebootRequired) {
            Write-VantaRestartNotice -Kind Required
        }
        elseif (-not $ShellRefreshByCaller) {
            Write-VantaRestartNotice -Kind ExplorerRestartNeeded
        }
        Wait-VantaExit
    }
    if ([bool]$packageResult.RebootRequired) {
        [Console]::Error.WriteLine('Open-Shell was installed and requires a restart.')
        exit 3010
    }
    exit 0
}
catch {
    Write-VantaLog -Level Error -Message "Installing Open-Shell failed: $($_.Exception.Message)" -ErrorRecord $_ -NoConsole:(-not $Silent)
    if (-not $Silent) {
        Write-VantaNotApplied -Title $title -Reason $_.Exception.Message -DetailsPath (Get-VantaInstallLogPath)
        Wait-VantaExit
    }
    exit 1
}
