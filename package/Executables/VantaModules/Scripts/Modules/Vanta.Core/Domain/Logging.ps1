# Vanta.Core domain: logging and phase lifecycle.
#
# The orchestrator, helpers running as the installing user and other privilege
# levels can all write these files. A named mutex serialises their appends.

$script:VantaCurrentPhase = $null
$script:VantaTranscriptActive = $false
# Diagnostic echoes every log line to the console as written to the file, which silent
# runs, replay, installation and the TrustedInstaller broker rely on for captured
# output. Interactive entry points switch to Interactive: Info stays in the file,
# Warning and Error appear in the presentation vocabulary.
$script:VantaLogConsoleStyle = 'Diagnostic'

function Set-VantaLogConsoleStyle {
    <#
    .SYNOPSIS
        Chooses how log lines reach the console: Diagnostic echoes every line, and
        Interactive keeps Info in the file and shows warnings and errors to the user.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Diagnostic', 'Interactive')]
        [string]$Style
    )

    $script:VantaLogConsoleStyle = $Style
}

function Get-VantaLogConsoleStyle {
    <#
    .SYNOPSIS
        Returns the console style log lines use: Diagnostic or Interactive.
    #>
    return $script:VantaLogConsoleStyle
}

function Get-VantaInstallLogDirectory {
    # Medium-integrity desktop actions cannot append to the protected machine log.
    # Keep their diagnostics in their own profile; elevated callers never follow it.
    # The machine log root is fixed. Use the context only once it is loaded, so
    # logging never reads the install-state documents and keeps working when one is
    # damaged or locked.
    $logsPath = if (-not (Test-VantaAdmin)) {
        Join-Path -Path ([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath 'Vanta\Logs'
    }
    elseif ($null -ne $script:VantaContext) {
        $script:VantaContext.LogsPath
    }
    else {
        Join-Path -Path ([Environment]::GetFolderPath('Windows')) -ChildPath 'VantaModules\Logs'
    }
    $installLogPath = Join-Path -Path $logsPath -ChildPath 'install'
    if (-not (Test-Path -LiteralPath $installLogPath -PathType Container)) {
        New-Item -Path $installLogPath -ItemType Directory -Force | Out-Null
    }

    return $installLogPath
}

function Get-VantaInstallLogPath {
    <#
    .SYNOPSIS
        The shared install log this process appends to, for pointing a user at details.
        Returns $null when the log folder is unavailable.
    #>
    # Failure handlers call this while reporting another error; it must not replace
    # that report with its own.
    try {
        return Join-Path -Path (Get-VantaInstallLogDirectory) -ChildPath 'vanta-install.log'
    }
    catch {
        return $null
    }
}

function Invoke-VantaInstallLogRetention {
    <#
    .SYNOPSIS
        Limits the size of the machine's install log folder, whose logs survive updates.
    .DESCRIPTION
        Moves vanta-install.log or warnings-summary.log aside as *.previous.log once it
        is larger than 16 MiB, replacing the one moved aside before. Deletes timestamped
        logs older than 90 days, except the newest 200, so the last installs' logs stay
        however long ago they ran. The parameters change these thresholds.
    #>
    param(
        [string]$Path = [IO.Path]::Combine([Environment]::GetFolderPath('Windows'), 'VantaModules', 'Logs', 'install'),
        [long]$RotateBytes = 16MB,
        [int]$MaximumAgeDays = 90,
        [int]$KeepNewest = 200,
        [DateTime]$Now = [DateTime]::UtcNow
    )

    if (-not [IO.Directory]::Exists($Path)) {
        return
    }
    if (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to tidy Vanta's install logs through a reparse point at '$Path'."
    }

    foreach ($name in @('vanta-install.log', 'warnings-summary.log')) {
        $log = [IO.FileInfo]::new([IO.Path]::Combine($Path, $name))
        if (-not $log.Exists -or $log.Length -le $RotateBytes) { continue }
        # Other processes append under this lock, so none writes half a line into
        # the file being moved.
        $mutex = New-Object System.Threading.Mutex($false, 'Global\VantaInstallLog')
        $acquired = $false
        try {
            try { $acquired = $mutex.WaitOne(5000) }
            catch [System.Threading.AbandonedMutexException] { $acquired = $true }
            if (-not $acquired) { throw "Timed out waiting for the Vanta install log lock to move '$name' aside." }
            $previous = [IO.Path]::Combine($Path, [IO.Path]::GetFileNameWithoutExtension($name) + '.previous.log')
            if ([IO.File]::Exists($previous)) { [IO.File]::Delete($previous) }
            [IO.File]::Move($log.FullName, $previous)
        }
        finally {
            if ($acquired) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
        }
    }

    # Phase transcripts and the session copies both begin with their time.
    $timestamped = @([IO.DirectoryInfo]::new($Path).GetFiles('*.log') |
            Where-Object { $_.Name -match '^\d{8}-\d{6}-.+\.log$' } |
            Sort-Object -Property LastWriteTimeUtc -Descending)
    $cutoff = $Now.ToUniversalTime().AddDays(-$MaximumAgeDays)
    $kept = @()
    foreach ($file in @($timestamped | Select-Object -Skip $KeepNewest)) {
        if ($file.LastWriteTimeUtc -ge $cutoff) { continue }
        try { $file.Delete() }
        catch { $kept += "$($file.Name) ($($_.Exception.Message))" }
    }
    if ($kept.Count -gt 0) {
        throw "Old install logs couldn't be deleted: $($kept -join '; ')"
    }
}

function Write-VantaLogFile {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string]$Line
    )

    $logPath = Join-Path -Path (Get-VantaInstallLogDirectory) -ChildPath $FileName

    $mutexName = if (Test-VantaAdmin) {
        'Global\VantaInstallLog'
    }
    else {
        'Local\VantaUserLog-' + (Get-VantaCurrentUserSid)
    }
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne(5000)
        }
        catch [System.Threading.AbandonedMutexException] {
            $acquired = $true
        }

        # Losing append serialisation beats losing the log line, so a lock timeout
        # degrades to an unserialised append with a warning.
        if (-not $acquired) {
            Write-Warning "Timed out acquiring the Vanta install log lock; appending to '$FileName' without serialization." `
                -WarningAction Continue
        }
        [System.IO.File]::AppendAllText($logPath, $Line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    }
    finally {
        if ($acquired) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function Write-VantaLog {
    <#
    .SYNOPSIS
        Writes a structured line to the shared install log (and warnings summary for
        Warning/Error), echoing it to the current console.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info',

        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        # The interactive presentation already shows this text; keep it out of the
        # console in Interactive style. Diagnostic style ignores the switch.
        [switch]$NoConsole
    )

    $phaseLabel = if ($script:VantaCurrentPhase) { $script:VantaCurrentPhase } else { '-' }
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$phaseLabel] [$($Level.ToUpperInvariant())] $Message"

    if ($ErrorRecord) {
        $line += " | $($ErrorRecord.InvocationInfo.PositionMessage -replace '\r?\n', ' ')"
    }

    try {
        Write-VantaLogFile -FileName 'vanta-install.log' -Line $line
        if ($Level -ne 'Info') {
            Write-VantaLogFile -FileName 'warnings-summary.log' -Line $line
        }
    }
    catch {
        # Helpers running as the user use ErrorActionPreference=Stop. A failed log
        # write must only warn, never make a handled best-effort step fail the process.
        Write-Warning "Failed to write to the Vanta install log: $($_.Exception.Message)" `
            -WarningAction Continue
    }

    if ($script:VantaLogConsoleStyle -ceq 'Interactive') {
        if (-not $NoConsole) {
            switch ($Level) {
                'Warning' { Write-VantaWarning -Text $Message }
                'Error' { Write-VantaFailure -Text $Message }
            }
        }
        return
    }

    switch ($Level) {
        'Info' { Write-Host $line }
        'Warning' { Write-Host $line -ForegroundColor Yellow }
        'Error' { Write-Host $line -ForegroundColor Red }
    }
}

