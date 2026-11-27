<#
.SYNOPSIS
    Stages files for Vanta Manager's elevated workers under Program Files\Vanta Setup
    Recovery.
.DESCRIPTION
    Only SYSTEM and Administrators can change that folder, so a process running as the
    same user can't swap a script or request before an elevated worker uses it.

    Vanta Manager runs this script elevated, as the text of -Command, and writes one
    JSON request to its standard input. The request's operation is one of:
      preparation           stage the Windows and Store preparation job
      media                 stage the files of an ISO or USB job
      validate-preparation  check that a preparation job still has its protected files
      executable            copy Vanta Manager itself, by content hash, for recovery
    The answer is the staged path, as JSON on standard output.
.PARAMETER FunctionsOnly
    Defines the functions without reading a request; for tests and other scripts.
.NOTES
    Exit codes: 0 staged, 1 failed (the error is on standard error), 2 Vanta Manager
    was started from a linked folder, which moving it fixes.
#>
param([switch]$FunctionsOnly)
# This elevated worker must never autoload a module from an inherited user path.
$env:PSModulePath = [IO.Path]::Combine($PSHOME, 'Modules')
if (-not $FunctionsOnly) {
    [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
}
$ErrorActionPreference = 'Stop'
# The exit code for an Vanta Manager started from a linked folder, which the
# user can fix by moving it, unlike a link on the protected side.
$VantaSourceLinkedExitCode = 2

# SYSTEM and Administrators: full control. Users: read and execute (0x1200a9). The
# owner is Administrators, and P protects the DACL from inheritance.
function Get-VantaRecoverySecurity {
    $security = New-Object Security.AccessControl.DirectorySecurity
    $security.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)')
    return $security
}

# Update-Windows.ps1 writes state.json with this same descriptor
# (Get-PreparationStateSecurity); validate-preparation rejects any other.
function Get-VantaRecoveryFileSecurity {
    $security = New-Object Security.AccessControl.FileSecurity
    $security.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;0x1200a9;;;BU)')
    return $security
}

function Write-VantaProtectedRecoveryFile {
    param([string]$Path, [byte[]]$Bytes, [Security.AccessControl.FileSecurity]$Security)
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::CreateNew, [Security.AccessControl.FileSystemRights]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::None, $Security)
    try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
}

# Root\Kind\Scope\Job, creating each level with the protected descriptor or,
# without -Create, checking that every level still has it.
function Get-VantaJobDirectory {
    param([string]$Root, [ValidateSet('Preparation', 'Media')][string]$Kind, [string]$Scope, [string]$Job, [switch]$Create)
    if ($Scope -cnotmatch '^[0-9a-f]{64}$' -or $Job -notmatch '^\d+-\d+$') { throw "Invalid $($Kind.ToLowerInvariant()) job identity." }
    $directory = $Root
    foreach ($part in @('', $Kind, $Scope, $Job)) {
        if ($part) { $directory = Join-Path $directory $part }
        if ($Create) { $null = New-VantaRecoveryDirectory $directory }
        else {
            Assert-VantaRecoveryPath $directory
            Assert-VantaRecoverySecurity ((Get-Item -LiteralPath $directory).GetAccessControl())
        }
    }
    return $directory
}

function Get-VantaRecoveryAccessDescriptor {
    param([Security.AccessControl.FileSecurity]$Security)
    $sections = [Security.AccessControl.AccessControlSections]::Access -bor [Security.AccessControl.AccessControlSections]::Owner
    $descriptor = New-Object Security.AccessControl.RawSecurityDescriptor($Security.GetSecurityDescriptorSddlForm($sections))
    # ReplaceFile can mark an unchanged protected DACL as auto-inherited.
    # Ignore that history flag, retaining ownership, protection and every ACE.
    $descriptor.SetFlags($descriptor.ControlFlags -band (-bnot [Security.AccessControl.ControlFlags]::DiscretionaryAclAutoInherited))
    return $descriptor.GetSddlForm($sections)
}

