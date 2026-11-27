# Companion for the VantaHealth toggle: runs the Vanta health report, Test-VantaHealth.ps1.
# Show-VantaHealthReport runs as Administrator when you run the launcher; nothing is recorded.

function Show-VantaHealthReport {
    param($Toggle)

    $health = Join-Path -Path $Toggle.ScriptsPath -ChildPath 'Entry\Test-VantaHealth.ps1'
    if (-not (Test-Path -LiteralPath $health -PathType Leaf)) {
        throw "The Vanta health check is missing at '$health'."
    }

    # The entry script reloads Vanta modules. Run it in its own process so those
    # imports cannot replace the module session executing this companion action.
    # Exit code 1 reports drift; only a check that could not run is an error.
    $powershell = [IO.Path]::Combine(
        $Toggle.WinDir, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'
    )
    $result = Invoke-VantaHiddenProcess -FilePath $powershell -ArgumentList @(
        '-NoProfile', '-NoLogo', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-OutputFormat', 'Text', '-File', $health
    ) -Wait -AllowedExitCode @(0, 1) -TimeoutSeconds 120 -CaptureOutput
    Write-Host $result.StandardOutput.TrimEnd()
    if (-not [string]::IsNullOrWhiteSpace($result.StandardError)) {
        Write-VantaWarning -Text $result.StandardError.TrimEnd()
    }
}