function Start-VantaPhase {
    <#
    .SYNOPSIS
        Begins a named install phase: starts a per-process transcript and logs the
        execution context (user, privilege, architecture, build).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Phase,

        [string]$Category
    )

    $script:VantaCurrentPhase = if ($Category) { "$Phase/$Category" } else { $Phase }

    $transcriptName = '{0:yyyyMMdd-HHmmss}-{1}-{2}.log' -f (Get-Date), ($script:VantaCurrentPhase -replace '[\\/]', '-'), $env:USERNAME
    $transcriptPath = Join-Path -Path (Get-VantaInstallLogDirectory) -ChildPath $transcriptName

    try {
        Start-Transcript -Path $transcriptPath -ErrorAction Stop | Out-Null
        $script:VantaTranscriptActive = $true
    }
    catch {
        $script:VantaTranscriptActive = $false
        Write-Warning "Couldn't start a transcript for phase '$Phase': $($_.Exception.Message)" `
            -WarningAction Continue
    }

    $context = Get-VantaContext
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    Write-VantaLog -Message "Phase started (user: $($identity.Name), sid: $($identity.User.Value), arm64: $($context.IsArm64), build: $($context.WindowsBuild), upgrade: $($context.IsUpgrade))"
}

function Stop-VantaPhase {
    <#
    .SYNOPSIS
        Ends the current install phase and stops its transcript. -Failed records the
        phase outcome in the log.
    #>
    param([switch]$Failed)

    if ($script:VantaCurrentPhase) {
        if ($Failed) {
            Write-VantaLog -Level Warning -Message 'Phase failed'
        }
        else {
            Write-VantaLog -Message 'Phase finished'
        }
    }

    if ($script:VantaTranscriptActive) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
            $null = $_
        }
        $script:VantaTranscriptActive = $false
    }

    $script:VantaCurrentPhase = $null
}