function Assert-VantaRecoveryFileSecurity {
    param([string]$Path, [Security.AccessControl.FileSecurity]$Expected = (Get-VantaRecoveryFileSecurity))
    Assert-VantaRecoveryPath $Path
    if ((Get-VantaRecoveryAccessDescriptor ((Get-Item -LiteralPath $Path).GetAccessControl())) -cne (Get-VantaRecoveryAccessDescriptor $Expected)) { throw 'The recovery file permissions changed.' }
}

function Get-VantaCancellationSecurity {
    $security = Get-VantaRecoveryFileSecurity
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $security.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($user, 'Read,Write', 'Allow')))
    return $security
}

function New-VantaPreparationJob {
    param([string]$Root, [string]$Scope, [string]$Job, [string]$Worker, [byte[]]$Policy, [string]$Library, [string]$Registry)
    $directory = Get-VantaJobDirectory $Root Preparation $Scope $Job -Create
    Write-VantaProtectedRecoveryFile (Join-Path $directory 'Update-Windows.ps1') ([Text.Encoding]::UTF8.GetBytes($Worker)) (Get-VantaRecoveryFileSecurity)
    Write-VantaProtectedRecoveryFile (Join-Path $directory 'WindowsTransition.ps1') ([Text.Encoding]::UTF8.GetBytes($Library)) (Get-VantaRecoveryFileSecurity)
    Write-VantaProtectedRecoveryFile (Join-Path $directory 'RegistryFile.ps1') ([Text.Encoding]::UTF8.GetBytes($Registry)) (Get-VantaRecoveryFileSecurity)
    Write-VantaProtectedRecoveryFile (Join-Path $directory 'DriverPolicy.reg') $Policy (Get-VantaRecoveryFileSecurity)
    foreach ($log in @('worker.log','updates.log')) { Write-VantaProtectedRecoveryFile (Join-Path $directory $log) ([byte[]]@()) (Get-VantaRecoveryFileSecurity) }
    Write-VantaProtectedRecoveryFile (Join-Path $directory 'cancel') ([byte[]]@()) (Get-VantaCancellationSecurity)
    return $directory
}

# Job folder for the elevated ISO and USB workers.
function New-VantaMediaJob {
    param([string]$Root, [string]$Scope, [string]$Job, [object[]]$Files)
    $directory = Get-VantaJobDirectory $Root Media $Scope $Job -Create
    foreach ($file in $Files) {
        if ([string]$file.name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$') { throw 'Invalid media job file name.' }
        Write-VantaProtectedRecoveryFile (Join-Path $directory $file.name) ([byte[]]$file.bytes) (Get-VantaRecoveryFileSecurity)
    }
    return $directory
}

# Whether a symbolic link or junction is anywhere on the path. Other reparse
# points store data rather than redirect: OneDrive Files On-Demand marks the
# Desktop and Downloads folders it backs up, where Vanta Manager often runs from.
function Test-VantaLinkedPath {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    while ($null -ne $item) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -and @('SymbolicLink', 'Junction') -contains $item.LinkType) { return $true }
        $item = if ($item -is [IO.FileInfo]) { $item.Directory } else { $item.Parent }
    }
    return $false
}

function Assert-VantaRecoveryPath {
    param([string]$Path)
    if (Test-VantaLinkedPath $Path) { throw 'Linked recovery paths are not supported.' }
}

function Assert-VantaRecoverySecurity {
    param([Security.AccessControl.DirectorySecurity]$Security)
    $sections = [Security.AccessControl.AccessControlSections]::Access -bor [Security.AccessControl.AccessControlSections]::Owner
    if ($Security.GetSecurityDescriptorSddlForm($sections) -cne (Get-VantaRecoverySecurity).GetSecurityDescriptorSddlForm($sections)) {
        throw 'The recovery directory does not have the required protected permissions.'
    }
}

