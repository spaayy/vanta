# Vanta.Core domain: the single loader for Vanta's native (C#) code.
#
# Every runtime-compiled type Vanta uses lives in Vanta.Core\Native\Vanta.Native.cs.
# This file owns Vanta's only Add-Type compile, so a high-integrity host
# never compiles through a requester-writable temp directory.

$script:VantaNativeTypeLoaded = $false

function Add-VantaNativeType {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This private compiler wrapper creates and removes only its random protected compiler directory.'
    )]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeDefinition
    )

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isHighIntegrityContext = $identity.User.Value -eq 'S-1-5-18' -or
        $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isHighIntegrityContext) {
        Add-Type -TypeDefinition $TypeDefinition -Language CSharp -ErrorAction Stop
        return
    }

    # Windows PowerShell 5.1 exposes the from-birth DirectorySecurity overload. A future
    # high-integrity host without it must fail closed instead of compiling through a
    # requester-writable temp directory.
    $createWithSecurity = [IO.Directory].GetMethod(
        'CreateDirectory',
        [type[]]@([string], [Security.AccessControl.DirectorySecurity])
    )
    if (-not $createWithSecurity) {
        throw 'A protected from-birth compiler directory is unavailable in this high-integrity PowerShell host.'
    }

    $windowsDirectory = [Environment]::GetFolderPath('Windows')
    $systemProfile = Join-Path -Path $windowsDirectory -ChildPath 'System32\config\systemprofile'
    if (-not (Test-Path -LiteralPath $systemProfile -PathType Container) -or
        ((Get-Item -LiteralPath $systemProfile -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Protected system-profile compiler parent '$systemProfile' is unavailable."
    }

    $security = New-Object Security.AccessControl.DirectorySecurity
    $administrators = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $system = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    $security.SetOwner($administrators)
    $security.SetAccessRuleProtection($true, $false)
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [Security.AccessControl.InheritanceFlags]::ObjectInherit
    foreach ($sid in @($system, $administrators)) {
        $security.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
            $sid,
            [Security.AccessControl.FileSystemRights]::FullControl,
            $inheritance,
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow
        )))
    }

    $compilerTemp = Join-Path -Path $systemProfile -ChildPath ('VantaCompiler-' + [guid]::NewGuid().ToString('N'))
    $originalTemp = $env:TEMP
    $originalTmp = $env:TMP
    try {
        if (Test-Path -LiteralPath $compilerTemp) {
            throw "Random protected compiler directory '$compilerTemp' unexpectedly exists."
        }
        $createArguments = [object[]]@(
            [string]$compilerTemp,
            $security.PSObject.BaseObject
        )
        [void]$createWithSecurity.Invoke($null, $createArguments)
        $env:TEMP = $compilerTemp
        $env:TMP = $compilerTemp
        Add-Type -TypeDefinition $TypeDefinition -Language CSharp -ErrorAction Stop
    }
    finally {
        $env:TEMP = $originalTemp
        $env:TMP = $originalTmp
        if (Test-Path -LiteralPath $compilerTemp -PathType Container) {
            [IO.Directory]::Delete($compilerTemp, $true)
        }
    }
}

function Test-VantaNativeAssembly {
    <#
    .SYNOPSIS
        Returns $true when a prebuilt Vanta.Native.dll beside the source is a regular file
        with a valid Authenticode signature. Anything else means the source is compiled.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        return $false
    }
    $signature = Get-AuthenticodeSignature -FilePath $item.FullName -ErrorAction SilentlyContinue
    return ($null -ne $signature -and $signature.Status -eq 'Valid')
}

function Initialize-VantaNativeType {
    <#
    .SYNOPSIS
        Loads all of Vanta's native code once per PowerShell process: a signed
        prebuilt Vanta.Native.dll when one sits beside the source (built by
        tools\native\Build-VantaNative.ps1), otherwise the source compiled in place.
    #>
    if ($script:VantaNativeTypeLoaded -or ('Vanta.Native.TrustedInstallerProcess' -as [type])) {
        $script:VantaNativeTypeLoaded = $true
        return
    }

    $assemblyPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Native\Vanta.Native.dll'
    if (Test-VantaNativeAssembly -Path $assemblyPath) {
        Add-Type -Path (Get-Item -LiteralPath $assemblyPath -Force).FullName -ErrorAction Stop
        $script:VantaNativeTypeLoaded = $true
        return
    }

    $sourcePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Native\Vanta.Native.cs'
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "The Vanta native source '$sourcePath' is missing."
    }
    $sourceItem = Get-Item -LiteralPath $sourcePath -Force
    if ($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "The Vanta native source '$sourcePath' is a reparse point."
    }

    Add-VantaNativeType -TypeDefinition ([IO.File]::ReadAllText($sourceItem.FullName))
    $script:VantaNativeTypeLoaded = $true
}