function New-VantaRecoveryDirectory {
    param([string]$Path)
    $parent = Split-Path -Parent $Path
    Assert-VantaRecoveryPath $parent
    $directory = New-Object IO.DirectoryInfo($Path)
    if (-not $directory.Exists) { $directory.Create((Get-VantaRecoverySecurity)) }
    Assert-VantaRecoveryPath $Path
    Assert-VantaRecoverySecurity ($directory.GetAccessControl())
    return $directory.FullName
}

function Copy-VantaRecoveryExecutable {
    param([string]$Source, [string]$Root)
    Assert-VantaRecoveryPath $Source
    $rootPath = New-VantaRecoveryDirectory $Root
    $inputStream = [IO.File]::Open($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $temporary = $null
    try {
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $digest = [BitConverter]::ToString($hasher.ComputeHash($inputStream)).Replace('-', '').ToLowerInvariant() }
        finally { $hasher.Dispose() }
        $inputStream.Position = 0
        $directory = New-VantaRecoveryDirectory (Join-Path $rootPath $digest)
        $destination = Join-Path $directory 'VantaManager.exe'
        if (-not [IO.File]::Exists($destination)) {
            $temporary = Join-Path $directory ('.copy-' + [guid]::NewGuid().ToString('N'))
            $outputStream = New-Object IO.FileStream($temporary, [IO.FileMode]::CreateNew, [Security.AccessControl.FileSystemRights]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::None, (Get-VantaRecoveryFileSecurity))
            try { $inputStream.CopyTo($outputStream); $outputStream.Flush($true) }
            finally { $outputStream.Dispose() }
            if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ine $digest) { throw 'Recovery copy verification failed.' }
            try { [IO.File]::Move($temporary, $destination) }
            catch [IO.IOException] { if (-not [IO.File]::Exists($destination)) { throw } }
        }
        Assert-VantaRecoveryFileSecurity $destination
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ine $digest) { throw 'The existing recovery executable does not match this app.' }
        return $destination
    }
    finally {
        $inputStream.Dispose()
        # Only the random file created by this invocation is eligible for cleanup.
        if ($temporary -and [IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

if (-not $FunctionsOnly) {
    $request = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $programFiles = [Environment]::GetFolderPath('ProgramFiles')
    if ([string]::IsNullOrWhiteSpace($programFiles)) { throw 'Windows did not provide the Program Files directory.' }
    $root = Join-Path $programFiles 'Vanta Setup Recovery'
    $path = switch -CaseSensitive ([string]$request.operation) {
        'preparation' {
            New-VantaPreparationJob -Root $root -Scope ([string]$request.scope) -Job ([string]$request.job) -Worker ([string]$request.worker) -Policy ([byte[]]$request.policy) -Library ([string]$request.library) -Registry ([string]$request.registry)
        }
        'media' { New-VantaMediaJob -Root $root -Scope ([string]$request.scope) -Job ([string]$request.job) -Files @($request.files) }
        'validate-preparation' {
            $directory = Get-VantaJobDirectory $root Preparation ([string]$request.scope) ([string]$request.job)
            foreach ($file in @('Update-Windows.ps1','WindowsTransition.ps1','RegistryFile.ps1','DriverPolicy.reg','state.json')) { Assert-VantaRecoveryFileSecurity (Join-Path $directory $file) }
            Assert-VantaRecoveryFileSecurity (Join-Path $directory 'cancel') (Get-VantaCancellationSecurity)
            $directory
        }
        'executable' {
            # Still refused: this user's processes could retarget the link
            # under the elevated read. The exit code lets the app say why.
            if (Test-VantaLinkedPath ([string]$request.source)) {
                [Console]::Error.WriteLine('Vanta Manager was started from a linked folder. Linked recovery paths are not supported.')
                exit $VantaSourceLinkedExitCode
            }
            Copy-VantaRecoveryExecutable -Source ([string]$request.source) -Root $root
        }
        default { throw 'Unknown staging operation.' }
    }
    [Console]::WriteLine(($path | ConvertTo-Json -Compress))
}
